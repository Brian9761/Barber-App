import UserNotifications
import XCTest
@testable import IzzyClipz

@MainActor
final class AppointmentStoreTests: XCTestCase {
    private let scheduler = FakeNotificationScheduler()
    private let api = ScriptedShopAPI()
    private let tokens = InMemorySecretStore()
    private var now = TestData.now

    private func makeStore(defaults: UserDefaults) -> AppointmentStore {
        AppointmentStore(
            api: api,
            tokens: tokens,
            scheduler: scheduler,
            defaults: defaults,
            calendar: AppData.bookingCalendar,
            now: { [unowned self] in self.now }
        )
    }

    private let id = "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b"

    // MARK: Saving

    func testStartsEmpty() {
        let store = makeStore(defaults: TestData.defaults())
        XCTAssertTrue(store.appointments.isEmpty)
        XCTAssertNil(store.next)
        XCTAssertTrue(store.homeAppointments.isEmpty)
        XCTAssertNil(store.latestFinishedStart)
    }

    func testABookingIsKeptWithItsTokenInTheSecretStore() async {
        let defaults = TestData.defaults()
        let store = makeStore(defaults: defaults)
        let saved = store.add(TestData.confirmation(token: "secret-token"), remind: false)
        await store.settle()

        XCTAssertEqual(saved.origin, .app)
        XCTAssertNil(saved.problem)
        XCTAssertEqual(tokens.secrets[id], "secret-token")
        XCTAssertEqual(store.next?.id, id)

        // Remembered between launches, and the token never goes into UserDefaults.
        let reopened = makeStore(defaults: defaults)
        XCTAssertEqual(reopened.appointments.map(\.id), [id])
        XCTAssertEqual(reopened.appointments.first?.snapshot, TestData.appointment())
        let stored = String(decoding: defaults.data(forKey: "appointments.v2") ?? Data(), as: UTF8.self)
        XCTAssertFalse(stored.isEmpty)
        XCTAssertFalse(stored.contains("secret-token"))
    }

    /// The Keychain refusing the token mustn't lose it: it's kept for this launch, cancelling
    /// still works, and the appointment says it can't be managed after the app closes.
    func testATokenTheKeychainRefusesIsKeptForThisLaunchAndFlagged() async throws {
        tokens.failsWrites = true
        let store = makeStore(defaults: TestData.defaults())
        let saved = store.add(TestData.confirmation(token: "only-copy"), remind: false)
        XCTAssertEqual(saved.problem, .tokenNotSaved)
        XCTAssertNil(tokens.secrets[id])

        api.cancelHandler = { id, token in
            XCTAssertEqual(token, "only-copy")
            return TestData.appointment(id: id, status: .cancelled, cancelledBy: .customer)
        }
        try await store.cancel(id)
        XCTAssertEqual(store.appointment(withID: id)?.status, .cancelled)
    }

    // MARK: Booking tokens

    private func request(start: Date = TestData.friday, name: String = "Alex", phone: String = "4425550123", note: String? = nil) -> IzzyAPI.NewAppointment {
        IzzyAPI.NewAppointment(
            target: .offering(id: TestData.carlosHaircutID),
            start: start,
            customer: IzzyAPI.NewCustomer(name: name, phone: phone),
            note: note
        )
    }

    /// One token per booking, the same for every try of it, kept in the Keychain (never in
    /// UserDefaults) across launches until the booking is confirmed.
    func testBookingTokensArePerBookingAndKeptUntilItsBooked() {
        let defaults = TestData.defaults()
        let store = makeStore(defaults: defaults)
        let token = store.bookingToken(for: request())
        XCTAssertEqual(store.bookingToken(for: request()), token)
        // Typed differently, sent the same: the same booking.
        XCTAssertEqual(store.bookingToken(for: request(name: "  Alex ", phone: "(442) 555-0123", note: "  ")), token)
        XCTAssertNotNil(tokens.secrets[AppointmentStore.pendingBookingsAccount])
        XCTAssertFalse(String(describing: defaults.dictionaryRepresentation()).contains(token.rawValue))

        // Anything sent that's different is another booking.
        let others = [
            request(start: TestData.friday.addingTimeInterval(30 * 60)),
            request(name: "Sam"),
            request(phone: "4425550124"),
            request(note: "Low fade"),
            IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestData.friday, customer: IzzyAPI.NewCustomer(name: "Alex", phone: "4425550123")),
        ]
        let otherTokens = others.map { store.bookingToken(for: $0) }
        XCTAssertEqual(Set(otherTokens + [token]).count, others.count + 1)

        // The app opened again: the same tokens.
        let reopened = makeStore(defaults: defaults)
        XCTAssertEqual(reopened.bookingToken(for: request()), token)
        XCTAssertEqual(others.map { reopened.bookingToken(for: $0) }, otherTokens)

        // Booked: the next booking of the same time is a new one.
        reopened.finishedBooking(request())
        XCTAssertNotEqual(makeStore(defaults: defaults).bookingToken(for: request()), token)
    }

    func testPendingTokensAreDroppedOnceTheirTimeHasPassed() {
        let store = makeStore(defaults: TestData.defaults())
        let token = store.bookingToken(for: request())
        now = TestData.friday.addingTimeInterval(60)
        store.refreshLocally()
        XCTAssertNil(tokens.secrets[AppointmentStore.pendingBookingsAccount], "Nothing left to retry")
        XCTAssertNotEqual(store.bookingToken(for: request()), token)
    }

    func testAtMostTheTenLatestPendingBookingsAreKept() {
        let store = makeStore(defaults: TestData.defaults())
        let requests = (0..<12).map { request(start: TestData.friday.addingTimeInterval(TimeInterval($0) * 30 * 60)) }
        let first = requests.map { store.bookingToken(for: $0) }
        XCTAssertEqual(requests.suffix(10).map { store.bookingToken(for: $0) }, Array(first.suffix(10)))
        XCTAssertNotEqual(store.bookingToken(for: requests[0]), first[0], "The oldest ones were let go")
    }

    /// If the Keychain won't take it, the token still covers retries until the app closes.
    func testAPendingTokenTheKeychainRefusesIsKeptForThisLaunch() {
        tokens.failsWrites = true
        let store = makeStore(defaults: TestData.defaults())
        let token = store.bookingToken(for: request())
        XCTAssertEqual(store.bookingToken(for: request()), token)
        XCTAssertNil(tokens.secrets[AppointmentStore.pendingBookingsAccount])
    }

    func testRemindersAreScheduledTheDayBeforeAndAnHourBefore() async throws {
        scheduler.status = .authorized
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: true)
        await store.settle()

        let dayBefore = AppointmentStore.identifier(for: id, kind: .dayBefore)
        let hourBefore = AppointmentStore.identifier(for: id, kind: .hourBefore)
        XCTAssertEqual(Set(scheduler.pending.keys), [dayBefore, hourBefore])
        let trigger = try XCTUnwrap(scheduler.pending[hourBefore]?.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, TestData.friday.timeIntervalSince(now) - 60 * 60, accuracy: 1)
        let content = try XCTUnwrap(scheduler.pending[hourBefore]?.content)
        XCTAssertTrue(content.title.contains("Haircut"), content.title)
        XCTAssertTrue(content.body.contains("Carlos"), content.body)
        XCTAssertTrue(store.willSendHourBeforeReminder(for: id))
    }

    func testTurningRemindersOffRemovesThem() async {
        scheduler.status = .authorized
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: true)
        await store.settle()
        store.setReminders(false, for: id)
        await store.settle()
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertFalse(store.willSendHourBeforeReminder(for: id))
    }

    func testDeniedPermissionIsReported() async {
        scheduler.status = .notDetermined
        scheduler.grantsPermission = false
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: true)
        await store.settle()
        XCTAssertTrue(store.remindersPermissionDenied)
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertEqual(store.next?.id, id, "The appointment is still saved")
    }

    func testNoPermissionPromptWhenNoReminderIsAhead() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(start: TestData.soon), remind: true)
        await store.settle()
        XCTAssertEqual(scheduler.permissionRequests, 0)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    // MARK: Checking with the shop

    func testRefreshFindsTheShopCancelledIt() async {
        scheduler.status = .authorized
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(token: "t1"), remind: true)
        await store.settle()
        XCTAssertEqual(scheduler.pending.count, 2)

        api.appointmentHandler = { id, token in
            XCTAssertEqual(token, "t1")
            return TestData.appointment(id: id, status: .cancelled, cancelledBy: .shop)
        }
        await store.refresh(force: true)
        await store.settle()

        let saved = store.appointment(withID: id)
        XCTAssertEqual(saved?.status, .cancelled)
        XCTAssertTrue(saved?.isCancelledByShop ?? false)
        XCTAssertNil(store.next, "Nothing is on any more")
        XCTAssertEqual(store.homeAppointments.map(\.id), [id], "Home still shows it, so the client hears about it")
        XCTAssertTrue(scheduler.pending.isEmpty, "A cancelled appointment's reminders are removed")
        XCTAssertNil(store.refreshError)
        XCTAssertEqual(saved?.checkedAt, now)
    }

    /// The shop cancels one and the client books another time after it: Home shows the
    /// cancellation and the new booking under it, not only the older cancelled one.
    func testHomeShowsANewBookingAfterAnEarlierShopCancellation() async {
        let store = makeStore(defaults: TestData.defaults())
        let cancelledStart = TestData.friday
        let rebookedStart = TestData.friday.addingTimeInterval(24 * 60 * 60)
        store.add(TestData.confirmation(id: "cancelled", start: cancelledStart, token: "t1"), remind: false)
        api.appointmentHandler = { id, _ in
            TestData.appointment(id: id, start: cancelledStart, status: .cancelled, cancelledBy: .shop)
        }
        await store.refresh(force: true)
        XCTAssertEqual(store.homeAppointments.map(\.id), ["cancelled"])

        store.add(TestData.confirmation(id: "rebooked", start: rebookedStart, token: "t2"), remind: false)
        XCTAssertEqual(store.homeAppointments.map(\.id), ["cancelled", "rebooked"], "The new booking is on Home too")
        XCTAssertEqual(store.homeAppointments.map(\.status), [.cancelled, .booked])

        // Once the cancelled one's time is over, only the booking is left.
        let cancelledEnd = cancelledStart.addingTimeInterval(45 * 60)
        XCTAssertEqual(AppointmentStore.homeAppointments(store.upcoming, at: cancelledEnd).map(\.id), ["rebooked"])
        now = cancelledEnd
        XCTAssertEqual(store.homeAppointments.map(\.id), ["rebooked"])
    }

    /// The shop cancels a later appointment: the next one that's on stays on Home by itself (the
    /// Book tab lists the cancellation), and Home shows the cancellation once the next one is over.
    func testHomeKeepsTheNextAppointmentAheadOfALaterShopCancellation() async {
        let store = makeStore(defaults: TestData.defaults())
        let laterStart = TestData.friday.addingTimeInterval(24 * 60 * 60)
        store.add(TestData.confirmation(id: "next", start: TestData.friday, token: "t1"), remind: false)
        store.add(TestData.confirmation(id: "later", start: laterStart, token: "t2"), remind: false)
        api.appointmentHandler = { id, _ in
            id == "later"
                ? TestData.appointment(id: id, start: laterStart, status: .cancelled, cancelledBy: .shop)
                : TestData.appointment(id: id)
        }
        await store.refresh(force: true)
        XCTAssertEqual(store.homeAppointments.map(\.id), ["next"])

        now = TestData.friday.addingTimeInterval(45 * 60)
        XCTAssertEqual(store.homeAppointments.map(\.id), ["later"], "Then the client hears about the cancellation")
    }

    /// Booked again at the very time the shop cancelled: the booking is all Home needs to show.
    func testHomeShowsOnlyTheBookingAtTheTimeTheShopCancelled() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(id: "cancelled", token: "t1"), remind: false)
        api.appointmentHandler = { id, _ in TestData.appointment(id: id, status: .cancelled, cancelledBy: .shop) }
        await store.refresh(force: true)
        store.add(TestData.confirmation(id: "rebooked", token: "t2"), remind: false)
        XCTAssertEqual(store.homeAppointments.map(\.id), ["rebooked"])
    }

    func testRefreshFindsItCompleted() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(start: TestData.soon), remind: false)
        now = TestData.soon.addingTimeInterval(60 * 60)
        api.appointmentHandler = { id, _ in TestData.appointment(id: id, start: TestData.soon, status: .completed) }
        await store.refresh(force: true)
        XCTAssertEqual(store.past.first?.status, .completed)
        XCTAssertEqual(store.latestFinishedStart, TestData.soon)
    }

    func testOfflineRefreshKeepsWhatWasThereAndSaysSo() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(id: "a", token: "ta"), remind: false)
        store.add(TestData.confirmation(id: "b", start: TestData.friday.addingTimeInterval(3600), token: "tb"), remind: false)
        api.appointmentHandler = { _, _ in throw APIError.offline }
        await store.refresh(force: true)

        XCTAssertEqual(store.refreshError, .offline)
        XCTAssertEqual(store.appointments.map(\.status), [.booked, .booked])
        XCTAssertEqual(api.lookups.count, 1, "Once offline, the others aren't tried")

        api.appointmentHandler = { id, _ in TestData.appointment(id: id) }
        await store.refresh(force: true)
        XCTAssertNil(store.refreshError)
    }

    /// Pulling Home down offline: the appointment stays as it was last known, and the store says
    /// the check failed, which Home shows as "Couldn't check for changes" above it.
    func testAnOfflinePullOnHomeKeepsTheAppointmentAndSaysTheCheckFailed() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        api.appointmentHandler = { id, _ in TestData.appointment(id: id) }
        await store.refresh(force: true)
        XCTAssertNil(store.refreshError)

        api.appointmentHandler = { _, _ in throw APIError.offline }
        await store.refresh(force: true)
        XCTAssertEqual(store.homeAppointments.map(\.id), [id])
        XCTAssertEqual(store.homeAppointments.first?.status, .booked)
        XCTAssertEqual(store.refreshError, .offline)
        XCTAssertEqual(store.refreshError?.userMessage, "We couldn't reach the shop. Check your internet connection and try again.")
    }

    /// The server answering 404 (wrong token or unknown ID) keeps the appointment and flags it.
    func testAnAppointmentTheServerDoesNotKnowIsKeptAndFlagged() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        api.appointmentHandler = { _, _ in throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "", status: 404) }
        await store.refresh(force: true)
        XCTAssertEqual(store.appointment(withID: id)?.problem, .notFound)
        XCTAssertNil(store.refreshError, "Not a connection problem")
        XCTAssertFalse(store.appointment(withID: id)?.canCancelInApp(at: now) ?? true)

        // It isn't asked about again.
        await store.refresh(force: true)
        XCTAssertEqual(api.lookups.count, 1)
    }

    func testAMissingTokenIsFlagged() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        try? tokens.removeSecret(for: id)
        await store.refresh(force: true)
        XCTAssertEqual(store.appointment(withID: id)?.problem, .tokenMissing)
        XCTAssertTrue(api.lookups.isEmpty)
    }

    /// A locked Keychain is "try later", not "missing".
    func testAnUnreadableTokenIsTriedAgainLater() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        tokens.failsReads = true
        await store.refresh(force: true)
        XCTAssertNil(store.appointment(withID: id)?.problem)
        XCTAssertTrue(api.lookups.isEmpty)
    }

    func testRefreshIsAtMostOnceAMinuteUnlessForced() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        api.appointmentHandler = { id, _ in TestData.appointment(id: id) }
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(api.lookups.count, 1)
        now = now.addingTimeInterval(61)
        await store.refresh()
        XCTAssertEqual(api.lookups.count, 2)
        await store.refresh(force: true)
        XCTAssertEqual(api.lookups.count, 3)
    }

    // MARK: Cancelling

    func testCancelling() async throws {
        scheduler.status = .authorized
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(token: "t1"), remind: true)
        await store.settle()
        api.cancelHandler = { id, _ in TestData.appointment(id: id, status: .cancelled, cancelledBy: .customer) }

        try await store.cancel(id)
        await store.settle()
        XCTAssertEqual(api.cancellations.map(\.token), ["t1"])
        XCTAssertEqual(store.appointment(withID: id)?.status, .cancelled)
        XCTAssertNil(store.next)
        XCTAssertTrue(store.homeAppointments.isEmpty, "Cancelled by the client: Home goes back to walk-ins")
        XCTAssertTrue(scheduler.pending.isEmpty)

        // Cancelled ones can be cleared away.
        store.remove(id)
        XCTAssertNil(store.appointment(withID: id))
        XCTAssertNil(tokens.secrets[id])
    }

    func testCancellingOfflineKeepsItBooked() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        api.cancelHandler = { _, _ in throw APIError.offline }
        do {
            try await store.cancel(id)
            XCTFail("Cancelling offline should throw")
        } catch {
            XCTAssertEqual(error as? AppointmentActionError, .server(.offline))
        }
        XCTAssertEqual(store.appointment(withID: id)?.status, .booked)
    }

    /// The shop changed it meanwhile: the error comes back and the appointment shows how it is now.
    func testCancellingSomethingThatCanNoLongerBeCancelledShowsItAsItIs() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        api.cancelHandler = { _, _ in throw APIError.notCancellable }
        api.appointmentHandler = { id, _ in TestData.appointment(id: id, status: .cancelled, cancelledBy: .shop) }
        do {
            try await store.cancel(id)
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? AppointmentActionError, .server(.notCancellable))
        }
        XCTAssertTrue(store.appointment(withID: id)?.isCancelledByShop ?? false)
    }

    func testCancellingWithoutATokenSaysToCall() async {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        try? tokens.removeSecret(for: id)
        do {
            try await store.cancel(id)
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as? AppointmentActionError, .cannotManage)
            XCTAssertTrue(AppointmentActionError.cannotManage.userMessage.contains(AppData.shop.phone.display))
        }
        XCTAssertTrue(api.cancellations.isEmpty)
        XCTAssertEqual(store.appointment(withID: id)?.problem, .tokenMissing)
    }

    func testABookedAppointmentCanOnlyBeRemovedByCancellingIt() {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(), remind: false)
        store.remove(id)
        XCTAssertNotNil(store.appointment(withID: id))
    }

    // MARK: Lists

    func testUpcomingPastAndNext() {
        let store = makeStore(defaults: TestData.defaults())
        store.add(TestData.confirmation(id: "later", start: TestData.friday), remind: false)
        store.add(TestData.confirmation(id: "past", start: TestData.monday), remind: false)
        store.add(TestData.confirmation(id: "sooner", start: TestData.soon), remind: false)
        XCTAssertEqual(store.upcoming.map(\.id), ["sooner", "later"])
        XCTAssertEqual(store.past.map(\.id), ["past"])
        XCTAssertEqual(store.next?.id, "sooner")
        XCTAssertEqual(store.latestFinishedStart, TestData.monday)
    }

    func testOldAppointmentsAndTheirTokensAreDropped() {
        let defaults = TestData.defaults()
        let store = makeStore(defaults: defaults)
        store.add(TestData.confirmation(id: "old", start: TestData.september), remind: false)
        store.add(TestData.confirmation(id: "new", start: TestData.friday), remind: false)
        store.refreshLocally()
        XCTAssertEqual(store.appointments.map(\.id), ["new"])
        XCTAssertNil(tokens.secrets["old"])
        XCTAssertNotNil(tokens.secrets["new"])
    }

    func testUnreadableStoredDataStartsEmpty() {
        let defaults = TestData.defaults()
        defaults.set(Data("not json".utf8), forKey: "appointments.v2")
        XCTAssertTrue(makeStore(defaults: defaults).appointments.isEmpty)
    }

    // MARK: From v3

    /// v3 saved Squire bookings under "appointments.v1". The ones still ahead come along,
    /// read-only, with their reminders; past ones are dropped; the old keys are cleared.
    func testSquireAppointmentsFromTheLastVersionComeAlongReadOnly() async throws {
        scheduler.status = .authorized
        let defaults = TestData.defaults()
        let ahead = Appointment(serviceID: "haircut", serviceName: "Haircut", barberID: nil, start: TestData.friday, durationMinutes: 45, priceLabel: "$35", createdAt: TestData.monday)
        let over = Appointment(serviceID: "vip", serviceName: "VIP", barberID: "israel-flores", barberName: "Izzy", start: TestData.monday, durationMinutes: 75, priceLabel: "$80", createdAt: TestData.monday)
        defaults.set(try AppointmentPlanner.encode([ahead, over]), forKey: "appointments.v1")
        defaults.set([ahead.id.uuidString], forKey: "appointments.reminding.v1")

        let store = makeStore(defaults: defaults)
        // As when the app becomes active.
        store.refreshLocally()
        await store.settle()
        XCTAssertEqual(store.appointments.map(\.id), [ahead.id.uuidString])
        let saved = try XCTUnwrap(store.appointments.first)
        XCTAssertEqual(saved.origin, .squire)
        XCTAssertTrue(saved.remind)
        XCTAssertEqual(saved.title, "Haircut with the first available barber")
        XCTAssertFalse(saved.canCancelInApp(at: now), "Booked on Squire: the shop changes it")
        XCTAssertNil(defaults.data(forKey: "appointments.v1"))
        XCTAssertNil(defaults.stringArray(forKey: "appointments.reminding.v1"))
        // Its reminders keep v3's identifiers, so nothing is scheduled twice.
        XCTAssertEqual(Set(scheduler.pending.keys), Set(AppointmentStore.identifiers(for: ahead.id.uuidString)))

        // Not something the server knows: it's never asked about.
        await store.refresh(force: true)
        XCTAssertTrue(api.lookups.isEmpty)

        // It can be taken off the list, and it goes once it's over.
        let reopened = makeStore(defaults: defaults)
        XCTAssertEqual(reopened.appointments.map(\.id), [ahead.id.uuidString])
        reopened.remove(ahead.id.uuidString)
        XCTAssertTrue(reopened.appointments.isEmpty)
    }
}
