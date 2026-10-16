import Foundation

/// Days of the week, numbered like `Calendar`'s `.weekday` component (Sunday = 1).
public enum Weekday: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: Int { rawValue }

    public var name: String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][rawValue - 1]
    }

    public var shortName: String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1]
    }

    /// The order the shop lists its hours in.
    public static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}

/// A wall-clock time in the shop's time zone.
public struct TimeOfDay: Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int = 0) {
        precondition((0...23).contains(hour), "Hour must be 0-23")
        precondition((0...59).contains(minute), "Minute must be 0-59")
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// "10 AM", "7 PM", "10:30 AM", "12 PM". Formatted by hand so it reads the
    /// same on every device, whatever its locale or 24-hour setting.
    public var label: String {
        let suffix = hour < 12 ? "AM" : "PM"
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        let minutes = minute == 0 ? "" : (minute < 10 ? ":0\(minute)" : ":\(minute)")
        return "\(twelveHour)\(minutes) \(suffix)"
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// When the shop is open on a given day. Closing is always later the same day.
public struct OpeningHours: Hashable, Sendable {
    public let opens: TimeOfDay
    public let closes: TimeOfDay

    public init(opens: TimeOfDay, closes: TimeOfDay) {
        precondition(opens < closes, "The shop must open before it closes")
        self.opens = opens
        self.closes = closes
    }

    /// "10 AM – 7 PM".
    public var label: String { "\(opens.label) – \(closes.label)" }
}

/// The regular weekly hours. Days that aren't listed are closed.
public struct WeeklySchedule: Hashable, Sendable {
    private let days: [Weekday: OpeningHours]

    public init(_ days: [Weekday: OpeningHours]) {
        self.days = days
    }

    public func hours(on day: Weekday) -> OpeningHours? {
        days[day]
    }

    public var isAlwaysClosed: Bool { days.isEmpty }
}

/// Whether the shop is open right now.
public enum ShopStatus: Equatable, Sendable {
    case open(closesAt: Date)
    case closed(opensAt: Date?)

    public var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}

/// A ready-to-display summary of `ShopStatus`.
public struct StatusSummary: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case open
        case changingSoon
        case closed
    }

    /// "Open now", "Closing soon", "Opening soon" or "Closed".
    public let headline: String
    /// "Closes 7 PM", "Opens 10 AM tomorrow", "Opens Monday 10 AM".
    public let detail: String
    public let tone: Tone

    public var accessibilityLabel: String { "\(headline). \(detail)." }
}

/// Answers time questions in the shop's own time zone, wherever the phone is.
public struct ShopClock: Sendable {
    public let schedule: WeeklySchedule
    public let calendar: Calendar
    /// How close to opening or closing counts as "soon".
    public let soonThreshold: TimeInterval

    public init(schedule: WeeklySchedule, timeZone: TimeZone, soonThreshold: TimeInterval = 60 * 60) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.schedule = schedule
        self.calendar = calendar
        self.soonThreshold = soonThreshold
    }

    public func weekday(of date: Date) -> Weekday {
        // `.weekday` is always 1...7 for the Gregorian calendar.
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    /// When the shop is open on the calendar day containing `date`.
    public func openInterval(onDayOf date: Date) -> DateInterval? {
        guard let hours = schedule.hours(on: weekday(of: date)) else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        guard let opens = moment(on: day, at: hours.opens),
              let closes = moment(on: day, at: hours.closes),
              opens < closes
        else { return nil }
        return DateInterval(start: opens, end: closes)
    }

    public func status(at now: Date) -> ShopStatus {
        if let today = openInterval(onDayOf: now), today.start <= now, now < today.end {
            return .open(closesAt: today.end)
        }
        return .closed(opensAt: nextOpening(after: now))
    }

    /// The next time the doors open, strictly after `now`.
    public func nextOpening(after now: Date) -> Date? {
        // A week and a day covers every case, including "opens at this time next week".
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let interval = openInterval(onDayOf: day),
                  interval.start > now
            else { continue }
            return interval.start
        }
        return nil
    }

    public func summary(at now: Date) -> StatusSummary {
        switch status(at: now) {
        case .open(let closesAt):
            let soon = closesAt.timeIntervalSince(now) <= soonThreshold
            return StatusSummary(
                headline: soon ? "Closing soon" : "Open now",
                detail: "Closes \(timeLabel(for: closesAt))",
                tone: soon ? .changingSoon : .open
            )
        case .closed(let opensAt?):
            let soon = opensAt.timeIntervalSince(now) <= soonThreshold
            return StatusSummary(
                headline: soon ? "Opening soon" : "Closed",
                detail: "Opens \(openingLabel(for: opensAt, relativeTo: now))",
                tone: soon ? .changingSoon : .closed
            )
        case .closed(nil):
            return StatusSummary(headline: "Closed", detail: "Call for hours", tone: .closed)
        }
    }

    /// "Today 10 AM – 7 PM" or "Closed today".
    public func todayLabel(at now: Date) -> String {
        guard let hours = schedule.hours(on: weekday(of: now)) else { return "Closed today" }
        return "Today \(hours.label)"
    }

    /// The wall-clock time of `date` in the shop's time zone: "7 PM".
    public func timeLabel(for date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0).label
    }

    /// "10 AM" (today), "10 AM tomorrow", or "Monday 10 AM".
    func openingLabel(for date: Date, relativeTo now: Date) -> String {
        let time = timeLabel(for: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(time) tomorrow"
        }
        return "\(weekday(of: date).name) \(time)"
    }

    private func moment(on day: DateComponents, at time: TimeOfDay) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}
