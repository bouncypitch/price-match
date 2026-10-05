import Foundation

/// Decides which Google Shopping sellers are US retailers Home Depot would normally price match.
/// This is a convenience only — the cashier should still follow the current store policy.
enum CompetitorFilter {
    struct Retailer {
        let name: String
        let matches: [String]   // lowercased prefixes of the Google Shopping "source"
        let eligible: Bool
    }

    static let retailers: [Retailer] = [
        Retailer(name: "Lowe's", matches: ["lowe's", "lowes"], eligible: true),
        Retailer(name: "Menards", matches: ["menards"], eligible: true),
        Retailer(name: "Walmart", matches: ["walmart"], eligible: true),
        Retailer(name: "Amazon", matches: ["amazon.com", "amazon"], eligible: true),
        Retailer(name: "Ace Hardware", matches: ["ace hardware", "acehardware"], eligible: true),
        Retailer(name: "Tractor Supply", matches: ["tractor supply"], eligible: true),
        Retailer(name: "Target", matches: ["target"], eligible: true),
        Retailer(name: "Best Buy", matches: ["best buy", "bestbuy"], eligible: true),
        Retailer(name: "Harbor Freight", matches: ["harbor freight"], eligible: true),
        Retailer(name: "Northern Tool", matches: ["northern tool"], eligible: true),
        Retailer(name: "True Value", matches: ["true value"], eligible: true),
        Retailer(name: "Do it Best", matches: ["do it best", "doitbest"], eligible: true),
        Retailer(name: "Sears", matches: ["sears"], eligible: true),
        Retailer(name: "Kohl's", matches: ["kohl's", "kohls"], eligible: true),
        Retailer(name: "Wayfair", matches: ["wayfair"], eligible: true),
        // Warehouse clubs need a membership, so they usually don't qualify.
        Retailer(name: "Costco", matches: ["costco"], eligible: false),
        Retailer(name: "Sam's Club", matches: ["sam's club", "sams club"], eligible: false),
        Retailer(name: "BJ's", matches: ["bj's", "bjs"], eligible: false),
    ]

    static func isHomeDepot(_ source: String) -> Bool {
        let s = source.lowercased()
        return s.hasPrefix("home depot") || s.hasPrefix("the home depot") || s.hasPrefix("homedepot")
    }

    /// The known retailer behind a seller name, or nil for marketplaces / unknown sellers.
    static func retailer(for source: String) -> Retailer? {
        let s = source.lowercased().trimmingCharacters(in: .whitespaces)
        // "Walmart - SomeSeller" / "eBay - seller" are marketplace sellers, not the store itself.
        if s.contains(" - ") { return nil }
        return retailers.first { r in
            r.matches.contains { key in
                s == key || s.hasPrefix(key + " ") || s.hasPrefix(key + ".") || s == key + ".com"
            }
        }
    }

    /// Marketplaces and resale sites Home Depot doesn't match.
    private static let marketplaces = ["ebay", "etsy", "mercari", "poshmark", "aliexpress", "temu", "facebook", "offerup", "craigslist", "whatnot"]

    /// Display name and kind of store for a Google Shopping seller name.
    static func classify(_ source: String) -> (name: String, kind: Offer.Kind) {
        if let retailer = retailer(for: source) {
            return (retailer.name, retailer.eligible ? .majorStore : .excluded)
        }
        let s = source.lowercased()
        if s.contains(" - ") || marketplaces.contains(where: { s.hasPrefix($0) }) {
            return (source, .excluded)
        }
        return (source, .otherStore)
    }

    /// Turns Google's delivery/pickup text into one short, plain sentence.
    static func availability(delivery: String?, notes: [String]) -> String {
        let all = ([delivery ?? ""] + notes).joined(separator: " ").lowercased()
        if all.contains("pick up") || all.contains("pickup") || all.contains("in store") || all.contains("nearby") {
            return "Pick up at a store near you"
        }
        let text = delivery ?? notes.first { $0.lowercased().contains("deliver") }
        if let text, !text.isEmpty {
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        if notes.contains(where: { $0.lowercased().contains("in stock") }) {
            return "In stock online"
        }
        return "Online · delivery time not shown"
    }
}
