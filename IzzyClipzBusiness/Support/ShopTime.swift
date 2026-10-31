import Foundation
import IzzyClipzKit

/// Dates and times on the shop's wall clock, whatever time zone the phone is in.
///
/// The schedule, bookings and time off are always shown and entered in the
/// shop's time zone (America/Los_Angeles): an owner travelling with the phone
/// still sees "10 AM" for a 10 AM haircut. Labels come from the Kit, which
/// formats them by hand so they read the same on every device.
struct ShopTime: Sendable {
    let shop: ShopInfo
    let calendar: Calendar
    let bookingCalendar: BookingCalendar

    init(shop: ShopInfo = .izzyClipz) {
        self.shop = shop
        self.bookingCalendar = shop.bookingCalendar
        self.calendar = shop.clock.calendar
    }

    var timeZone: TimeZone { shop.timeZone }

    /// The shop day containing `date`.
    func day(containing date: Date) -> LocalDate {
        LocalDate(containing: date, in: timeZone)
    }

    /// Noon on `day` in the shop: a safe moment to hand a date picker, since
    /// noon exists on every day, daylight saving or not.
    func noon(on day: LocalDate) -> Date {
        bookingCalendar.date(on: day.calendarDay, at: TimeOfDay(hour: 12))
            ?? bookingCalendar.startOfDay(day.calendarDay).addingTimeInterval(12 * 3_600)
    }

    /// Midnight at the start of `day` in the shop.
    func startOfDay(_ day: LocalDate) -> Date {
        bookingCalendar.startOfDay(day.calendarDay)
    }

    /// The moment the shop's clock shows `hour:minute` on `day`; `nil` when
    /// that time is skipped by a daylight saving change.
    func date(on day: LocalDate, hour: Int, minute: Int) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return bookingCalendar.date(on: day.calendarDay, at: TimeOfDay(hour: hour, minute: minute))
    }

    /// The shop's opening hours on `day`, as moments, or `nil` when closed.
    func openInterval(on day: LocalDate) -> DateInterval? {
        shop.clock.openInterval(onDayOf: noon(on: day))
    }

    /// "2:30 PM".
    func time(_ date: Date) -> String {
        bookingCalendar.timeLabel(for: date)
    }

    /// "2:30 – 3:15 PM" style ranges, written out in full: "2:30 PM – 3:15 PM".
    func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "Monday, November 2".
    func longDay(_ day: LocalDate) -> String {
        bookingCalendar.longLabel(for: day.calendarDay)
    }

    /// "Mon, Nov 2".
    func shortDay(_ day: LocalDate) -> String {
        bookingCalendar.shortLabel(for: day.calendarDay)
    }

    /// "Today", "Tomorrow", "Yesterday", or "Mon, Nov 2".
    func relativeDay(_ day: LocalDate, today: LocalDate) -> String {
        switch day {
        case today: return "Today"
        case today.adding(days: 1): return "Tomorrow"
        case today.adding(days: -1): return "Yesterday"
        default: return shortDay(day)
        }
    }

    /// "Mon, Nov 2 at 2:30 PM".
    func dayAndTime(_ date: Date) -> String {
        bookingCalendar.dateTimeLabel(for: date)
    }
}
