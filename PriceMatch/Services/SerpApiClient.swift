import Foundation

/// One store's listing, from any of the searches below.
struct ShoppingListing {
    let title: String
    let source: String           // store name, e.g. "Lowe's" or "Walmart - SomeSeller"
    let price: Double
    let delivery: String?
    let notes: [String]
    let link: URL?
    let thumbnail: URL?
    var productToken: String? = nil   // Google Shopping: opens the product page listing every store
}

/// The exact item as Home Depot sells it.
struct HomeDepotProduct {
    let title: String
    let brand: String?
    let model: String?
    let price: Double?
    let thumbnail: URL?
}

/// Live prices through SerpApi (https://serpapi.com). Each call below is one search.
struct SerpApiClient {
    let apiKey: String
    var location: String?

    // MARK: - Home Depot (accepts the barcode directly)

    /// Search Home Depot by barcode (or by model, with `model` set to pick the exact one).
    func homeDepot(barcode: String, model: String? = nil) async throws -> HomeDepotProduct? {
        let json = try await get(["engine": "home_depot", "q": barcode])
        let products = json["products"] as? [[String: Any]] ?? []
        let match: [String: Any]?
        if let model {
            let wanted = model.uppercased().filter { $0.isLetter || $0.isNumber }
            match = products.first {
                ($0["model_number"] as? String)?.uppercased().filter { $0.isLetter || $0.isNumber } == wanted
            }
        } else {
            // Several results means Home Depot didn't recognise the barcode.
            match = products.count == 1 ? products.first : nil
        }
        guard let p = match, let title = p["title"] as? String else { return nil }

        let thumbs = (p["thumbnails"] as? [[String]])?.first
        return HomeDepotProduct(
            title: title,
            brand: p["brand"] as? String,
            model: p["model_number"] as? String,
            price: number(p["price"]),
            thumbnail: thumbs?.last.flatMap(URL.init(string:))
        )
    }

    // MARK: - Competitors (searched by brand + model)

    func walmart(_ query: String) async throws -> [ShoppingListing] {
        let json = try await get(["engine": "walmart", "query": query])
        return (json["organic_results"] as? [[String: Any]] ?? []).compactMap { r in
            guard r["out_of_stock"] as? Bool != true,
                  let title = r["title"] as? String,
                  let price = number((r["primary_offer"] as? [String: Any])?["offer_price"])
            else { return nil }
            let seller = r["seller_name"] as? String ?? "Walmart.com"
            let soldByWalmart = seller.lowercased().hasPrefix("walmart")
            let delivery = r["two_day_shipping"] as? Bool == true ? "Delivers in about 2 days"
                : r["free_shipping"] as? Bool == true ? "Free delivery" : nil
            return ShoppingListing(
                title: title,
                source: soldByWalmart ? "Walmart" : "Walmart - \(seller)",
                price: price,
                delivery: delivery,
                notes: [],
                link: (r["product_page_url"] as? String).flatMap(URL.init(string:)),
                thumbnail: (r["thumbnail"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    func amazon(_ query: String) async throws -> [ShoppingListing] {
        let json = try await get(["engine": "amazon", "k": query, "amazon_domain": "amazon.com"])
        return (json["organic_results"] as? [[String: Any]] ?? []).compactMap { r in
            guard let title = r["title"] as? String, let price = number(r["extracted_price"]) else { return nil }
            let deliveries = r["delivery"] as? [String] ?? []
            // Prefer the non-Prime delivery date, since the customer may not have Prime.
            let delivery = deliveries.first { $0.lowercased().contains("non-members") }
                .map { $0.replacingOccurrences(of: "Or Non-members get ", with: "") }
                ?? deliveries.first
            return ShoppingListing(
                title: title,
                source: "Amazon",
                price: price,
                delivery: delivery,
                notes: [],
                link: ((r["link_clean"] ?? r["link"]) as? String).flatMap(URL.init(string:)),
                thumbnail: (r["thumbnail"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    /// Everyone else (Lowe's, Menards, Ace, ...) via Google Shopping.
    func googleShopping(_ query: String) async throws -> [ShoppingListing] {
        var params = ["engine": "google_shopping", "q": query, "gl": "us", "hl": "en"]
        if let location, !location.isEmpty { params["location"] = location }
        let json: [String: Any]
        do {
            json = try await get(params)
        } catch LookupError.other(let message) where params["location"] != nil && message.localizedCaseInsensitiveContains("location") {
            // SerpApi rejects locations it doesn't recognise; fall back to nationwide results.
            params["location"] = nil
            json = try await get(params)
        }
        return (json["shopping_results"] as? [[String: Any]] ?? []).compactMap { r in
            guard let source = r["source"] as? String, let price = number(r["extracted_price"]) else { return nil }
            var notes = r["extensions"] as? [String] ?? []
            if let tag = r["tag"] as? String { notes.append(tag) }
            return ShoppingListing(
                title: r["title"] as? String ?? "",
                source: source,
                price: price,
                delivery: r["delivery"] as? String,
                notes: notes,
                link: ((r["link"] ?? r["product_link"]) as? String).flatMap(URL.init(string:)),
                thumbnail: (r["thumbnail"] as? String).flatMap(URL.init(string:)),
                productToken: r["immersive_product_page_token"] as? String
            )
        }
    }

    /// Google's own product page: every store selling this identical product, grouped by Google.
    /// This is where Lowe's shows up, since Lowe's leaves model numbers out of its titles.
    func googleProductStores(token: String) async throws -> [ShoppingListing] {
        let json = try await get(["engine": "google_immersive_product", "page_token": token])
        let stores = (json["product_results"] as? [String: Any])?["stores"] as? [[String: Any]] ?? []
        return stores.compactMap { s in
            guard let name = s["name"] as? String, let price = number(s["extracted_price"]) else { return nil }
            return ShoppingListing(
                title: s["title"] as? String ?? "",
                source: name,
                price: price,
                delivery: nil,
                notes: s["details_and_offers"] as? [String] ?? [],
                link: (s["link"] as? String).flatMap(URL.init(string:)),
                thumbnail: nil
            )
        }
    }

    // MARK: - Plumbing

    private func get(_ params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "api_key", value: apiKey)]

        let data: Data
        let response: URLResponse
        do {
            // Never let one slow store hold up the answer at the register.
            (data, response) = try await URLSession.shared.data(for: URLRequest(url: components.url!, timeoutInterval: 12))
        } catch {
            throw LookupError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.other("Unreadable response (HTTP \(status))")
        }

        if let error = json["error"] as? String {
            let e = error.lowercased()
            if e.contains("hasn't returned any results") || e.contains("not found") || e.contains("no results") { return [:] }
            if status == 401 || e.contains("api key") { throw LookupError.badKey }
            if e.contains("run out of searches") { throw LookupError.outOfSearches }
            throw LookupError.other(error)
        }
        return json
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d > 0 ? d : nil
        case let i as Int: return i > 0 ? Double(i) : nil
        case let s as String: return Double(s.filter { $0.isNumber || $0 == "." })
        default: return nil
        }
    }
}
