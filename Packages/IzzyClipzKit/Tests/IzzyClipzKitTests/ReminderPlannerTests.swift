import XCTest
@testable import IzzyClipzKit

final class ReminderPlannerTests: XCTestCase {
    let planner = ReminderPlanner(calendar: pacificCalendar, hour: 10)

    func testUpcomingReminders() {
        let reminders = planner.upcoming(
            lastCut: pacificDate(2026, 10, 1, 15),
            intervalWeeks: 3,
            now: pacificDate(2026, 10, 16, 12),
            count: 3
        )
        XCTAssertEqual(reminders.map(\.date), [
            pacificDate(2026, 10, 22, 10),
            pacificDate(2026, 11, 12, 10),
            pacificDate(2026, 12, 3, 10),
        ])
        XCTAssertEqual(reminders.map(\.weeksSinceCut), [3, 6, 9])
    }

    func testTodaysReminderIsKeptUntilItFires() {
        let cut = pacificDate(2026, 10, 1)
        let beforeTen = planner.upcoming(lastCut: cut, intervalWeeks: 2, now: pacificDate(2026, 10, 15, 9, 59), count: 1)
        XCTAssertEqual(beforeTen.first?.date, pacificDate(2026, 10, 15, 10))

        let afterTen = planner.upcoming(lastCut: cut, intervalWeeks: 2, now: pacificDate(2026, 10, 15, 10), count: 1)
        XCTAssertEqual(afterTen.first?.date, pacificDate(2026, 10, 29, 10))
        XCTAssertEqual(afterTen.first?.weeksSinceCut, 4)
    }

    func testCutLongAgoStillGivesFutureReminders() {
        let now = pacificDate(2026, 10, 16, 12)
        let reminders = planner.upcoming(lastCut: pacificDate(2019, 1, 1), intervalWeeks: 4, now: now, count: 5)
        XCTAssertEqual(reminders.count, 5)
        XCTAssertTrue(reminders.allSatisfy { $0.date > now })
        for (earlier, later) in zip(reminders, reminders.dropFirst()) {
            let days = pacificCalendar.dateComponents([.day], from: earlier.date, to: later.date).day
            XCTAssertEqual(days, 28)
            XCTAssertEqual(later.weeksSinceCut - earlier.weeksSinceCut, 4)
        }
        // The first reminder is the very next one, not one further out.
        XCTAssertLessThanOrEqual(reminders[0].date.timeIntervalSince(now), 28 * 24 * 60 * 60)
    }

    func testCutInTheFutureCountsFromThatDay() {
        let reminders = planner.upcoming(
            lastCut: pacificDate(2026, 10, 20),
            intervalWeeks: 2,
            now: pacificDate(2026, 10, 16, 12),
            count: 1
        )
        XCTAssertEqual(reminders.first?.date, pacificDate(2026, 11, 3, 10))
        XCTAssertEqual(reminders.first?.weeksSinceCut, 2)
    }

    func testRemindersKeepTheirTimeAcrossDaylightSaving() {
        // Reminders on either side of the November 1 change still fire at 10 AM.
        let reminders = planner.upcoming(
            lastCut: pacificDate(2026, 10, 1),
            intervalWeeks: 2,
            now: pacificDate(2026, 10, 2),
            count: 4
        )
        for reminder in reminders {
            XCTAssertEqual(pacificCalendar.component(.hour, from: reminder.date), 10)
            XCTAssertEqual(pacificCalendar.component(.minute, from: reminder.date), 0)
        }
        XCTAssertEqual(reminders.map(\.date), [
            pacificDate(2026, 10, 15, 10),
            pacificDate(2026, 10, 29, 10),
            pacificDate(2026, 11, 12, 10),
            pacificDate(2026, 11, 26, 10),
        ])
    }

    func testNothingToScheduleForBadInput() {
        let cut = pacificDate(2026, 10, 1)
        let now = pacificDate(2026, 10, 2)
        XCTAssertEqual(planner.upcoming(lastCut: cut, intervalWeeks: 0, now: now, count: 3), [])
        XCTAssertEqual(planner.upcoming(lastCut: cut, intervalWeeks: 3, now: now, count: 0), [])
    }

    func testIntervalChoicesIncludeTheDefault() {
        XCTAssertTrue(ReminderPlanner.intervalChoices.contains(ReminderPlanner.defaultIntervalWeeks))
        XCTAssertTrue(ReminderPlanner.intervalChoices.allSatisfy { $0 > 0 })
    }

    func testCopy() {
        XCTAssertEqual(ReminderPlanner.title(), "Time for a fresh cut")
        XCTAssertEqual(
            ReminderPlanner.body(weeksSinceCut: 3, shopName: "Izzy Clipz"),
            "It's been 3 weeks since your last cut. Tap to book at Izzy Clipz."
        )
        XCTAssertEqual(
            ReminderPlanner.body(weeksSinceCut: 1, shopName: "Izzy Clipz"),
            "It's been 1 week since your last cut. Tap to book at Izzy Clipz."
        )
    }
}
