import Foundation

protocol BatteryProtocolAdapter {
    var identifier: BatteryProtocolID { get }
    var candidateTransactionIDs: [UInt8] { get }

    func pairedProductsRequest() -> RazerReport
    func serialNumberRequest(transactionID: UInt8) -> RazerReport
    func batteryRequest(transactionID: UInt8) -> RazerReport
    func parseProductIDs(from response: RazerReport, request: RazerReport) throws -> [UInt16]
    func parseSerial(from response: RazerReport, request: RazerReport) throws -> String
    func parseBattery(from response: RazerReport, request: RazerReport) throws -> UInt8
}

struct HyperSpeedV1Adapter: BatteryProtocolAdapter {
    let identifier = BatteryProtocolID.hyperSpeedV1
    let candidateTransactionIDs = RazerCommands.candidateTransactionIDs

    func pairedProductsRequest() -> RazerReport { RazerCommands.pairedProducts() }
    func serialNumberRequest(transactionID: UInt8) -> RazerReport {
        RazerCommands.serialNumber(transactionID: transactionID)
    }
    func batteryRequest(transactionID: UInt8) -> RazerReport {
        RazerCommands.battery(transactionID: transactionID)
    }
    func parseProductIDs(from response: RazerReport, request: RazerReport) throws -> [UInt16] {
        try RazerCommands.parseProductIDs(from: response, request: request)
    }
    func parseSerial(from response: RazerReport, request: RazerReport) throws -> String {
        try RazerCommands.parseSerial(from: response, request: request)
    }
    func parseBattery(from response: RazerReport, request: RazerReport) throws -> UInt8 {
        try RazerCommands.parseBattery(from: response, request: request)
    }
}

enum BatteryProtocolRegistry {
    static func adapter(for identifier: BatteryProtocolID) -> any BatteryProtocolAdapter {
        switch identifier {
        case .hyperSpeedV1: HyperSpeedV1Adapter()
        }
    }
}
