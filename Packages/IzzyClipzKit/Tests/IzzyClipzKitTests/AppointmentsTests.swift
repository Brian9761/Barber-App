import XCTest
@testable import IzzyClipzKit

final class AppointmentTests: XCTestCase {
    func testEndAndDuration() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30), minutes: 75)
        XCTAssertEqual(appointment.end, pacificDate(2026, 10, 30, 15, 45))
        XCTAssertEqual(appointment.durationLabel, "1 hr 15 min")
    }

    func testIsUpcomingUntilItEnds() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30), minutes: 45)
        XCTAssertTrue(appointment.isUpcoming(at: pacificDate(2026, 10, 29, 9)))
        XCTAssertTrue(appointment.isUpcoming(at: pacificDate(2026, 10, 30, 14, 30)))
        XCTAssertTrue(appointment.isUpcoming(at: pacificDate(2026, 10, 30, 15, 14)))
        XCTAssertFalse(appointment.isUpcoming(at: pacificDate(2026, 10, 30, 15, 15)))
        XCTAssertFalse(appointment.isUpcoming(at: pacificDate(2026, 11, 1)))
    }

    func testFirstAvailableBarberName() {
        let firstAvailable = makeAppointment(start: pacificDate(2026, 10, 30, 14), barberID: nil, barberName: nil)
        XCTAssertNil(firstAvailable.barberID)
        XCTAssertEqual(firstAvailable.barberName, "First available")
        XCTAssertEqual(Appointment.firstAvailableName, "First available")

        let carlos = makeAppointment(start: pacificDate(2026, 10, 30, 14))
        XCTAssertEqual(carlos.barberName, "Carlos")
    }

    func testDefaultsToANewIDAndNow() {
        let before = Date()
        let one = Appointment(serviceID: "haircut", serviceName: "Haircut", barberID: nil, start: before, durationMinutes: 45, priceLabel: "$35")
        let two = Appointment(serviceID: "haircut", serviceName: "Haircut", barberID: nil, start: before, durationMinutes: 45, priceLabel: "$35")
        XCTAssertNotEqual(one.id, two.id)
        XCTAssertGreaterThanOrEqual(one.createdAt, before)
        XCTAssertLessThanOrEqual(one.createdAt, Date())
    }
}

final class AppointmentStorageTests: XCTestCase {
    func testRoundTrip() throws {
        let appointments = [
            makeAppointment(start: pacificDate(2026, 10, 30, 14, 30), created: Date(timeIntervalSinceReferenceDate: 815_000_000.123456)),
            makeAppointment(start: pacificDate(2026, 11, 6, 10), minutes: 240, barberID: nil, barberName: nil, price: "From $80"),
        ]
        let decoded = try AppointmentPlanner.decode(AppointmentPlanner.encode(appointments))
        XCTAssertEqual(decoded, appointments)
        XCTAssertEqual(decoded[1].barberName, "First available")
        XCTAssertNil(decoded[1].barberID)
    }

    func testRoundTripOfNothing() throws {
        XCTAssertEqual(try AppointmentPlanner.decode(AppointmentPlanner.encode([])), [])
    }

    func testEncodingIsStable() throws {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(try AppointmentPlanner.encode([appointment]), try AppointmentPlanner.encode([appointment]))
    }

    func testUnreadableEntriesAreSkipped() throws {
        let good = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        let goodJSON = try XCTUnwrap(String(data: AppointmentPlanner.encode([good]), encoding: .utf8)).dropFirst().dropLast()
        XCTAssertTrue(goodJSON.contains(#""durationMinutes":45"#), String(goodJSON))
        let noLength = goodJSON
            .replacingOccurrences(of: #""durationMinutes":45"#, with: #""durationMinutes":0"#)
            .replacingOccurrences(of: good.id.uuidString, with: UUID().uuidString)
        let json = "[\(goodJSON), {\"id\": \"not-a-uuid\"}, \(noLength), 42, \"text\"]"
        XCTAssertEqual(try AppointmentPlanner.decode(Data(json.utf8)), [good])
    }

    func testMissingBarberNameMeansFirstAvailable() throws {
        let json = """
        [{"id": "6F1C3B0E-0D7A-4E43-9D44-2C1B5A7E9F10", "serviceID": "haircut", "serviceName": "Haircut",
          "start": 815000000, "durationMinutes": 45, "priceLabel": "$35", "createdAt": 814000000}]
        """
        let decoded = try AppointmentPlanner.decode(Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.barberName, "First available")
        XCTAssertEqual(decoded.first?.start, Date(timeIntervalSinceReferenceDate: 815_000_000))
    }

    func testDecodingSomethingElseThrows() {
        XCTAssertThrowsError(try AppointmentPlanner.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try AppointmentPlanner.decode(Data("nope".utf8)))
        XCTAssertThrowsError(try AppointmentPlanner.decode(Data()))
    }
}

final class AppointmentPlannerTests: XCTestCase {
    let now = pacificDate(2026, 10, 28, 12)

    func testUpcomingIsSoonestFirstAndDropsFinishedOnes() {
        let later = makeAppointment(start: pacificDate(2026, 11, 6, 10))
        let soon = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        let inProgress = makeAppointment(start: pacificDate(2026, 10, 28, 11, 30), minutes: 45)
        let done = makeAppointment(start: pacificDate(2026, 10, 20, 10))
        let justDone = makeAppointment(start: pacificDate(2026, 10, 28, 11), minutes: 60)
        XCTAssertEqual(
            AppointmentPlanner.upcoming([later, done, soon, justDone, inProgress], now: now).map(\.id),
            [inProgress, soon, later].map(\.id)
        )
        XCTAssertEqual(AppointmentPlanner.upcoming([], now: now), [])
    }

    func testUpcomingBreaksTiesBySaveTime() {
        let start = pacificDate(2026, 10, 30, 14, 30)
        let second = makeAppointment(start: start, created: pacificDate(2026, 10, 2))
        let first = makeAppointment(start: start, created: pacificDate(2026, 10, 1))
        XCTAssertEqual(AppointmentPlanner.upcoming([second, first], now: now).map(\.id), [first.id, second.id])
    }

    func testPruningKeepsAMonthOfHistory() {
        let ancient = makeAppointment(start: pacificDate(2026, 9, 1, 10))
        let monthAgo = makeAppointment(start: pacificDate(2026, 9, 27, 10)) // ended 31 days ago
        let recent = makeAppointment(start: pacificDate(2026, 9, 29, 10)) // ended 29 days ago
        let upcoming = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(
            AppointmentPlanner.pruned([upcoming, ancient, recent, monthAgo], now: now).map(\.id),
            [recent, upcoming].map(\.id)
        )
        XCTAssertEqual(AppointmentPlanner.pruned([upcoming, recent], now: now, keepDays: 0).map(\.id), [upcoming.id])
        XCTAssertEqual(AppointmentPlanner.pruned([monthAgo], now: now, keepDays: 60).map(\.id), [monthAgo.id])
    }

    func testPruningKeepsSomethingThatJustEnded() {
        let justDone = makeAppointment(start: pacificDate(2026, 10, 28, 11), minutes: 60)
        XCTAssertEqual(AppointmentPlanner.pruned([justDone], now: now, keepDays: 0), [justDone])
    }

    func testLatestFinishedStart() {
        let older = makeAppointment(start: pacificDate(2026, 10, 1, 10))
        let newer = makeAppointment(start: pacificDate(2026, 10, 20, 15))
        let inProgress = makeAppointment(start: pacificDate(2026, 10, 28, 11, 30), minutes: 45)
        let upcoming = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(
            AppointmentPlanner.latestFinishedStart([older, upcoming, newer, inProgress], now: now),
            pacificDate(2026, 10, 20, 15)
        )
        XCTAssertNil(AppointmentPlanner.latestFinishedStart([upcoming, inProgress], now: now))
        XCTAssertNil(AppointmentPlanner.latestFinishedStart([], now: now))
    }

    // MARK: Reminders

    let shop = ShopInfo.izzyClipz
    let calendar = ShopInfo.izzyClipz.bookingCalendar

    func reminders(for appointment: Appointment, now: Date, address: String = "1919 Mission Ave") -> [AppointmentReminder] {
        AppointmentPlanner.reminders(for: appointment, shopName: "Izzy Clipz", address: address, calendar: calendar, now: now)
    }

    func testDayBeforeAndHourBefore() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        let reminders = reminders(for: appointment, now: now)
        XCTAssertEqual(reminders, [
            AppointmentReminder(
                kind: .dayBefore,
                date: pacificDate(2026, 10, 29, 14, 30),
                title: "Haircut tomorrow at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave."
            ),
            AppointmentReminder(
                kind: .hourBefore,
                date: pacificDate(2026, 10, 30, 13, 30),
                title: "Haircut at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave."
            ),
        ])
    }

    func testOnlyRemindersStillInTheFuture() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 29, 14, 29)).map(\.kind), [.dayBefore, .hourBefore])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 29, 14, 30)).map(\.kind), [.hourBefore])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 30, 13, 29)).map(\.kind), [.hourBefore])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 30, 13, 30)), [])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 31)), [])
    }

    func testFirstAvailableReminder() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 10), barberID: nil, barberName: nil)
        let reminders = reminders(for: appointment, now: now)
        XCTAssertEqual(reminders.map(\.title), ["Haircut tomorrow at 10 AM", "Haircut at 10 AM"])
        XCTAssertEqual(reminders.first?.body, "With the first available barber at Izzy Clipz, 1919 Mission Ave.")
    }

    func testReminderBodiesReadWell() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(reminders(for: appointment, now: now, address: "1919 Mission Ave.").first?.body, "With Carlos at Izzy Clipz, 1919 Mission Ave.")
        XCTAssertEqual(reminders(for: appointment, now: now, address: "").first?.body, "With Carlos at Izzy Clipz.")
        XCTAssertEqual(
            AppointmentPlanner.reminders(for: appointment, shopName: shop.name, address: shop.address.street, calendar: calendar, now: now).first?.body,
            "With Carlos at Izzy Clipz, 1919 Mission Ave."
        )
    }

    func testDayBeforeIsTwentyFourHoursAcrossDaylightSaving() {
        // Sunday November 1, 2026 is the first day of standard time.
        let appointment = makeAppointment(start: pacificDate(2026, 11, 1, 10), serviceName: "Hot Towel Shave")
        let dayBefore = reminders(for: appointment, now: now).first
        XCTAssertEqual(dayBefore?.kind, .dayBefore)
        XCTAssertEqual(dayBefore.map { appointment.start.timeIntervalSince($0.date) }, 24 * 60 * 60)
        XCTAssertEqual(dayBefore?.date, pacificDate(2026, 10, 31, 11))
        XCTAssertEqual(dayBefore?.title, "Hot Towel Shave tomorrow at 10 AM")
    }

    func testRemindersUseShopTimeWhereverThePhoneIs() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 6:30 AM Saturday in Tokyo is 2:30 PM Friday in Oceanside.
        let start = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 6, minute: 30))!
        let appointment = makeAppointment(start: start)
        XCTAssertEqual(reminders(for: appointment, now: now).map(\.title), ["Haircut tomorrow at 2:30 PM", "Haircut at 2:30 PM"])
    }

    func testReminderKinds() {
        XCTAssertEqual(AppointmentReminderKind.allCases, [.dayBefore, .hourBefore, .freeCancelEnds])
        XCTAssertEqual(AppointmentReminderKind.dayBefore.leadTime, 24 * 60 * 60)
        XCTAssertEqual(AppointmentReminderKind.hourBefore.leadTime, 60 * 60)
        XCTAssertEqual(AppointmentReminderKind.freeCancelEnds.leadTime, 60 * 60, "an hour before free cancelling ends")
        XCTAssertEqual(AppointmentReminderKind.dayBefore.rawValue, "dayBefore")
        XCTAssertEqual(AppointmentReminderKind.hourBefore.rawValue, "hourBefore")
        XCTAssertEqual(AppointmentReminderKind.freeCancelEnds.rawValue, "freeCancelEnds")
    }

    // MARK: Reminders when cancelling late may be charged

    /// The shop's starting policy: the full service price for cancelling less than 1 hour before.
    let oneHour = LateCancelTerms(windowMinutes: 60, feeLabel: "$45")

    func reminders(for appointment: Appointment, now: Date, lateCancel: LateCancelTerms?) -> [AppointmentReminder] {
        AppointmentPlanner.reminders(for: appointment, shopName: "Izzy Clipz", address: "1919 Mission Ave", calendar: calendar, now: now, lateCancel: lateCancel)
    }

    func testFreeUntilIsExactlyTheWindowBeforeTheStart() {
        XCTAssertEqual(oneHour.freeUntil(start: pacificDate(2026, 10, 30, 14, 30)), pacificDate(2026, 10, 30, 13, 30))
        XCTAssertEqual(LateCancelTerms(windowMinutes: 2_880, feeLabel: "$45").freeUntil(start: pacificDate(2026, 10, 30, 14, 30)), pacificDate(2026, 10, 28, 14, 30))
        // Booked days ahead, the 15 minutes after booking are long over by then.
        let early = LateCancelTerms(windowMinutes: 60, feeLabel: "$45", bookedAt: pacificDate(2026, 10, 28, 12))
        XCTAssertEqual(early.freeUntil(start: pacificDate(2026, 10, 30, 14, 30)), pacificDate(2026, 10, 30, 13, 30))
    }

    /// Cancelling within 15 minutes of booking is always free: booked 70 minutes ahead under a 1-hour
    /// window, cancelling is free for 15 minutes after booking, not just 10, to the minute.
    func testTheFifteenMinutesAfterBookingAreFreeToo() {
        let start = pacificDate(2026, 10, 28, 13, 10)
        let booked = pacificDate(2026, 10, 28, 12).addingTimeInterval(30)
        let terms = LateCancelTerms(windowMinutes: 60, feeLabel: "$45", bookedAt: booked)
        XCTAssertEqual(terms.freeUntil(start: start), pacificDate(2026, 10, 28, 12, 15))
        // So the hour-before reminder, at 12:10, still says it's free, and until when.
        let appointment = makeAppointment(start: start)
        let hourBefore = reminders(for: appointment, now: pacificDate(2026, 10, 28, 12, 1), lateCancel: terms).first { $0.kind == .hourBefore }
        XCTAssertEqual(hourBefore?.body, "With Carlos at Izzy Clipz, 1919 Mission Ave. Can't make it? Cancel in the app by 12:15 PM so it's free.")
        // Without the booking time, only the window counts: at 12:10 cancelling may be charged.
        let windowOnly = reminders(for: appointment, now: pacificDate(2026, 10, 28, 12, 1), lateCancel: oneHour).first { $0.kind == .hourBefore }
        XCTAssertEqual(windowOnly?.body, "With Carlos at Izzy Clipz, 1919 Mission Ave. Cancelling now may be charged $45.")
    }

    /// Booked days ahead under a 1-hour window: the day-before reminder says until when cancelling
    /// is free, and the hour-before one, which comes exactly when free cancelling ends, says
    /// cancelling now may be charged. Nothing more: the day before was in time.
    func testRemindersSayUntilWhenCancellingIsFree() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        XCTAssertEqual(reminders(for: appointment, now: now, lateCancel: oneHour), [
            AppointmentReminder(
                kind: .dayBefore,
                date: pacificDate(2026, 10, 29, 14, 30),
                title: "Haircut tomorrow at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave. Can't make it? Cancel in the app by 1:30 PM tomorrow so it's free."
            ),
            AppointmentReminder(
                kind: .hourBefore,
                date: pacificDate(2026, 10, 30, 13, 30),
                title: "Haircut at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave. Cancelling now may be charged $45."
            ),
        ])
        // Without the terms (no card on file, or late cancellations off), the reminders are as always.
        XCTAssertEqual(reminders(for: appointment, now: now, lateCancel: nil), reminders(for: appointment, now: now))
        XCTAssertEqual(reminders(for: appointment, now: now).map(\.body), ["With Carlos at Izzy Clipz, 1919 Mission Ave.", "With Carlos at Izzy Clipz, 1919 Mission Ave."])
    }

    /// Booked less than a day ahead, the hour-before reminder is the only one, and it comes exactly
    /// when free cancelling ends: one more comes an hour before that, while it's still free.
    func testAReminderAnHourBeforeFreeCancellingEnds() {
        // Wednesday noon, for 3:30 PM the same day.
        let appointment = makeAppointment(start: pacificDate(2026, 10, 28, 15, 30))
        XCTAssertEqual(reminders(for: appointment, now: now, lateCancel: oneHour), [
            AppointmentReminder(
                kind: .freeCancelEnds,
                date: pacificDate(2026, 10, 28, 13, 30),
                title: "Haircut at 3:30 PM",
                body: "Can't make it? Cancel in the app by 2:30 PM so it's free. After that, cancelling may be charged $45."
            ),
            AppointmentReminder(
                kind: .hourBefore,
                date: pacificDate(2026, 10, 28, 14, 30),
                title: "Haircut at 3:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave. Cancelling now may be charged $45."
            ),
        ])
    }

    /// Only what's still ahead: booked later on, the reminder before free cancelling ends has gone by.
    func testTheReminderBeforeFreeCancellingEndsOnlyWhileItsAhead() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 28, 15, 30))
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 28, 13, 29), lateCancel: oneHour).map(\.kind), [.freeCancelEnds, .hourBefore])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 28, 13, 30), lateCancel: oneHour).map(\.kind), [.hourBefore])
        XCTAssertEqual(reminders(for: appointment, now: pacificDate(2026, 10, 28, 14, 30), lateCancel: oneHour), [])
        // Booked inside the window: nothing is free any more, and nothing is left to remind.
        let soon = makeAppointment(start: pacificDate(2026, 10, 28, 12, 45))
        XCTAssertEqual(reminders(for: soon, now: now, lateCancel: oneHour), [])
    }

    /// A 30-minute window: the hour-before reminder still comes while cancelling is free, and says
    /// until when.
    func testAShortWindow() {
        let appointment = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        let halfHour = LateCancelTerms(windowMinutes: 30, feeLabel: "$22.50")
        XCTAssertEqual(reminders(for: appointment, now: now, lateCancel: halfHour).map(\.body), [
            "With Carlos at Izzy Clipz, 1919 Mission Ave. Can't make it? Cancel in the app by 2 PM tomorrow so it's free.",
            "With Carlos at Izzy Clipz, 1919 Mission Ave. Can't make it? Cancel in the app by 2 PM so it's free.",
        ])
        // Booked the same day: the hour-before reminder is in time, so nothing more.
        let today = makeAppointment(start: pacificDate(2026, 10, 28, 15, 30))
        XCTAssertEqual(reminders(for: today, now: now, lateCancel: halfHour).map(\.kind), [.hourBefore])
    }

    /// A window of a day or two: the day-before reminder comes when it isn't free any more, so one
    /// comes an hour before free cancelling ends, in time.
    func testLongWindows() {
        let friday = makeAppointment(start: pacificDate(2026, 10, 30, 14, 30))
        let day = LateCancelTerms(windowMinutes: 24 * 60, feeLabel: "$45")
        XCTAssertEqual(reminders(for: friday, now: now, lateCancel: day), [
            AppointmentReminder(
                kind: .freeCancelEnds,
                date: pacificDate(2026, 10, 29, 13, 30),
                title: "Haircut tomorrow at 2:30 PM",
                body: "Can't make it? Cancel in the app by 2:30 PM so it's free. After that, cancelling may be charged $45."
            ),
            AppointmentReminder(
                kind: .dayBefore,
                date: pacificDate(2026, 10, 29, 14, 30),
                title: "Haircut tomorrow at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave. Cancelling now may be charged $45."
            ),
            AppointmentReminder(
                kind: .hourBefore,
                date: pacificDate(2026, 10, 30, 13, 30),
                title: "Haircut at 2:30 PM",
                body: "With Carlos at Izzy Clipz, 1919 Mission Ave. Cancelling now may be charged $45."
            ),
        ])

        let saturday = makeAppointment(start: pacificDate(2026, 10, 31, 14, 30))
        let twoDays = LateCancelTerms(windowMinutes: 48 * 60, feeLabel: "$45")
        let first = reminders(for: saturday, now: now, lateCancel: twoDays).first
        XCTAssertEqual(first?.kind, .freeCancelEnds)
        XCTAssertEqual(first?.date, pacificDate(2026, 10, 29, 13, 30))
        XCTAssertEqual(first?.title, "Haircut on Sat, Oct 31 at 2:30 PM")
        XCTAssertEqual(first?.body, "Can't make it? Cancel in the app by 2:30 PM so it's free. After that, cancelling may be charged $45.")
        XCTAssertEqual(reminders(for: saturday, now: now, lateCancel: twoDays).map(\.kind), [.freeCancelEnds, .dayBefore, .hourBefore])
    }

    /// The reminder before free cancelling ends never comes at night: before 8 AM or from 9 PM it
    /// comes at 8 PM the evening before, and not at all once that's past.
    func testNeverAtNight() {
        // 10 AM Thursday with a 6-hour window: free until 4 AM, so an hour before is 3 AM.
        let thursday = makeAppointment(start: pacificDate(2026, 10, 29, 10))
        let sixHours = LateCancelTerms(windowMinutes: 6 * 60, feeLabel: "$45")
        XCTAssertEqual(reminders(for: thursday, now: now, lateCancel: sixHours).first, AppointmentReminder(
            kind: .freeCancelEnds,
            date: pacificDate(2026, 10, 28, 20),
            title: "Haircut tomorrow at 10 AM",
            body: "Can't make it? Cancel in the app by 4 AM tomorrow so it's free. After that, cancelling may be charged $45."
        ))
        // An 11-hour window: free until 11 PM Wednesday, so an hour before is 10 PM: 8 PM instead.
        let elevenHours = LateCancelTerms(windowMinutes: 11 * 60, feeLabel: "$45")
        let evening = reminders(for: thursday, now: now, lateCancel: elevenHours).first
        XCTAssertEqual(evening?.date, pacificDate(2026, 10, 28, 20))
        XCTAssertEqual(evening?.body, "Can't make it? Cancel in the app by 11 PM so it's free. After that, cancelling may be charged $45.")
        // A 12-hour window: an hour before is 9 PM, night already.
        XCTAssertEqual(reminders(for: thursday, now: now, lateCancel: LateCancelTerms(windowMinutes: 12 * 60, feeLabel: "$45")).first?.date, pacificDate(2026, 10, 28, 20))
        // 13 hours: an hour before is 8 PM, which isn't night.
        XCTAssertEqual(reminders(for: thursday, now: now, lateCancel: LateCancelTerms(windowMinutes: 13 * 60, feeLabel: "$45")).first?.date, pacificDate(2026, 10, 28, 20))
        // Booked at 8:30 PM, after the evening reminder would have come: only the hour before.
        XCTAssertEqual(reminders(for: thursday, now: pacificDate(2026, 10, 28, 20, 30), lateCancel: sixHours).map(\.kind), [.hourBefore])
        // 8 AM is morning already: an hour before a 9 AM deadline comes then.
        let elevenAM = makeAppointment(start: pacificDate(2026, 10, 29, 11))
        XCTAssertEqual(reminders(for: elevenAM, now: now, lateCancel: LateCancelTerms(windowMinutes: 2 * 60, feeLabel: "$45")).first?.date, pacificDate(2026, 10, 29, 8))
    }
}

func makeAppointment(
    start: Date,
    minutes: Int = 45,
    serviceName: String = "Haircut",
    barberID: String? = "carlos-rafael",
    barberName: String? = "Carlos",
    price: String = "$45",
    created: Date = pacificDate(2026, 10, 1)
) -> Appointment {
    Appointment(
        serviceID: "haircut",
        serviceName: serviceName,
        barberID: barberID,
        barberName: barberName,
        start: start,
        durationMinutes: minutes,
        priceLabel: price,
        createdAt: created
    )
}
