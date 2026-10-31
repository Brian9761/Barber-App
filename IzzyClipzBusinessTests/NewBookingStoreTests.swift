import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Walk-ins and phone bookings: the owner's availability (no lead time), the
/// "next open slot" shortcut, "Now", booking, a slot taken in the meantime, and
/// a new day after the app sat open overnight.
@MainActor
final class NewBookingStoreTests: XCTestCase {
    private var harness: Harness!
    private var booked: [IzzyAPI.Appointment] = []

    override func setUp() async throws {
        harness = Harness()
        booked = []
    }

    private func makeStore() -> NewBookingStore {
        let store = NewBookingStore(api: harness.api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { TestClock.now })
        store.onBooked = { [weak self] in self?.booked.append($0) }
        return store
    }

    /// A store and its own sample server on one clock that the test moves on.
    private func makeStore(clock: MovableClock) -> (NewBookingStore, FakeServer) {
        let server = FakeServer(shopTime: TestClock.shopTime, now: { clock.now })
        let store = NewBookingStore(
            api: server.api(ownerKey: FakeServer.ownerKey), shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { clock.now }
        )
        return (store, server)
    }

    func testPickingAServiceChoosesAnyBarberWhenItCan() {
        let store = makeStore()
        store.selectService("haircut")
        XCTAssertEqual(store.choice, .anyBarber)
        XCTAssertEqual(store.target, .anyBarber(serviceId: "haircut"))
        XCTAssertTrue(store.offerings.count >= 5, "Every barber's haircut is listed")
        store.selectService("perm")
        XCTAssertFalse(store.offersAnyBarber, "Only Izzy does perms")
        XCTAssertEqual(store.choice, .offering("israel-flores/7e5d9547-5951-475e-87d9-9b915ca5684e"))
        XCTAssertEqual(store.label(for: store.offerings[0]), "Izzy · 4 hr · $150")
    }

    func testSlotsComeFromTheOwnersAvailabilityWithoutTheLeadTime() async throws {
        let store = makeStore()
        store.selectService("haircut")
        await store.loadSlots()
        XCTAssertEqual(store.slotsState, .loaded)
        let first = try XCTUnwrap(store.slots.first)
        XCTAssertEqual(store.shopTime.time(first.start), "11:30 AM", "Walk-ins can take the next slot; customers' first is 30 minutes later")
        XCTAssertTrue(harness.server.calls.contains("ownerAvailability"))
        XCTAssertFalse(harness.server.calls.contains("availability"))

        let customers = try await harness.api.availability(.init(target: .anyBarber(serviceId: "haircut"), from: TestClock.today))
        XCTAssertEqual(customers.slots(on: TestClock.today).first.map { store.shopTime.time($0.start) }, "12 PM")
    }

    func testSlotsSkipBookedTimesAndBlockedTime() async throws {
        let store = makeStore()
        store.selectService("haircut")
        let flowxbori = try XCTUnwrap(store.offerings.first { $0.barberID == "flowxbori" && $0.durationMinutes == 45 })
        store.selectChoice(.offering(flowxbori.id))
        await store.loadSlots()
        let times = store.slots.map { store.shopTime.time($0.start) }
        XCTAssertFalse(times.contains("1 PM"), "Flowxbori's lunch")
        XCTAssertFalse(times.contains("12:30 PM"), "Would run into lunch")
        XCTAssertTrue(times.contains("2 PM"))
    }

    func testNextOpenSlotPicksTheEarliestFreeTime() async throws {
        let store = makeStore()
        store.selectService("haircut-and-beard")
        await store.findNextOpenSlot()
        let slot = try XCTUnwrap(store.selectedSlot)
        XCTAssertEqual(store.day, TestClock.today)
        XCTAssertEqual(store.shopTime.time(slot.start), "11:30 AM")
        XCTAssertFalse(slot.barberIds.contains("israel-flores"), "Izzy is with Andre at 11:30")
        XCTAssertEqual(store.slotsState, .loaded)
    }

    func testNextOpenSlotMovesToAnotherDayWhenTodayIsFull() async throws {
        // Late on a Monday evening, nothing is left today.
        let late = TestClock.at(18, 40)
        let server = FakeServer(shopTime: TestClock.shopTime, now: { late })
        let store = NewBookingStore(api: server.api(ownerKey: FakeServer.ownerKey), shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { late })
        store.selectService("haircut")
        await store.findNextOpenSlot()
        XCTAssertEqual(store.day, TestClock.today.adding(days: 1))
        XCTAssertEqual(store.selectedSlot.map { store.shopTime.time($0.start) }, "10 AM")
    }

    func testNextOpenSlotNeedsAService() async {
        let store = makeStore()
        await store.findNextOpenSlot()
        XCTAssertEqual(store.formError, "Pick a service first.")
    }

    func testBookingAWalkInWithoutAPhone() async throws {
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        store.clientName = "  Walk-in Sample "
        await store.book()
        let appointment = try XCTUnwrap(store.booked)
        XCTAssertEqual(appointment.customer.name, "Walk-in Sample")
        XCTAssertNil(appointment.customer.phone)
        XCTAssertEqual(appointment.status, .booked)
        XCTAssertEqual(store.shopTime.time(appointment.start), "11:30 AM")
        XCTAssertEqual(booked.map(\.id), [appointment.id], "The schedule hears about it")
        XCTAssertTrue(store.summary(of: appointment).hasSuffix("today at 11:30 AM"))

        let version = store.slotsVersion
        store.startOver()
        XCTAssertGreaterThan(store.slotsVersion, version, "The screen reloads the times for the next walk-in")
        XCTAssertEqual(store.slotsState, .idle)
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.clientName, "")
        XCTAssertNil(store.selectedSlot)
        XCTAssertEqual(store.serviceID, "haircut", "The next walk-in usually wants the same thing")
    }

    func testAPhoneNumberIsSentInE164() async throws {
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        store.clientName = "Phone Sample"
        store.clientPhone = "(442) 555-0123"
        XCTAssertTrue(store.phoneIsValid)
        await store.book()
        XCTAssertEqual(store.booked?.customer.phone, "+14425550123")
    }

    /// The form turns down exactly the numbers the server does, N11 codes like 911 included, so
    /// the owner hears about a typo before booking, not from the server.
    func testThePhoneNumberFollowsTheServersRules() async throws {
        let store = makeStore()
        for typed in ["", "  ", "(442) 555-0123", "+1 442 555 0123", "442\t555\t0123"] {
            store.clientPhone = typed
            XCTAssertTrue(store.phoneIsValid, typed.debugDescription)
        }
        for typed in ["12", "(442) 911-3053", "(211) 555-0123", "911-555-0100", "442-555-0123 ext 2", "+44 20 7946 0958"] {
            store.clientPhone = typed
            XCTAssertFalse(store.phoneIsValid, typed)
        }
        // The sample server answers like the real one when a number gets through anyway.
        let open = try await harness.api.ownerAvailability(.init(target: .anyBarber(serviceId: "haircut"), from: TestClock.today))
        let slot = try XCTUnwrap(open.slots(on: TestClock.today).first)
        do {
            _ = try await harness.api.createAppointment(.init(
                target: .anyBarber(serviceId: "haircut"), start: slot.start, customer: .init(name: "Sample", phone: "(442) 911-3053")
            ), idempotencyKey: .generate())
            XCTFail("An N11 exchange was booked")
        } catch {
            XCTAssertEqual(error as? APIError, .server(
                code: "invalid_request", message: "Enter a US mobile number, like (442) 341-3053, or leave it empty.", status: 400
            ))
        }
        XCTAssertNil(harness.appointment(named: "Sample"))
    }

    func testWhatsMissingIsSaidInOrder() async {
        let store = makeStore()
        XCTAssertEqual(store.missing, "Pick a service.")
        store.selectService("haircut")
        XCTAssertEqual(store.missing, "Pick a time.")
        await store.findNextOpenSlot()
        XCTAssertEqual(store.missing, "Enter the client's name.")
        store.clientName = "Sample"
        store.clientPhone = "12"
        XCTAssertFalse(store.phoneIsValid)
        XCTAssertTrue(store.missing?.contains("phone number") == true)
        store.clientPhone = ""
        XCTAssertNil(store.missing)
        await store.book()
        XCTAssertNotNil(store.booked)
    }

    func testBookingWithoutATimeDoesntCallTheServer() async {
        let store = makeStore()
        store.selectService("haircut")
        store.clientName = "Sample"
        await store.book()
        XCTAssertEqual(store.formError, "Pick a time.")
        XCTAssertFalse(harness.server.calls.contains("createAppointment"))
    }

    func testASlotTakenMeanwhileReloadsTheTimes() async throws {
        harness.server.options.takeNextSlot = true
        let store = makeStore()
        store.selectService("haircut")
        let julian = try XCTUnwrap(store.offerings.first { $0.barberID == "julian-ramos" })
        store.selectChoice(.offering(julian.id))
        await store.loadSlots()
        let taken = try XCTUnwrap(store.slots.first { store.shopTime.time($0.start) == "1 PM" })
        store.selectedSlot = taken
        store.clientName = "Sample"
        await store.book()
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.formError, "Someone just took that time. Pick another one.")
        XCTAssertNil(store.selectedSlot)
        XCTAssertEqual(store.slotsState, .loaded)
        XCTAssertFalse(store.slots.contains { $0.start == taken.start }, "The taken time is gone from the list")

        // Another time works.
        store.selectedSlot = store.slots.first
        await store.book()
        XCTAssertNotNil(store.booked)
    }

    // MARK: Book again after a lost answer

    /// The walk-in went through but the answer never arrived: Book again sends the same
    /// Idempotency-Key and gets that appointment, instead of putting the client in a second
    /// barber's chair.
    func testALostAnswerThenBookAgainMakesOneAppointment() async throws {
        harness.server.options.loseNextBookingAnswer = true
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        store.clientName = "Walk-in Sample"
        await store.book()
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.formError, APIError.offline.userMessage)
        XCTAssertNotNil(store.selectedSlot, "The form stays as it was")
        let first = try XCTUnwrap(harness.appointment(named: "Walk-in Sample"), "It went through on the server")

        await store.book()
        let appointment = try XCTUnwrap(store.booked)
        XCTAssertNil(store.formError)
        XCTAssertEqual(appointment, first)
        XCTAssertEqual(harness.server.appointments.filter { $0.customer.name == "Walk-in Sample" }.map(\.id), [first.id],
                       "One appointment, one barber")
        XCTAssertEqual(harness.server.bookingKeys.count, 2)
        XCTAssertEqual(Set(harness.server.bookingKeys).count, 1, "Both tries sent the same key")
        XCTAssertEqual(booked.map(\.id), [first.id], "The schedule hears about it once")
    }

    /// With a specific barber, Book again used to find the shop's own booking in the way and say
    /// "Someone just took that time".
    func testBookAgainWithASpecificBarberIsntSlotTaken() async throws {
        harness.server.options.loseNextBookingAnswer = true
        let store = makeStore()
        store.selectService("haircut")
        let julian = try XCTUnwrap(store.offerings.first { $0.barberID == "julian-ramos" })
        store.selectChoice(.offering(julian.id))
        await store.loadSlots()
        store.selectedSlot = store.slots.first
        store.clientName = "Phone Sample"
        store.clientPhone = "(442) 555-0123"
        await store.book()
        XCTAssertEqual(store.formError, APIError.offline.userMessage)
        await store.book()
        XCTAssertNotEqual(store.formError, "Someone just took that time. Pick another one.")
        XCTAssertEqual(store.booked?.customer.phone, "+14425550123")
        XCTAssertEqual(harness.server.appointments.filter { $0.customer.name == "Phone Sample" }.count, 1)
    }

    /// One key per booking: the same booking (as sent) keeps it, anything that changes what's
    /// sent gets a new one.
    func testAnythingThatChangesTheBookingGetsANewKey() {
        let store = makeStore()
        let start = TestClock.at(15)
        func request(name: String = "Sample", phone: String? = nil, note: String? = nil, start: Date? = nil,
                     target: IzzyAPI.BookingTarget = .anyBarber(serviceId: "haircut")) -> IzzyAPI.NewAppointment {
            IzzyAPI.NewAppointment(target: target, start: start ?? TestClock.at(15), customer: .init(name: name, phone: phone), note: note)
        }
        let key = store.idempotencyKey(for: request())
        XCTAssertEqual(store.idempotencyKey(for: request()), key, "Book again")
        XCTAssertEqual(store.idempotencyKey(for: request(name: " Sample ", note: " ")), key, "The same once sent: spaces are trimmed")
        var previous = key
        let changes = [
            request(name: "Sample Two"),
            request(name: "Sample Two", phone: "(442) 555-0123"),
            request(name: "Sample Two", phone: "(442) 555-0123", note: "Beard too"),
            request(name: "Sample Two", phone: "(442) 555-0123", note: "Beard too", start: start.addingTimeInterval(1_800)),
            request(name: "Sample Two", phone: "(442) 555-0123", note: "Beard too", start: start.addingTimeInterval(1_800),
                    target: .offering(id: "julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a")),
        ]
        for changed in changes {
            let next = store.idempotencyKey(for: changed)
            XCTAssertNotEqual(next, previous, "\(changed)")
            XCTAssertEqual(store.idempotencyKey(for: changed), next)
            previous = next
        }
        // The number as typed doesn't matter, only the number.
        XCTAssertEqual(store.idempotencyKey(for: request(name: "Sample Two", phone: "442.555.0123", note: "Beard too", start: start.addingTimeInterval(1_800),
                                                         target: .offering(id: "julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a"))), previous)
    }

    /// A change after a lost answer is a new booking the owner asked for; once one is booked,
    /// the next walk-in gets a key of its own, even for the same client and time.
    func testAChangedOrNextBookingIsntTakenForBookAgain() async throws {
        harness.server.options.loseNextBookingAnswer = true
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        let slot = try XCTUnwrap(store.selectedSlot)
        store.clientName = "Sample One"
        await store.book()
        XCTAssertNotNil(harness.appointment(named: "Sample One"))
        store.clientName = "Sample Two"
        await store.book()
        XCTAssertEqual(store.booked?.customer.name, "Sample Two")
        XCTAssertEqual(Set(harness.server.bookingKeys).count, 2)
        XCTAssertNotNil(harness.appointment(named: "Sample One"), "Both were booked, as the owner asked")

        // Booked: the very same details again would be another walk-in, with a key of its own.
        let same = IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: slot.start, customer: .init(name: "Sample Two"), note: "")
        XCTAssertFalse(harness.server.bookingKeys.contains(store.idempotencyKey(for: same)))
        store.startOver()
        await store.findNextOpenSlot()
        store.clientName = "Sample Two"
        await store.book()
        XCTAssertNotNil(store.booked)
        XCTAssertEqual(Set(harness.server.bookingKeys).count, 3)
        XCTAssertEqual(harness.server.appointments.filter { $0.customer.name == "Sample Two" }.count, 2,
                       "A second walk-in with the same name is booked, not mistaken for the first")
    }

    /// The first try went through, then was cancelled from the schedule before Book again: say
    /// so, and the next Book books it afresh.
    func testBookAgainFindsItCancelledSince() async throws {
        harness.server.options.loseNextBookingAnswer = true
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        store.clientName = "Walk-in Sample"
        await store.book()
        let first = try XCTUnwrap(harness.appointment(named: "Walk-in Sample"))
        _ = try await harness.api.setStatus(.cancelled, ofAppointment: first.id)

        await store.book()
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.formError, "Your first try went through, but that appointment isn't booked any more. Book again to add it back.")
        XCTAssertEqual(booked.map(\.status), [.cancelled], "The schedule shows it as it is")

        await store.book()
        let again = try XCTUnwrap(store.booked)
        XCTAssertNotEqual(again.id, first.id)
        XCTAssertEqual(again.status, .booked)
    }

    /// The sample server follows the real one: the same key with another booking is a 400.
    func testTheSampleServerTurnsDownAKeyUsedForAnotherBooking() async throws {
        let key = IzzyAPI.IdempotencyKey.generate()
        let walkIn = IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestClock.at(15), customer: .init(name: "Sample"))
        let first = try await harness.api.createAppointment(walkIn, idempotencyKey: key)
        let again = try await harness.api.createAppointment(
            IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestClock.at(15), customer: .init(name: " Sample "), note: "Changed"),
            idempotencyKey: key
        )
        XCTAssertEqual(again, first, "The note may differ, as on the server")
        for other in [
            IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestClock.at(16), customer: .init(name: "Sample")),
            IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestClock.at(15), customer: .init(name: "Someone Else")),
            IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: TestClock.at(15), customer: .init(name: "Sample", phone: "4425550123")),
        ] {
            do {
                _ = try await harness.api.createAppointment(other, idempotencyKey: key)
                XCTFail("Booked \(other) with a used key")
            } catch {
                XCTAssertEqual(error as? APIError, .server(
                    code: "invalid_request", message: "That booking key was already used for another booking.", status: 400
                ))
            }
        }
        XCTAssertEqual(harness.server.appointments.filter { $0.customer.name == "Sample" }.count, 1)
    }

    func testChangingTheDayOrBarberClearsTheTime() async throws {
        let store = makeStore()
        store.selectService("haircut")
        await store.findNextOpenSlot()
        XCTAssertNotNil(store.selectedSlot)
        store.select(day: TestClock.today.adding(days: 1))
        XCTAssertNil(store.selectedSlot)
        XCTAssertEqual(store.slotsState, .idle)
        await store.loadSlots()
        store.selectedSlot = store.slots.first
        store.selectChoice(store.offerings.first.map { .offering($0.id) })
        XCTAssertNil(store.selectedSlot)
    }

    func testOfflineSaysSoAndKeepsTheForm() async {
        let store = makeStore()
        store.selectService("haircut")
        harness.server.options.offline = true
        await store.loadSlots()
        XCTAssertEqual(store.slotsState, .failed(APIError.offline.userMessage))
        await store.findNextOpenSlot()
        XCTAssertEqual(store.formError, APIError.offline.userMessage)
    }

    // MARK: Now

    /// A walk-in who's in the chair at 11:05 is booked from 11:05, not from the next half hour.
    func testNowBooksAWalkInFromThisMinute() async throws {
        let clock = MovableClock(TestClock.at(11, 5).addingTimeInterval(40))
        let (store, server) = makeStore(clock: clock)
        XCTAssertNil(store.nowStart, "Not before a service is picked")
        store.selectService("haircut")
        XCTAssertEqual(store.nowStart, TestClock.at(11, 5), "This minute, without the seconds")
        await store.loadSlots()
        XCTAssertEqual(store.slots.first.map { store.shopTime.time($0.start) }, "11:30 AM", "The listed times stay on the half hour")
        store.selectNow()
        XCTAssertTrue(store.isNowSelected)
        store.clientName = "Walk-in Sample"
        await store.book()
        let appointment = try XCTUnwrap(store.booked)
        XCTAssertEqual(appointment.start, TestClock.at(11, 5))
        XCTAssertTrue(["flowxbori", "cristian-ceja", "julian-ramos"].contains(appointment.barberId), appointment.barberId)
        XCTAssertTrue(store.summary(of: appointment).hasSuffix("today at 11:05 AM"))
        XCTAssertEqual(server.appointments.filter { $0.customer.name == "Walk-in Sample" }.map(\.start), [TestClock.at(11, 5)])
    }

    /// Izzy is free now but has Andre at 11:30: an hour's cut doesn't fit in, and the owner
    /// hears that, not "someone just took that time".
    func testNowWithABarberWhoCantFitItInSaysSo() async throws {
        let store = makeStore()
        store.selectService("haircut")
        let izzy = try XCTUnwrap(store.offerings.first { $0.barberID == "israel-flores" })
        store.selectChoice(.offering(izzy.id))
        await store.loadSlots()
        store.selectNow()
        XCTAssertEqual(store.selectedSlot?.start, TestClock.at(11, 5))
        store.clientName = "Walk-in Sample"
        await store.book()
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.formError, "Izzy can't fit this in right now. Pick another time.")
        XCTAssertNil(store.selectedSlot)
        XCTAssertEqual(store.slotsState, .loaded, "The times were checked again")
        XCTAssertNotNil(store.nowStart, "Now is still there, for another barber or service")
        XCTAssertNil(harness.appointment(named: "Walk-in Sample"))
    }

    func testNowWithNobodyFreeSaysSo() async {
        harness.server.options.takeNextSlot = true
        let store = makeStore()
        store.selectService("haircut")
        store.selectNow()
        store.clientName = "Walk-in Sample"
        await store.book()
        XCTAssertEqual(store.formError, "No barber can fit this in right now. Pick another time.")
        XCTAssertNil(store.selectedSlot)
    }

    /// Now is for today while the shop is open, when the service ends by closing.
    func testNowIsOfferedTodayWhileOpenWhenTheServiceFits() {
        let clock = MovableClock(TestClock.at(9, 30))
        let (store, _) = makeStore(clock: clock)
        store.selectService("haircut")
        XCTAssertNil(store.nowStart, "Not before opening")
        clock.now = TestClock.at(10)
        XCTAssertEqual(store.nowStart, TestClock.at(10), "From opening")
        clock.now = TestClock.at(18, 15)
        XCTAssertEqual(store.nowStart, TestClock.at(18, 15), "A 45-minute cut still ends by 7 PM")
        clock.now = TestClock.at(18, 16)
        XCTAssertNil(store.nowStart, "A 45-minute cut wouldn't end by closing")
        store.selectService("eyebrows")
        XCTAssertEqual(store.nowStart, TestClock.at(18, 16), "Carlos's 15 minutes still fit")
        clock.now = TestClock.at(19)
        XCTAssertNil(store.nowStart, "Closed")

        clock.now = TestClock.at(11, 5)
        store.select(day: TestClock.today.adding(days: 1))
        XCTAssertNil(store.nowStart, "Only today")
        store.selectNow()
        XCTAssertNil(store.selectedSlot)
    }

    /// Picking Now before the times arrive keeps it picked; a listed time replaces it.
    func testNowStaysPickedWhenTheTimesLoad() async {
        let store = makeStore()
        store.selectService("haircut")
        store.selectNow()
        await store.loadSlots()
        XCTAssertTrue(store.isNowSelected)
        XCTAssertEqual(store.selectedSlot?.start, TestClock.at(11, 5))
        store.selectedSlot = store.slots.first
        XCTAssertFalse(store.isNowSelected)
    }

    /// Now picked at 6:14 PM stays on screen at 6:16, when a 45-minute cut would no longer be
    /// offered as Now: Book still sends 6:14, so the screen shows that, instead of hiding the
    /// chip and saying there are no times.
    func testNowStaysOnScreenOncePickedEvenWhenItWouldntBeOfferedNow() async throws {
        let clock = MovableClock(TestClock.at(18, 14))
        let (store, _) = makeStore(clock: clock)
        store.selectService("haircut")
        await store.loadSlots()
        XCTAssertEqual(store.nowChoice, TestClock.at(18, 14), "Before it's picked, the time it is")
        store.selectNow()
        clock.now = TestClock.at(18, 16)
        XCTAssertNil(store.nowStart, "A 45-minute cut from 6:16 wouldn't end by closing")
        XCTAssertTrue(store.isNowSelected)
        XCTAssertEqual(store.nowChoice, TestClock.at(18, 14), "The minute Now was picked, which Book sends")
        store.selectNow()
        XCTAssertEqual(store.selectedSlot?.start, TestClock.at(18, 14), "Tapping it again keeps it")
        store.clientName = "Walk-in Sample"
        await store.book()
        XCTAssertEqual(store.booked?.start, TestClock.at(18, 14))

        store.startOver()
        XCTAssertNil(store.nowChoice, "Nothing picked, and Now doesn't fit any more")
    }

    /// Book again after a lost answer sends the minute Now was picked, so it finds the booking
    /// that went through instead of putting the client in a second barber's chair.
    func testBookAgainAfterALostAnswerKeepsNowsMinute() async throws {
        let clock = MovableClock(TestClock.at(11, 5))
        let (store, server) = makeStore(clock: clock)
        server.options.loseNextBookingAnswer = true
        store.selectService("haircut")
        store.selectNow()
        store.clientName = "Walk-in Sample"
        await store.book()
        XCTAssertEqual(store.formError, APIError.offline.userMessage)
        clock.now = TestClock.at(11, 7)
        await store.book()
        XCTAssertEqual(store.booked?.start, TestClock.at(11, 5))
        XCTAssertEqual(server.appointments.filter { $0.customer.name == "Walk-in Sample" }.count, 1, "One appointment, one barber")
        XCTAssertEqual(Set(server.bookingKeys).count, 1)
    }

    /// The sample server takes the starts the real one takes from the shop: any whole minute
    /// inside opening hours, from today (earlier today too, to record a walk-in late) to 60
    /// days ahead.
    func testTheSampleServerTakesTheShopsStartsLikeTheServer() async throws {
        let julian = try XCTUnwrap(Catalog.izzyClipz.offerings.first { $0.barberID == "julian-ramos" && $0.serviceID == "haircut" })
        let api = harness.api
        func book(_ start: Date) async throws -> IzzyAPI.Appointment {
            try await api.createAppointment(
                .init(target: .offering(id: julian.id), start: start, customer: .init(name: "Sample")), idempotencyKey: .generate()
            )
        }
        func error(booking start: Date) async -> APIError? {
            do {
                _ = try await book(start)
                return nil
            } catch {
                return error as? APIError
            }
        }
        let now = try await book(TestClock.at(11, 5).addingTimeInterval(40))
        XCTAssertEqual(now.start, TestClock.at(11, 5), "Seconds are dropped")
        let late = try await book(TestClock.at(10, 10))
        XCTAssertEqual(late.start, TestClock.at(10, 10), "Earlier today, to record a walk-in late")
        let lastDay = TestClock.today.adding(days: 60)
        _ = try await book(TestClock.at(14, 0, on: lastDay))

        let passed = await error(booking: TestClock.at(14, 0, on: TestClock.today.adding(days: -1)))
        XCTAssertEqual(passed, .tooSoon)
        let tooFar = await error(booking: TestClock.at(14, 0, on: lastDay.adding(days: 1)))
        XCTAssertEqual(tooFar, .tooFar)
        let early = await error(booking: TestClock.at(9, 50))
        XCTAssertEqual(early, .outsideHours, "Before opening")
        let pastClosing = await error(booking: TestClock.at(18, 30))
        XCTAssertEqual(pastClosing, .outsideHours, "Wouldn't end by closing")
    }

    // MARK: A new day

    /// The app sat open overnight: New booking moves on from yesterday to today and loads its
    /// times, instead of offering yesterday's or saying there are none.
    func testAfterTheAppSatOpenOvernightNewBookingMovesToToday() async throws {
        let clock = MovableClock(TestClock.at(11, 5))
        let (store, _) = makeStore(clock: clock)
        store.selectService("haircut")
        await store.loadSlots()
        store.selectedSlot = store.slots.first
        let tuesday = TestClock.today.adding(days: 1)
        clock.now = TestClock.at(9, 0, on: tuesday)
        store.catchUpToToday()
        XCTAssertEqual(store.day, tuesday)
        XCTAssertNil(store.selectedSlot, "Yesterday's time is gone")
        XCTAssertEqual(store.slotsState, .idle, "The screen loads Tuesday's times")
        await store.loadSlots()
        XCTAssertEqual(store.slots.first.map { store.shopTime.time($0.start) }, "10 AM")

        // A day ahead that the owner picked stays.
        store.select(day: tuesday.adding(days: 2))
        store.catchUpToToday()
        XCTAssertEqual(store.day, tuesday.adding(days: 2))
    }

    /// The day picker runs from today to the last day the server takes bookings for.
    func testTheDayStaysBetweenTodayAndTheLastBookingDay() {
        let store = makeStore()
        let last = TestClock.today.adding(days: 60)
        XCTAssertEqual(store.lastDay, last)
        XCTAssertEqual(store.dayRange.lowerBound, TestClock.shopTime.startOfDay(TestClock.today))
        XCTAssertEqual(store.dayRange.upperBound, TestClock.shopTime.noon(on: last))
        XCTAssertTrue(store.dayRange.contains(store.dayAsDate))
        store.select(day: TestClock.today.adding(days: 90))
        XCTAssertEqual(store.day, last)
        XCTAssertTrue(store.dayRange.contains(store.dayAsDate))
        store.select(day: TestClock.today.adding(days: -3))
        XCTAssertEqual(store.day, TestClock.today)
    }

    /// The app stayed open past midnight with a time picked: booking it says the day has
    /// passed and moves on to today, instead of "too soon, pick a later time".
    func testBookingADayThatHasPassedMovesToToday() async throws {
        let clock = MovableClock(TestClock.at(18))
        let (store, server) = makeStore(clock: clock)
        store.selectService("haircut")
        await store.loadSlots()
        store.selectedSlot = try XCTUnwrap(store.slots.last)
        store.clientName = "Late Sample"
        let tuesday = TestClock.today.adding(days: 1)
        clock.now = TestClock.at(0, 5, on: tuesday)
        await store.book()
        XCTAssertNil(store.booked)
        XCTAssertEqual(store.formError, "That day has passed. Pick a time today.")
        XCTAssertEqual(store.day, tuesday)
        XCTAssertNil(store.selectedSlot)
        XCTAssertFalse(server.appointments.contains { $0.customer.name == "Late Sample" })
    }
}
