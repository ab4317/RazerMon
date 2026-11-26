import Foundation

private struct DiscoveredDevice {
    let receiverProductID: Int
    let interfaceID: UInt64
    let protocolID: BatteryProtocolID
    let transactionID: UInt8
    let identity: DeviceStatus
}

enum RazerMonitor {
    /// Discovery first tries every interface once per command, which is what
    /// working devices need. Only when nothing answers is the scan repeated
    /// with OpenRazer's five attempts, so slow firmware gets a second chance
    /// without slowing down every refresh.
    static let discoveryAttemptPasses = [1, 5]
    static let batteryAttempts = 5

    static func readDevices(
        connectedProductIDs: Set<Int>,
        cachedDevices: [String: CachedDeviceStatus],
        batteryMaximumAge: TimeInterval,
        forceBatteryRefresh: Bool,
        now: Date = Date(),
        onDiscovery: @escaping ([DeviceStatus]) -> Void
    ) throws -> [CachedDeviceStatus] {
        let (discovered, unavailable) = discoverDevices(connectedProductIDs: connectedProductIDs)
        guard !discovered.isEmpty || !unavailable.isEmpty else { throw HIDError.noCompatibleInterface }

        // Publish topology before battery requests. Existing devices retain
        // their value; a new device displays a temporary reading state.
        onDiscovery(discovered.map { device in
            status(
                for: device.identity,
                batteryPercent: cachedDevices[device.identity.serialNumber]?.status.batteryPercent
            )
        } + unavailable)

        var results: [CachedDeviceStatus] = []
        for group in Dictionary(grouping: discovered, by: \.receiverProductID).values {
            guard let first = group.first,
                  let transport = try? HIDTransport(productID: first.receiverProductID, interfaceID: first.interfaceID) else {
                results.append(contentsOf: group.map {
                    cachedDevices[$0.identity.serialNumber] ?? unavailableResult(for: $0.identity)
                })
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
                    let raw = try adapter.parseBattery(
                        from: transport.exchange(request, attempts: batteryAttempts), request: request
                    )
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
                    // Keep the device visible: the last known value if there
                    // is one, otherwise an explicit "unavailable" row.
                    results.append(cachedDevices[device.identity.serialNumber] ?? unavailableResult(for: device.identity))
                }
            }
        }
        results.append(contentsOf: unavailable.map { CachedDeviceStatus(status: $0, batteryReadAt: .distantPast) })
        return results
    }

    /// Row for a connected catalog product that did not answer any Razer
    /// report. The identifier doubles as the cache key and is unique per
    /// product, unlike a real serial number.
    static func unavailableStatus(for product: DeviceCatalog.Product) -> DeviceStatus {
        DeviceStatus(
            name: RazerProducts.displayName(from: product.name),
            kind: product.kind,
            serialNumber: "\(product.vendorID):\(product.productID)",
            batteryPercent: nil,
            batteryUnavailable: true
        )
    }

    private static func unavailableResult(for identity: DeviceStatus) -> CachedDeviceStatus {
        var status = status(for: identity, batteryPercent: nil)
        status.batteryUnavailable = true
        return CachedDeviceStatus(status: status, batteryReadAt: .distantPast)
    }

    private static func discoverDevices(
        connectedProductIDs: Set<Int>
    ) -> (discovered: [DiscoveredDevice], unavailable: [DeviceStatus]) {
        let catalog = DeviceCatalog.bundled
        var results: [DiscoveredDevice] = []
        var unavailable: [DeviceStatus] = []
        var serials = Set<String>()

        for candidate in catalog.batteryCandidates where connectedProductIDs.contains(candidate.numericProductID ?? -1) {
            guard let receiverProductID = candidate.numericProductID,
                  let protocolID = candidate.batteryProtocol else { continue }
            let adapter = BatteryProtocolRegistry.adapter(for: protocolID)
            guard let transport = try? HIDTransport(productID: receiverProductID),
                  let scan = scanInterfaces(of: transport, adapter: adapter) else {
                unavailable.append(unavailableStatus(for: candidate))
                continue
            }

            let receiverDevices = scan.devices.filter { serials.insert($0.serialNumber).inserted }
            for (index, device) in receiverDevices.enumerated() {
                let productID = index < scan.productIDs.count ? scan.productIDs[index] : UInt16(receiverProductID)
                let fallback = productFallback(
                    for: productID, receiver: candidate, pairedCount: scan.productIDs.count
                )
                let hid = transport.metadata(for: productID)
                results.append(DiscoveredDevice(
                    receiverProductID: receiverProductID,
                    interfaceID: scan.interface.registryID,
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
        return (results, unavailable)
    }

    /// A single-device dongle may answer the paired-products query with a
    /// product ID that is not a catalog entry (for example its wired PID).
    /// Name it after the receiver rather than as an anonymous device.
    static func productFallback(
        for productID: UInt16, receiver: DeviceCatalog.Product, pairedCount: Int
    ) -> DeviceCatalog.Product {
        if let product = DeviceCatalog.bundled.product(for: productID) { return product }
        return pairedCount <= 1 ? receiver : RazerProducts.product(for: productID)
    }

    private struct InterfaceScan {
        let interface: HIDInterfaceInfo
        let productIDs: [UInt16]
        let devices: [(transactionID: UInt8, serialNumber: String)]
    }

    /// Return the first interface on which at least one endpoint answers the
    /// serial-number request.
    private static func scanInterfaces(
        of transport: HIDTransport, adapter: any BatteryProtocolAdapter
    ) -> InterfaceScan? {
        for attempts in discoveryAttemptPasses {
            for interface in transport.interfaces {
                guard (try? transport.activate(interface)) != nil else { continue }
                let pairedRequest = adapter.pairedProductsRequest()
                // Names depend on this list, so it always gets the full retry
                // budget; a receiver without the command rejects it at once.
                let productIDs = (try? adapter.parseProductIDs(
                    from: transport.exchange(pairedRequest, attempts: batteryAttempts), request: pairedRequest
                )) ?? []
                var devices: [(transactionID: UInt8, serialNumber: String)] = []
                for transactionID in adapter.candidateTransactionIDs {
                    let request = adapter.serialNumberRequest(transactionID: transactionID)
                    guard let serial = try? adapter.parseSerial(
                        from: transport.exchange(request, attempts: attempts), request: request
                    ), !devices.contains(where: { $0.serialNumber == serial }) else { continue }
                    devices.append((transactionID, serial))
                }
                if !devices.isEmpty {
                    return InterfaceScan(interface: interface, productIDs: productIDs, devices: devices)
                }
            }
        }
        return nil
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

/// Plain-text report a user can paste into a GitHub issue. It lists what
/// macOS reports for every Razer HID interface and the raw answers to the
/// read-only serial, battery and paired-product requests. Serial numbers are
/// never included. The report is intentionally not localized.
enum RazerDiagnostics {
    static func report(appVersion: String, systemVersion: String, inputMonitoringGranted: Bool) -> String {
        let catalog = DeviceCatalog.bundled
        let interfaces = HIDTransport.allInterfaces()
        var lines = [
            "RazerMon diagnostics",
            "App: \(appVersion)",
            "macOS: \(systemVersion)",
            "Input Monitoring: \(inputMonitoringGranted ? "granted" : "not granted")",
            "Catalog: \(catalog.source.name) \(catalog.source.revision.prefix(12)), \(catalog.products.count) products",
            "",
            "HID interfaces (vendor 1532): \(interfaces.count)",
        ]
        for interface in interfaces {
            lines.append(describe(interface, catalogProduct: catalog.product(for: UInt16(truncatingIfNeeded: interface.productID))))
        }

        let productIDs = Array(Set(interfaces.filter(\.canCarryRazerReport).map(\.productID))).sorted()
        lines.append("")
        lines.append("Protocol probe:")
        if productIDs.isEmpty { lines.append("- no interface declares a feature report of at least \(RazerReport.length) bytes") }
        for productID in productIDs {
            guard let transport = try? HIDTransport(productID: productID) else {
                lines.append("- \(productLabel(productID)): could not open")
                continue
            }
            let inCatalog = catalog.product(for: UInt16(truncatingIfNeeded: productID)) != nil
            for interface in transport.interfaces {
                lines.append("- \(productLabel(productID)) \(interfaceLabel(interface)):")
                do {
                    try transport.activate(interface)
                } catch {
                    lines.append("    open failed: \(error)")
                    continue
                }
                if inCatalog {
                    let request = RazerCommands.pairedProducts()
                    lines.append("    paired products: " + probe(transport, request))
                }
                for transactionID in RazerCommands.candidateTransactionIDs {
                    let serial = RazerCommands.serialNumber(transactionID: transactionID)
                    let battery = RazerCommands.battery(transactionID: transactionID)
                    lines.append(String(format: "    tid %02X serial: ", transactionID) + probe(transport, serial, redactPayload: true))
                    lines.append(String(format: "    tid %02X battery: ", transactionID) + probe(transport, battery))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func describe(_ interface: HIDInterfaceInfo, catalogProduct: DeviceCatalog.Product?) -> String {
        let usages = interface.usagePairs.map { hex($0.page, 4) + "/" + hex($0.usage, 4) }.joined(separator: ", ")
        let catalogText = catalogProduct.map {
            "catalog \"\($0.name)\" \($0.batteryProtocol?.rawValue ?? "no protocol")\($0.verified ? " verified" : "")"
        } ?? "not in catalog"
        return "- \(productLabel(interface.productID)) \"\(interface.product ?? "?")\" \(catalogText)\n"
            + "    transport \(interface.transport ?? "?"), \(interfaceLabel(interface)), usages [\(usages)]\n"
            + "    report sizes feature \(interface.maxFeatureReportSize) input \(interface.maxInputReportSize)"
            + " output \(interface.maxOutputReportSize), razer report \(interface.canCarryRazerReport ? "yes" : "no")"
    }

    /// Summarize one response. Serial-number payloads (and anything else when
    /// `redactPayload` is set) are reduced to a byte count so no serial leaks,
    /// even when a stale serial response answers a later request.
    static func describe(response: RazerReport, to request: RazerReport, redactPayload: Bool = false) -> String {
        var text = String(
            format: "status %02X tid %02X class %02X cmd %02X size %02X",
            response.status, response.transactionID, response.commandClass, response.commandID, response.dataSize
        )
        if !response.matches(request) { text += " (does not match request)" }
        let payload = response.bytes[8..<88]
        let isSerial = { (report: RazerReport) in report.commandClass == 0x00 && report.commandID == 0x82 }
        if redactPayload || isSerial(response) || isSerial(request) {
            text += " payload <\(payload.prefix { $0 != 0 }.count) bytes omitted>"
        } else {
            text += " args " + payload.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        return text
    }

    private static func probe(_ transport: HIDTransport, _ request: RazerReport, redactPayload: Bool = false) -> String {
        do {
            return describe(response: try transport.exchangeRaw(request), to: request, redactPayload: redactPayload)
        } catch {
            return "error: \(error)"
        }
    }

    private static func productLabel(_ productID: Int) -> String { "1532:" + hex(productID, 4) }

    private static func interfaceLabel(_ interface: HIDInterfaceInfo) -> String {
        "interface \(interface.interfaceNumber.map(String.init) ?? "?")"
            + " primary " + hex(interface.primaryUsagePage, 4) + "/" + hex(interface.primaryUsage, 4)
    }

    private static func hex(_ value: Int, _ width: Int) -> String {
        String(format: "%0\(width)X", value)
    }
}
