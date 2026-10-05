import Foundation

/// Turns a barcode into a product name, brand and model number
/// (UPCitemdb free trial, ~100 lookups/day, no key).
/// Its prices are often years old, so they are never shown.
struct UPCItemDBClient {
    private struct Response: Decodable {
        struct Item: Decodable {
            let title: String?
            let brand: String?
            let model: String?
            let images: [String]?
        }
        let items: [Item]?
    }

    func product(for barcode: String) async throws -> ProductInfo? {
        var components = URLComponents(string: "https://api.upcitemdb.com/prod/trial/lookup")!
        components.queryItems = [URLQueryItem(name: "upc", value: barcode)]

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: components.url!)
        } catch {
            throw LookupError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw LookupError.tooManyLookups }
        guard status == 200 else { return nil }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let item = decoded.items?.first,
              let title = item.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty
        else { return nil }

        // iOS blocks plain http images, so only keep https ones.
        let image = item.images?.first { $0.hasPrefix("https://") }.flatMap(URL.init(string:))
        return ProductInfo(
            title: title,
            imageURL: image,
            brand: item.brand?.nilIfBlank,
            model: item.model?.nilIfBlank
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
