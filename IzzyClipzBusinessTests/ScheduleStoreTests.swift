import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// The schedule: loading a day, filtering, refreshing without losing what's
/// shown, status changes, and blocked time.
@MainActor
final class ScheduleStoreTests: XCTestCase {
    private var harness: Harness!
    private var api: ScriptedAPI!

    override func setUp() async throws {
        harness = Harness()
        api = ScriptedAPI(base: harness.api)
    }

    private func makeStore() -> ScheduleStore {
        ScheduleStore(api: api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { TestClock.now })
    }

    func testLoadsTodayInTheShopsTimeZoneInOrder() async {
        let store = makeStore()
        XCTAssertEqual(store.day, LocalDate(year: 2026, month: 11, day: 2))
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.appointments.count, 8)
        XCTAssertEqual(store.appointments.map(\.start), store.appointments.map(\.start).sorted())
        XCTAssertEqual(store.appointments.prefix(2).map(\.customer.name), ["Jay Sample", "Marcus Sample"], "Two 10 AM clients: by barber name, Cristian before Izzy")
        XCTAssertEqual(store.timeOff.count, 1)
        XCTAssertEqual(store.summary, "4 booked · 2 completed")
        XCTAssertEqual(store.lastUpdated, TestClock.now)
        XCTAssertEqual(store.shopTime.time(store.appointments[0].start), "10 AM")
    }

    func testFiltersByBarberAndKeepsWholeShopBlocks() async throws {
        let store = makeStore()
        await store.refresh()
        store.barberFilter = "israel-flores"
        XCTAssertEqual(store.filterTitle, "Izzy")
        XCTAssertEqual(Set(store.visibleAppointments.map(\.barberId)), ["israel-flores"])
        XCTAssertTrue(store.visibleTimeOff.isEmpty, "Flowxbori's lunch isn't Izzy's")
        try await store.addTimeOff(barberId: nil, start: TestClock.at(17), end: TestClock.at(18), reason: "Team meeting")
        XCTAssertEqual(store.visibleTimeOff.map(\.reason), ["Team meeting"], "Whole-shop blocks show for everyone")
        store.barberFilter = nil
        XCTAssertEqual(store.visibleTimeOff.count, 2)
        XCTAssertEqual(store.filterTitle, "Everyone")
    }

    func testDaysMoveAndAnOldAnswerNeverReplacesTheNewDay() async throws {
        let store = makeStore()
        await store.refresh()
        // Tomorrow's answer is slow; today's comes back first.
        let gate = AsyncGate()
        api.appointmentsHandler = { [base = api.base] date in
            if date == TestClock.today { await gate.wait() }
            return try await base.appointments(on: date)
        }
        let slowToday = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        store.showNextDay()
        XCTAssertEqual(store.day, TestClock.today.adding(days: 1))
        XCTAssertTrue(store.appointments.isEmpty, "A new day starts empty, never with the old day's list")
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        await gate.open()
        await slowToday.value
        XCTAssertTrue(store.appointments.isEmpty, "Monday's late answer didn't land on Tuesday")
        store.showToday()
        XCTAssertEqual(store.day, TestClock.today)
        store.showPreviousDay()
        XCTAssertEqual(store.day, TestClock.today.adding(days: -1))
    }

    func testTheDatePickerWorksInShopTime() {
        let store = makeStore()
        let noon = store.dayAsDate
        XCTAssertEqual(TestClock.shopTime.time(noon), "12 PM")
        // 11:30 PM in the shop on Nov 3 is Nov 4 in UTC: still the shop's Nov 3.
        store.dayAsDate = TestClock.at(23, 30, on: TestClock.today.adding(days: 1))
        XCTAssertEqual(store.day, TestClock.today.adding(days: 1))
    }

    func testARefreshThatFailsKeepsWhatWasShown() async {
        let store = makeStore()
        await store.refresh()
        harness.server.options.offline = true
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.appointments.count, 8)
        XCTAssertEqual(store.refreshError, APIError.offline.userMessage)
        harness.server.options.offline = false
        await store.refresh()
        XCTAssertNil(store.refreshError)
    }

    func testAFirstLoadThatFailsSaysSo() async {
        harness.server.options.offline = true
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.loadState, .failed(APIError.offline.userMessage))
    }

    func testRefreshPicksUpChangesMadeElsewhere() async throws {
        let store = makeStore()
        await store.refresh()
        let walkIn = try await harness.api.createAppointment(.init(
            target: .anyBarber(serviceId: "haircut"), start: TestClock.at(16, 30), customer: .init(name: "Elsewhere Sample")
        ), idempotencyKey: .generate())
        await store.refresh()
        XCTAssertTrue(store.appointments.contains { $0.id == walkIn.id })
    }

    // MARK: Status

    func testMarkCompletedNoShowCancelAndReopen() async throws {
        let store = makeStore()
        await store.refresh()
        let andre = try XCTUnwrap(store.appointments.first { $0.customer.name == "Andre Sample" })

        for status in [IzzyAPI.AppointmentStatus.completed, .noShow, .cancelled] {
            let changed = await store.setStatus(status, for: andre)
            XCTAssertTrue(changed)
            XCTAssertEqual(store.appointment(withID: andre.id)?.status, status)
        }
        XCTAssertEqual(store.appointment(withID: andre.id)?.cancelledBy, .shop, "Cancelled here means the shop cancelled")
        let reopened = await store.setStatus(.booked, for: andre)
        XCTAssertTrue(reopened)
        XCTAssertEqual(store.appointment(withID: andre.id)?.status, .booked)
        XCTAssertNil(store.appointment(withID: andre.id)?.cancelledBy)
        XCTAssertTrue(store.updating.isEmpty)
    }

    func testARefreshFromBeforeAChangeDoesntUndoIt() async throws {
        let store = makeStore()
        await store.refresh()
        let andre = try XCTUnwrap(store.appointments.first { $0.customer.name == "Andre Sample" })
        // The timer's refresh read the schedule just before the change was saved.
        let gate = AsyncGate()
        let before = try await harness.api.appointments(on: TestClock.today)
        api.appointmentsHandler = { _ in
            await gate.wait()
            return before
        }
        let refresh = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        let changed = await store.setStatus(.completed, for: andre)
        XCTAssertTrue(changed)
        await gate.open()
        await refresh.value
        XCTAssertEqual(store.appointment(withID: andre.id)?.status, .completed, "The old list didn't bring \"Booked\" back")
    }

    func testReopeningATimeSomeoneElseTookExplainsWhy() async throws {
        let store = makeStore()
        await store.refresh()
        let sam = try XCTUnwrap(store.appointments.first { $0.customer.name == "Sam Sample" })
        XCTAssertEqual(sam.status, .cancelled)
        // Someone booked Cristian at 1 PM after Sam cancelled.
        let cut = try XCTUnwrap(Catalog.izzyClipz.offering(withID: sam.offeringId))
        _ = try await harness.api.createAppointment(
            .init(target: .offering(cut), start: sam.start, customer: .init(name: "New Sample")), idempotencyKey: .generate()
        )

        let reopened = await store.setStatus(.booked, for: sam)
        XCTAssertFalse(reopened)
        XCTAssertEqual(store.actionError, "Another appointment is booked at that time now, so this one can't be reopened.")
        XCTAssertEqual(store.appointment(withID: sam.id)?.status, .cancelled)
    }

    func testAFailedChangeLeavesTheAppointmentAsItWas() async throws {
        let store = makeStore()
        await store.refresh()
        let andre = try XCTUnwrap(store.appointments.first { $0.customer.name == "Andre Sample" })
        harness.server.options.offline = true
        let changed = await store.setStatus(.completed, for: andre)
        XCTAssertFalse(changed)
        XCTAssertEqual(store.appointment(withID: andre.id)?.status, .booked)
        XCTAssertEqual(store.actionError, APIError.offline.userMessage)
    }

    func testANewBookingForThisDayShowsAtOnce() async throws {
        let store = makeStore()
        await store.refresh()
        let appointment = try await harness.api.createAppointment(.init(
            target: .anyBarber(serviceId: "haircut"), start: TestClock.at(17), customer: .init(name: "Walk-in Sample")
        ), idempotencyKey: .generate())
        store.didBook(appointment)
        XCTAssertEqual(store.appointments.last?.id, appointment.id)
        let tomorrow = try await harness.api.createAppointment(.init(
            target: .anyBarber(serviceId: "haircut"), start: TestClock.at(11, on: TestClock.today.adding(days: 1)), customer: .init(name: "Later Sample")
        ), idempotencyKey: .generate())
        store.didBook(tomorrow)
        XCTAssertFalse(store.appointments.contains { $0.id == tomorrow.id })
    }

    // MARK: Time off

    func testBlockTimeForABarberAndRemoveIt() async throws {
        let store = makeStore()
        await store.refresh()
        try await store.addTimeOff(barberId: "julian-ramos", start: TestClock.at(15), end: TestClock.at(16), reason: " Dentist ")
        let block = try XCTUnwrap(store.timeOff.first { $0.barberId == "julian-ramos" })
        XCTAssertEqual(block.reason, "Dentist")
        XCTAssertEqual(harness.server.timeOff.count, 2)

        // The barber can't be booked then.
        let julian = try XCTUnwrap(Catalog.izzyClipz.offerings.first { $0.barberID == "julian-ramos" && $0.serviceID == "haircut" })
        let slots = try await harness.api.ownerAvailability(.init(target: .offering(julian), from: TestClock.today)).slots(on: TestClock.today)
        XCTAssertFalse(slots.contains { $0.start >= TestClock.at(14, 30) && $0.start < TestClock.at(16) })

        await store.removeTimeOff(block)
        XCTAssertFalse(store.timeOff.contains { $0.id == block.id })
        XCTAssertEqual(harness.server.timeOff.count, 1)
    }

    func testBlockTimeNeedsAnEndAfterTheStart() async {
        let store = makeStore()
        do {
            try await store.addTimeOff(barberId: nil, start: TestClock.at(15), end: TestClock.at(15), reason: "")
            XCTFail("An empty block was saved")
        } catch {
            XCTAssertEqual(error as? ScheduleError, ScheduleError(message: "The end has to be after the start."))
        }
        XCTAssertEqual(harness.server.calls.filter { $0 == "createTimeOff" }.count, 0)
    }

    func testRemovingABlockThatsAlreadyGoneIsFine() async throws {
        let store = makeStore()
        await store.refresh()
        let block = try XCTUnwrap(store.timeOff.first)
        try await harness.api.deleteTimeOff(id: block.id)
        await store.removeTimeOff(block)
        XCTAssertTrue(store.timeOff.isEmpty)
        XCTAssertNil(store.actionError)
    }

    func testOverlappingBookingsAreFoundForTheWarning() async {
        let store = makeStore()
        await store.refresh()
        let draft = IzzyAPI.TimeOff(id: "draft", barberId: "israel-flores", start: TestClock.at(11), end: TestClock.at(16))
        XCTAssertEqual(Set(store.appointmentsOverlapping(draft).map(\.customer.name)), ["Andre Sample", "Tony Sample"])
        let shop = IzzyAPI.TimeOff(id: "draft", barberId: nil, start: TestClock.at(13), end: TestClock.at(15))
        XCTAssertEqual(store.appointmentsOverlapping(shop).map(\.customer.name), ["Chris Sample"], "Cancelled ones don't count")
    }

    func testDefaultBlockStartsAtTheNextHalfHourToday() {
        let store = makeStore()
        let (start, end) = store.defaultBlockTimes()
        XCTAssertEqual(store.shopTime.time(start), "11:30 AM")
        XCTAssertEqual(end.timeIntervalSince(start), 3_600)
        store.showNextDay()
        XCTAssertEqual(store.shopTime.time(store.defaultBlockTimes().start), "10 AM", "Other days start at opening")
    }

    // MARK: Auto refresh

    func testTheTickerRunsUntilCancelled() async throws {
        let ticks = Counter()
        let task = Task { @MainActor in
            await Ticker.run(every: .milliseconds(20)) { ticks.value += 1 }
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await task.value
        let afterCancel = ticks.value
        XCTAssertGreaterThanOrEqual(afterCancel, 2, "It ticks right away and then on the interval")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ticks.value, afterCancel, "Nothing runs once the screen is gone")
        XCTAssertEqual(ScheduleStore.refreshInterval, .seconds(60))
    }
}

@MainActor
final class Counter {
    var value = 0
}

/// Holds async work until the test opens it.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
