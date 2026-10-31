import Foundation

extension PhoneNumber {
    /// Reads a US mobile number the way people type it: "(442) 341-3053",
    /// "442.341.3053", "+1 442 341 3053", "14423413053".
    ///
    /// `nil` unless it's a valid North American number: ten digits (or eleven
    /// starting with 1, or "+1" and ten), with an area code and exchange that
    /// start with 2–9 and aren't N11 codes like 211 or 911. Letters,
    /// extensions and other symbols are rejected rather than guessed at.
    ///
    /// It accepts exactly what the server's `normalizeUSPhone` accepts, so a
    /// number the app lets through is never turned down at the last step. Both
    /// sides are tested against `server/test/fixtures/phone-numbers.json`.
    public init?(parsing input: String) {
        // Trim and split like the server (JavaScript's `trim()` and `\s`), one scalar at a time.
        var text = input.unicodeScalars[...]
        while let first = text.first, Self.isSpace(first) { text.removeFirst() }
        while let last = text.last, Self.isSpace(last) { text.removeLast() }
        var digits: [Character] = []
        for (offset, scalar) in text.enumerated() {
            switch scalar {
            case "0"..."9":
                digits.append(Character(scalar))
            case "(", ")", ".", "-":
                continue
            case "+" where offset == 0:
                continue
            default:
                guard Self.isSpace(scalar) else { return nil }
            }
        }
        if text.first == "+" {
            // "+" must be followed by the country code 1.
            guard digits.first == "1" else { return nil }
            digits.removeFirst()
        } else if digits.count == 11, digits.first == "1" {
            digits.removeFirst()
        }
        guard digits.count == 10,
              ("2"..."9").contains(digits[0]),
              ("2"..."9").contains(digits[3]),
              // N11 codes (211, 411, 911…) are never area codes or exchanges.
              !(digits[1] == "1" && digits[2] == "1"),
              !(digits[4] == "1" && digits[5] == "1")
        else { return nil }
        self.init(digits: String(digits))
    }

    /// The form the server stores: "+14423413053".
    public var e164: String { "+1" + digits }

    /// What JavaScript counts as white space (`\s`, and what `trim()` drops).
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }
}
