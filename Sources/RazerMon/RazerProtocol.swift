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
        case .invalidLength(let length): return "expected a 90-byte report, got \(length)"
        case .invalidChecksum: return "report checksum does not match"
        case .staleResponse: return "device returned a stale or unrelated response"
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
    let batteryPercent: Int
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
            throw ProtocolError.malformedResponse("serial-number response has no ASCII serial")
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
    struct Product: Equatable {
        let name: String
        let kind: DeviceKind
    }

    /// The receiver reports product IDs but not HID device categories, so the
    /// category belongs in this small, extendable catalog. Unknown products
    /// continue to work and simply use a generic peripheral icon.
    private static let catalog: [UInt16: Product] = [
        0x00B7: Product(name: "Razer DeathAdder V3 Pro Wireless", kind: .mouse),
        0x0290: Product(name: "Razer DeathStalker V2 Pro Wireless", kind: .keyboard),
    ]

    static func product(for productID: UInt16) -> Product {
        let product = catalog[productID] ?? Product(
            name: String(format: "Razer Device (1532:%04X)", productID),
            kind: .unknown
        )
        return Product(name: displayName(from: product.name), kind: product.kind)
    }

    static func name(for productID: UInt16) -> String {
        product(for: productID).name
    }

    /// Keep the model name intact and apply one rule to every current and
    /// future device: the menu already represents Razer hardware, so omit the
    /// redundant vendor prefix.
    static func displayName(from canonicalName: String) -> String {
        canonicalName.hasPrefix("Razer ") ? String(canonicalName.dropFirst("Razer ".count)) : canonicalName
    }
}
