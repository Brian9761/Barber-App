import Foundation
import IzzyClipzKit

/// Money in whole cents, the way the server and Stripe count it. Never a
/// floating point number, so $35.10 is always 3510.
enum Money {
    /// "$35.00", "$1,250.50": always two decimals, for amounts being charged.
    static func amount(_ cents: Int) -> String {
        let negative = cents < 0
        let absolute = cents.magnitude
        let dollars = absolute / 100
        let remainder = absolute % 100
        var grouped = ""
        let digits = String(dollars)
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return (negative ? "-$" : "$") + grouped + "." + (remainder < 10 ? "0" : "") + String(remainder)
    }

    /// "35 dollars", "35 dollars and 50 cents": what VoiceOver reads for an amount.
    static func spoken(_ cents: Int) -> String {
        let dollars = cents / 100
        let remainder = cents % 100
        let dollarText = dollars == 1 ? "1 dollar" : "\(dollars) dollars"
        guard remainder != 0 else { return dollarText }
        let centText = remainder == 1 ? "1 cent" : "\(remainder) cents"
        return dollars == 0 ? centText : "\(dollarText) and \(centText)"
    }

    /// Reads a price typed into a text field: "25", "25.5", "$25.50", "1,250".
    /// `nil` for anything else, including more than two decimals and negative
    /// amounts.
    static func cents(from text: String) -> Int? {
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.hasPrefix("$") { typed.removeFirst() }
        typed = typed.replacingOccurrences(of: ",", with: "")
        guard !typed.isEmpty else { return nil }
        let parts = typed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              let whole = parts.first, whole.allSatisfy(\.isASCIIDigit)
        else { return nil }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2, fraction.allSatisfy(\.isASCIIDigit) else { return nil }
        guard whole.count <= 9 else { return nil }
        let dollars = Int(whole) ?? 0
        let centsPart = fraction.isEmpty ? 0 : (Int(fraction) ?? 0) * (fraction.count == 1 ? 10 : 1)
        return dollars * 100 + centsPart
    }

    /// How a price in cents is typed back into a text field: "25", "25.50".
    static func editable(_ cents: Int) -> String {
        let dollars = cents / 100
        let remainder = cents % 100
        return remainder == 0 ? "\(dollars)" : "\(dollars)." + (remainder < 10 ? "0" : "") + "\(remainder)"
    }

    /// The smallest and largest card payment the server takes, for messages.
    static var allowedRangeText: String {
        "Enter an amount from \(amount(IzzyAPI.paymentAmountRange.lowerBound)) to \(amount(IzzyAPI.paymentAmountRange.upperBound))."
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// The cash-register style amount entry: each digit pushes the others left,
/// so typing 3, 5, 0, 0 gives $35.00.
struct AmountEntry: Equatable {
    /// The largest amount the keypad accepts: one digit more than the
    /// server's maximum, so a typo past it is visible and explained.
    static let maximumCents = 999_999

    private(set) var cents: Int

    init(cents: Int = 0) {
        self.cents = min(max(cents, 0), AmountEntry.maximumCents)
    }

    mutating func append(digit: Int) {
        guard (0...9).contains(digit) else { return }
        let next = cents * 10 + digit
        guard next <= AmountEntry.maximumCents else { return }
        cents = next
    }

    /// "00": two zeros at once, for whole dollar amounts.
    mutating func appendDoubleZero() {
        append(digit: 0)
        append(digit: 0)
    }

    mutating func deleteLast() {
        cents /= 10
    }

    mutating func clear() {
        cents = 0
    }

    var isChargeable: Bool { IzzyAPI.paymentAmountRange.contains(cents) }
}
