import Foundation

extension IzzyAPI {
    /// A manage token made on this phone: 32 random bytes in base64url without padding (43
    /// characters), exactly the format the server makes its own in.
    ///
    /// The app makes one for each booking it tries and sends it with `POST /api/appointments`
    /// (`X-Manage-Token`). The server uses it as the appointment's manage token and as the
    /// booking's idempotency key: if the answer is lost and the app tries again with the same
    /// token and the same booking, the server answers with the appointment it already made
    /// instead of booking twice (or saying the client's own time was taken).
    ///
    /// Like every manage token it's a secret: keep it in the Keychain, never in a log.
    public struct ManageToken: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
        /// How many random bytes a token holds.
        public static let byteCount = 32
        /// How many characters it takes in base64url without padding.
        public static let length = 43

        public let rawValue: String

        /// `nil` unless `rawValue` is exactly what 32 bytes encode to: 43 base64url characters
        /// (`A–Z a–z 0–9 - _`), the last of them with its two unused bits clear.
        public init?(rawValue: String) {
            let scalars = Array(rawValue.unicodeScalars)
            guard scalars.count == Self.length,
                  let last = scalars.last.flatMap(Self.sextet),
                  scalars.allSatisfy({ Self.sextet($0) != nil }),
                  last & 0b11 == 0
            else { return nil }
            self.rawValue = rawValue
        }

        /// A new token from the system's cryptographically secure random number generator.
        public static func generate() -> ManageToken {
            var generator = SystemRandomNumberGenerator()
            return generate(using: &generator)
        }

        /// A new token from `generator`. Use `generate()` in the apps; this is for tests.
        public static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> ManageToken {
            var bytes = [UInt8]()
            bytes.reserveCapacity(byteCount)
            while bytes.count < byteCount {
                var word = generator.next()
                for _ in 0..<8 where bytes.count < byteCount {
                    bytes.append(UInt8(truncatingIfNeeded: word))
                    word >>= 8
                }
            }
            return ManageToken(encoding: bytes)
        }

        /// The token for exactly these 32 bytes.
        init(encoding bytes: [UInt8]) {
            precondition(bytes.count == Self.byteCount, "A manage token is \(Self.byteCount) bytes")
            let base64 = Data(bytes).base64EncodedString()
            var text = ""
            text.reserveCapacity(Self.length)
            for character in base64 {
                switch character {
                case "+": text.append("-")
                case "/": text.append("_")
                case "=": continue
                default: text.append(character)
                }
            }
            rawValue = text
        }

        /// Leaves the token out, so it never ends up in a log.
        public var description: String { "ManageToken(<redacted>)" }

        /// The 6-bit value of a base64url character, or `nil` for anything else.
        private static func sextet(_ scalar: Unicode.Scalar) -> UInt8? {
            switch scalar {
            case "A"..."Z": return UInt8(scalar.value - 65)
            case "a"..."z": return UInt8(scalar.value - 97 + 26)
            case "0"..."9": return UInt8(scalar.value - 48 + 52)
            case "-": return 62
            case "_": return 63
            default: return nil
            }
        }
    }
}
