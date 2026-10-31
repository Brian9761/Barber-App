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

/// Booking from the review step: what's sent, what's saved, and what each failure becomes.
@MainActor
final class BookingSubmitterTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private let tokens = InMemorySecretStore()
    private let defaults = TestData.defaults()
    private var now = TestData.now

    /// The appointments as the app keeps them; a second one with the same Keychain and settings is
    /// the app opened again.
    private func makeAppointments(api: (any ShopAPI)? = nil) -> AppointmentStore {
        AppointmentStore(
            api: api ?? self.api,
            tokens: tokens,
            scheduler: FakeNotificationScheduler(),
            defaults: defaults,
            calendar: AppData.bookingCalendar,
            now: { [unowned self] in self.now }
        )
    }

    private func makeSubmitter(_ appointments: AppointmentStore? = nil) -> BookingSubmitter {
        BookingSubmitter(api: api, appointments: appointments ?? makeAppointments())
    }

    private func draft(note: String = "", start: Date = TestData.friday, phone: String = "(442) 555-0123") throws -> BookingDraft {
        let offering = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        return BookingDraft(
            plan: BookingPlan(choice: .offering(offering), start: start),
            customer: CustomerDetails(name: "Alex", phone: phone),
            note: note
        )
    }

    func testSendsTheSlotStartUnchangedAndTheNumberInE164() async throws {
        api.bookHandler = { _ in TestData.confirmation() }
        let appointments = makeAppointments()
        let submitter = makeSubmitter(appointments)
        let saved = await submitter.book(try draft(note: "Low fade"))
        XCTAssertEqual(saved?.id, TestData.appointment().id)
        XCTAssertEqual(appointments.appointments.map(\.id), [TestData.appointment().id])
        XCTAssertEqual(tokens.secrets[TestData.appointment().id], "token-1", "The server's token is the one kept")
        XCTAssertTrue(appointments.appointments.first?.remind ?? false, "Reminders start on")
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
        let submitter = makeSubmitter()
        let draft = BookingDraft(plan: BookingPlan(choice: .anyBarber(option), start: TestData.friday), customer: CustomerDetails(name: "Alex", phone: "4425550123"), note: "")
        _ = await submitter.book(draft)
        XCTAssertEqual(api.bookings.first?.target, .anyBarber(serviceId: "haircut"))
    }

    func testATakenTimeGoesBackToTheTimes() async throws {
        api.bookHandler = { _ in throw APIError.slotTaken }
        let submitter = makeSubmitter()
        let confirmation = await submitter.book(try draft())
        XCTAssertNil(confirmation)
        XCTAssertEqual(submitter.failure, .timeGone("Someone just booked 2:30 PM. Pick another time."))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
        XCTAssertEqual(submitter.failure?.title, "Not booked yet", "The server said no: it's not booked")
        XCTAssertNil(submitter.failure?.retryNote)
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
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .offline(APIError.offline.userMessage))
        XCTAssertTrue(submitter.failure?.canRetry ?? false)
        // It may have reached the shop with only the answer lost: not "not booked".
        XCTAssertEqual(submitter.failure?.title, "Not confirmed yet")
        XCTAssertEqual(submitter.failure?.retryNote, "Trying again won't book it twice.")

        api.bookHandler = { _ in TestData.confirmation() }
        let confirmation = await submitter.book(try draft())
        XCTAssertNotNil(confirmation)
        XCTAssertNil(submitter.failure)
        XCTAssertEqual(api.bookings.count, 2)
    }

    /// The server has two limits and says which one was hit: a number with 3 upcoming
    /// appointments (waiting never helps, cancelling one does) or too many tries from one network.
    func testALimitSaysWhichOneAndWhatHelps() async throws {
        let phoneLimit = "This number already has 3 upcoming appointments. Cancel one, or call the shop to book more."
        api.bookHandler = { _ in throw APIError.rateLimited(message: phoneLimit) }
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .rateLimited(phoneLimit))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)

        let networkLimit = "Too many booking attempts from this network. Try again in an hour, or call the shop."
        api.bookHandler = { _ in throw APIError.rateLimited(message: networkLimit) }
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .rateLimited(networkLimit))
    }

    func testALimitWithoutTheServersWordsSaysToWaitOrCall() async throws {
        api.bookHandler = { _ in throw APIError.rateLimited(message: "") }
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .rateLimited("That's a lot of tries in a short time. Wait a little and try again, or call the shop."))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
    }

    func testTheServersWordsAboutTheDetailsAreShown() async throws {
        api.bookHandler = { _ in
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Enter a US mobile number.", status: 400)
        }
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft())
        XCTAssertEqual(submitter.failure, .details("Enter a US mobile number."))
    }

    // MARK: One token per booking

    /// Every try of the same booking goes with the same token, so a try that went through but
    /// whose answer was lost can be recognized by the server.
    func testEveryTryOfTheSameBookingSendsTheSameToken() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        let appointments = makeAppointments()
        let submitter = makeSubmitter(appointments)
        _ = await submitter.book(try draft())
        _ = await submitter.book(try draft())
        api.bookHandler = { _ in throw APIError.server(code: IzzyAPI.ErrorCode.serverError, message: "", status: 503) }
        _ = await submitter.book(try draft())
        // Another review screen for the same booking (back, then Continue again) too.
        _ = await makeSubmitter(appointments).book(try draft())
        XCTAssertEqual(api.bookingTokens.count, 4)
        XCTAssertEqual(Set(api.bookingTokens).count, 1, "One token for every try")
        XCTAssertNotNil(tokens.secrets[AppointmentStore.pendingBookingsAccount], "Kept in the Keychain until it's booked")
    }

    /// The pending token is kept in the Keychain, so a retry after the app was closed and opened
    /// again is still safe: the same service, barber, time and number get the same token, even
    /// with the name typed again another way and the note left out this time.
    func testTheTokenSurvivesTheAppClosing() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        _ = await makeSubmitter().book(try draft(note: "Low fade"))
        let first = try XCTUnwrap(api.bookingTokens.first)

        let reopened = makeAppointments()
        api.bookHandler = { _ in TestData.confirmation(token: first.rawValue) }
        let retyped = BookingDraft(plan: try draft().plan, customer: CustomerDetails(name: "Alex Smith", phone: "442-555-0123"), note: "")
        let saved = await makeSubmitter(reopened).book(retyped)
        XCTAssertEqual(api.bookingTokens.last, first, "The same booking after a relaunch sends the same token")
        XCTAssertNotNil(saved)
        // Booked: the token is the appointment's now, and nothing is pending.
        XCTAssertEqual(tokens.secrets, [TestData.appointment().id: first.rawValue])
    }

    /// Another time, number, or service and barber is another booking, with its own token; one
    /// tried before keeps the one it had. A fixed name or an added note isn't: the server would
    /// answer it with the booking already made, so it keeps the token, and a new one would book
    /// a second appointment.
    func testAChangedBookingGetsItsOwnToken() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        let appointments = makeAppointments()
        let later = TestData.friday.addingTimeInterval(30 * 60)
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        let drafts = [
            try draft(),
            try draft(start: later),
            try draft(phone: "(442) 555-0124"),
            BookingDraft(plan: BookingPlan(choice: .anyBarber(option), start: TestData.friday), customer: try draft().customer, note: ""),
        ]
        for draft in drafts {
            _ = await makeSubmitter(appointments).book(draft)
        }
        XCTAssertEqual(Set(api.bookingTokens).count, drafts.count, "A new token for each different booking")
        // Back to the first one: the token it was tried with.
        _ = await makeSubmitter(appointments).book(drafts[0])
        XCTAssertEqual(api.bookingTokens.last, api.bookingTokens.first)

        // The first one with its details fixed: still that booking, still its token.
        let edited = [
            try draft(note: "Low fade"),
            BookingDraft(plan: try draft().plan, customer: CustomerDetails(name: "Sam", phone: "(442) 555-0123"), note: "Skin fade"),
        ]
        for draft in edited {
            _ = await makeSubmitter(appointments).book(draft)
            XCTAssertEqual(api.bookingTokens.last, api.bookingTokens.first)
        }
    }

    /// The whole thing against the in-memory server: the booking goes through but its answer is
    /// lost; Try again gets that same appointment, and there's one appointment and one token.
    func testALostAnswerThenTryAgainBooksOnce() async throws {
        var options = FakeShopAPI.Options()
        options.latency = .zero
        options.loseBookingResponseOnce = true
        let fake = FakeShopAPI(options: options, now: TestData.now)
        let tomorrow = TestData.calendarDay(2026, 10, 29)
        let slots = try await fake.availability(IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1))
        let start = try XCTUnwrap(slots.slots(on: tomorrow).first?.start)
        let appointments = makeAppointments(api: fake)
        let submitter = BookingSubmitter(api: fake, appointments: appointments)
        let booking = try draft(start: start)

        let lost = await submitter.book(booking)
        XCTAssertNil(lost)
        XCTAssertEqual(submitter.failure, .offline(APIError.offline.userMessage))
        XCTAssertTrue(submitter.failure?.canRetry ?? false, "Offers Try again")
        XCTAssertTrue(appointments.appointments.isEmpty, "The app doesn't know it yet")
        XCTAssertEqual(fake.bookingsMade, 1, "But the server booked it")

        let retried = await submitter.book(booking)
        let saved = try XCTUnwrap(retried, "Try again books it")
        XCTAssertNil(submitter.failure)
        XCTAssertEqual(saved.start, start)
        XCTAssertEqual(fake.bookingsMade, 1, "Still one appointment on the server")
        XCTAssertEqual(appointments.appointments.map(\.id), [saved.id])
        XCTAssertEqual(tokens.secrets.count, 1, "One token kept: the appointment's")
        let token = try XCTUnwrap(tokens.secrets[saved.id])
        let found = try await fake.appointment(id: saved.id, manageToken: token)
        XCTAssertEqual(found.id, saved.id, "The kept token manages the appointment")
    }

    /// On the in-memory server: the booking goes through but its answer is lost, then the client
    /// fixes their name and adds a note before trying again. That's the same booking to the
    /// server, so it comes back as it was made: one appointment, not a second barber at the same
    /// time ("Any barber") or "Someone just booked" about their own time (one barber).
    func testALostAnswerThenEditedDetailsBooksOnce() async throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        let carlos = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        for choice in [BookingChoice.anyBarber(option), .offering(carlos)] {
            var options = FakeShopAPI.Options()
            options.latency = .zero
            options.loseBookingResponseOnce = true
            let fake = FakeShopAPI(options: options, now: TestData.now)
            let tomorrow = TestData.calendarDay(2026, 10, 29)
            let slots = try await fake.availability(IzzyAPI.AvailabilityQuery(target: choice.target, from: tomorrow, days: 1))
            let start = try XCTUnwrap(slots.slots(on: tomorrow).first?.start)
            let keychain = InMemorySecretStore()
            let appointments = AppointmentStore(api: fake, tokens: keychain, scheduler: FakeNotificationScheduler(), defaults: TestData.defaults(), calendar: AppData.bookingCalendar, now: { TestData.now })
            let plan = BookingPlan(choice: choice, start: start)

            let first = BookingDraft(plan: plan, customer: CustomerDetails(name: "Alx", phone: "(442) 555-0123"), note: "")
            let lost = await BookingSubmitter(api: fake, appointments: appointments).book(first)
            XCTAssertNil(lost)
            XCTAssertEqual(fake.bookingsMade, 1, "The server booked it")

            // Change, fix the details, Continue: a new review for the edited booking.
            let edited = BookingDraft(plan: plan, customer: CustomerDetails(name: "Alex", phone: "4425550123"), note: "Low fade")
            let submitter = BookingSubmitter(api: fake, appointments: appointments)
            let retried = await submitter.book(edited)
            let saved = try XCTUnwrap(retried, "\(choice): \(String(describing: submitter.failure))")
            XCTAssertEqual(fake.bookingsMade, 1, "\(choice): still one appointment on the server")
            XCTAssertEqual(appointments.appointments.map(\.id), [saved.id])
            XCTAssertEqual(saved.snapshot.customer.name, "Alx", "As the shop has it: the first try's details")
            XCTAssertEqual(Array(keychain.secrets.keys), [saved.id], "Only the appointment's token; nothing left pending")
        }
    }

    /// Without the same token, the same retry would have found its own time taken. This is what
    /// the token prevents.
    func testWithoutTheSameTokenTheRetryWouldFindItsOwnTimeTaken() async throws {
        var options = FakeShopAPI.Options()
        options.latency = .zero
        options.loseBookingResponseOnce = true
        let fake = FakeShopAPI(options: options, now: TestData.now)
        let tomorrow = TestData.calendarDay(2026, 10, 29)
        let slots = try await fake.availability(IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1))
        let start = try XCTUnwrap(slots.slots(on: tomorrow).first?.start)
        let request = try draft(start: start).request
        do {
            _ = try await fake.book(request, token: .generate())
            XCTFail("The answer is lost")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        do {
            _ = try await fake.book(request, token: .generate())
            XCTFail("A new token is a new booking, and the time is taken")
        } catch {
            XCTAssertEqual(error as? APIError, .slotTaken)
        }
    }

    /// A retry that finds the earlier booking, cancelled by the shop since: it's saved as it is,
    /// and the client is sent back to the times with why.
    func testARetryThatFindsTheBookingCancelledSaysSo() async throws {
        api.bookHandler = { _ in
            IzzyAPI.BookingConfirmation(appointment: TestData.appointment(status: .cancelled, cancelledBy: .shop), manageToken: "token-1")
        }
        let appointments = makeAppointments()
        let submitter = makeSubmitter(appointments)
        let saved = await submitter.book(try draft())
        XCTAssertNil(saved)
        XCTAssertEqual(
            appointments.appointment(withID: TestData.appointment().id)?.isCancelledByShop,
            true,
            "Saved as the shop left it, so Home says so"
        )
        guard case .timeGone(let message)? = submitter.failure else {
            return XCTFail("Back to the times, not \(String(describing: submitter.failure))")
        }
        XCTAssertEqual(message, "Your booking for 2:30 PM went through, but the shop has cancelled it since. Pick another time, or call the shop.")
        XCTAssertNil(tokens.secrets[AppointmentStore.pendingBookingsAccount], "Settled: nothing to retry")
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
        let confirmation = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: first.start, customer: customer()), token: .generate())
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
        let confirmation = try await fake.book(IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: slot.start, customer: customer()), token: .generate())
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
            _ = try await fake.book(request, token: .generate())
            XCTFail("The first booking finds the time taken")
        } catch {
            XCTAssertEqual(error as? APIError, .slotTaken)
        }
        let remaining = try await fake.availability(query).slots(on: tomorrow)
        XCTAssertFalse(remaining.contains { $0.start == first.start })
        let secondSlots = try await fake.availability(query).slots(on: tomorrow)

        let second = try XCTUnwrap(secondSlots.first)
        _ = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: second.start, customer: customer()), token: .generate())
    }

    /// Like the server: a retry with the same token and the same booking gets the same
    /// appointment; the same token for another booking is turned down.
    func testARetryWithTheSameTokenGetsTheSameAppointment() async throws {
        let fake = makeFake()
        let query = IzzyAPI.AvailabilityQuery(target: .offering(id: TestData.carlosHaircutID), from: tomorrow, days: 1)
        let open = try await fake.availability(query).slots(on: tomorrow)
        let first = try XCTUnwrap(open.first)
        let request = IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: first.start, customer: customer())
        let token = IzzyAPI.ManageToken.generate()
        let booked = try await fake.book(request, token: token)
        XCTAssertEqual(booked.manageToken, token.rawValue, "The app's token is the appointment's")

        // The name and note may differ, and the number may be typed another way.
        var retry = request
        retry.customer = IzzyAPI.NewCustomer(name: "Someone else", phone: "(442) 555-0123")
        retry.note = "Changed"
        let again = try await fake.book(retry, token: token)
        XCTAssertEqual(again, booked)
        XCTAssertEqual(fake.bookingsMade, 1)

        var otherTime = request
        otherTime.start = first.start.addingTimeInterval(3600)
        var otherTarget = request
        otherTarget.target = .anyBarber(serviceId: "haircut")
        var otherPhone = request
        otherPhone.customer = IzzyAPI.NewCustomer(name: "Test", phone: "4425550124")
        for other in [otherTime, otherTarget, otherPhone] {
            do {
                _ = try await fake.book(other, token: token)
                XCTFail("The same token for another booking is turned down")
            } catch {
                XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That booking token was already used.", status: 400))
            }
        }
        do {
            _ = try await fake.book(request, token: .generate())
            XCTFail("A new token is a new booking, and the time is taken")
        } catch {
            XCTAssertEqual(error as? APIError, .slotTaken)
        }
        XCTAssertEqual(fake.bookingsMade, 1)
    }

    func testTurnsDownTimesItDoesNotOffer() async throws {
        let fake = makeFake()
        let past = TestData.now.addingTimeInterval(-3600)
        do {
            _ = try await fake.book(IzzyAPI.NewAppointment(target: .offering(id: TestData.carlosHaircutID), start: past, customer: customer()), token: .generate())
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
            _ = try await once.book(request, token: .generate())
            XCTFail("The first booking is offline")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        _ = try await once.book(request, token: .generate())
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
