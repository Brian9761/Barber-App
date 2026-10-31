import Foundation

/// A day on the shop's calendar as the API writes it: `"2026-11-02"`.
///
/// It's a plain year, month and day with no time or time zone, so the same
/// string means the same shop day on every phone. Use `init(containing:in:)`
/// with the shop's time zone to find "today", and `calendarDay` to use it with
/// `BookingCalendar`.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible, LosslessStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// `nil` for a day that doesn't exist (February 30) or a year outside 1–9999.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...CalendarDay.numberOfDays(inMonth: month, year: year)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads exactly `YYYY-MM-DD`; anything else is `nil`.
    public init?(_ description: String) {
        var scanner = ASCIIScanner(Array(description.utf8))
        guard let year = scanner.number(digits: 4), scanner.skip("-"),
              let month = scanner.number(digits: 2), scanner.skip("-"),
              let day = scanner.number(digits: 2), scanner.isAtEnd
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(_ calendarDay: CalendarDay) {
        self.year = calendarDay.year
        self.month = calendarDay.month
        self.day = calendarDay.day
    }

    /// The calendar day containing `date` in `timeZone`, e.g. today in the shop.
    public init(containing date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            // Gregorian components are always available; fall back to the UTC day.
            self = LocalDate(CalendarDay(dayNumber: Int((date.timeIntervalSince1970 / 86_400).rounded(.down))))
            return
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The same day for `BookingCalendar` and friends.
    public var calendarDay: CalendarDay {
        CalendarDay(dayNumber: CalendarDay.dayNumber(year: year, month: month, day: day))
    }

    public var weekday: Weekday { calendarDay.weekday }

    /// The day `days` later (or earlier, when negative).
    public func adding(days: Int) -> LocalDate {
        LocalDate(calendarDay.adding(days: days))
    }

    /// `"2026-11-02"`.
    public var description: String {
        IzzyAPI.Timestamp.pad(year, 4) + "-" + IzzyAPI.Timestamp.pad(month, 2) + "-" + IzzyAPI.Timestamp.pad(day, 2)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = LocalDate(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a day like 2026-11-02, got \"\(string)\""
            )
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
