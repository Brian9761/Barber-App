import XCTest
@testable import IzzyClipzKit

final class CalendarDayTests: XCTestCase {
    func testIDsAreZeroPadded() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 30).id, "2026-10-30")
        XCTAssertEqual(CalendarDay(year: 2027, month: 1, day: 5).id, "2027-01-05")
    }

    func testWeekdays() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 1).weekday, .thursday)
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 28).weekday, .wednesday)
        XCTAssertEqual(CalendarDay(year: 2026, month: 11, day: 1).weekday, .sunday)
        XCTAssertEqual(CalendarDay(year: 2028, month: 2, day: 29).weekday, .tuesday)
        XCTAssertEqual(CalendarDay(year: 1970, month: 1, day: 1).weekday, .thursday)
        XCTAssertEqual(CalendarDay(year: 1969, month: 12, day: 31).weekday, .wednesday)
        XCTAssertEqual(CalendarDay(year: 2000, month: 1, day: 1).weekday, .saturday)
    }

    func testOrdering() {
        let days = [
            CalendarDay(year: 2027, month: 1, day: 1),
            CalendarDay(year: 2026, month: 12, day: 31),
            CalendarDay(year: 2026, month: 2, day: 3),
            CalendarDay(year: 2026, month: 10, day: 30),
        ]
        XCTAssertEqual(days.sorted().map(\.id), ["2026-02-03", "2026-10-30", "2026-12-31", "2027-01-01"])
        XCTAssertLessThan(CalendarDay(year: 2026, month: 10, day: 30), CalendarDay(year: 2026, month: 10, day: 31))
    }

    func testAddingDaysAcrossMonthsYearsAndLeapDays() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1), CalendarDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(CalendarDay(year: 2027, month: 1, day: 1).adding(days: -1), CalendarDay(year: 2026, month: 12, day: 31))
        XCTAssertEqual(CalendarDay(year: 2027, month: 2, day: 28).adding(days: 1), CalendarDay(year: 2027, month: 3, day: 1))
        XCTAssertEqual(CalendarDay(year: 2028, month: 2, day: 28).adding(days: 1), CalendarDay(year: 2028, month: 2, day: 29))
        XCTAssertEqual(CalendarDay(year: 2028, month: 3, day: 1).adding(days: -1), CalendarDay(year: 2028, month: 2, day: 29))
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 28).adding(days: 60), CalendarDay(year: 2026, month: 12, day: 27))
        XCTAssertEqual(CalendarDay(year: 2026, month: 10, day: 28).adding(days: 0), CalendarDay(year: 2026, month: 10, day: 28))
    }

    func testDayArithmeticMatchesFoundation() {
        // Walk three years day by day and compare with Foundation's calendar.
        var day = CalendarDay(year: 2026, month: 1, day: 1)
        var date = pacificDate(2026, 1, 1, 12)
        for _ in 0..<(3 * 366) {
            let parts = pacificCalendar.dateComponents([.year, .month, .day, .weekday], from: date)
            XCTAssertEqual(day.year, parts.year)
            XCTAssertEqual(day.month, parts.month)
            XCTAssertEqual(day.day, parts.day)
            XCTAssertEqual(day.weekday.rawValue, parts.weekday, day.id)
            day = day.adding(days: 1)
            date = pacificCalendar.date(byAdding: .day, value: 1, to: date)!
        }
    }

    func testMonthLengths() {
        XCTAssertEqual((1...12).map { CalendarDay.numberOfDays(inMonth: $0, year: 2026) }, [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        XCTAssertEqual(CalendarDay.numberOfDays(inMonth: 2, year: 2028), 29)
        XCTAssertEqual(CalendarDay.numberOfDays(inMonth: 2, year: 2100), 28)
        XCTAssertEqual(CalendarDay.numberOfDays(inMonth: 2, year: 2000), 29)
    }
}

final class DayPartTests: XCTestCase {
    func testBoundaries() {
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 0)), .morning)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 10)), .morning)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 11, minute: 30)), .morning)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 11, minute: 59)), .morning)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 12)), .afternoon)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 16, minute: 59)), .afternoon)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 17)), .evening)
        XCTAssertEqual(DayPart(time: TimeOfDay(hour: 23, minute: 59)), .evening)
    }

    func testTitlesAndOrder() {
        XCTAssertEqual(DayPart.allCases, [.morning, .afternoon, .evening])
        XCTAssertEqual(DayPart.allCases.map(\.title), ["Morning", "Afternoon", "Evening"])
        XCTAssertEqual(DayPart.allCases.map(\.id), ["morning", "afternoon", "evening"])
    }
}

final class BookingCalendarTests: XCTestCase {
    let calendar = BookingCalendar(clock: shopClock)

    // Wednesday October 28, 2026, at noon in Oceanside.
    let now = pacificDate(2026, 10, 28, 12)
    let friday = CalendarDay(year: 2026, month: 10, day: 30)

    // MARK: Month pages

    func testMonthGridIsSundayFirst() {
        let october = MonthPage(year: 2026, month: 10)
        XCTAssertEqual(october.id, "2026-10")
        XCTAssertEqual(october.title, "October 2026")
        XCTAssertEqual(october.leadingBlanks, 4) // October 1, 2026 is a Thursday.
        XCTAssertEqual(october.days.count, 31)
        XCTAssertEqual(october.days.first, CalendarDay(year: 2026, month: 10, day: 1))
        XCTAssertEqual(october.days.last, CalendarDay(year: 2026, month: 10, day: 31))

        let november = MonthPage(year: 2026, month: 11)
        XCTAssertEqual(november.leadingBlanks, 0) // November 1, 2026 is a Sunday.
        XCTAssertEqual(november.days.count, 30)

        let december = MonthPage(year: 2026, month: 12)
        XCTAssertEqual(december.leadingBlanks, 2) // A Tuesday.

        XCTAssertEqual(MonthPage(year: 2028, month: 2).days.count, 29)
        XCTAssertEqual(MonthPage(year: 2027, month: 2).days.count, 28)
        XCTAssertEqual(MonthPage(year: 2026, month: 8).leadingBlanks, 6) // A Saturday.
    }

    func testMonthTitles() {
        XCTAssertEqual((1...12).map { MonthPage(year: 2027, month: $0).title }, [
            "January 2027", "February 2027", "March 2027", "April 2027", "May 2027", "June 2027",
            "July 2027", "August 2027", "September 2027", "October 2027", "November 2027", "December 2027",
        ])
    }

    func testMonthsSpanTodayThroughTheLastBookableDay() {
        XCTAssertEqual(calendar.lastBookableDay(now: now), CalendarDay(year: 2026, month: 12, day: 27))
        XCTAssertEqual(calendar.months(now: now).map(\.id), ["2026-10", "2026-11", "2026-12"])
        XCTAssertEqual(calendar.months(now: now).map(\.title), ["October 2026", "November 2026", "December 2026"])
    }

    func testMonthsCrossTheNewYear() {
        let december = pacificDate(2026, 12, 15, 9)
        XCTAssertEqual(calendar.lastBookableDay(now: december), CalendarDay(year: 2027, month: 2, day: 13))
        XCTAssertEqual(calendar.months(now: december).map(\.id), ["2026-12", "2027-01", "2027-02"])
    }

    func testShortWindows() {
        let threeDays = BookingCalendar(clock: shopClock, windowDays: 3)
        XCTAssertEqual(threeDays.months(now: now).map(\.id), ["2026-10"])
        XCTAssertEqual(threeDays.months(now: pacificDate(2026, 10, 30, 12)).map(\.id), ["2026-10", "2026-11"])

        let todayOnly = BookingCalendar(clock: shopClock, windowDays: 0)
        XCTAssertEqual(todayOnly.lastBookableDay(now: now), CalendarDay(year: 2026, month: 10, day: 28))
        XCTAssertEqual(todayOnly.months(now: now).map(\.id), ["2026-10"])
        XCTAssertTrue(todayOnly.availability(of: CalendarDay(year: 2026, month: 10, day: 28), durationMinutes: 30, now: now).isBookable)
        XCTAssertEqual(todayOnly.availability(of: CalendarDay(year: 2026, month: 10, day: 29), durationMinutes: 30, now: now), .outsideWindow)
    }

    // MARK: Slots

    func testSlotsEveryHalfHourFromOpening() {
        let slots = calendar.slots(on: friday, durationMinutes: 30, now: now)
        XCTAssertEqual(slots.count, 18)
        XCTAssertEqual(slots.first?.start, pacificDate(2026, 10, 30, 10))
        XCTAssertEqual(slots.last?.start, pacificDate(2026, 10, 30, 18, 30))
        XCTAssertEqual(slots.prefix(3).map(\.label), ["10 AM", "10:30 AM", "11 AM"])
        XCTAssertEqual(slots.prefix(3).map(\.id), ["1000", "1030", "1100"])
        for (earlier, later) in zip(slots, slots.dropFirst()) {
            XCTAssertEqual(later.start.timeIntervalSince(earlier.start), 30 * 60)
        }
    }

    func testAppointmentsMustEndByClosing() {
        func lastStart(_ minutes: Int) -> String? {
            calendar.slots(on: friday, durationMinutes: minutes, now: now).last?.label
        }
        XCTAssertEqual(lastStart(30), "6:30 PM")
        XCTAssertEqual(lastStart(45), "6 PM")
        XCTAssertEqual(lastStart(60), "6 PM")
        XCTAssertEqual(lastStart(75), "5:30 PM")
        XCTAssertEqual(lastStart(240), "3 PM")
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 240, now: now).count, 11)

        // Sunday closes at 6.
        let sunday = CalendarDay(year: 2026, month: 11, day: 8)
        XCTAssertEqual(calendar.slots(on: sunday, durationMinutes: 30, now: now).last?.label, "5:30 PM")
        XCTAssertEqual(calendar.slots(on: sunday, durationMinutes: 30, now: now).count, 16)
    }

    func testSlotTimesAndParts() {
        let slots = calendar.slots(on: friday, durationMinutes: 30, now: now)
        let byID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        XCTAssertEqual(byID["1130"]?.part, .morning)
        XCTAssertEqual(byID["1200"]?.part, .afternoon)
        XCTAssertEqual(byID["1630"]?.part, .afternoon)
        XCTAssertEqual(byID["1700"]?.part, .evening)
        XCTAssertEqual(byID["1430"]?.label, "2:30 PM")
        XCTAssertEqual(byID["1430"]?.time, TimeOfDay(hour: 14, minute: 30))
        XCTAssertEqual(byID["1430"]?.start, pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(Dictionary(grouping: slots, by: \.part).mapValues(\.count), [.morning: 4, .afternoon: 10, .evening: 4])
    }

    func testSlotIDsAreZeroPadded() {
        let early = BookingCalendar(clock: ShopClock(
            schedule: WeeklySchedule([.friday: OpeningHours(opens: TimeOfDay(hour: 9, minute: 30), closes: TimeOfDay(hour: 11))]),
            timeZone: pacific
        ))
        XCTAssertEqual(early.slots(on: friday, durationMinutes: 30, now: now).map(\.id), ["0930", "1000", "1030"])
    }

    func testCustomInterval() {
        let quarterHours = BookingCalendar(clock: shopClock, slotIntervalMinutes: 15, leadTimeMinutes: 0)
        let slots = quarterHours.slots(on: friday, durationMinutes: 15, now: now)
        XCTAssertEqual(slots.count, 36)
        XCTAssertEqual(slots.last?.label, "6:45 PM")
    }

    func testOpenDayCarriesItsHoursAndStartTimes() {
        let availability = calendar.availability(of: friday, durationMinutes: 45, now: now)
        guard case .open(let hours, let startTimes) = availability else {
            return XCTFail("Expected an open day, got \(availability)")
        }
        XCTAssertEqual(hours.label, "10 AM – 7 PM")
        XCTAssertEqual(startTimes, calendar.slots(on: friday, durationMinutes: 45, now: now).map(\.start))
        XCTAssertTrue(availability.isBookable)
    }

    // MARK: Today and lead time

    func testLeadTime() {
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 10, 10)).first?.label, "11 AM")
        // Exactly the lead time ahead still counts.
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 10)).first?.label, "10:30 AM")
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 10, 1)).first?.label, "11 AM")
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 7)).first?.label, "10 AM")

        let noLead = BookingCalendar(clock: shopClock, leadTimeMinutes: 0)
        XCTAssertEqual(noLead.slots(on: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 10)).first?.label, "10 AM")
    }

    func testLastSlotOfTheDay() {
        let lastCall = pacificDate(2026, 10, 30, 18)
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: lastCall).map(\.label), ["6:30 PM"])
        XCTAssertEqual(calendar.availability(of: friday, durationMinutes: 45, now: lastCall), .noTimesLeft)
    }

    func testTodayAfterClosingHasNoTimesLeft() {
        let evening = pacificDate(2026, 10, 30, 19, 30)
        XCTAssertEqual(calendar.availability(of: friday, durationMinutes: 30, now: evening), .noTimesLeft)
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: evening), [])
        XCTAssertFalse(calendar.availability(of: friday, durationMinutes: 30, now: evening).isBookable)

        // Too close to closing for the last slot's lead time.
        XCTAssertEqual(calendar.availability(of: friday, durationMinutes: 30, now: pacificDate(2026, 10, 30, 18, 45)), .noTimesLeft)
    }

    func testFirstBookableDaySkipsATooLateToday() {
        XCTAssertEqual(
            calendar.firstBookableDay(durationMinutes: 30, now: pacificDate(2026, 10, 30, 18, 45)),
            CalendarDay(year: 2026, month: 10, day: 31)
        )
        XCTAssertEqual(calendar.firstBookableDay(durationMinutes: 30, now: now), CalendarDay(year: 2026, month: 10, day: 28))
        // A long appointment that no longer fits today moves to tomorrow.
        XCTAssertEqual(
            calendar.firstBookableDay(durationMinutes: 240, now: pacificDate(2026, 10, 28, 15)),
            CalendarDay(year: 2026, month: 10, day: 29)
        )
    }

    func testAnAppointmentLongerThanTheDayNeverFits() {
        XCTAssertEqual(calendar.availability(of: friday, durationMinutes: 10 * 60, now: now), .noTimesLeft)
        XCTAssertNil(calendar.firstBookableDay(durationMinutes: 10 * 60, now: now))
    }

    // MARK: Past, closed and out-of-window days

    func testPastDays() {
        let yesterday = CalendarDay(year: 2026, month: 10, day: 27)
        XCTAssertEqual(calendar.availability(of: yesterday, durationMinutes: 30, now: now), .past)
        XCTAssertEqual(calendar.slots(on: yesterday, durationMinutes: 30, now: now), [])
        XCTAssertEqual(calendar.availability(of: CalendarDay(year: 2025, month: 12, day: 31), durationMinutes: 30, now: now), .past)
    }

    func testClosedWeekdays() {
        let mondaysOnly = BookingCalendar(clock: ShopClock(
            schedule: WeeklySchedule([.monday: OpeningHours(opens: TimeOfDay(hour: 9, minute: 30), closes: TimeOfDay(hour: 17))]),
            timeZone: pacific
        ))
        XCTAssertEqual(mondaysOnly.availability(of: friday, durationMinutes: 30, now: now), .closed)
        XCTAssertEqual(mondaysOnly.slots(on: friday, durationMinutes: 30, now: now), [])

        let monday = CalendarDay(year: 2026, month: 11, day: 2)
        XCTAssertEqual(mondaysOnly.firstBookableDay(durationMinutes: 30, now: now), monday)
        XCTAssertEqual(mondaysOnly.slots(on: monday, durationMinutes: 30, now: now).first?.label, "9:30 AM")
        XCTAssertEqual(mondaysOnly.slots(on: monday, durationMinutes: 30, now: now).last?.label, "4:30 PM")

        let neverOpen = BookingCalendar(clock: ShopClock(schedule: WeeklySchedule([:]), timeZone: pacific))
        XCTAssertNil(neverOpen.firstBookableDay(durationMinutes: 30, now: now))
    }

    func testOutsideTheWindow() {
        XCTAssertTrue(calendar.availability(of: CalendarDay(year: 2026, month: 12, day: 27), durationMinutes: 30, now: now).isBookable)
        XCTAssertEqual(calendar.availability(of: CalendarDay(year: 2026, month: 12, day: 28), durationMinutes: 30, now: now), .outsideWindow)
        XCTAssertEqual(calendar.availability(of: CalendarDay(year: 2027, month: 6, day: 1), durationMinutes: 30, now: now), .outsideWindow)
        XCTAssertEqual(calendar.slots(on: CalendarDay(year: 2026, month: 12, day: 28), durationMinutes: 30, now: now), [])
    }

    func testEveryDayOnTheGridHasAnAnswer() {
        // Each day shown is past, bookable or out of the window; the shop opens every day.
        let today = calendar.day(containing: now)
        let last = calendar.lastBookableDay(now: now)
        for page in calendar.months(now: now) {
            for day in page.days {
                let availability = calendar.availability(of: day, durationMinutes: 45, now: now)
                if day < today {
                    XCTAssertEqual(availability, .past, day.id)
                } else if day > last {
                    XCTAssertEqual(availability, .outsideWindow, day.id)
                } else {
                    XCTAssertTrue(availability.isBookable, day.id)
                }
            }
        }
    }

    // MARK: Days and dates

    func testDayContainingADate() {
        XCTAssertEqual(calendar.day(containing: pacificDate(2026, 10, 30, 0)), friday)
        XCTAssertEqual(calendar.day(containing: pacificDate(2026, 10, 30, 23, 59)), friday)
        XCTAssertEqual(calendar.day(containing: pacificDate(2026, 10, 31, 0)), CalendarDay(year: 2026, month: 10, day: 31))
    }

    func testStartOfDay() {
        XCTAssertEqual(calendar.startOfDay(friday), pacificDate(2026, 10, 30))
        XCTAssertEqual(calendar.startOfDay(CalendarDay(year: 2026, month: 11, day: 1)), pacificDate(2026, 11, 1))
        XCTAssertEqual(calendar.startOfDay(CalendarDay(year: 2027, month: 3, day: 14)), pacificDate(2027, 3, 14))
        XCTAssertEqual(calendar.day(containing: calendar.startOfDay(friday)), friday)
    }

    func testDateOnADayAtATime() {
        XCTAssertEqual(calendar.date(on: friday, at: TimeOfDay(hour: 14, minute: 30)), pacificDate(2026, 10, 30, 14, 30))
        // 2:30 AM doesn't exist on March 14, 2027: clocks jump from 2 to 3.
        XCTAssertNil(calendar.date(on: CalendarDay(year: 2027, month: 3, day: 14), at: TimeOfDay(hour: 2, minute: 30)))
        // 1:30 AM happens twice on November 1, 2026; either way it's a real time.
        let repeated = calendar.date(on: CalendarDay(year: 2026, month: 11, day: 1), at: TimeOfDay(hour: 1, minute: 30))
        XCTAssertEqual(repeated.map { calendar.timeLabel(for: $0) }, "1:30 AM")
    }

    // MARK: Daylight saving

    func testFallBackKeepsWallClockSlots() {
        // Clocks fall back from 2 AM to 1 AM on Sunday November 1, 2026.
        let sunday = CalendarDay(year: 2026, month: 11, day: 1)
        let slots = calendar.slots(on: sunday, durationMinutes: 30, now: now)
        XCTAssertEqual(slots.count, 16)
        XCTAssertEqual(slots.first?.start, pacificDate(2026, 11, 1, 10))
        XCTAssertEqual(slots.last?.start, pacificDate(2026, 11, 1, 17, 30))
        XCTAssertEqual(slots.map(\.label), slots.map { calendar.timeLabel(for: $0.start) })
        for (earlier, later) in zip(slots, slots.dropFirst()) {
            XCTAssertEqual(later.start.timeIntervalSince(earlier.start), 30 * 60)
        }
        // Saturday 10 AM to Sunday 10 AM is 25 hours that weekend.
        let saturday = calendar.slots(on: CalendarDay(year: 2026, month: 10, day: 31), durationMinutes: 30, now: now)
        XCTAssertEqual(slots.first.map { $0.start.timeIntervalSince(saturday[0].start) }, 25 * 60 * 60)
    }

    func testSpringForwardKeepsWallClockSlots() {
        // Clocks jump from 2 AM to 3 AM on Sunday March 14, 2027.
        let now = pacificDate(2027, 3, 1, 12)
        let sunday = CalendarDay(year: 2027, month: 3, day: 14)
        XCTAssertEqual(sunday.weekday, .sunday)
        let slots = calendar.slots(on: sunday, durationMinutes: 30, now: now)
        XCTAssertEqual(slots.count, 16)
        XCTAssertEqual(slots.first?.start, pacificDate(2027, 3, 14, 10))
        XCTAssertEqual(slots.first?.label, "10 AM")
        XCTAssertEqual(slots.last?.start, pacificDate(2027, 3, 14, 17, 30))
        // Saturday 10 AM to Sunday 10 AM is only 23 hours that weekend.
        let saturday = calendar.slots(on: CalendarDay(year: 2027, month: 3, day: 13), durationMinutes: 30, now: now)
        XCTAssertEqual(slots.first.map { $0.start.timeIntervalSince(saturday[0].start) }, 23 * 60 * 60)
        XCTAssertEqual(calendar.dateTimeLabel(for: slots[0].start), "Sun, Mar 14 at 10 AM")
    }

    // MARK: Other time zones

    func testAPhoneInTokyoGetsTheShopsDaysAndTimes() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 3 AM Friday in Tokyo is 11 AM Thursday in Oceanside.
        let now = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 3))!
        let thursday = CalendarDay(year: 2026, month: 10, day: 29)

        XCTAssertEqual(calendar.day(containing: now), thursday)
        XCTAssertEqual(calendar.firstBookableDay(durationMinutes: 30, now: now), thursday)
        let slots = calendar.slots(on: thursday, durationMinutes: 30, now: now)
        XCTAssertEqual(slots.first?.label, "11:30 AM")
        XCTAssertEqual(slots.first?.start, pacificDate(2026, 10, 29, 11, 30))
        XCTAssertEqual(slots.first.map { calendar.dateTimeLabel(for: $0.start) }, "Thu, Oct 29 at 11:30 AM")
        // Friday is tomorrow for the shop, so all of it is open.
        XCTAssertEqual(calendar.slots(on: friday, durationMinutes: 30, now: now).count, 18)
        XCTAssertEqual(calendar.lastBookableDay(now: now), CalendarDay(year: 2026, month: 12, day: 28))
    }

    func testAPhoneInUTCAfterTheShopCloses() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 5 AM Saturday UTC is 10 PM Friday in Oceanside.
        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 5))!
        XCTAssertEqual(calendar.day(containing: now), friday)
        XCTAssertEqual(calendar.availability(of: friday, durationMinutes: 30, now: now), .noTimesLeft)
        XCTAssertEqual(calendar.firstBookableDay(durationMinutes: 30, now: now), CalendarDay(year: 2026, month: 10, day: 31))
        XCTAssertEqual(calendar.availability(of: CalendarDay(year: 2026, month: 10, day: 29), durationMinutes: 30, now: now), .past)
    }

    // MARK: Labels

    func testDayLabels() {
        // October 30, 2025 was a Thursday; in 2026 it's a Friday.
        let thursday = CalendarDay(year: 2025, month: 10, day: 30)
        XCTAssertEqual(calendar.longLabel(for: thursday), "Thursday, October 30")
        XCTAssertEqual(calendar.shortLabel(for: thursday), "Thu, Oct 30")
        XCTAssertEqual(calendar.longLabel(for: friday), "Friday, October 30")
        XCTAssertEqual(calendar.shortLabel(for: friday), "Fri, Oct 30")
        XCTAssertEqual(calendar.longLabel(for: CalendarDay(year: 2027, month: 1, day: 3)), "Sunday, January 3")
    }

    func testShortMonthNames() {
        XCTAssertEqual((1...12).map { calendar.shortLabel(for: CalendarDay(year: 2027, month: $0, day: 1)).split(separator: " ")[1] }, [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ])
    }

    func testTimeLabels() {
        XCTAssertEqual(calendar.dateTimeLabel(for: pacificDate(2025, 10, 30, 14, 30)), "Thu, Oct 30 at 2:30 PM")
        XCTAssertEqual(calendar.timeLabel(for: pacificDate(2025, 10, 30, 14, 30)), "2:30 PM")
        XCTAssertEqual(calendar.dateTimeLabel(for: pacificDate(2026, 10, 30, 10)), "Fri, Oct 30 at 10 AM")
        XCTAssertEqual(calendar.timeLabel(for: pacificDate(2026, 10, 30, 12)), "12 PM")
    }
}
