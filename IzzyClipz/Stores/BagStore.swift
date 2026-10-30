import Foundation
import Observation

/// The client's bag of Bravo products, kept on this iPhone between launches.
///
/// Bravo sells and ships everything. The bag ends in "Check out on Bravo",
/// which opens Bravo's own checkout with the items already in its cart, so
/// the app never sees a payment. Prices, variants and stock come from
/// `BravoStore`: live once Bravo's feed has answered, bundled until then.
@MainActor
@Observable
final class BagStore {
    /// A bag line with its product looked up, at today's price.
    struct Line: Identifiable, Hashable {
        let product: Product
        let quantity: Int
        /// Bravo's live price when known, the bundled one otherwise.
        let unitPrice: Price
        /// Sold out at Bravo since it went in the bag. It stays in the bag
        /// (the client picked it) but is left out of the subtotal and checkout.
        let isSoldOut: Bool

        var id: String { product.id }

        var total: Price { Price(cents: unitPrice.cents * quantity) }
    }

    static let storageKey = "bag.v1"
    /// How many of one product a line can hold, for steppers.
    static let quantityRange = Bag.quantityRange

    private(set) var bag: Bag

    private let bravo: BravoStore
    private let defaults: UserDefaults
    private let catalog: ProductCatalog

    init(bravo: BravoStore, defaults: UserDefaults, catalog: ProductCatalog = AppData.products) {
        self.bravo = bravo
        self.defaults = defaults
        self.catalog = catalog

        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Bag.self, from: $0) }
        var bag = saved ?? Bag()
        // Bravo stopped selling it, or a later version of the app dropped it.
        bag.removeAll { catalog.product(withID: $0.productID) == nil }
        self.bag = bag
        if let saved, saved != bag {
            persist()
        }
    }

    // MARK: Contents

    /// How many items in all, for the badge on the bag button.
    var count: Int { bag.itemCount }

    var isEmpty: Bool { bag.isEmpty }

    /// In the order they were added.
    var lines: [Line] {
        bag.lines.compactMap { line in
            guard let product = catalog.product(withID: line.productID) else { return nil }
            return Line(
                product: product,
                quantity: line.quantity,
                unitPrice: bravo.price(for: product),
                isSoldOut: bravo.isSoldOut(product)
            )
        }
    }

    func quantity(of product: Product) -> Int {
        bag.quantity(of: product.id)
    }

    /// Whether `add(product)` would put one more in: it's sold by Bravo, not
    /// sold out, and there's room for it.
    func canAdd(_ product: Product) -> Bool {
        guard isSold(product) else { return false }
        if bag.contains(product.id) {
            return bag.quantity(of: product.id) < Self.quantityRange.upperBound
        }
        return !bag.isFull
    }

    // MARK: Changes

    /// Puts more of a product in the bag.
    ///
    /// - Returns: Whether anything was added. Sold-out products, products
    ///   Bravo doesn't sell here, and a line already at 10 or a full bag add nothing.
    @discardableResult
    func add(_ product: Product, quantity: Int = 1) -> Bool {
        guard isSold(product), bag.add(product.id, quantity: quantity) else { return false }
        persist()
        return true
    }

    /// Changes a line's quantity (clamped to 10); zero takes it out. A sold-out
    /// product can go down but not up.
    func setQuantity(_ quantity: Int, of product: Product) {
        var updated = bag
        let current = updated.quantity(of: product.id)
        updated.setQuantity(bravo.isSoldOut(product) ? min(quantity, current) : quantity, for: product.id)
        guard updated != bag else { return }
        bag = updated
        persist()
    }

    func remove(_ product: Product) {
        guard bag.contains(product.id) else { return }
        bag.remove(product.id)
        persist()
    }

    /// Empties the bag, e.g. once the client says they've checked out on Bravo.
    func removeAll() {
        guard !bag.isEmpty else { return }
        bag.removeAll()
        persist()
    }

    // MARK: Totals and checkout

    /// What the items that can be bought cost, at today's prices. Bravo's
    /// checkout shows the final total with shipping and tax.
    var subtotal: Price {
        bag.subtotal { purchasablePrice($0) }
    }

    /// Bravo's free U.S. shipping threshold ($64).
    var freeShippingThreshold: Price {
        catalog.sponsor.freeShippingThreshold
    }

    /// "$8.03" more to go; $0 once the subtotal reaches it.
    var amountToFreeShipping: Price {
        bag.amountToFreeShipping(threshold: freeShippingThreshold) { purchasablePrice($0) }
    }

    /// From 0 to 1, for the free-shipping meter.
    var freeShippingProgress: Double {
        bag.freeShippingProgress(threshold: freeShippingThreshold) { purchasablePrice($0) }
    }

    /// Whether the subtotal reaches free shipping. Bravo decides at checkout.
    var reachesFreeShipping: Bool {
        bag.reachesFreeShipping(threshold: freeShippingThreshold) { purchasablePrice($0) }
    }

    /// Bravo's cart link with every item that can be bought, at the live
    /// variant when known: https://bravohairgel.com/cart/44210083561649:2,…
    /// `nil` when nothing in the bag can be bought.
    var checkoutURL: URL? {
        bag.checkoutURL(storeURL: catalog.sponsor.storeURL) { id in
            purchasableProduct(id).map { bravo.variantID(for: $0) }
        }
    }

    // MARK: Private

    /// In the catalog and not sold out.
    private func isSold(_ product: Product) -> Bool {
        catalog.product(withID: product.id) != nil && !bravo.isSoldOut(product)
    }

    private func purchasableProduct(_ id: String) -> Product? {
        guard let product = catalog.product(withID: id), !bravo.isSoldOut(product) else { return nil }
        return product
    }

    private func purchasablePrice(_ id: String) -> Price? {
        purchasableProduct(id).map { bravo.price(for: $0) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bag) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
