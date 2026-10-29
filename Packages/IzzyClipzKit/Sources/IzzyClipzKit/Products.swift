import Foundation

/// Groups on the Shop tab, in display order.
public enum ProductCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case gels
    case styling
    case grooming

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gels: return "Hair Gels"
        case .styling: return "Styling"
        case .grooming: return "Grooming"
        }
    }
}

/// A product the shop's sponsor sells, as listed on its online store.
public struct Product: Identifiable, Hashable, Sendable {
    /// The product's handle on the sponsor's Shopify store, e.g. "blue-bravo-hair-gel-16oz".
    public let id: String
    /// "Blue Hair Gel".
    public let name: String
    /// "16 oz", or `nil` when there's only one size.
    public let size: String?
    public let category: ProductCategory
    /// The price when the app was built. The store's live price may differ.
    public let price: Price
    /// One or two sentences from the sponsor's description.
    public let summary: String
    /// Three to five short points from the sponsor's description.
    public let highlights: [String]
    /// The bundled image's asset name: "Bravo-<id>".
    public let imageName: String
    public let isFeatured: Bool

    public init(
        id: String,
        name: String,
        size: String? = nil,
        category: ProductCategory,
        price: Price,
        summary: String,
        highlights: [String],
        imageName: String? = nil,
        isFeatured: Bool = false
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.category = category
        self.price = price
        self.summary = summary
        self.highlights = highlights
        self.imageName = imageName ?? "Bravo-\(id)"
        self.isFeatured = isFeatured
    }
}

/// The brand that sponsors the shop.
public struct Sponsor: Hashable, Sendable {
    /// "Bravo".
    public let name: String
    /// "Bravo Hair Gel".
    public let fullName: String
    public let tagline: String
    public let about: [String]
    /// The online store's home page, without tracking.
    public let storeURL: URL
    public let shippingNote: String
    public let phone: PhoneNumber?

    public init(
        name: String,
        fullName: String,
        tagline: String,
        about: [String],
        storeURL: URL,
        shippingNote: String,
        phone: PhoneNumber? = nil
    ) {
        self.name = name
        self.fullName = fullName
        self.tagline = tagline
        self.about = about
        self.storeURL = storeURL
        self.shippingNote = shippingNote
        self.phone = phone
    }
}

/// The sponsor's products shown on the Shop tab, and links to buy them.
///
/// Products are sold and shipped by the sponsor: the app links to each one
/// on the sponsor's store and never handles a payment itself.
public struct ProductCatalog: Sendable {
    public let sponsor: Sponsor
    public let products: [Product]
    /// Added to every store link so the sponsor can tell which visits came from the app.
    public let tracking: [BookingLinks.QueryParameter]

    public init(sponsor: Sponsor, products: [Product], tracking: [BookingLinks.QueryParameter] = ProductCatalog.appTracking) {
        self.sponsor = sponsor
        self.products = products
        self.tracking = tracking
    }

    public static let appTracking = BookingLinks.appTracking + [
        BookingLinks.QueryParameter("utm_campaign", "izzy-clipz-partner"),
    ]

    // MARK: Lookup

    /// Categories that have at least one product, in display order.
    public var categories: [ProductCategory] {
        ProductCategory.allCases.filter { category in
            products.contains { $0.category == category }
        }
    }

    public func products(in category: ProductCategory) -> [Product] {
        products.filter { $0.category == category }
    }

    public var featured: [Product] {
        products.filter(\.isFeatured)
    }

    public func product(withID id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: Links

    /// e.g. https://bravohairgel.com/products/blue-bravo-hair-gel-16oz?utm_source=izzyclipz-app&…
    public func url(for product: Product) -> URL {
        storeLink(path: "/products/\(product.id)")
    }

    /// The store's home page, with tracking.
    public var storeURL: URL {
        storeLink(path: "/")
    }

    private func storeLink(path: String) -> URL {
        guard var components = URLComponents(url: sponsor.storeURL, resolvingAgainstBaseURL: false) else {
            return sponsor.storeURL
        }
        components.path = path
        components.fragment = nil
        let query = tracking.map { URLQueryItem(name: $0.name, value: $0.value) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? sponsor.storeURL
    }

    // MARK: Integrity

    /// Everything wrong with the data, as human-readable messages. Empty means valid.
    public func validationProblems() -> [String] {
        var problems: [String] = []

        for (id, count) in Dictionary(grouping: products.map(\.id), by: { $0 }).mapValues(\.count) where count > 1 {
            problems.append("Duplicate product ID '\(id)'")
        }
        if sponsor.storeURL.scheme != "https" || sponsor.storeURL.host == nil {
            problems.append("The store URL isn't an https link")
        }
        if products.isEmpty { problems.append("There are no products") }
        if !products.isEmpty && featured.isEmpty { problems.append("No product is featured") }

        for product in products {
            if !Catalog.isURLSlug(product.id) { problems.append("Product ID '\(product.id)' isn't a URL slug") }
            if product.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Product '\(product.id)' has no name") }
            if product.summary.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Product '\(product.id)' has no summary") }
            if !(3...5).contains(product.highlights.count) { problems.append("Product '\(product.id)' needs 3 to 5 highlights") }
            if product.highlights.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                problems.append("Product '\(product.id)' has an empty highlight")
            }
            if product.price.kind != .fixed || product.price.cents <= 0 { problems.append("Product '\(product.id)' needs a price") }
            if product.imageName.isEmpty { problems.append("Product '\(product.id)' has no image") }
            if let size = product.size, size.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("Product '\(product.id)' has an empty size")
            }
        }
        return problems
    }
}

/// A product's current price and stock on the sponsor's store.
public struct LivePrice: Hashable, Sendable {
    public let cents: Int
    public let isAvailable: Bool

    public init(cents: Int, isAvailable: Bool) {
        self.cents = cents
        self.isAvailable = isAvailable
    }
}

/// Reads prices from a Shopify store's public product feed (`/products.json`).
public enum ShopifyPrices {
    public enum ParseError: Error, Equatable, Sendable {
        /// The response isn't a JSON object with a "products" array.
        case notAProductList
    }

    /// Parses a Shopify `/products.json` response: handle -> lowest variant price & whether any variant is available.
    ///
    /// Prices are strings like "17.99"; they're turned into cents by hand, never
    /// through floating point. Variants without a readable, non-zero price are
    /// ignored, products left with no variants are skipped, and a variant
    /// without an "available" flag counts as available.
    public static func parse(_ data: Data) throws -> [String: LivePrice] {
        let feed: Feed
        do {
            feed = try JSONDecoder().decode(Feed.self, from: data)
        } catch {
            throw ParseError.notAProductList
        }

        var prices: [String: LivePrice] = [:]
        for product in feed.products.decodedValues() where prices[product.handle] == nil {
            let variants = product.variants.decodedValues()
            guard let lowest = variants.map(\.cents).min() else { continue }
            prices[product.handle] = LivePrice(cents: lowest, isAvailable: variants.contains(where: \.isAvailable))
        }
        return prices
    }

    /// "17.99" -> 1799, "18" -> 1800, "18.9" -> 1890. `nil` for anything else,
    /// including negative amounts and more than two decimals.
    static func cents(fromPrice text: String) -> Int? {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let wholePart = parts.first,
              (1...9).contains(wholePart.count),
              let dollars = digitsValue(wholePart)
        else { return nil }
        guard parts.count == 2 else { return dollars * 100 }
        let fraction = parts[1]
        guard (1...2).contains(fraction.count), let value = digitsValue(fraction) else { return nil }
        return dollars * 100 + (fraction.count == 1 ? value * 10 : value)
    }

    private static func digitsValue(_ text: Substring) -> Int? {
        var value = 0
        for scalar in text.unicodeScalars {
            guard ("0"..."9").contains(scalar) else { return nil }
            value = value * 10 + Int(scalar.value - 48)
        }
        return value
    }

    // MARK: Feed

    private struct Feed: Decodable {
        let products: [Lossy<FeedProduct>]
    }

    private struct FeedProduct: Decodable {
        let handle: String
        let variants: [Lossy<FeedVariant>]
    }

    private struct FeedVariant: Decodable {
        let cents: Int
        let isAvailable: Bool

        enum CodingKeys: String, CodingKey {
            case price
            case available
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let text = try container.decode(String.self, forKey: .price)
            guard let cents = ShopifyPrices.cents(fromPrice: text), cents > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .price, in: container, debugDescription: "Unreadable price '\(text)'")
            }
            self.cents = cents
            self.isAvailable = (try? container.decodeIfPresent(Bool.self, forKey: .available)) ?? true
        }
    }
}
