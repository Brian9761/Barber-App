import Foundation

/// A price as listed on the shop's booking menu.
///
/// Prices are stored in whole cents so they never suffer from floating point
/// rounding, and are formatted by hand so the output is identical on every
/// platform and locale.
public struct Price: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A flat price.
        case fixed
        /// The listed price is where it starts; the final price depends on the work.
        case startingAt
        /// Added to a haircut at no extra charge.
        case includedWithCut
    }

    public let cents: Int
    public let kind: Kind

    public init(cents: Int, kind: Kind = .fixed) {
        precondition(cents >= 0, "A price can't be negative")
        self.cents = kind == .includedWithCut ? 0 : cents
        self.kind = kind
    }

    public static func dollars(_ amount: Int) -> Price {
        Price(cents: amount * 100)
    }

    public static func startingAt(dollars amount: Int) -> Price {
        Price(cents: amount * 100, kind: .startingAt)
    }

    public static let includedWithCut = Price(cents: 0, kind: .includedWithCut)

    /// Short label, e.g. "$35", "From $80" or "Included with cut".
    public var label: String {
        switch kind {
        case .fixed: return Price.currencyString(cents: cents)
        case .startingAt: return "From " + Price.currencyString(cents: cents)
        case .includedWithCut: return "Included with cut"
        }
    }

    /// Formats cents as US dollars, dropping ".00" for whole amounts: "$35", "$7.50".
    public static func currencyString(cents: Int) -> String {
        let dollars = cents / 100
        let remainder = cents % 100
        guard remainder != 0 else { return "$\(dollars)" }
        return remainder < 10 ? "$\(dollars).0\(remainder)" : "$\(dollars).\(remainder)"
    }

    /// Summarizes several prices for the same service, e.g. "$35–$45".
    ///
    /// - Any "starting at" price turns the summary into "From $lowest".
    /// - Included-with-cut prices only show when nothing is charged.
    public static func summary(of prices: [Price]) -> String {
        let charged = prices.filter { $0.kind != .includedWithCut }.map(\.cents)
        guard let lowest = charged.min(), let highest = charged.max() else {
            return prices.isEmpty ? "" : Price.includedWithCut.label
        }
        if prices.contains(where: { $0.kind == .startingAt }) {
            return "From " + currencyString(cents: lowest)
        }
        if lowest == highest {
            return currencyString(cents: lowest)
        }
        return currencyString(cents: lowest) + "–" + currencyString(cents: highest)
    }
}

extension Price: Comparable {
    public static func < (lhs: Price, rhs: Price) -> Bool {
        lhs.cents < rhs.cents
    }
}
