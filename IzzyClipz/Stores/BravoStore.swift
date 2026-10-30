import Foundation
import Observation

/// Bravo's current prices and stock, checked against bravohairgel.com once a
/// launch. Until that answers (or if it can't be reached) the prices bundled
/// with the app are shown.
@MainActor
@Observable
final class BravoStore {
    private(set) var livePrices: [String: LivePrice] = [:]

    private let catalog: ProductCatalog
    private let session: URLSession
    @ObservationIgnored private var lastChecked: Date?
    @ObservationIgnored private var isChecking = false

    /// Shopify's public product feed for the store.
    static let feedURL = URL(string: "https://bravohairgel.com/products.json?limit=250")

    init(catalog: ProductCatalog = AppData.products, session: URLSession = .shared) {
        self.catalog = catalog
        self.session = session
    }

    func price(for product: Product) -> Price {
        guard let live = livePrices[product.id] else { return product.price }
        return Price(cents: live.cents)
    }

    func isSoldOut(_ product: Product) -> Bool {
        livePrices[product.id]?.isAvailable == false
    }

    /// The Shopify variant a cart link adds: the one whose live price is shown,
    /// or the bundled one until the store answers (or if its feed leaves it out).
    func variantID(for product: Product) -> Int64 {
        livePrices[product.id]?.variantID ?? product.variantID
    }

    /// Fetches current prices, at most once an hour.
    func refresh() async {
        guard !LaunchOptions.isUITesting, !isChecking, let url = Self.feedURL else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 60 * 60 { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let parsed = try ShopifyPrices.parse(data)
            let known = Set(catalog.products.map(\.id))
            // Ignore anything that doesn't look like a real price.
            livePrices = parsed.filter { known.contains($0.key) && (1..<100_000).contains($0.value.cents) }
            lastChecked = Date()
        } catch {
            // Offline or the feed changed: keep the bundled prices.
        }
    }
}
