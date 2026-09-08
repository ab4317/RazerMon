import Foundation

enum RazerMonitor {
    static func readDevices() throws -> [DeviceStatus] {
        let transport = try HIDTransport()
        let pairedRequest = RazerCommands.pairedProducts()
        let productIDs = (try? RazerCommands.parseProductIDs(
            from: transport.exchange(pairedRequest), request: pairedRequest
        )) ?? []
        var devices: [PairedDevice] = []
        var serials = Set<String>()
        for tid in RazerCommands.candidateTransactionIDs {
            do {
                let serialRequest = RazerCommands.serialNumber(transactionID: tid)
                let serial = try RazerCommands.parseSerial(from: transport.exchange(serialRequest), request: serialRequest)
                guard serials.insert(serial).inserted else { continue }
                let batteryRequest = RazerCommands.battery(transactionID: tid)
                let raw = try RazerCommands.parseBattery(from: transport.exchange(batteryRequest), request: batteryRequest)
                devices.append(PairedDevice(transactionID: tid, serialNumber: serial, batteryRaw: raw))
            } catch { continue }
        }
        return devices.enumerated().map { index, device in
            guard index < productIDs.count else {
                return DeviceStatus(
                    name: "Paired device",
                    kind: .unknown,
                    serialNumber: device.serialNumber,
                    batteryPercent: device.batteryPercent
                )
            }
            let productID = productIDs[index]
            let fallback = RazerProducts.product(for: productID)
            let hid = transport.metadata(for: productID)
            return DeviceStatus(
                name: hid?.name.map(RazerProducts.displayName(from:)) ?? fallback.name,
                kind: hid?.kind == .unknown || hid == nil ? fallback.kind : hid!.kind,
                serialNumber: device.serialNumber,
                batteryPercent: device.batteryPercent
            )
        }
    }
}
