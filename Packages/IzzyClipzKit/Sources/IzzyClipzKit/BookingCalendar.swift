import Foundation

/// A calendar date in the shop's time zone.
///
/// Dates are plain year/month/day values so a day on the booking calendar is
/// the same day for everyone, wherever their phone thinks it is.
public struct CalendarDay: Hashable, Comparable, Identifiable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let weekday: Weekday

    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month), "Month must be 1-12")
        precondition((1...CalendarDay.numberOfDays(inMonth: month, year: year)).contains(day), "No such day")
        self.init(dayNumber: CalendarDay.dayNumber(year: year, month: month, day: day))
    }

    /// "2026-10-30".
    public var id: String {
        "\(year)-\(CalendarDay.twoDigits(month))-\(CalendarDay.twoDigits(day))"
    }

    /// The day `days` later (or earlier, when negative).
    public func adding(days: Int) -> CalendarDay {
        CalendarDay(dayNumber: dayNumber + days)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Day arithmetic
    //
    // Days are counted from January 1, 1970 on the proleptic Gregorian
    // calendar, using Howard Hinnant's `days_from_civil` algorithms. Pure
    // integer math: no time zones, so no daylight saving surprises.

    /// Days since January 1, 1970.
    var dayNumber: Int {
        CalendarDay.dayNumber(year: year, month: month, day: day)
    }

    init(dayNumber: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        self.year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.month = month
        self.day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        // January 1, 1970 was a Thursday.
        let sinceSunday = ((dayNumber + 4) % 7 + 7) % 7
        self.weekday = Weekday(rawValue: sinceSunday + 1) ?? .sunday
    }

    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let marchYear = month <= 2 ? year - 1 : year
        let era = (marchYear >= 0 ? marchYear : marchYear - 399) / 400
        let yearOfEra = marchYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func numberOfDays(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    static let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// Where a start time falls in the shop's day, for grouping time chips.
public enum DayPart: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Before noon.
    case morning
    /// Noon until 5 PM.
    case afternoon
    /// 5 PM and later.
    case evening

    public init(time: TimeOfDay) {
        switch time.hour {
        case ..<12: self = .morning
        case ..<17: self = .afternoon
        default: self = .evening
        }
    }

    public var id: String { rawValue }

    /// "Morning", "Afternoon", "Evening".
    public var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }
}

/// Whether a day can be picked on the booking calendar, and why not.
public enum DayAvailability: Hashable, Sendable {
    /// Open, with at least one start time that fits.
    case open(hours: OpeningHours, startTimes: [Date])
    /// The shop is closed that day of the week.
    case closed
    /// Before today.
    case past
    /// Open, but no start time is far enough ahead or ends before closing.
    case noTimesLeft
    /// Later than the last day that can be booked.
    case outsideWindow

    public var isBookable: Bool {
        if case .open = self { return true }
        return false
    }
}

/// One month of the booking calendar, laid out Sunday first.
public struct MonthPage: Hashable, Identifiable, Sendable {
    public let year: Int
    public let month: Int
    /// "October 2026".
    public let title: String
    /// Empty cells before day 1 in a Sunday-first week grid.
    public let leadingBlanks: Int
    /// Every day of the month, in order.
    public let days: [CalendarDay]

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Month must be 1-12")
        let first = CalendarDay(year: year, month: month, day: 1)
        self.year = year
        self.month = month
        self.title = "\(CalendarDay.monthNames[month - 1]) \(year)"
        self.leadingBlanks = first.weekday.rawValue - Weekday.sunday.rawValue
        self.days = (0..<CalendarDay.numberOfDays(inMonth: month, year: year)).map { first.adding(days: $0) }
    }

    /// "2026-10".
    public var id: String {
        "\(year)-\(CalendarDay.twoDigits(month))"
    }
}

/// A start time that can be picked on the booking calendar.
public struct TimeSlot: Hashable, Identifiable, Sendable {
    public let start: Date
    /// The start's wall-clock time in the shop.
    public let time: TimeOfDay
    public let part: DayPart

    public init(start: Date, time: TimeOfDay) {
        self.start = start
        self.time = time
        self.part = DayPart(time: time)
    }

    /// "1430" (24-hour, zero-padded), e.g. for accessibility identifiers.
    public var id: String {
        CalendarDay.twoDigits(time.hour) + CalendarDay.twoDigits(time.minute)
    }

    /// "2:30 PM".
    public var label: String { time.label }
}

/// The app's booking calendar: which days and start times to offer.
///
/// It only knows the shop's hours, not the barbers' real calendars; Squire
/// confirms the actual slot. Everything is worked out on the shop's wall clock
/// in its own time zone, so slots stay at 10 AM, 10:30 AM… across daylight
/// saving changes and wherever the phone is.
public struct BookingCalendar: Sendable {
    public let clock: ShopClock
    /// Minutes between start times, counted from opening.
    public let slotIntervalMinutes: Int
    /// A slot must start at least this long after now.
    public let leadTimeMinutes: Int
    /// How many days after today can be booked: today + `windowDays` is the last.
    public let windowDays: Int

    public init(clock: ShopClock, slotIntervalMinutes: Int = 30, leadTimeMinutes: Int = 30, windowDays: Int = 60) {
        precondition(slotIntervalMinutes > 0, "Slots need a positive interval")
        precondition(leadTimeMinutes >= 0, "Lead time can't be negative")
        precondition(windowDays >= 0, "The booking window can't be negative")
        self.clock = clock
        self.slotIntervalMinutes = slotIntervalMinutes
        self.leadTimeMinutes = leadTimeMinutes
        self.windowDays = windowDays
    }

    private var calendar: Calendar { clock.calendar }

    // MARK: Days

    /// The shop's calendar day at `date`.
    public func day(containing date: Date) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            // Gregorian components are always available; fall back to UTC days.
            return CalendarDay(dayNumber: Int((date.timeIntervalSince1970 / 86_400).rounded(.down)))
        }
        return CalendarDay(year: year, month: month, day: day)
    }

    /// Midnight at the start of `day` in the shop's time zone.
    public func startOfDay(_ day: CalendarDay) -> Date {
        // Noon always exists, even where a time zone skips midnight.
        if let noon = date(on: day, at: TimeOfDay(hour: 12)) {
            return calendar.startOfDay(for: noon)
        }
        let utcMidnight = Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400)
        return utcMidnight.addingTimeInterval(-TimeInterval(calendar.timeZone.secondsFromGMT(for: utcMidnight)))
    }

    /// The last day that can be booked: `windowDays` after today.
    public func lastBookableDay(now: Date) -> CalendarDay {
        day(containing: now).adding(days: windowDays)
    }

    /// Whether `day` can be booked for an appointment of `durationMinutes`.
    public func availability(of day: CalendarDay, durationMinutes: Int, now: Date) -> DayAvailability {
        precondition(durationMinutes > 0, "An appointment needs a length")
        switch check(day, now: now) {
        case .unavailable(let reason):
            return reason
        case .opens(let hours):
            let slots = candidateSlots(on: day, hours: hours, durationMinutes: durationMinutes, now: now)
            if slots.isEmpty { return .noTimesLeft }
            return .open(hours: hours, startTimes: slots.map(\.start))
        }
    }

    /// The start times on `day`, in order. Empty unless the day is bookable.
    ///
    /// Slots start at opening and every `slotIntervalMinutes` after, as long as
    /// the appointment ends by closing and starts at least `leadTimeMinutes`
    /// after `now`.
    public func slots(on day: CalendarDay, durationMinutes: Int, now: Date) -> [TimeSlot] {
        precondition(durationMinutes > 0, "An appointment needs a length")
        guard case .opens(let hours) = check(day, now: now) else { return [] }
        return candidateSlots(on: day, hours: hours, durationMinutes: durationMinutes, now: now)
    }

    /// The first day from today on with a start time that fits, if any.
    public func firstBookableDay(durationMinutes: Int, now: Date) -> CalendarDay? {
        precondition(durationMinutes > 0, "An appointment needs a length")
        let today = day(containing: now)
        return (0...windowDays)
            .lazy
            .map { today.adding(days: $0) }
            .first { availability(of: $0, durationMinutes: durationMinutes, now: now).isBookable }
    }

    /// This month through the month of the last bookable day.
    public func months(now: Date) -> [MonthPage] {
        let first = day(containing: now)
        let last = lastBookableDay(now: now)
        var pages: [MonthPage] = []
        var year = first.year, month = first.month
        while (year, month) <= (last.year, last.month) {
            pages.append(MonthPage(year: year, month: month))
            if month == 12 {
                year += 1
                month = 1
            } else {
                month += 1
            }
        }
        return pages
    }

    /// The moment the shop's wall clock shows `time` on `day`, or `nil` if that
    /// time doesn't exist that day (it's skipped when clocks spring forward).
    public func date(on day: CalendarDay, at time: TimeOfDay) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }
        // Calendars move a skipped time to a real one; that's not what was asked for.
        let shown = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard shown.year == day.year, shown.month == day.month, shown.day == day.day,
              shown.hour == time.hour, shown.minute == time.minute
        else { return nil }
        return date
    }

    // MARK: Labels
    //
    // Formatted by hand so they read the same on every device, whatever its
    // locale, language or 24-hour setting.

    /// "Thursday, October 29".
    public func longLabel(for day: CalendarDay) -> String {
        "\(day.weekday.name), \(CalendarDay.monthNames[day.month - 1]) \(day.day)"
    }

    /// "Thu, Oct 29".
    public func shortLabel(for day: CalendarDay) -> String {
        "\(day.weekday.shortName), \(CalendarDay.shortMonthNames[day.month - 1]) \(day.day)"
    }

    /// "Thu, Oct 29 at 2:30 PM", in shop time.
    public func dateTimeLabel(for date: Date) -> String {
        "\(shortLabel(for: day(containing: date))) at \(timeLabel(for: date))"
    }

    /// "2:30 PM", in shop time.
    public func timeLabel(for date: Date) -> String {
        clock.timeLabel(for: date)
    }

    // MARK: Slots

    private enum DayCheck {
        case opens(OpeningHours)
        case unavailable(DayAvailability)
    }

    /// Everything about a day that doesn't depend on the appointment's length.
    private func check(_ day: CalendarDay, now: Date) -> DayCheck {
        let today = self.day(containing: now)
        if day < today { return .unavailable(.past) }
        if day > today.adding(days: windowDays) { return .unavailable(.outsideWindow) }
        guard let hours = clock.schedule.hours(on: day.weekday) else { return .unavailable(.closed) }
        return .opens(hours)
    }

    private func candidateSlots(on day: CalendarDay, hours: OpeningHours, durationMinutes: Int, now: Date) -> [TimeSlot] {
        guard let closes = date(on: day, at: hours.closes) else { return [] }
        let earliest = now.addingTimeInterval(TimeInterval(leadTimeMinutes) * 60)
        let length = TimeInterval(durationMinutes) * 60
        var slots: [TimeSlot] = []
        var minutes = hours.opens.minutesSinceMidnight
        while minutes < hours.closes.minutesSinceMidnight {
            let time = TimeOfDay(hour: minutes / 60, minute: minutes % 60)
            if let start = date(on: day, at: time) {
                if start.addingTimeInterval(length) > closes { break }
                if start >= earliest { slots.append(TimeSlot(start: start, time: time)) }
            }
            minutes += slotIntervalMinutes
        }
        return slots
    }
}
