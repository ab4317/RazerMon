import Foundation

enum BatteryProtocolID: String, Codable {
    case hyperSpeedV1 = "hyperspeed-v1"
}

struct DeviceCatalog: Decodable {
    struct Source: Decodable {
        let name: String
        let url: String
        let revision: String
        let note: String
    }

    struct Product: Decodable, Equatable {
        let vendorID: String
        let productID: String
        let name: String
        let kind: DeviceKind
        let batteryProtocol: BatteryProtocolID?
        let verified: Bool

        var numericVendorID: Int? { Int(vendorID, radix: 16) }
        var numericProductID: Int? { Int(productID, radix: 16) }
    }

    let schemaVersion: Int
    let source: Source
    let products: [Product]

    private var productsByID: [UInt16: Product] {
        Dictionary(products.compactMap { product in
            guard product.numericVendorID == 0x1532,
                  let productID = product.numericProductID,
                  let id = UInt16(exactly: productID) else { return nil }
            return (id, product)
        }, uniquingKeysWith: { current, candidate in
            candidate.verified ? candidate : current
        })
    }

    var batteryCandidates: [Product] {
        products.filter {
            $0.numericVendorID == 0x1532 && $0.numericProductID != nil && $0.batteryProtocol != nil
        }.sorted {
            if $0.verified != $1.verified { return $0.verified }
            return ($0.numericProductID ?? 0) < ($1.numericProductID ?? 0)
        }
    }

    func product(for productID: UInt16) -> Product? {
        productsByID[productID]
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    private init(schemaVersion: Int, source: Source, products: [Product]) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.products = products
    }

    static let bundled: DeviceCatalog = {
        guard let url = Bundle.main.url(forResource: "DeviceCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? DeviceCatalog(data: data),
              catalog.schemaVersion == 1 else {
            return fallback
        }
        return catalog
    }()

    private static let fallback = DeviceCatalog(
        schemaVersion: 1,
        source: Source(
            name: "Built-in fallback",
            url: "",
            revision: "",
            note: "Used only when the bundled catalog cannot be loaded."
        ),
        products: [
            Product(
                vendorID: "1532", productID: "00B7",
                name: "Razer DeathAdder V3 Pro (Wireless)", kind: .mouse,
                batteryProtocol: .hyperSpeedV1, verified: true
            ),
            Product(
                vendorID: "1532", productID: "0290",
                name: "Razer DeathStalker V2 Pro (Wireless)", kind: .keyboard,
                batteryProtocol: .hyperSpeedV1, verified: true
            ),
            Product(
                vendorID: "1532", productID: "0094",
                name: "Razer Orochi V2 (Receiver)", kind: .mouse,
                batteryProtocol: .hyperSpeedV1, verified: true
            ),
        ]
    )
}
