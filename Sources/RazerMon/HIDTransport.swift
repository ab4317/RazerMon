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

final class HIDTransport {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    let productID: UInt16

    init(vendorID: Int = 0x1532, productID: Int) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        self.productID = UInt16(productID)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: vendorID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw HIDError.managerOpenFailed(managerResult) }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard let device = devices.first(where: {
            Self.intProperty(kIOHIDProductIDKey, of: $0) == productID
                && Self.intProperty(kIOHIDPrimaryUsagePageKey, of: $0) == kHIDPage_GenericDesktop
                && Self.deviceKind(of: $0) != nil
                && Self.intProperty(kIOHIDMaxFeatureReportSizeKey, of: $0) >= RazerReport.length
        }) else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HIDError.noCompatibleInterface
        }
        self.device = device
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HIDError.deviceOpenFailed(deviceResult)
        }
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func exchange(_ request: RazerReport) throws -> RazerReport {
        let setResult = request.bytes.withUnsafeBytes {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0,
                $0.bindMemory(to: UInt8.self).baseAddress!, request.bytes.count)
        }
        guard setResult == kIOReturnSuccess else { throw HIDError.setReportFailed(setResult) }
        usleep(30_000)
        var response = [UInt8](repeating: 0, count: RazerReport.length)
        var length = response.count
        let getResult = response.withUnsafeMutableBytes {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0,
                $0.bindMemory(to: UInt8.self).baseAddress!, &length)
        }
        guard getResult == kIOReturnSuccess else { throw HIDError.getReportFailed(getResult) }
        let report = try RazerReport(validating: Array(response.prefix(length)))
        guard report.matches(request) else { throw ProtocolError.staleResponse }
        return report
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
