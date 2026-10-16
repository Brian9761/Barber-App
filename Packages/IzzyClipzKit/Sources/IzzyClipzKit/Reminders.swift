import Foundation

/// A "time for a fresh cut" reminder.
public struct ScheduledReminder: Hashable, Sendable {
    public let date: Date
    /// Weeks since the last cut when this fires.
    public let weeksSinceCut: Int
}

/// Works out when to nudge a client to book their next cut.
///
/// Reminders fire every `intervalWeeks` after the last cut, at a fixed local
/// time. Each one is a separate calendar date rather than a repeating timer,
/// so they stay at the same wall-clock time across daylight saving changes.
public struct ReminderPlanner: Sendable {
    public static let intervalChoices = [2, 3, 4, 5, 6]
    public static let defaultIntervalWeeks = 3

    public let calendar: Calendar
    public let hour: Int
    public let minute: Int

    public init(calendar: Calendar = .current, hour: Int = 10, minute: Int = 0) {
        precondition((0...23).contains(hour) && (0...59).contains(minute), "Invalid reminder time")
        self.calendar = calendar
        self.hour = hour
        self.minute = minute
    }

    /// The next `count` reminders after `now`, for a cut on `lastCut`.
    public func upcoming(lastCut: Date, intervalWeeks: Int, now: Date, count: Int) -> [ScheduledReminder] {
        guard intervalWeeks > 0, count > 0 else { return [] }
        let cutDay = calendar.startOfDay(for: lastCut)
        let today = calendar.startOfDay(for: now)
        let daysSinceCut = max(0, calendar.dateComponents([.day], from: cutDay, to: today).day ?? 0)
        let intervalDays = intervalWeeks * 7

        // Skip intervals that are already over instead of walking from the cut
        // one interval at a time; this stays fast even for a cut years ago.
        var step = max(1, daysSinceCut / intervalDays)
        var reminders: [ScheduledReminder] = []
        // A few extra steps absorb the interval that might still fall earlier today.
        while reminders.count < count, step <= daysSinceCut / intervalDays + count + 2 {
            if let day = calendar.date(byAdding: .day, value: step * intervalDays, to: cutDay),
               let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               date > now {
                reminders.append(ScheduledReminder(date: date, weeksSinceCut: step * intervalWeeks))
            }
            step += 1
        }
        return reminders
    }

    public static func title() -> String {
        "Time for a fresh cut"
    }

    public static func body(weeksSinceCut: Int, shopName: String) -> String {
        let weeks = weeksSinceCut == 1 ? "1 week" : "\(weeksSinceCut) weeks"
        return "It's been \(weeks) since your last cut. Tap to book at \(shopName)."
    }
}
