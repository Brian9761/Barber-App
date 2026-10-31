import Foundation

/// The Izzy Clipz server's JSON API (v1), shared by the customer app and the
/// owner app.
///
/// Everything here follows the v1 contract exactly:
/// - Times are ISO 8601 in UTC with a `Z` and no fractional seconds,
///   e.g. `2026-11-02T18:00:00Z` (`IzzyAPI.Timestamp`). Reading also accepts
///   fractional seconds and numeric offsets, so a slightly different server
///   never breaks the apps; writing always uses the exact contract form.
/// - Shop-local days are `YYYY-MM-DD` (`LocalDate`).
/// - Money is integer cents.
/// - Errors are `{ "error": { "code": …, "message": … } }` (`APIError`).
///
/// The models live in this namespace because the Kit already has an
/// `Appointment`, a `Review` and a `Product` of its own.
public enum IzzyAPI {
    /// What `POST /api/owner/payments` accepts, in cents: $0.50 to $1,000.
    public static let paymentAmountRange: ClosedRange<Int> = 50...100_000

    /// How many days one `GET /api/availability` call can cover.
    public static let availabilityDaysRange: ClosedRange<Int> = 1...31

    /// The largest product photo the server takes ("≤ 4 MB"), counted in
    /// decimal megabytes so it's safe whichever way the server counts.
    public static let maxPhotoBytes = 4_000_000

    /// The `barberId` value that means "whoever is free first".
    public static let anyBarberID = "any"

    /// A JSON encoder for request bodies and fakes: contract time format,
    /// sorted keys, and slashes left unescaped.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Timestamp.string(from: date))
        }
        return encoder
    }

    /// A JSON decoder for server responses. Times may have fractional seconds
    /// or a numeric offset; anything else that isn't ISO 8601 is an error.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Timestamp.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 time like 2026-11-02T18:00:00Z, got \"\(string)\""
                )
            }
            return date
        }
        return decoder
    }
}

// MARK: - Times

extension IzzyAPI {
    /// ISO 8601 times as the contract writes them: `2026-11-02T18:00:00Z`.
    ///
    /// Parsed and formatted by hand with integer day math, so the result is
    /// the same on every platform, locale and time zone setting.
    public enum Timestamp {
        /// The contract form of `date`: UTC, a `Z`, whole seconds (rounded
        /// down). Dates outside the years 1–9999 are clamped into them.
        public static func string(from date: Date) -> String {
            var seconds = date.timeIntervalSince1970
            // 0001-01-01T00:00:00Z ... 9999-12-31T23:59:59Z. `!(x >= min)` also catches NaN.
            if !(seconds >= -62_135_596_800) { seconds = -62_135_596_800 }
            if seconds > 253_402_300_799 { seconds = 253_402_300_799 }
            let whole = Int(seconds.rounded(.down))
            var dayNumber = whole / 86_400
            var secondOfDay = whole % 86_400
            if secondOfDay < 0 {
                secondOfDay += 86_400
                dayNumber -= 1
            }
            let day = CalendarDay(dayNumber: dayNumber)
            return pad(day.year, 4) + "-" + pad(day.month, 2) + "-" + pad(day.day, 2)
                + "T" + pad(secondOfDay / 3_600, 2) + ":" + pad(secondOfDay % 3_600 / 60, 2) + ":" + pad(secondOfDay % 60, 2)
                + "Z"
        }

        /// Reads `YYYY-MM-DDTHH:MM:SS`, optionally followed by a fraction of a
        /// second (`.5`, `.123`, up to nanoseconds), then `Z` or an offset
        /// (`+00:00`, `-0800`). `nil` for anything else, including impossible
        /// dates like February 30.
        public static func date(from string: String) -> Date? {
            var scanner = ASCIIScanner(Array(string.utf8))
            guard let year = scanner.number(digits: 4), scanner.skip("-"),
                  let month = scanner.number(digits: 2), scanner.skip("-"),
                  let day = scanner.number(digits: 2), scanner.skip("T") || scanner.skip("t"),
                  let hour = scanner.number(digits: 2), scanner.skip(":"),
                  let minute = scanner.number(digits: 2), scanner.skip(":"),
                  let second = scanner.number(digits: 2)
            else { return nil }
            guard (1...12).contains(month),
                  (1...CalendarDay.numberOfDays(inMonth: month, year: year)).contains(day),
                  hour <= 23, minute <= 59, second <= 59
            else { return nil }

            var fraction = 0.0
            if scanner.skip(".") {
                guard let digits = scanner.digitRun(), !digits.isEmpty else { return nil }
                // Nanoseconds are plenty; ignore anything finer.
                let significant = digits.prefix(9)
                let value = significant.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
                let scale = significant.reduce(1) { scale, _ in scale * 10 }
                fraction = Double(value) / Double(scale)
            }

            var offsetSeconds = 0
            if scanner.skip("Z") || scanner.skip("z") {
                offsetSeconds = 0
            } else if let sign = scanner.sign() {
                guard let offsetHours = scanner.number(digits: 2) else { return nil }
                _ = scanner.skip(":")
                guard let offsetMinutes = scanner.number(digits: 2), offsetHours <= 23, offsetMinutes <= 59 else { return nil }
                offsetSeconds = sign * (offsetHours * 3_600 + offsetMinutes * 60)
            } else {
                return nil
            }
            guard scanner.isAtEnd else { return nil }

            let dayNumber = CalendarDay.dayNumber(year: year, month: month, day: day)
            let seconds = dayNumber * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
            return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
        }

        static func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
        }
    }
}

/// A tiny ASCII scanner for the hand-written date parsers.
struct ASCIIScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { index == bytes.count }

    /// Exactly `digits` ASCII digits as a number.
    mutating func number(digits: Int) -> Int? {
        guard index + digits <= bytes.count else { return nil }
        var value = 0
        for offset in 0..<digits {
            let byte = bytes[index + offset]
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        index += digits
        return value
    }

    /// Every ASCII digit from here on.
    mutating func digitRun() -> ArraySlice<UInt8>? {
        let start = index
        while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
            index += 1
        }
        return bytes[start..<index]
    }

    /// Skips `character` if it's next.
    mutating func skip(_ character: Unicode.Scalar) -> Bool {
        guard index < bytes.count, bytes[index] == UInt8(ascii: character) else { return false }
        index += 1
        return true
    }

    /// +1 or -1 for a leading "+" or "-".
    mutating func sign() -> Int? {
        if skip("+") { return 1 }
        if skip("-") { return -1 }
        return nil
    }
}
