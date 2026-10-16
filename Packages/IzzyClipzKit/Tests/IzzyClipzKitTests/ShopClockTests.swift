import XCTest
@testable import IzzyClipzKit

final class TimeOfDayTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(TimeOfDay(hour: 0).label, "12 AM")
        XCTAssertEqual(TimeOfDay(hour: 9, minute: 5).label, "9:05 AM")
        XCTAssertEqual(TimeOfDay(hour: 10).label, "10 AM")
        XCTAssertEqual(TimeOfDay(hour: 10, minute: 30).label, "10:30 AM")
        XCTAssertEqual(TimeOfDay(hour: 12).label, "12 PM")
        XCTAssertEqual(TimeOfDay(hour: 19).label, "7 PM")
        XCTAssertEqual(TimeOfDay(hour: 23, minute: 59).label, "11:59 PM")
    }

    func testOpeningHoursLabel() {
        XCTAssertEqual(OpeningHours(opens: TimeOfDay(hour: 10), closes: TimeOfDay(hour: 19)).label, "10 AM – 7 PM")
    }

    func testOrdering() {
        XCTAssertLessThan(TimeOfDay(hour: 9, minute: 59), TimeOfDay(hour: 10))
    }
}

final class ShopClockTests: XCTestCase {
    // October 16, 2026 is a Friday.

    func testWeekdays() {
        XCTAssertEqual(shopClock.weekday(of: pacificDate(2026, 10, 16, 12)), .friday)
        XCTAssertEqual(shopClock.weekday(of: pacificDate(2026, 10, 18, 12)), .sunday)
        XCTAssertEqual(shopClock.weekday(of: pacificDate(2026, 10, 19, 0, 0)), .monday)
    }

    func testShopHours() {
        for day in [Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday] {
            XCTAssertEqual(shopClock.schedule.hours(on: day)?.label, "10 AM – 7 PM", day.name)
        }
        XCTAssertEqual(shopClock.schedule.hours(on: .sunday)?.label, "10 AM – 6 PM")
    }

    func testOpenMidday() {
        let now = pacificDate(2026, 10, 16, 12)
        XCTAssertEqual(shopClock.status(at: now), .open(closesAt: pacificDate(2026, 10, 16, 19)))
        XCTAssertEqual(shopClock.summary(at: now), StatusSummary(headline: "Open now", detail: "Closes 7 PM", tone: .open))
    }

    func testOpensExactlyOnTheHour() {
        XCTAssertTrue(shopClock.status(at: pacificDate(2026, 10, 16, 10)).isOpen)
        XCTAssertFalse(shopClock.status(at: pacificDate(2026, 10, 16, 9, 59)).isOpen)
    }

    func testClosesExactlyOnTheHour() {
        XCTAssertTrue(shopClock.status(at: pacificDate(2026, 10, 16, 18, 59)).isOpen)
        XCTAssertFalse(shopClock.status(at: pacificDate(2026, 10, 16, 19)).isOpen)
    }

    func testClosingSoon() {
        XCTAssertEqual(
            shopClock.summary(at: pacificDate(2026, 10, 16, 18, 30)),
            StatusSummary(headline: "Closing soon", detail: "Closes 7 PM", tone: .changingSoon)
        )
        // Exactly an hour out counts as soon; a minute more doesn't.
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 16, 18)).headline, "Closing soon")
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 16, 17, 59)).headline, "Open now")
    }

    func testSundayClosesEarly() {
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 18, 17, 30)).detail, "Closes 6 PM")
        XCTAssertFalse(shopClock.status(at: pacificDate(2026, 10, 18, 18, 30)).isOpen)
    }

    func testBeforeOpening() {
        XCTAssertEqual(
            shopClock.summary(at: pacificDate(2026, 10, 16, 7)),
            StatusSummary(headline: "Closed", detail: "Opens 10 AM", tone: .closed)
        )
        XCTAssertEqual(
            shopClock.summary(at: pacificDate(2026, 10, 16, 9, 15)),
            StatusSummary(headline: "Opening soon", detail: "Opens 10 AM", tone: .changingSoon)
        )
    }

    func testAfterClosingOpensTomorrow() {
        let now = pacificDate(2026, 10, 16, 20)
        XCTAssertEqual(shopClock.status(at: now), .closed(opensAt: pacificDate(2026, 10, 17, 10)))
        XCTAssertEqual(shopClock.summary(at: now), StatusSummary(headline: "Closed", detail: "Opens 10 AM tomorrow", tone: .closed))
    }

    func testJustBeforeMidnight() {
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 17, 23, 59)).detail, "Opens 10 AM tomorrow")
    }

    func testJustAfterMidnight() {
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 18, 0, 1)).detail, "Opens 10 AM")
    }

    func testTodayLabel() {
        XCTAssertEqual(shopClock.todayLabel(at: pacificDate(2026, 10, 16, 8)), "Today 10 AM – 7 PM")
        XCTAssertEqual(shopClock.todayLabel(at: pacificDate(2026, 10, 18, 8)), "Today 10 AM – 6 PM")
    }

    // MARK: Closed days

    let mondaysOnly = ShopClock(
        schedule: WeeklySchedule([.monday: OpeningHours(opens: TimeOfDay(hour: 9, minute: 30), closes: TimeOfDay(hour: 17))]),
        timeZone: TimeZone(identifier: "America/Los_Angeles")!
    )

    func testNamesTheDayWhenTheNextOpeningIsFurtherOut() {
        // Wednesday October 14, 2026.
        let now = pacificDate(2026, 10, 14, 12)
        XCTAssertEqual(mondaysOnly.status(at: now), .closed(opensAt: pacificDate(2026, 10, 19, 9, 30)))
        XCTAssertEqual(mondaysOnly.summary(at: now).detail, "Opens Monday 9:30 AM")
        XCTAssertEqual(mondaysOnly.todayLabel(at: now), "Closed today")
    }

    func testFindsTheSameDayNextWeek() {
        // Monday October 19, 2026, after closing: next opening is a week later.
        let now = pacificDate(2026, 10, 19, 18)
        XCTAssertEqual(mondaysOnly.nextOpening(after: now), pacificDate(2026, 10, 26, 9, 30))
        XCTAssertEqual(mondaysOnly.summary(at: now).detail, "Opens Monday 9:30 AM")
    }

    func testNeverOpen() {
        let closed = ShopClock(schedule: WeeklySchedule([:]), timeZone: pacific)
        XCTAssertTrue(closed.schedule.isAlwaysClosed)
        XCTAssertEqual(closed.status(at: pacificDate(2026, 10, 16, 12)), .closed(opensAt: nil))
        XCTAssertEqual(closed.summary(at: pacificDate(2026, 10, 16, 12)), StatusSummary(headline: "Closed", detail: "Call for hours", tone: .closed))
    }

    // MARK: Time zones and daylight saving

    func testUsesTheShopsTimeZoneWhateverTheDeviceUses() {
        // 2:00 UTC on Oct 16 is 7:00 PM Thursday in Oceanside: just closed.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 2))!
        XCTAssertEqual(shopClock.weekday(of: now), .thursday)
        XCTAssertEqual(shopClock.status(at: now), .closed(opensAt: pacificDate(2026, 10, 16, 10)))
        XCTAssertEqual(shopClock.summary(at: now).detail, "Opens 10 AM tomorrow")
    }

    func testSpringForward() {
        // Clocks jump from 2 AM to 3 AM on Sunday March 8, 2026.
        let sunday = shopClock.openInterval(onDayOf: pacificDate(2026, 3, 8, 12))
        XCTAssertEqual(sunday?.start, pacificDate(2026, 3, 8, 10))
        XCTAssertEqual(sunday?.duration, 8 * 60 * 60)
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 3, 8, 1)).detail, "Opens 10 AM")
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 3, 7, 22)).detail, "Opens 10 AM tomorrow")
        XCTAssertEqual(shopClock.timeLabel(for: pacificDate(2026, 3, 8, 10)), "10 AM")
    }

    func testFallBack() {
        // Clocks fall back from 2 AM to 1 AM on Sunday November 1, 2026.
        let sunday = shopClock.openInterval(onDayOf: pacificDate(2026, 11, 1, 12))
        XCTAssertEqual(sunday?.start, pacificDate(2026, 11, 1, 10))
        XCTAssertEqual(sunday?.duration, 8 * 60 * 60)
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 10, 31, 23)).detail, "Opens 10 AM tomorrow")
        XCTAssertEqual(shopClock.summary(at: pacificDate(2026, 11, 1, 17, 30)).detail, "Closes 6 PM")
    }

    func testStatusAcrossAWholeWeekIsConsistent() {
        // Walk a week in 15-minute steps: whenever the shop is open the next
        // close must be later the same day, and whenever it's closed the next
        // opening must be in the future and within a week.
        var now = pacificDate(2026, 10, 12)
        let end = pacificDate(2026, 10, 19)
        while now < end {
            switch shopClock.status(at: now) {
            case .open(let closesAt):
                XCTAssertGreaterThan(closesAt, now)
                XCTAssertTrue(pacificCalendar.isDate(closesAt, inSameDayAs: now))
            case .closed(let opensAt):
                XCTAssertNotNil(opensAt)
                if let opensAt {
                    XCTAssertGreaterThan(opensAt, now)
                    XCTAssertLessThanOrEqual(opensAt.timeIntervalSince(now), 7 * 24 * 60 * 60)
                }
            }
            now = now.addingTimeInterval(15 * 60)
        }
    }
}
