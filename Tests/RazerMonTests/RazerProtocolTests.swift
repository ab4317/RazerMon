import XCTest
@testable import RazerMon

final class RazerProtocolTests: XCTestCase {
    func testTransactionScanIncludesKnownEndpoints() {
        XCTAssertEqual(RazerCommands.candidateTransactionIDs.first, 0x1F)
        XCTAssertEqual(RazerCommands.candidateTransactionIDs.last, 0xFF)
        XCTAssertEqual(RazerCommands.candidateTransactionIDs.count, 8)
    }

    func testRequestLayoutAndChecksum() {
        let report = RazerCommands.battery(transactionID: 0x1F)
        XCTAssertEqual(report.bytes.count, 90)
        XCTAssertEqual(report.bytes[1], 0x1F)
        XCTAssertEqual(report.bytes[5], 2)
        XCTAssertEqual(report.bytes[6], 0x07)
        XCTAssertEqual(report.bytes[7], 0x80)
        XCTAssertEqual(report.bytes[88], RazerReport.checksum(report.bytes))
    }

    func testBatteryConversion() {
        XCTAssertEqual(PairedDevice(transactionID: 0x1F, serialNumber: "A", batteryRaw: 102).batteryPercent, 40)
        XCTAssertEqual(PairedDevice(transactionID: 0xFF, serialNumber: "B", batteryRaw: 153).batteryPercent, 60)
    }

    func testBatteryCacheFreshnessIsPerDevice() {
        let now = Date(timeIntervalSince1970: 1_000)
        let cached = CachedDeviceStatus(
            status: DeviceStatus(name: "Mouse", kind: .mouse, serialNumber: "A", batteryPercent: 80),
            batteryReadAt: now.addingTimeInterval(-299)
        )
        XCTAssertTrue(cached.hasFreshBattery(at: now, maximumAge: 300))
        XCTAssertFalse(cached.hasFreshBattery(at: now.addingTimeInterval(2), maximumAge: 300))
    }

    func testRejectsCachedResponseFromAnotherTransaction() throws {
        let request = RazerCommands.battery(transactionID: 0x3F)
        var stale = RazerCommands.battery(transactionID: 0x1F).bytes
        stale[9] = 102
        stale[88] = RazerReport.checksum(stale)
        let response = try RazerReport(validating: stale)
        XCTAssertThrowsError(try RazerCommands.parseBattery(from: response, request: request))
    }

    func testPairedProductParsing() throws {
        let request = RazerCommands.pairedProducts()
        var bytes = request.bytes
        bytes[8] = 2
        bytes[9] = 1
        bytes[10] = 0x00
        bytes[11] = 0xB7
        bytes[12] = 1
        bytes[13] = 0x02
        bytes[14] = 0x90
        bytes[88] = RazerReport.checksum(bytes)
        let response = try RazerReport(validating: bytes)
        XCTAssertEqual(try RazerCommands.parseProductIDs(from: response, request: request), [0x00B7, 0x0290])
    }

    func testProductNamesOnlyDropRedundantVendorPrefix() {
        XCTAssertEqual(RazerProducts.name(for: 0x00B7), "DeathAdder V3 Pro (Wireless)")
        XCTAssertEqual(RazerProducts.name(for: 0x0290), "DeathStalker V2 Pro (Wireless)")
        XCTAssertEqual(RazerProducts.name(for: 0x1234), "Device (1532:1234)")
        XCTAssertEqual(RazerProducts.displayName(from: "Future Model X"), "Future Model X")
        XCTAssertEqual(RazerProducts.product(for: 0x00B7).kind, .mouse)
        XCTAssertEqual(RazerProducts.product(for: 0x0290).kind, .keyboard)
        XCTAssertEqual(RazerProducts.product(for: 0x1234).kind, .unknown)
    }

    func testBundledCatalogIncludesOpenRazerDevicesAndVerifiedHardware() {
        let catalog = DeviceCatalog.bundled
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.products.count, 42)
        XCTAssertTrue(catalog.products.allSatisfy { $0.batteryProtocol != nil })
        XCTAssertEqual(catalog.product(for: 0x0083)?.name, "Razer Basilisk X HyperSpeed")
        XCTAssertEqual(catalog.product(for: 0x025C)?.kind, .keyboard)
        XCTAssertEqual(catalog.product(for: 0x00B7)?.verified, true)
        XCTAssertEqual(catalog.product(for: 0x0290)?.verified, true)
        XCTAssertEqual(catalog.product(for: 0x0094)?.verified, true)
        XCTAssertTrue(catalog.batteryCandidates.contains { $0.numericProductID == 0x00B7 })
    }

    func testSerialRequestUsesOpenRazerDataSize() {
        let report = RazerCommands.serialNumber(transactionID: 0x1F)
        XCTAssertEqual(report.dataSize, 0x16)
        XCTAssertEqual(report.commandClass, 0x00)
        XCTAssertEqual(report.commandID, 0x82)
        XCTAssertEqual(report.bytes[88], RazerReport.checksum(report.bytes))
    }

    func testResponseStatusHandlingRetriesBusyAndFailures() throws {
        XCTAssertEqual(ResponseDisposition(status: RazerStatus.successful), .accept)
        // A receiver read too early answers busy with zeroed arguments.
        XCTAssertEqual(ResponseDisposition(status: RazerStatus.busy), .retry(0x01))
        XCTAssertEqual(ResponseDisposition(status: RazerStatus.notSupported), .reject(0x05))
        XCTAssertEqual(ResponseDisposition(status: RazerStatus.failure), .retry(0x03))
        XCTAssertEqual(ResponseDisposition(status: RazerStatus.timeout), .retry(0x04))
        XCTAssertEqual(ResponseDisposition(status: 0x00), .retry(0x00))

        var bytes = RazerCommands.battery(transactionID: 0x1F).bytes
        bytes[0] = RazerStatus.timeout
        bytes[88] = RazerReport.checksum(bytes)
        XCTAssertEqual(try RazerReport(validating: bytes).status, RazerStatus.timeout)
    }

    func testProTypeUltraWirelessUsesVerifiedKeyboardPath() {
        let catalog = DeviceCatalog.bundled
        let product = catalog.product(for: 0x027B)
        XCTAssertEqual(product?.name, "Razer Pro Type Ultra (Wireless)")
        XCTAssertEqual(product?.kind, .keyboard)
        XCTAssertEqual(product?.batteryProtocol, .hyperSpeedV1)
        XCTAssertEqual(product?.verified, false)
        XCTAssertTrue(catalog.batteryCandidates.contains { $0.numericProductID == 0x027B })
        // OpenRazer PR #2888 addresses it with transaction ID 0x9F.
        XCTAssertTrue(RazerCommands.candidateTransactionIDs.contains(0x9F))
    }

    func testDeathAdderV3HyperSpeedIsABatteryCandidate() {
        let product = DeviceCatalog.bundled.product(for: 0x00C5)
        XCTAssertEqual(product?.kind, .mouse)
        XCTAssertEqual(product?.batteryProtocol, .hyperSpeedV1)
        XCTAssertTrue(DeviceCatalog.bundled.batteryCandidates.contains { $0.numericProductID == 0x00C5 })
    }

    func testInterfaceProbeOrderIsDeterministic() {
        func interface(_ id: UInt64, number: Int?, page: Int, usage: Int) -> HIDInterfaceInfo {
            HIDInterfaceInfo(
                registryID: id, productID: 0x00C5, product: nil, transport: "USB", interfaceNumber: number,
                primaryUsagePage: page, primaryUsage: usage, usagePairs: [],
                maxFeatureReportSize: 90, maxInputReportSize: 8, maxOutputReportSize: 0
            )
        }
        let vendor = interface(1, number: 0, page: 0xFF00, usage: 0x01)
        let keyboard = interface(2, number: 1, page: 0x01, usage: 0x06)
        let mouse = interface(3, number: 0, page: 0x01, usage: 0x02)
        let unnumbered = interface(4, number: nil, page: 0x01, usage: 0x02)
        let sorted = [unnumbered, vendor, keyboard, mouse].sorted(by: HIDInterfaceInfo.probeOrder)
        XCTAssertEqual(sorted.map(\.registryID), [3, 2, 4, 1])
        XCTAssertTrue(mouse.canCarryRazerReport)
    }

    func testUnavailableDeviceStaysVisibleWithUniqueKey() throws {
        let catalog = DeviceCatalog.bundled
        let mouse = try XCTUnwrap(catalog.product(for: 0x00C5))
        let keyboard = try XCTUnwrap(catalog.product(for: 0x027B))
        let mouseStatus = RazerMonitor.unavailableStatus(for: mouse)
        XCTAssertEqual(mouseStatus.name, "DeathAdder V3 HyperSpeed (Wireless)")
        XCTAssertEqual(mouseStatus.kind, .mouse)
        XCTAssertTrue(mouseStatus.batteryUnavailable)
        XCTAssertNil(mouseStatus.batteryPercent)
        XCTAssertNotEqual(mouseStatus.serialNumber, RazerMonitor.unavailableStatus(for: keyboard).serialNumber)
    }

    func testUnknownPairedProductFallsBackToSingleDeviceReceiver() throws {
        let receiver = try XCTUnwrap(DeviceCatalog.bundled.product(for: 0x00C5))
        XCTAssertEqual(RazerMonitor.productFallback(for: 0x00C4, receiver: receiver, pairedCount: 1), receiver)
        XCTAssertEqual(RazerMonitor.productFallback(for: 0x00C4, receiver: receiver, pairedCount: 0), receiver)
        XCTAssertEqual(RazerMonitor.productFallback(for: 0x00C4, receiver: receiver, pairedCount: 2).kind, .unknown)
        XCTAssertEqual(RazerMonitor.productFallback(for: 0x00B7, receiver: receiver, pairedCount: 1).productID, "00B7")
    }

    func testDiagnosticsNeverIncludeSerialNumbers() throws {
        let serialRequest = RazerCommands.serialNumber(transactionID: 0x1F)
        var bytes = serialRequest.bytes
        bytes[0] = RazerStatus.successful
        let serial = Array("PM1234567890".utf8)
        for (index, byte) in serial.enumerated() { bytes[8 + index] = byte }
        bytes[88] = RazerReport.checksum(bytes)
        let serialResponse = try RazerReport(validating: bytes)

        let direct = RazerDiagnostics.describe(response: serialResponse, to: serialRequest)
        XCTAssertFalse(direct.contains("50 4D"))
        XCTAssertTrue(direct.contains("<12 bytes omitted>"))
        // A stale serial response answering a battery request is redacted too.
        let stale = RazerDiagnostics.describe(response: serialResponse, to: RazerCommands.battery(transactionID: 0x1F))
        XCTAssertFalse(stale.contains("50 4D"))
        XCTAssertTrue(stale.contains("does not match request"))

        let batteryRequest = RazerCommands.battery(transactionID: 0x1F)
        var batteryBytes = batteryRequest.bytes
        batteryBytes[0] = RazerStatus.successful
        batteryBytes[9] = 0xB2
        batteryBytes[88] = RazerReport.checksum(batteryBytes)
        let battery = RazerDiagnostics.describe(response: try RazerReport(validating: batteryBytes), to: batteryRequest)
        XCTAssertEqual(battery, "status 02 tid 1F class 07 cmd 80 size 02 args 00 B2 00 00 00 00 00 00")
    }
}
