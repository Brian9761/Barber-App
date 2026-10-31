import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Walk-ins and phone bookings: the owner's availability (no lead time), the
/// "next open slot" shortcut, booking, and a slot taken in the meantime.
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

        store.startOver()
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
}
