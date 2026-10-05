import Foundation

/// Makes sure a store listing is the *same* item, not a similar one or a bundle.
enum ProductMatcher {
    /// What to search competitors for, e.g. "DEWALT DCD771C2".
    static func query(for product: ProductInfo) -> String {
        if let model = product.model {
            return [product.brand, model].compactMap { $0 }.joined(separator: " ")
        }
        // No model on file: use the title without bracketed codes, kept short.
        let cleaned = product.title.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        return cleaned.split(separator: " ").prefix(10).joined(separator: " ")
    }

    /// Model numbers that identify this product, e.g. ["DCD771C2"].
    static func modelCodes(for product: ProductInfo) -> [String] {
        var result: [String] = []
        if let model = product.model { result.append(normalize(model)) }
        for code in codes(in: product.title) where !result.contains(code) {
            result.append(code)
        }
        return result.filter { $0.count >= 4 }
    }

    /// True only if the listing names this exact model and no other model
    /// (a second model number means a bundle like "drill + bit set").
    static func matches(_ listingTitle: String, product: ProductInfo) -> Bool {
        let wanted = modelCodes(for: product)
        if !wanted.isEmpty {
            let title = normalize(listingTitle)
            guard wanted.contains(where: { title.contains($0) }) else { return false }
            return codes(in: listingTitle).allSatisfy(wanted.contains)
        }
        // No model number at all: require the brand and most of the important words.
        let title = normalize(listingTitle)
        if let brand = product.brand, !title.contains(normalize(brand)) { return false }
        let words = importantWords(product.title)
        guard !words.isEmpty else { return false }
        let listingWords = Set(importantWords(listingTitle))
        let shared = words.filter(listingWords.contains).count
        return Double(shared) / Double(words.count) >= 0.7
    }

    /// For stores Google has already grouped as the same product: only reject listings
    /// that name a *different* model (a bundle or variant). Many stores, like Lowe's,
    /// leave the model number out of the title entirely.
    static func hasNoOtherModel(_ listingTitle: String, product: ProductInfo) -> Bool {
        let wanted = modelCodes(for: product)
        return codes(in: listingTitle).allSatisfy(wanted.contains)
    }

    /// Model-number-looking words: letters and digits mixed, 5+ characters,
    /// not a measurement ("12INCH", "100PIECE", "20VMAX") and not an Amazon ID ("B0...").
    static func codes(in text: String) -> [String] {
        let measurement = #"^[0-9]+[A-Z]+$"#
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

    private static func importantWords(_ s: String) -> [String] {
        let stop: Set<String> = ["THE", "AND", "FOR", "WITH", "KIT", "IN", "OF", "PACK"]
        return s.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }
}
