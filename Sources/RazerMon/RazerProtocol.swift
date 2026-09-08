import Foundation

struct RazerReport: Equatable {
    static let length = 90

    var bytes: [UInt8]

    init(transactionID: UInt8, dataSize: UInt8, commandClass: UInt8, commandID: UInt8, data: [UInt8] = []) {
        precondition(data.count <= 80)
        var bytes = [UInt8](repeating: 0, count: Self.length)
        bytes[1] = transactionID
        bytes[5] = dataSize
        bytes[6] = commandClass
        bytes[7] = commandID
        for (index, value) in data.enumerated() {
            bytes[8 + index] = value
        }
        bytes[88] = Self.checksum(bytes)
        self.bytes = bytes
    }

    init(validating bytes: [UInt8]) throws {
        guard bytes.count == Self.length else { throw ProtocolError.invalidLength(bytes.count) }
        guard bytes[88] == Self.checksum(bytes) else { throw ProtocolError.invalidChecksum }
        self.bytes = bytes
    }

    var transactionID: UInt8 { bytes[1] }
    var commandClass: UInt8 { bytes[6] }
    var commandID: UInt8 { bytes[7] }

    func matches(_ request: RazerReport) -> Bool {
        transactionID == request.transactionID
            && commandClass == request.commandClass
            && commandID == request.commandID
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes[2...87].reduce(0, ^)
    }
}

enum ProtocolError: Error, CustomStringConvertible {
    case invalidLength(Int)
    case invalidChecksum
    case staleResponse
    case malformedResponse(String)

    var description: String {
        switch self {
        case .invalidLength(let length): return L10n.format("error.protocol.invalid_length", length)
        case .invalidChecksum: return L10n.text("error.protocol.invalid_checksum")
        case .staleResponse: return L10n.text("error.protocol.stale_response")
        case .malformedResponse(let detail): return detail
        }
    }
}

struct PairedDevice: Equatable {
    let transactionID: UInt8
    let serialNumber: String
    let batteryRaw: UInt8

    var batteryPercent: Int {
        Int((Double(batteryRaw) * 100.0 / 255.0).rounded())
    }
}

enum DeviceKind: String, Codable, Equatable {
    case mouse
    case keyboard
    case unknown
}

struct DeviceStatus: Codable, Equatable {
    let name: String
    let kind: DeviceKind
    let serialNumber: String
    let batteryPercent: Int?
}

struct CachedDeviceStatus: Equatable {
    let status: DeviceStatus
    let batteryReadAt: Date

    func hasFreshBattery(at date: Date, maximumAge: TimeInterval) -> Bool {
        date.timeIntervalSince(batteryReadAt) < maximumAge
    }
}


enum RazerCommands {
    static let candidateTransactionIDs = stride(from: 0x1F, through: 0xFF, by: 0x20).map(UInt8.init)

    static func serialNumber(transactionID: UInt8) -> RazerReport {
        RazerReport(transactionID: transactionID, dataSize: 2, commandClass: 0x00, commandID: 0x82)
    }

    static func battery(transactionID: UInt8) -> RazerReport {
        RazerReport(transactionID: transactionID, dataSize: 2, commandClass: 0x07, commandID: 0x80)
    }

    static func pairedProducts() -> RazerReport {
        RazerReport(transactionID: 0x0C, dataSize: 7, commandClass: 0x00, commandID: 0xBF)
    }

    static func parseSerial(from response: RazerReport, request: RazerReport) throws -> String {
        guard response.matches(request) else { throw ProtocolError.staleResponse }
        let payload = response.bytes[8..<88]
        let serialBytes = payload.prefix { $0 != 0 }
        guard !serialBytes.isEmpty, let serial = String(bytes: serialBytes, encoding: .ascii) else {
            throw ProtocolError.malformedResponse(L10n.text("error.protocol.missing_serial"))
        }
        return serial
    }

    static func parseBattery(from response: RazerReport, request: RazerReport) throws -> UInt8 {
        guard response.matches(request) else { throw ProtocolError.staleResponse }
        return response.bytes[9]
    }

    static func parseProductIDs(from response: RazerReport, request: RazerReport) throws -> [UInt16] {
        guard response.matches(request) else { throw ProtocolError.staleResponse }
        let count = Int(response.bytes[8])
        guard count > 0 else { return [] }
        var productIDs: [UInt16] = []
        for index in 0..<count {
            let offset = 10 + index * 3
            guard offset + 1 < 88 else { break }
            productIDs.append(UInt16(response.bytes[offset]) << 8 | UInt16(response.bytes[offset + 1]))
        }
        return productIDs
    }
}

enum RazerProducts {
    typealias Product = DeviceCatalog.Product

    static func product(for productID: UInt16) -> Product {
        if let product = DeviceCatalog.bundled.product(for: productID) { return product }
        return Product(
            vendorID: "1532", productID: String(format: "%04X", productID),
            name: "Razer Device (1532:\(String(format: "%04X", productID)))",
            kind: .unknown, batteryProtocol: nil, verified: false
        )
    }

    static func name(for productID: UInt16) -> String {
        displayName(from: product(for: productID).name)
    }

    /// Keep the model name intact and apply one rule to every current and
    /// future device: the menu already represents Razer hardware, so omit the
    /// redundant vendor prefix.
    static func displayName(from canonicalName: String) -> String {
        canonicalName.hasPrefix("Razer ") ? String(canonicalName.dropFirst("Razer ".count)) : canonicalName
    }
}
