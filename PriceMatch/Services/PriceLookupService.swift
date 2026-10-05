import Foundation
import Observation

@Observable
@MainActor
final class PriceLookupService {
    enum State: Equatable {
        case scanning
        case loading
        case loaded(LookupResult)
        case failed(String)
    }

    var state: State = .scanning

    private var cache: [String: (date: Date, result: LookupResult)] = [:]
    private var task: Task<Void, Never>?

    func lookUp(_ raw: String) {
        let barcode = Barcode.normalize(raw)
        guard barcode.count >= 6 else {
            state = .failed("Couldn't read that. Try again, or tap \"Type the numbers\".")
            return
        }

        if let hit = cache[barcode], Date().timeIntervalSince(hit.date) < 15 * 60 {
            state = .loaded(hit.result)
            return
        }

        guard let key = KeychainStore.string(for: SettingsKeys.apiKey), !key.isEmpty else {
            state = .failed(LookupError.notSetUp.errorDescription!)
            return
        }

        let defaults = UserDefaults.standard
        let location = defaults.string(forKey: SettingsKeys.location)
        let maxResults = defaults.object(forKey: SettingsKeys.maxResults) as? Int ?? 5
        let showOthers = defaults.bool(forKey: SettingsKeys.showOthers)

        state = .loading
        task?.cancel()
        task = Task {
            do {
                let result = try await Self.fetch(
                    barcode: barcode,
                    client: SerpApiClient(apiKey: key, location: location),
                    maxResults: maxResults,
                    showOthers: showOthers
                )
                guard !Task.isCancelled else { return }
                cache[barcode] = (Date(), result)
                state = .loaded(result)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed((error as? LookupError ?? .other("\(error)")).errorDescription!)
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        state = .scanning
    }

    /// 1. Home Depot by barcode → exact model + Home Depot's price (falls back to UPCitemdb for the model).
    /// 2. Walmart, Amazon and Google Shopping by brand + model, in parallel, then Google's
    ///    product page for the exact item (every store Google groups as identical, incl. Lowe's).
    /// 3. Keep only listings for that exact model. (Google Shopping can't search by barcode —
    ///    it returns unrelated products — so we never ask it to.)
    nonisolated static func fetch(
        barcode: String,
        client: SerpApiClient,
        maxResults: Int,
        showOthers: Bool
    ) async throws -> LookupResult {
        let product: ProductInfo
        var homeDepotPrice: Double?
        if let hd = try await client.homeDepot(barcode: barcode) {
            product = ProductInfo(title: [hd.brand, hd.title].compactMap { $0 }.joined(separator: " "),
                                  imageURL: hd.thumbnail, brand: hd.brand, model: hd.model)
            homeDepotPrice = hd.price
        } else if var found = try await UPCItemDBClient().product(for: barcode) {
            // Home Depot didn't know this barcode (often older packaging): find its price by model instead.
            if let model = found.model,
               let hd = try? await client.homeDepot(barcode: [found.brand, model].compactMap { $0 }.joined(separator: " "), model: model) {
                homeDepotPrice = hd.price
                found.imageURL = found.imageURL ?? hd.thumbnail
            }
            product = found
        } else {
            throw LookupError.notFound
        }

        let query = ProductMatcher.query(for: product)
        async let walmart = try? client.walmart(query)
        async let amazon = try? client.amazon(query)
        // "Lowe's" in the search pulls Lowe's listings to the top without hiding other stores.
        async let google = try? client.googleShopping("Lowe's " + query)
        let googleListings = await google ?? []
        let all = (await walmart ?? []) + (await amazon ?? []) + googleListings
        var listings = all.filter { ProductMatcher.matches($0.title, product: product) }

        // Open Google's product page for this exact item to get every store, including Lowe's.
        if let token = googleListings.first(where: {
               $0.productToken != nil && ProductMatcher.matches($0.title, product: product)
           })?.productToken,
           let stores = try? await client.googleProductStores(token: token) {
            listings += stores.filter { ProductMatcher.hasNoOtherModel($0.title, product: product) }
        }

        if homeDepotPrice == nil {
            homeDepotPrice = listings.filter { CompetitorFilter.isHomeDepot($0.source) }.map(\.price).min()
        }
        return build(barcode: barcode, product: product, homeDepotPrice: homeDepotPrice,
                     listings: listings, maxResults: maxResults, showOthers: showOthers)
    }

    /// `listings` must already be filtered to the exact product.
    nonisolated static func build(
        barcode: String,
        product: ProductInfo,
        homeDepotPrice: Double?,
        listings: [ShoppingListing],
        maxResults: Int,
        showOthers: Bool
    ) -> LookupResult {

        // Cheapest listing per store.
        var bestPerStore: [String: Offer] = [:]
        for listing in listings where !CompetitorFilter.isHomeDepot(listing.source) {
            let store = CompetitorFilter.classify(listing.source)
            if store.kind == .excluded && !showOthers { continue }
            let offer = Offer(
                storeName: store.name,
                price: listing.price,
                availability: CompetitorFilter.availability(delivery: listing.delivery, notes: listing.notes),
                link: listing.link,
                kind: store.kind
            )
            if let existing = bestPerStore[offer.storeName], existing.price <= offer.price { continue }
            bestPerStore[offer.storeName] = offer
        }

        // Major stores first, then other stores, then excluded sellers; cheapest first within each.
        let offers = bestPerStore.values
            .sorted { ($0.kind.rawValue, $0.price) < ($1.kind.rawValue, $1.price) }
            .prefix(max(1, maxResults))

        var info = product
        if info.imageURL == nil { info.imageURL = listings.first?.thumbnail }
        return LookupResult(barcode: barcode, product: info,
                            homeDepotPrice: homeDepotPrice, offers: Array(offers))
    }
}
