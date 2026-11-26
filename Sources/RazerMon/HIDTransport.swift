import Foundation
import IOKit.hid

enum HIDError: Error, CustomStringConvertible {
    case managerOpenFailed(IOReturn)
    case noCompatibleInterface
    case deviceOpenFailed(IOReturn)
    case setReportFailed(IOReturn)
    case getReportFailed(IOReturn)

    var description: String {
        switch self {
        case .managerOpenFailed(let code): return L10n.format("error.hid.manager_open", code)
        case .noCompatibleInterface: return L10n.text("error.hid.interface_not_found")
        case .deviceOpenFailed(let code): return L10n.format("error.hid.device_open", code)
        case .setReportFailed(let code): return L10n.format("error.hid.battery_request", code)
        case .getReportFailed(let code): return L10n.format("error.hid.battery_response", code)
        }
    }
}

/// Standard HID properties of one logical interface, as macOS reports them.
struct HIDInterfaceInfo: Equatable {
    let registryID: UInt64
    let productID: Int
    let product: String?
    let transport: String?
    let interfaceNumber: Int?
    let primaryUsagePage: Int
    let primaryUsage: Int
    let usagePairs: [(page: Int, usage: Int)]
    let maxFeatureReportSize: Int
    let maxInputReportSize: Int
    let maxOutputReportSize: Int

    /// Interfaces declaring a feature report large enough for the 90-byte
    /// Razer report are the only ones worth sending commands to.
    var canCarryRazerReport: Bool { maxFeatureReportSize >= RazerReport.length }

    var isKeyboardOrMouse: Bool {
        primaryUsagePage == kHIDPage_GenericDesktop
            && (primaryUsage == kHIDUsage_GD_Mouse || primaryUsage == kHIDUsage_GD_Keyboard)
    }

    /// Deterministic probe order. Keyboard/mouse interfaces come first because
    /// every verified device answers there; then the lowest USB interface
    /// number, which is where OpenRazer addresses most mice (wIndex 0).
    static func probeOrder(_ lhs: HIDInterfaceInfo, _ rhs: HIDInterfaceInfo) -> Bool {
        if lhs.isKeyboardOrMouse != rhs.isKeyboardOrMouse { return lhs.isKeyboardOrMouse }
        let left = lhs.interfaceNumber ?? Int.max
        let right = rhs.interfaceNumber ?? Int.max
        if left != right { return left < right }
        return lhs.registryID < rhs.registryID
    }

    static func == (lhs: HIDInterfaceInfo, rhs: HIDInterfaceInfo) -> Bool {
        lhs.registryID == rhs.registryID
    }
}

final class HIDTransport {
    private static let responseDelayMicroseconds: useconds_t = 30_000
    private static let retryDelayMicroseconds: useconds_t = 10_000

    private let manager: IOHIDManager
    private let candidates: [(info: HIDInterfaceInfo, device: IOHIDDevice)]
    private var device: IOHIDDevice?
    private(set) var activeInterface: HIDInterfaceInfo?
    let productID: UInt16

    /// Interfaces of this product that can carry a Razer report, in probe order.
    var interfaces: [HIDInterfaceInfo] { candidates.map(\.info) }

    /// Opens the first compatible interface, or the one with `interfaceID`
    /// when it is still present.
    init(vendorID: Int = 0x1532, productID: Int, interfaceID: UInt64? = nil) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        self.productID = UInt16(productID)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw HIDError.managerOpenFailed(managerResult) }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        candidates = devices
            .map { (info: Self.info(for: $0), device: $0) }
            .filter { $0.info.productID == productID && $0.info.canCarryRazerReport }
            .sorted { HIDInterfaceInfo.probeOrder($0.info, $1.info) }
        guard let first = candidates.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HIDError.noCompatibleInterface
        }
        let preferred = candidates.first { $0.info.registryID == interfaceID }?.info ?? first.info
        do {
            try activate(preferred)
        } catch {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw error
        }
    }

    deinit {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Switch subsequent exchanges to another compatible interface.
    func activate(_ interface: HIDInterfaceInfo) throws {
        guard interface != activeInterface else { return }
        guard let candidate = candidates.first(where: { $0.info == interface }) else {
            throw HIDError.noCompatibleInterface
        }
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        activeInterface = nil
        let result = IOHIDDeviceOpen(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.deviceOpenFailed(result) }
        device = candidate.device
        activeInterface = candidate.info
    }

    /// Send a request and read its response, making up to `attempts` reads
    /// 10 ms apart (OpenRazer's razer_send_payload retries five times).
    /// A busy answer to this request means the receiver is still working on
    /// it, so it is read again without re-sending: re-sending restarts the
    /// command and a slow receiver would never finish. A stale answer (to an
    /// earlier request) is read once more, then the request is re-sent in
    /// case the receiver dropped it. A transfer error, an invalid report or a
    /// failure status re-sends the request.
    func exchange(_ request: RazerReport, attempts: Int = 1) throws -> RazerReport {
        var lastError: Error = HIDError.noCompatibleInterface
        var needsSend = true
        for attempt in 0..<max(1, attempts) {
            if attempt > 0 { usleep(Self.retryDelayMicroseconds) }
            do {
                let justSent = needsSend
                if needsSend { try send(request) }
                needsSend = true
                let response = try receive()
                guard response.matches(request) else {
                    needsSend = !justSent
                    throw ProtocolError.staleResponse
                }
                switch ResponseDisposition(status: response.status) {
                case .accept:
                    return response
                case .reject(let status):
                    throw ProtocolError.commandFailed(status)
                case .retry(let status):
                    needsSend = status != RazerStatus.busy
                    lastError = ProtocolError.commandFailed(status)
                }
            } catch ProtocolError.commandFailed(let status) {
                throw ProtocolError.commandFailed(status)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// One SET_REPORT/GET_REPORT round trip with checksum validation only.
    /// Diagnostics use this directly to record what the device answered.
    func exchangeRaw(_ request: RazerReport) throws -> RazerReport {
        try send(request)
        return try receive()
    }

    private func send(_ request: RazerReport) throws {
        guard let device else { throw HIDError.noCompatibleInterface }
        let setResult = request.bytes.withUnsafeBytes {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0,
                $0.bindMemory(to: UInt8.self).baseAddress!, request.bytes.count)
        }
        guard setResult == kIOReturnSuccess else { throw HIDError.setReportFailed(setResult) }
        usleep(Self.responseDelayMicroseconds)
    }

    private func receive() throws -> RazerReport {
        guard let device else { throw HIDError.noCompatibleInterface }
        var response = [UInt8](repeating: 0, count: RazerReport.length)
        var length = response.count
        let getResult = response.withUnsafeMutableBytes {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0,
                $0.bindMemory(to: UInt8.self).baseAddress!, &length)
        }
        guard getResult == kIOReturnSuccess else { throw HIDError.getReportFailed(getResult) }
        return try RazerReport(validating: Array(response.prefix(length)))
    }

    /// Resolve the paired product through standard HID properties when macOS
    /// exposes a matching logical interface. A product may publish several
    /// interfaces; auxiliary consumer-control interfaces are ignored, while a
    /// conflicting mouse+keyboard result is treated as unknown.
    func metadata(for productID: UInt16) -> HIDDeviceMetadata? {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let matches = devices.filter {
            Self.intProperty(kIOHIDProductIDKey, of: $0) == Int(productID)
        }
        guard !matches.isEmpty else { return nil }

        let kinds = Set(matches.compactMap(Self.deviceKind))
        let kind = kinds.count == 1 ? kinds.first! : .unknown
        let productName = matches.lazy.compactMap {
            Self.stringProperty(kIOHIDProductKey, of: $0)
        }.first { !$0.isEmpty }
        return HIDDeviceMetadata(name: productName, kind: kind)
    }

    /// Every HID interface macOS currently publishes for the vendor, without
    /// opening any of them.
    static func allInterfaces(vendorID: Int = 0x1532) -> [HIDInterfaceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        defer { if opened { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) } }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return devices.map(info).sorted {
            $0.productID != $1.productID ? $0.productID < $1.productID : HIDInterfaceInfo.probeOrder($0, $1)
        }
    }

    static func info(for device: IOHIDDevice) -> HIDInterfaceInfo {
        let service = IOHIDDeviceGetService(device)
        var registryID: UInt64 = 0
        if service != IO_OBJECT_NULL { IORegistryEntryGetRegistryEntryID(service, &registryID) }
        let pairs = (IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]]) ?? []
        return HIDInterfaceInfo(
            registryID: registryID,
            productID: intProperty(kIOHIDProductIDKey, of: device),
            product: stringProperty(kIOHIDProductKey, of: device),
            transport: stringProperty(kIOHIDTransportKey, of: device),
            interfaceNumber: interfaceNumber(of: service),
            primaryUsagePage: intProperty(kIOHIDPrimaryUsagePageKey, of: device),
            primaryUsage: intProperty(kIOHIDPrimaryUsageKey, of: device),
            usagePairs: pairs.map {
                (page: ($0[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue ?? 0,
                 usage: ($0[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue ?? 0)
            },
            maxFeatureReportSize: intProperty(kIOHIDMaxFeatureReportSizeKey, of: device),
            maxInputReportSize: intProperty(kIOHIDMaxInputReportSizeKey, of: device),
            maxOutputReportSize: intProperty(kIOHIDMaxOutputReportSizeKey, of: device)
        )
    }

    /// The USB interface number lives on the IOUSBHostInterface ancestor of
    /// the HID service; Bluetooth and virtual devices have none.
    private static func interfaceNumber(of service: io_service_t) -> Int? {
        guard service != IO_OBJECT_NULL,
              let value = IORegistryEntrySearchCFProperty(
                  service, kIOServicePlane, "bInterfaceNumber" as CFString, kCFAllocatorDefault,
                  IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
              ) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func intProperty(_ key: String, of device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func stringProperty(_ key: String, of device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func deviceKind(of device: IOHIDDevice) -> DeviceKind? {
        guard intProperty(kIOHIDPrimaryUsagePageKey, of: device) == kHIDPage_GenericDesktop else {
            return nil
        }
        switch intProperty(kIOHIDPrimaryUsageKey, of: device) {
        case kHIDUsage_GD_Mouse: return .mouse
        case kHIDUsage_GD_Keyboard: return .keyboard
        default: return nil
        }
    }
}

struct HIDDeviceMetadata {
    let name: String?
    let kind: DeviceKind
}
