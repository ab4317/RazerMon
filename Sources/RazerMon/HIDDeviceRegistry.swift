import Foundation
import IOKit.hid

/// Maintains a low-cost, event-driven snapshot of connected catalog devices.
/// IOKit delivers matching and removal callbacks on the main run loop, so no
/// polling loop or dedicated worker thread is required.
final class HIDDeviceRegistry {
    var onChange: ((Set<Int>) -> Void)?

    private let manager: IOHIDManager
    private let candidateIDs: Set<Int>
    private var devices: [ObjectIdentifier: Int] = [:]
    private var changeNotificationScheduled = false
    private(set) var isStarted = false

    var connectedProductIDs: Set<Int> { Set(devices.values) }

    init(catalog: DeviceCatalog = .bundled) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        candidateIDs = Set(catalog.batteryCandidates.compactMap(\.numericProductID))

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceRegistry>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceRegistry>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
    }

    func start() throws {
        guard !isStarted else { return }
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            throw HIDError.managerOpenFailed(result)
        }
        isStarted = true
    }

    deinit {
        guard isStarted else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Any interface of a catalog product marks it as connected. Which
    /// interface answers Razer reports is decided later by HIDTransport, so a
    /// product whose control interface macOS describes unexpectedly is still
    /// listed (as unavailable) instead of silently missing from the menu.
    private func deviceMatched(_ device: IOHIDDevice) {
        let productID = Self.intProperty(kIOHIDProductIDKey, of: device)
        guard candidateIDs.contains(productID) else { return }

        let key = ObjectIdentifier(device)
        guard devices.updateValue(productID, forKey: key) == nil else { return }
        scheduleChangeNotification()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard devices.removeValue(forKey: ObjectIdentifier(device)) != nil else { return }
        scheduleChangeNotification()
    }

    private func scheduleChangeNotification() {
        guard !changeNotificationScheduled else { return }
        changeNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.changeNotificationScheduled = false
            self.onChange?(self.connectedProductIDs)
        }
    }

    private static func intProperty(_ key: String, of device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
        return (value as? NSNumber)?.intValue ?? 0
    }
}
