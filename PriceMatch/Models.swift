import Foundation

/// One store's price for the scanned item, ready to show on a card.
struct Offer: Identifiable, Hashable {
    enum Kind: Int, Hashable {
        case majorStore = 0      // known US retailer Home Depot normally matches
        case otherStore = 1      // real store, but the cashier should check it qualifies
        case excluded = 2        // marketplace seller, eBay, warehouse club
    }

    let id = UUID()
    let storeName: String
    let price: Double            // US dollars
    let availability: String     // plain words, e.g. "Pick up at a store near you"
    let link: URL?
    let kind: Kind
    var matchedByName = false   // no model number in the listing; matched by name and specs

    var isEligible: Bool { kind == .majorStore }

    /// Short warning shown on the card, or nil for major stores.
    var note: String? {
        switch kind {
        case .majorStore: return matchedByName ? "Check it's the same item" : nil
        case .otherStore: return "Check if this store qualifies"
        case .excluded: return "Usually can't be matched"
        }
    }
}

struct ProductInfo: Hashable {
    var title: String
    var imageURL: URL?
    var brand: String?
    var model: String?
}

struct LookupResult: Hashable {
    let barcode: String
    let product: ProductInfo
    let homeDepotPrice: Double?
    let offers: [Offer]          // sorted, cheapest first

    var cheapest: Offer? { offers.first(where: \.isEligible) }
}

enum LookupError: LocalizedError {
    case notFound
    case tooManyLookups
    case notSetUp
    case badKey
    case outOfSearches
    case busy
    case offline
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Couldn't find this item online. Try scanning again, or try another barcode on the box."
        case .tooManyLookups:
            return "Too many items looked up today. Please try again tomorrow."
        case .notSetUp:
            return "This phone isn't set up yet. Ask a manager to add the price service key in Settings."
        case .badKey:
            return "The price service key isn't working. Ask a manager to check Settings."
        case .busy:
            return "Too many lookups right now. Please wait a minute and try again."
        case .outOfSearches:
            return "The price service has used up its searches for this month. Ask a manager."
        case .offline:
            return "No internet connection. Check Wi-Fi and try again."
        case .other:
            return "Something went wrong looking up prices. Please try again."
        }
    }
}

enum Barcode {
    /// Keeps digits only, and turns a 13-digit EAN that starts with 0 into a 12-digit UPC.
    static func normalize(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 13, digits.hasPrefix("0") {
            return String(digits.dropFirst())
        }
        return digits
    }
}

enum Money {
    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

/// True when prices can be looked up: a key server is built in, or a key was entered in Setup.
var isPriceServiceSetUp: Bool {
    PriceServer.current != nil || KeychainStore.string(for: SettingsKeys.apiKey) != nil
}

enum SettingsKeys {
    static let apiKey = "serpapi-key"          // Keychain account
    static let location = "storeLocation"      // UserDefaults
    static let maxResults = "maxResults"
    static let showOthers = "showOtherSellers"
}
