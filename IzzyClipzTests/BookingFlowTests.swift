import XCTest
@testable import IzzyClipz

/// The day-and-time step's loader: what it asks the server, and what it makes of the answers.
@MainActor
final class AvailabilityLoaderTests: XCTestCase {
    private let api = ScriptedShopAPI()
    // Wednesday, October 28, 2026, noon in Oceanside.
    private var now = TestData.now
    private let calendar = AppData.bookingCalendar

    private func makeLoader(_ target: IzzyAPI.BookingTarget = .offering(id: TestData.carlosHaircutID)) -> AvailabilityLoader {
        AvailabilityLoader(target: target, api: api, calendar: calendar, now: { [unowned self] in self.now })
    }

    private func page(_ year: Int, _ month: Int) -> MonthPage {
        MonthPage(year: year, month: month)
    }

    /// A slot at `hour`:`minute` shop time on `day`.
    private func slot(_ day: LocalDate, _ hour: Int, _ minute: Int = 0, barbers: [String] = ["carlos-rafael"]) -> IzzyAPI.Slot {
        IzzyAPI.Slot(start: calendar.date(on: day.calendarDay, at: TimeOfDay(hour: hour, minute: minute))!, barberIds: barbers)
    }

    func testAsksForTheRestOfTheMonthFromToday() async {
        let loader = makeLoader()
        await loader.load(page(2026, 10))
        // October 28–31: one request.
        XCTAssertEqual(api.availabilityQueries.count, 1)
        XCTAssertEqual(api.availabilityQueries.first?.from, TestData.calendarDay(2026, 10, 28))
        XCTAssertEqual(api.availabilityQueries.first?.days, 4)
        XCTAssertEqual(api.availabilityQueries.first?.target, .offering(id: TestData.carlosHaircutID))
    }

    func testAsksTwoWeeksAtATime() async {
        let loader = makeLoader()
        await loader.load(page(2026, 11))
        XCTAssertEqual(api.availabilityQueries.map(\.from), [
            TestData.calendarDay(2026, 11, 1),
            TestData.calendarDay(2026, 11, 15),
            TestData.calendarDay(2026, 11, 29),
        ])
        XCTAssertEqual(api.availabilityQueries.map(\.days), [14, 14, 2])
        XCTAssertTrue(api.availabilityQueries.allSatisfy { IzzyAPI.availabilityDaysRange.contains($0.days) })
    }

    /// Nothing past the booking window (60 days after today) is asked for.
    func testStopsAtTheLastBookableDay() async {
        let loader = makeLoader()
        XCTAssertEqual(loader.lastDay, TestData.calendarDay(2026, 12, 27))
        await loader.load(page(2026, 12))
        let last = api.availabilityQueries.map { $0.from.adding(days: $0.days - 1) }.max()
        XCTAssertEqual(last, TestData.calendarDay(2026, 12, 27))
        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 12, 28)), .tooFar)
        // And a month entirely outside it isn't asked for at all.
        let before = api.availabilityQueries.count
        await loader.load(page(2027, 1))
        XCTAssertEqual(api.availabilityQueries.count, before)
    }

    func testDayStatuses() async {
        let open = TestData.calendarDay(2026, 10, 29)
        api.availabilityHandler = { [self] query in
            var response = ScriptedShopAPI.emptyAvailability(for: query)
            response.days = response.days.map { day in
                day.date == open ? IzzyAPI.DaySlots(date: day.date, slots: [self.slot(open, 15), self.slot(open, 10)]) : day
            }
            return response
        }
        let loader = makeLoader()
        XCTAssertEqual(loader.status(of: open), .notLoaded)
        await loader.load(page(2026, 10))

        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 10, 27)), .past)
        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 10, 28)), .noOpenings)
        guard case .open(let slots) = loader.status(of: open) else { return XCTFail("The 29th has times") }
        XCTAssertEqual(slots.map(\.start), [slot(open, 10).start, slot(open, 15).start], "Earliest first")
        XCTAssertEqual(loader.firstOpenDay(onOrAfter: loader.today), open)
        XCTAssertEqual(loader.slots(on: open)?.count, 2)
        XCTAssertEqual(loader.slots(on: TestData.calendarDay(2026, 10, 28)), [])
        XCTAssertNil(loader.slots(on: TestData.calendarDay(2026, 11, 3)), "Not asked yet")
    }

    func testClosedDaysAreKnownWithoutAsking() {
        let loader = makeLoader()
        for offset in 0..<14 {
            let day = loader.today.adding(days: offset)
            if AppData.clock.schedule.hours(on: day.weekday) == nil {
                XCTAssertEqual(loader.status(of: day), .closed)
            }
        }
    }

    /// Days are the server's shop days (`DaySlots.date`): a 6:30 PM slot belongs to its day in
    /// Oceanside even though it's already the next day in UTC.
    func testSlotsAreKeptByTheShopDayTheServerGives() async {
        let day = TestData.calendarDay(2026, 10, 29)
        let evening = slot(day, 18, 30)
        XCTAssertEqual(LocalDate(containing: evening.start, in: TimeZone(identifier: "UTC")!), day.adding(days: 1))
        api.availabilityHandler = { query in
            var response = ScriptedShopAPI.emptyAvailability(for: query)
            response.days = response.days.map { $0.date == day ? IzzyAPI.DaySlots(date: day, slots: [evening]) : $0 }
            return response
        }
        let loader = makeLoader()
        await loader.load(page(2026, 10))
        XCTAssertEqual(loader.slots(on: day), [evening])
        XCTAssertEqual(loader.status(of: day.adding(days: 1)), .noOpenings)
    }

    func testLoadedDaysAreNotAskedForAgainButReloadAsksForAll() async {
        let loader = makeLoader()
        await loader.load(page(2026, 10))
        await loader.load(page(2026, 10))
        XCTAssertEqual(api.availabilityQueries.count, 1)
        await loader.reload(page(2026, 10))
        XCTAssertEqual(api.availabilityQueries.count, 2)
    }

    /// A day the server leaves out counts as having no openings, so it isn't asked for forever.
    func testDaysMissingFromTheAnswerHaveNoOpenings() async {
        api.availabilityHandler = { query in
            IzzyAPI.AvailabilityResponse(timeZone: "America/Los_Angeles", days: [])
        }
        let loader = makeLoader()
        await loader.load(page(2026, 10))
        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 10, 30)), .noOpenings)
    }

    func testAFailedRequestLeavesTheDaysUnknownAndTheErrorShows() async {
        api.availabilityHandler = { _ in throw APIError.offline }
        let loader = makeLoader()
        await loader.load(page(2026, 10))
        XCTAssertEqual(loader.error, .offline)
        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 10, 29)), .notLoaded)
        XCTAssertTrue(loader.isStale(maxAge: 60))

        api.availabilityHandler = { ScriptedShopAPI.emptyAvailability(for: $0) }
        await loader.reload(page(2026, 10))
        XCTAssertNil(loader.error)
        XCTAssertEqual(loader.status(of: TestData.calendarDay(2026, 10, 29)), .noOpenings)
        XCTAssertFalse(loader.isStale(maxAge: 60))
        now = now.addingTimeInterval(120)
        XCTAssertTrue(loader.isStale(maxAge: 60))
    }

    func testAnyBarberAsksForTheService() async {
        let loader = makeLoader(.anyBarber(serviceId: "haircut"))
        await loader.load(page(2026, 10))
        XCTAssertEqual(api.availabilityQueries.first?.target, .anyBarber(serviceId: "haircut"))
    }
}

/// Booking from the review step: what's sent, and what each failure becomes.
@MainActor
final class BookingSubmitterTests: XCTestCase {
    private let api = ScriptedShopAPI()

    private func draft(note: String = "") throws -> BookingDraft {
        let offering = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        return BookingDraft(
            plan: BookingPlan(choice: .offering(offering), start: TestData.friday),
            customer: CustomerDetails(name: "Alex", phone: "(442) 555-0123"),
            note: note
        )
    }

    func testSendsTheSlotStartUnchangedAndTheNumberInE164() async throws {
        api.bookHandler = { _ in TestData.confirmation() }
        let submitter = BookingSubmitter(api: api)
        let confirmation = await submitter.book(try draft(note: "Low fade"))
        XCTAssertEqual(confirmation?.manageToken, "token-1")
        XCTAssertNil(submitter.failure)
        XCTAssertFalse(submitter.isBooking)

        let sent = try XCTUnwrap(api.bookings.first)
        XCTAssertEqual(sent.start, TestData.friday)
        XCTAssertEqual(sent.target, .offering(id: TestData.carlosHaircutID))
        XCTAssertEqual(sent.customer.name, "Alex")
        XCTAssertEqual(sent.customer.phone, "+14425550123")
        XCTAssertEqual(sent.note, "Low fade")
    }

    func testAnyBarberBooksTheService() async throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        api.bookHandler = { _ in TestData.confirmation() }
        let submitter = BookingSubmitter(api: api)
        let draft = BookingDraft(plan: BookingPlan(choice: .anyBarber(option), start: TestData.friday), customer: CustomerDetails(name: "Alex", phone: "4425550123"), note: "")
        _ = await submitter.book(draft)
        XCTAssertEqual(api.bookings.first?.target, .anyBarber(serviceId: "haircut"))
    }

    func testATakenTimeGoesBackToTheTimes() async throws {
        api.bookHandler = { _ in throw APIError.slotTaken }
        let submitter = BookingSubmitter(api: api)
        let confirmation = await submitter.book(try draft())
        XCTAssertNil(confirmation)
        XCTAssertEqual(submitter.failure, .timeGone("Someone just booked 2:30 PM. Pick another time."))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
    }

    func testTimesThatCanNoLongerBeBookedGoBackToTheTimes() {
        let calendar = AppData.bookingCalendar
        for error in [APIError.tooSoon, .outsideHours, .tooFar] {
            guard case .timeGone = BookingSubmitter.failure(for: error, start: TestData.friday, calendar: calendar) else {
                return XCTFail("\(error) should go back to the times")
            }
        }
    }

    func testOfflineCanBeRetried() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        let submitter = BookingSubmitter(api: api)
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .offline(APIError.offline.userMessage))
        XCTAssertTrue(submitter.failure?.canRetry ?? false)

        api.bookHandler = { _ in TestData.confirmation() }
        let confirmation = await submitter.book(try draft())
        XCTAssertNotNil(confirmation)
        XCTAssertNil(submitter.failure)
        XCTAssertEqual(api.bookings.count, 2)
    }

    func testTooManyTriesSaysToWaitOrCall() async throws {
        api.bookHandler = { _ in throw APIError.rateLimited }
        let submitter = BookingSubmitter(api: api)
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .rateLimited(APIError.rateLimited.userMessage))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
    }

    func testTheServersWordsAboutTheDetailsAreShown() async throws {
        api.bookHandler = { _ in
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Enter a US mobile number.", status: 400)
        }
        let submitter = BookingSubmitter(api: api)
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .details("Enter a US mobile number."))
    }

    func testOtherProblemsCanBeRetried() {
        let failure = BookingSubmitter.failure(
            for: .server(code: IzzyAPI.ErrorCode.serverError, message: "", status: 500),
            start: TestData.friday,
            calendar: AppData.bookingCalendar
        )
        XCTAssertTrue(failure.canRetry)
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertTrue(BookingSubmitter.failure(for: .notConfigured(APIError.Feature.server), start: TestData.friday, calendar: AppData.bookingCalendar).message.contains("Call the shop"))
    }
}

/// The in-memory server the UI tests use behaves like the real one.
@MainActor
final class FakeShopAPITests: XCTestCase {
    private func makeFake(_ configure: (inout FakeShopAPI.Options) -> Void = { _ in }) -> FakeShopAPI {
        var options = FakeShopAPI.Options()
        options.latency = .zero
        configure(&options)
        return FakeShopAPI(options: options, now: TestData.now)
    }

    private let tomorrow = TestData.calendarDay(2026, 10, 29)

    private func customer() -> IzzyAPI.NewCustomer {
        IzzyAPI.NewCustomer(name: "Test", phone: "4425550123")
    }

    func testOffersTheShopsTimesMinusItsBookings() async throws {
        let fake = makeFake()
        let response = try await fake.availability(IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1))
        let slots = response.slots(on: tomorrow)
        let calendarSlots = AppData.bookingCalendar.slots(on: tomorrow.calendarDay, durationMinutes: 45, now: TestData.now)
        XCTAssertFalse(slots.isEmpty)
        XCTAssertLessThan(slots.count, calendarSlots.count, "Carlos already has a booking that day")
        XCTAssertTrue(Set(slots.map(\.start)).isSubset(of: Set(calendarSlots.map(\.start))))
    }

    func testBookingTakesTheTimeAndTheTokenLooksItUp() async throws {
        let fake = makeFake()
        let query = IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1)
        let firstSlots = try await fake.availability(query).slots(on: tomorrow)

        let first = try XCTUnwrap(firstSlots.first)
        let confirmation = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: first.start, customer: customer()))
        XCTAssertEqual(confirmation.appointment.start, first.start)
        XCTAssertEqual(confirmation.appointment.customer.phone, "+14425550123")

        let after = try await fake.availability(query).slots(on: tomorrow)
        XCTAssertFalse(after.contains { $0.start == first.start })

        let found = try await fake.appointment(id: confirmation.appointment.id, manageToken: confirmation.manageToken)
        XCTAssertEqual(found.id, confirmation.appointment.id)
        do {
            _ = try await fake.appointment(id: confirmation.appointment.id, manageToken: "wrong")
            XCTFail("A wrong token is a 404")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, IzzyAPI.ErrorCode.notFound)
        }

        let cancelled = try await fake.cancelAppointment(id: found.id, manageToken: confirmation.manageToken)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.cancelledBy, .customer)
        let freed = try await fake.availability(query).slots(on: tomorrow)
        XCTAssertTrue(freed.contains { $0.start == first.start }, "Cancelling frees the time")
    }

    func testAnyBarberAssignsSomeoneFree() async throws {
        let fake = makeFake()
        let query = IzzyAPI.AvailabilityQuery(target: .anyBarber(serviceId: "haircut"), from: tomorrow, days: 1)
        let slotSlots = try await fake.availability(query).slots(on: tomorrow)

        let slot = try XCTUnwrap(slotSlots.first)
        XCTAssertFalse(slot.barberIds.isEmpty)
        let confirmation = try await fake.book(IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: slot.start, customer: customer()))
        XCTAssertTrue(slot.barberIds.contains(confirmation.appointment.barberId))
        XCTAssertTrue(["flowxbori", "cristian-ceja", "julian-ramos"].contains(confirmation.appointment.barberId))
    }

    func testSlotTakenOnceThenTheTimeIsGone() async throws {
        let fake = makeFake { $0.slotTakenOnce = true }
        let query = IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1)
        let firstSlots = try await fake.availability(query).slots(on: tomorrow)

        let first = try XCTUnwrap(firstSlots.first)
        let request = IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: first.start, customer: customer())
        do {
            _ = try await fake.book(request)
            XCTFail("The first booking finds the time taken")
        } catch {
            XCTAssertEqual(error as? APIError, .slotTaken)
        }
        let remaining = try await fake.availability(query).slots(on: tomorrow)
        XCTAssertFalse(remaining.contains { $0.start == first.start })
        let secondSlots = try await fake.availability(query).slots(on: tomorrow)

        let second = try XCTUnwrap(secondSlots.first)
        _ = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: second.start, customer: customer()))
    }

    func testTurnsDownTimesItDoesNotOffer() async throws {
        let fake = makeFake()
        let past = TestData.now.addingTimeInterval(-3600)
        do {
            _ = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: past, customer: customer()))
            XCTFail("A time in the past can't be booked")
        } catch {
            XCTAssertEqual(error as? APIError, .tooSoon)
        }
    }

    func testOfflineAndBookingOfflineOnce() async throws {
        let offline = makeFake { $0.offline = true }
        do {
            _ = try await offline.products()
            XCTFail("Offline")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }

        let once = makeFake { $0.bookingOfflineOnce = true }
        let query = IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1)
        let firstSlots = try await once.availability(query).slots(on: tomorrow)

        let first = try XCTUnwrap(firstSlots.first)
        let request = IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: first.start, customer: customer())
        do {
            _ = try await once.book(request)
            XCTFail("The first booking is offline")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        _ = try await once.book(request)
    }

    func testSampleDataIsClearlySamples() async throws {
        let fake = makeFake()
        let products = try await fake.products()
        XCTAssertTrue(products.allSatisfy { $0.name.hasPrefix("Sample") && $0.imageUrl == nil })
        let reviews = try await fake.reviews()
        XCTAssertTrue(reviews.google.reviews.allSatisfy { $0.author.hasPrefix("Sample") })
        XCTAssertFalse(reviews.yelp.available)
        let none = try await makeFake { $0.noProducts = true }.products()
        XCTAssertTrue(none.isEmpty)
        let unavailable = try await makeFake { $0.reviewsUnavailable = true }.reviews()
        XCTAssertFalse(unavailable.google.available)
    }

    func testSeededBookingCanBeCancelledByTheShop() async throws {
        let fake = makeFake { $0.shopCancels = true }
        let seeded = try XCTUnwrap(fake.seedBooking())
        let found = try await fake.appointment(id: seeded.appointment.id, manageToken: seeded.manageToken)
        XCTAssertEqual(found.status, .cancelled)
        XCTAssertEqual(found.cancelledBy, .shop)
    }
}
