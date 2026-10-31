import Foundation

extension PhoneNumber {
    /// Reads a US mobile number the way people type it: "(442) 341-3053",
    /// "442.341.3053", "+1 442 341 3053", "14423413053".
    ///
    /// `nil` unless it's a valid North American number: ten digits (or eleven
    /// starting with 1), with an area code and exchange that start with 2–9.
    /// Letters, extensions and other symbols are rejected rather than guessed at.
    public init?(parsing input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits: [Character] = []
        for (index, character) in text.enumerated() {
            if let ascii = character.asciiValue, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(ascii) {
                digits.append(character)
                continue
            }
            switch character {
            case " ", "-", ".", "(", ")", "\u{00A0}":
                continue
            case "+" where index == 0:
                continue
            default:
                return nil
            }
        }
        if digits.count == 11, digits.first == "1" {
            digits.removeFirst()
        } else if text.hasPrefix("+") {
            // "+" must be followed by the country code 1.
            return nil
        }
        guard digits.count == 10,
              ("2"..."9").contains(digits[0]),
              ("2"..."9").contains(digits[3])
        else { return nil }
        self.init(digits: String(digits))
    }

    /// The form the server stores: "+14423413053".
    public var e164: String { "+1" + digits }
}
