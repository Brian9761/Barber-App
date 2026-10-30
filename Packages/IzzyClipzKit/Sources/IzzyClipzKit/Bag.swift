import Foundation

/// The sponsor's products a client is gathering to buy, and how many of each.
///
/// The bag holds only product IDs and quantities. Prices, stock and Shopify
/// variants come from whoever asks (bundled or live), so a saved bag never
/// shows yesterday's price. The sponsor sells and ships everything: the bag
/// ends in a cart link that opens the sponsor's own checkout with these items
/// in it, and the app never handles a payment.
///
/// Every way of making or changing a bag keeps it valid: one line per
/// product, in the order they were first added, each with 1 to 10 of it, and
/// at most 10 different products.
public struct Bag: Hashable, Sendable, Codable {
    /// One product and how many of it.
    public struct Line: Identifiable, Hashable, Sendable, Codable {
        /// The product's ID in its catalog (its Shopify handle).
        public let productID: String
        public let quantity: Int

        /// A line as given. A `Bag` merges, clamps or drops lines that would break its rules.
        public init(productID: String, quantity: Int) {
            self.productID = productID
            self.quantity = quantity
        }

        public var id: String { productID }
    }

    /// How many of one product a bag holds. A shop's client buying for
    /// themselves never needs more, and a typo can't order 100 gels.
    public static let quantityRange = 1...10
    /// How many different products a bag holds, which keeps the cart link short.
    public static let maxLines = 10

    /// In the order the products were first added.
    public private(set) var lines: [Line]

    /// A bag with these lines, made valid: lines without a product ID or with
    /// fewer than 1 are dropped, repeated products are merged into the first
    /// line for them, quantities are clamped to 1...10, and only the first 10
    /// different products are kept.
    public init(lines: [Line] = []) {
        var bag: [Line] = []
        for line in lines where !line.productID.isEmpty && line.quantity >= Self.quantityRange.lowerBound {
            if let index = bag.firstIndex(where: { $0.productID == line.productID }) {
                bag[index] = Line(productID: line.productID, quantity: Self.sum(bag[index].quantity, line.quantity))
            } else if bag.count < Self.maxLines {
                bag.append(Line(productID: line.productID, quantity: Self.clamped(line.quantity)))
            }
        }
        self.lines = bag
    }

    // MARK: Contents

    public var isEmpty: Bool { lines.isEmpty }

    /// How many items in all: 3 for two gels and a clay.
    public var itemCount: Int {
        lines.reduce(0) { $0 + $1.quantity }
    }

    /// Whether the bag already holds as many different products as it can.
    public var isFull: Bool { lines.count >= Self.maxLines }

    /// How many of a product are in the bag; 0 when it isn't.
    public func quantity(of productID: String) -> Int {
        lines.first { $0.productID == productID }?.quantity ?? 0
    }

    public func contains(_ productID: String) -> Bool {
        lines.contains { $0.productID == productID }
    }

    // MARK: Changes

    /// Puts more of a product in the bag: onto its line if it has one (up to
    /// 10 in all), or on a new line at the end if there's room.
    ///
    /// - Returns: Whether anything was added. `false` when `quantity` is less
    ///   than 1, the product already has 10 in the bag, or the bag is full.
    @discardableResult
    public mutating func add(_ productID: String, quantity: Int = 1) -> Bool {
        guard !productID.isEmpty, quantity >= Self.quantityRange.lowerBound else { return false }
        if let index = lines.firstIndex(where: { $0.productID == productID }) {
            let current = lines[index].quantity
            let updated = Self.sum(current, quantity)
            guard updated != current else { return false }
            lines[index] = Line(productID: productID, quantity: updated)
            return true
        }
        guard !isFull else { return false }
        lines.append(Line(productID: productID, quantity: Self.clamped(quantity)))
        return true
    }

    /// Changes how many of a product are in the bag, clamped to 10. Zero or
    /// less takes it out. A product that isn't in the bag stays out: use
    /// `add` for that.
    public mutating func setQuantity(_ quantity: Int, for productID: String) {
        guard let index = lines.firstIndex(where: { $0.productID == productID }) else { return }
        if quantity < Self.quantityRange.lowerBound {
            lines.remove(at: index)
        } else {
            lines[index] = Line(productID: productID, quantity: Self.clamped(quantity))
        }
    }

    public mutating func remove(_ productID: String) {
        lines.removeAll { $0.productID == productID }
    }

    public mutating func removeAll() {
        lines.removeAll()
    }

    /// Takes out every line that matches, e.g. products that are no longer sold.
    public mutating func removeAll(where shouldRemove: (Line) -> Bool) {
        lines.removeAll(where: shouldRemove)
    }

    // MARK: Totals

    /// What the lines cost together, at `price(productID)` each. Products the
    /// lookup doesn't know (`nil`) are left out.
    public func subtotal(price: (String) -> Price?) -> Price {
        let cents = lines.reduce(0) { total, line in
            guard let unit = price(line.productID) else { return total }
            return total + unit.cents * line.quantity
        }
        return Price(cents: cents)
    }

    /// How much more would reach free shipping from `threshold`: $0 once it's met.
    public func amountToFreeShipping(threshold: Price, price: (String) -> Price?) -> Price {
        Price(cents: max(0, threshold.cents - subtotal(price: price).cents))
    }

    /// How far the subtotal is toward free shipping, from 0 (nothing yet) to 1 (there).
    public func freeShippingProgress(threshold: Price, price: (String) -> Price?) -> Double {
        guard threshold.cents > 0 else { return 1 }
        return min(1, Double(subtotal(price: price).cents) / Double(threshold.cents))
    }

    /// Whether the subtotal reaches `threshold`. An estimate: the store's checkout decides.
    public func reachesFreeShipping(threshold: Price, price: (String) -> Price?) -> Bool {
        subtotal(price: price).cents >= threshold.cents
    }

    // MARK: Checkout

    /// A Shopify cart link that opens the store's checkout with the bag's
    /// items in it: https://bravohairgel.com/cart/44210083561649:2,43628496945329:1
    ///
    /// Lines whose product has no variant (`variantID` returns `nil`, e.g. a
    /// product that's gone or sold out) are left out. `nil` when no line is
    /// left, or `storeURL` has no host.
    public func checkoutURL(storeURL: URL, variantID: (String) -> Int64?) -> URL? {
        let items = lines.compactMap { line -> String? in
            guard let id = variantID(line.productID), id > 0 else { return nil }
            return "\(id):\(line.quantity)"
        }
        guard !items.isEmpty,
              var components = URLComponents(url: storeURL, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false
        else { return nil }
        components.path = "/cart/" + items.joined(separator: ",")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case lines
    }

    /// Decodes a saved bag. Unreadable lines are skipped and the rest made
    /// valid, so a bag saved by another version of the app never fails to load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try? container.decodeIfPresent([Lossy<Line>].self, forKey: .lines)
        self.init(lines: saved?.decodedValues() ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lines, forKey: .lines)
    }

    // MARK: Private

    private static func clamped(_ quantity: Int) -> Int {
        min(max(quantity, quantityRange.lowerBound), quantityRange.upperBound)
    }

    /// Adds two quantities without overflowing, clamped.
    private static func sum(_ lhs: Int, _ rhs: Int) -> Int {
        clamped(clamped(lhs) + clamped(rhs))
    }
}
