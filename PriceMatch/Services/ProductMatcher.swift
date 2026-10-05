import Foundation

/// Decides whether a store listing is the *same* item, not a similar one, a bundle or an accessory.
///
/// Two ways to match:
/// 1. **Model number** in the listing title (strongest), e.g. "DCD771C2".
/// 2. **Product name**, for brands whose listings don't show a model number (e.g. Ring):
///    same brand, every key word and spec ("2K", "20V", "2-Pack"), and no extra variant word
///    ("Plus", "Pro", "Wired") or used/accessory wording.
/// Either way, a listing priced under half or over double Home Depot's price is rejected.
enum ProductMatcher {
    enum Match {
        case model
        case name
    }

    /// What to search competitors for: brand + model when the model is a real manufacturer
    /// number, otherwise brand + the product's short name.
    static func query(for product: ProductInfo) -> String {
        if let model = product.model, isSearchableModel(model) {
            return [product.brand, model].compactMap { $0 }.joined(separator: " ")
        }
        let name = coreName(product.title)
        if let brand = product.brand, !normalize(name).hasPrefix(normalize(brand)) {
            return brand + " " + name
        }
        return name
    }

    /// Model numbers that identify this product, e.g. ["DCD771C2"].
    static func modelCodes(for product: ProductInfo) -> [String] {
        var result: [String] = []
        if let model = product.model, isSearchableModel(model) { result.append(normalize(model)) }
        for code in codes(in: product.title) where !result.contains(code) {
            result.append(code)
        }
        return result.filter { $0.count >= 4 }
    }

    /// How (if at all) a listing matches the product. `referencePrice` is Home Depot's price.
    static func match(_ listingTitle: String, price: Double? = nil, product: ProductInfo,
                      referencePrice: Double? = nil) -> Match? {
        if let price, let reference = referencePrice, reference > 0,
           price < reference * 0.5 || price > reference * 2 {
            return nil   // far too cheap or expensive: an accessory, part, multi-pack or different item
        }
        if looksUsedOrAccessory(listingTitle, brand: product.brand) { return nil }
        if hasDifferentColor(listingTitle, product: product) { return nil }
        if hasDifferentSize(listingTitle, product: product) { return nil }

        let wanted = modelCodes(for: product)
        let found = codes(in: listingTitle)
        // Naming a model we don't want means a different item or a bundle.
        guard found.allSatisfy(wanted.contains) else { return nil }

        let title = normalize(listingTitle)
        if wanted.contains(where: { title.contains($0) }) { return .model }
        return matchesByName(listingTitle, product: product) ? .name : nil
    }

    /// Convenience used where only yes/no matters.
    static func matches(_ listingTitle: String, product: ProductInfo) -> Bool {
        match(listingTitle, product: product) != nil
    }

    /// For stores Google has already grouped as the same product: only reject listings
    /// that name a *different* model (a bundle or variant). Many stores, like Lowe's,
    /// leave the model number out of the title entirely.
    static func hasNoOtherModel(_ listingTitle: String, product: ProductInfo) -> Bool {
        let wanted = modelCodes(for: product)
        return codes(in: listingTitle).allSatisfy(wanted.contains)
    }

    // MARK: - Name matching

    private static let variantWords: Set<String> = [
        "PLUS", "PRO", "MAX", "MINI", "ULTRA", "ELITE", "LITE", "XL", "XR", "WIRED", "BATTERY", "SOLAR",
        "KIT", "COMBO", "BUNDLE", "SET", "PACK", "BARE", "TOOL", "STARTER", "GEN", "CHIME", "CAM", "CAMERA",
    ]
    private static let stopWords: Set<String> = [
        "THE", "AND", "WITH", "FOR", "IN", "OF", "A", "AN", "NEW", "NEWEST", "MODEL", "LATEST", "BY", "TO", "ON",
    ]

    private static func matchesByName(_ listingTitle: String, product: ProductInfo) -> Bool {
        let listing = Set(words(listingTitle).map(singular))
        if let brand = product.brand {
            guard words(brand).map(singular).allSatisfy(listing.contains) else { return false }
        }
        let brandWords = Set(product.brand.map { words($0).map(singular) } ?? [])
        let core = words(coreName(product.title)).map(singular).filter { !brandWords.contains($0) }
        guard core.count >= 2 else { return false }

        // Like a cashier reading the label: every word of the product's name must be there
        // ("Clean Burst" ≠ "Deep Clean"). Long names may differ by one word.
        let missing = core.filter { !listing.contains($0) }.count
        guard missing == 0 || (core.count >= 6 && missing == 1) else { return false }

        // An extra variant word means a different version ("Doorbell 2K Plus" vs "Doorbell 2K").
        let productWords = Set(words(product.title).map(singular))
        guard listing.intersection(Set(variantWords.map(singular))).subtracting(productWords).isEmpty else { return false }

        // If Home Depot's item has a size, the listing must show the same size to be checkable.
        let wantedSizes = sizes(in: product.title)
        if !wantedSizes.isEmpty {
            let offered = sizes(in: listingTitle)
            let confirmed = wantedSizes.contains { group, mine in
                offered[group]?.contains { v in mine.contains { abs($0 - v) <= max(0.02 * $0, 0.01) } } ?? false
            }
            guard confirmed else { return false }
        }
        return true
    }

    /// "Doorbells" → "DOORBELL", "Loads" → "LOAD" (so plurals don't block a match).
    private static func singular(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("S") && !word.hasSuffix("SS") ? String(word.dropLast()) : word
    }

    // MARK: - Size and quantity (what a cashier reads on the label)

    /// Sizes stated in a title, grouped by kind: "174 fl oz, 174 Loads" → ["OZ": [174], "LOADS": [174]].
    static func sizes(in text: String) -> [String: [Double]] {
        let t = text.lowercased().replacingOccurrences(of: "&amp;", with: "&")
        var result: [String: [Double]] = [:]
        func add(_ group: String, _ value: Double) { result[group, default: []].append(value) }

        let units: [(String, String)] = [
            (#"fl\.?\s*oz|fluid\s*ounces?|ounces?|oz"#, "OZ"),
            (#"loads?"#, "LOADS"),
            (#"lbs?|pounds?"#, "LB"),
            (#"gal(?:lons?)?"#, "GAL"),
            (#"qt|quarts?"#, "QT"),
            (#"ml"#, "ML"),
            (#"liters?|litres?|l"#, "L"),
            (#"ct|count|pcs?|pieces?"#, "COUNT"),
            (#"pk|packs?"#, "PACK"),
            (#"ft|feet|foot"#, "FT"),
            (#"inch(?:es)?|in\."#, "IN"),
        ]
        for (unit, group) in units {
            let pattern = #"(\d+(?:\.\d+)?)\s*-?\s*(?:"# + unit + #")(?![a-z])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in regex.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                if let r = Range(m.range(at: 1), in: t), let v = Double(t[r]) { add(group, v) }
            }
        }
        // "(2 pack)", "case of 4", "set of 3", "4 units", "pack of 6"
        for pattern in [#"(?:case|set|pack|box)\s+of\s+(\d+)"#, #"(\d+)\s*units?\b"#, #"\((\d+)\s*pack\)"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in regex.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                if let r = Range(m.range(at: 1), in: t), let v = Double(t[r]) { add("PACK", v) }
            }
        }
        return result
    }

    /// Both titles state a size of the same kind and none of the numbers agree (within 2%),
    /// or the listing is a multi-pack of a single item.
    static func hasDifferentSize(_ listingTitle: String, product: ProductInfo) -> Bool {
        let wanted = sizes(in: product.title)
        let offered = sizes(in: listingTitle)
        for (group, values) in offered {
            guard let mine = wanted[group] else {
                // A 2-pack / case of 4 when Home Depot sells one.
                if group == "PACK", values.contains(where: { $0 > 1 }) { return true }
                continue
            }
            let agrees = values.contains { v in mine.contains { abs($0 - v) <= max(0.02 * $0, 0.01) } }
            if !agrees { return true }
        }
        return false
    }

    private static let colorWords: Set<String> = [
        "BLACK", "WHITE", "GRAY", "GREY", "SILVER", "RED", "BLUE", "GREEN", "YELLOW", "ORANGE", "PINK",
        "PURPLE", "BROWN", "TAN", "BEIGE", "IVORY", "ALMOND", "BRONZE", "NICKEL", "CHROME", "BRASS",
        "GOLD", "COPPER", "STAINLESS", "NATURAL", "CLEAR",
    ]

    /// Both name a color/finish and they share none: a different variant ("Satin Nickel" vs "Oil-Rubbed Bronze").
    private static func hasDifferentColor(_ listingTitle: String, product: ProductInfo) -> Bool {
        let wanted = Set(words(product.title)).intersection(colorWords)
        let offered = Set(words(listingTitle)).intersection(colorWords)
        return !wanted.isEmpty && !offered.isEmpty && wanted.isDisjoint(with: offered)
    }

    private static func looksUsedOrAccessory(_ title: String, brand: String?) -> Bool {
        let t = title.lowercased()
        let flags = ["used", "refurbished", "renewed", "like-new", "like new", "pre-owned", "open box",
                     "parts only", "for parts", "replacement for", "compatible with", "faceplate", "case for", "cover for"]
        if flags.contains(where: { t.contains($0) }) { return true }
        if let brand, t.contains("for \(brand.lowercased())") { return true }   // "Mount for Ring Doorbell"
        return false
    }

    /// The product's short name: the title before marketing details.
    /// "Battery Doorbell 2K - Retinal 2K with Wide-Angle Video" → "Battery Doorbell 2K"
    static func coreName(_ title: String) -> String {
        var name = title.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        for separator in [" - ", " – ", " — ", ",", " | ", " with "] {
            if let range = name.range(of: separator) {
                let head = String(name[..<range.lowerBound])
                if head.split(separator: " ").count >= 2 { name = head }
            }
        }
        return name.split(separator: " ").prefix(8).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    /// Manufacturer model numbers: letters and digits mixed ("DCD771C2"), or a long digit-only
    /// number ("99160-022"). Amazon IDs ("B0…") and barcode-length numbers never appear in titles.
    private static func isSearchableModel(_ model: String) -> Bool {
        let m = normalize(model)
        if m.count == 10 && m.hasPrefix("B0") { return false }               // Amazon ID
        if m.allSatisfy(\.isNumber) {
            return (6...11).contains(m.count)                                  // "99160-022" yes; barcodes no
        }
        return m.count >= 4 && m.contains(where: \.isLetter) && m.contains(where: \.isNumber)
    }

    /// Model-number-looking words: letters and digits mixed, 5+ characters,
    /// not a measurement ("12INCH", "100PIECE", "20VMAX") and not an Amazon ID ("B0...").
    static func codes(in text: String) -> [String] {
        let measurement = #"^[0-9.]+[A-Z]+$"#
        var result: [String] = []
        for word in text.split(whereSeparator: { " ()[],/&+|:;*".contains($0) }) {
            let code = normalize(String(word))
            guard code.count >= 5,
                  code.contains(where: \.isLetter),
                  code.contains(where: \.isNumber),
                  !(code.count == 10 && code.hasPrefix("B0")),
                  code.range(of: measurement, options: .regularExpression) == nil,
                  !result.contains(code)
            else { continue }
            result.append(code)
        }
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Upper-case words with hyphens joined ("2-Pack" → "2PACK", "Wide-Angle" → "WIDEANGLE").
    private static func words(_ s: String) -> [String] {
        s.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stopWords.contains($0) && ($0.count >= 2 || $0.contains(where: \.isNumber)) }
    }
}
