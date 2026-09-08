import Foundation

private struct DiscoveredDevice {
    let receiverProductID: Int
    let protocolID: BatteryProtocolID
    let transactionID: UInt8
    let identity: DeviceStatus
}

enum RazerMonitor {
    static func readDevices(
        connectedProductIDs: Set<Int>,
        cachedDevices: [String: CachedDeviceStatus],
        batteryMaximumAge: TimeInterval,
        forceBatteryRefresh: Bool,
        now: Date = Date(),
        onDiscovery: @escaping ([DeviceStatus]) -> Void
    ) throws -> [CachedDeviceStatus] {
        let discovered = try discoverDevices(connectedProductIDs: connectedProductIDs)

        // Publish topology before battery requests. Existing devices retain
        // their value; a new device displays a temporary reading state.
        onDiscovery(discovered.map { device in
            status(
                for: device.identity,
                batteryPercent: cachedDevices[device.identity.serialNumber]?.status.batteryPercent
            )
        })

        var results: [CachedDeviceStatus] = []
        for group in Dictionary(grouping: discovered, by: \.receiverProductID).values {
            guard let first = group.first,
                  let transport = try? HIDTransport(productID: first.receiverProductID) else {
                results.append(contentsOf: group.compactMap { cachedDevices[$0.identity.serialNumber] })
                continue
            }
            let adapter = BatteryProtocolRegistry.adapter(for: first.protocolID)
            for device in group {
                if !forceBatteryRefresh,
                   let cached = cachedDevices[device.identity.serialNumber],
                   cached.hasFreshBattery(at: now, maximumAge: batteryMaximumAge) {
                    results.append(CachedDeviceStatus(
                        status: status(for: device.identity, batteryPercent: cached.status.batteryPercent),
                        batteryReadAt: cached.batteryReadAt
                    ))
                    continue
                }
                do {
                    let request = adapter.batteryRequest(transactionID: device.transactionID)
                    let raw = try adapter.parseBattery(from: transport.exchange(request), request: request)
                    let percent = PairedDevice(
                        transactionID: device.transactionID,
                        serialNumber: device.identity.serialNumber,
                        batteryRaw: raw
                    ).batteryPercent
                    results.append(CachedDeviceStatus(
                        status: status(for: device.identity, batteryPercent: percent),
                        batteryReadAt: now
                    ))
                } catch {
                    if let cached = cachedDevices[device.identity.serialNumber] { results.append(cached) }
                }
            }
        }
        return results
    }

    private static func discoverDevices(connectedProductIDs: Set<Int>) throws -> [DiscoveredDevice] {
        let catalog = DeviceCatalog.bundled
        var results: [DiscoveredDevice] = []
        var serials = Set<String>()
        var openedCandidate = false

        for candidate in catalog.batteryCandidates where connectedProductIDs.contains(candidate.numericProductID ?? -1) {
            guard let receiverProductID = candidate.numericProductID,
                  let protocolID = candidate.batteryProtocol,
                  let transport = try? HIDTransport(productID: receiverProductID) else { continue }
            openedCandidate = true
            let adapter = BatteryProtocolRegistry.adapter(for: protocolID)
            let pairedRequest = adapter.pairedProductsRequest()
            let productIDs = (try? adapter.parseProductIDs(
                from: transport.exchange(pairedRequest), request: pairedRequest
            )) ?? []
            var receiverDevices: [(transactionID: UInt8, serialNumber: String)] = []
            for transactionID in adapter.candidateTransactionIDs {
                do {
                    let request = adapter.serialNumberRequest(transactionID: transactionID)
                    let serial = try adapter.parseSerial(from: transport.exchange(request), request: request)
                    guard serials.insert(serial).inserted else { continue }
                    receiverDevices.append((transactionID, serial))
                } catch { continue }
            }
            for (index, device) in receiverDevices.enumerated() {
                let productID = index < productIDs.count ? productIDs[index] : UInt16(receiverProductID)
                let fallback = RazerProducts.product(for: productID)
                let hid = transport.metadata(for: productID)
                results.append(DiscoveredDevice(
                    receiverProductID: receiverProductID,
                    protocolID: protocolID,
                    transactionID: device.transactionID,
                    identity: DeviceStatus(
                        name: hid?.name.map(RazerProducts.displayName(from:)) ?? RazerProducts.displayName(from: fallback.name),
                        kind: hid?.kind == .unknown || hid == nil ? fallback.kind : hid!.kind,
                        serialNumber: device.serialNumber,
                        batteryPercent: nil
                    )
                ))
            }
        }

        guard openedCandidate else { throw HIDError.noCompatibleInterface }
        return results
    }

    private static func status(for identity: DeviceStatus, batteryPercent: Int?) -> DeviceStatus {
        DeviceStatus(
            name: identity.name,
            kind: identity.kind,
            serialNumber: identity.serialNumber,
            batteryPercent: batteryPercent
        )
    }
}
