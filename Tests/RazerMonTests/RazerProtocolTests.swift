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
        XCTAssertEqual(RazerProducts.name(for: 0x00B7), "DeathAdder V3 Pro Wireless")
        XCTAssertEqual(RazerProducts.name(for: 0x0290), "DeathStalker V2 Pro Wireless")
        XCTAssertEqual(RazerProducts.name(for: 0x1234), "Device (1532:1234)")
        XCTAssertEqual(RazerProducts.displayName(from: "Future Model X"), "Future Model X")
        XCTAssertEqual(RazerProducts.product(for: 0x00B7).kind, .mouse)
        XCTAssertEqual(RazerProducts.product(for: 0x0290).kind, .keyboard)
        XCTAssertEqual(RazerProducts.product(for: 0x1234).kind, .unknown)
    }
}
