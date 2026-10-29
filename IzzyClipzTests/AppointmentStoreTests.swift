import UserNotifications
import XCTest
@testable import IzzyClipz

@MainActor
final class AppointmentStoreTests: XCTestCase {
    private let scheduler = FakeNotificationScheduler()
    // Wednesday, October 28, 2026, noon in Oceanside.
    private let now = Date(timeIntervalSince1970: 1_793_214_000)
    // Friday, October 30, 2026, 2:30 PM.
    private let friday = Date(timeIntervalSince1970: 1_793_395_800)
    // Today at 12:45 PM: too soon for a day-before reminder.
    private let soon = Date(timeIntervalSince1970: 1_793_216_700)
    // Monday, October 26, 2026, 10 AM: already over.
    private let monday = Date(timeIntervalSince1970: 1_793_034_000)
    // Tuesday, September 15, 2026, 10 AM: over a month ago.
    private let september = Date(timeIntervalSince1970: 1_789_491_600)

    private func makeDefaults() -> UserDefaults {
        let suite = "AppointmentStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> AppointmentStore {
        AppointmentStore(scheduler: scheduler, defaults: defaults, calendar: AppData.bookingCalendar, now: { [now] in now })
    }

    private func appointment(at start: Date, service: String = "Haircut") -> Appointment {
        Appointment(
            serviceID: "haircut",
            serviceName: service,
            barberID: "carlos-rafael",
            barberName: "Carlos",
            start: start,
            durationMinutes: 45,
            priceLabel: "$45",
            createdAt: now
        )
    }

    func testStartsEmpty() {
        let store = makeStore(defaults: makeDefaults())
        XCTAssertTrue(store.appointments.isEmpty)
        XCTAssertTrue(store.upcoming.isEmpty)
        XCTAssertNil(store.next)
        XCTAssertNil(store.latestFinishedStart)
    }

    func testSavedAppointmentsAreRemembered() async {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let saved = appointment(at: friday)
        store.save(saved, remind: false)
        await store.settle()

        let reopened = makeStore(defaults: defaults)
        XCTAssertEqual(reopened.appointments, [saved])
        XCTAssertEqual(reopened.next, saved)
        XCTAssertFalse(reopened.isReminding(saved.id))
    }

    func testUpcomingIsSoonestFirst() async {
        let store = makeStore(defaults: makeDefaults())
        let later = appointment(at: friday, service: "VIP")
        let sooner = appointment(at: soon)
        let past = appointment(at: monday)
        store.save(later, remind: false)
        store.save(past, remind: false)
        store.save(sooner, remind: false)
        await store.settle()

        XCTAssertEqual(store.upcoming.map(\.id), [sooner.id, later.id])
        XCTAssertEqual(store.next?.id, sooner.id)
        XCTAssertEqual(store.appointments.map(\.id), [past.id, sooner.id, later.id])
        XCTAssertEqual(store.latestFinishedStart, monday)
    }

    func testSavingAgainReplacesTheSameAppointment() async {
        let store = makeStore(defaults: makeDefaults())
        var saved = appointment(at: friday)
        store.save(saved, remind: false)
        saved.start = friday.addingTimeInterval(60 * 60)
        store.save(saved, remind: false)
        await store.settle()
        XCTAssertEqual(store.appointments.count, 1)
        XCTAssertEqual(store.appointments.first?.start, saved.start)
    }

    func testRemindersAreScheduledTheDayBeforeAndAnHourBefore() async throws {
        scheduler.status = .authorized
        let store = makeStore(defaults: makeDefaults())
        let saved = appointment(at: friday)
        store.save(saved, remind: true)
        await store.settle()

        XCTAssertTrue(store.isReminding(saved.id))
        XCTAssertFalse(store.remindersPermissionDenied)
        let dayBefore = AppointmentStore.identifier(for: saved.id, kind: .dayBefore)
        let hourBefore = AppointmentStore.identifier(for: saved.id, kind: .hourBefore)
        XCTAssertEqual(Set(scheduler.pending.keys), [dayBefore, hourBefore])

        let dayTrigger = try XCTUnwrap(scheduler.pending[dayBefore]?.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(dayTrigger.timeInterval, friday.timeIntervalSince(now) - 24 * 60 * 60, accuracy: 1)
        let hourTrigger = try XCTUnwrap(scheduler.pending[hourBefore]?.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(hourTrigger.timeInterval, friday.timeIntervalSince(now) - 60 * 60, accuracy: 1)
        XCTAssertFalse(hourTrigger.repeats)

        let content = try XCTUnwrap(scheduler.pending[hourBefore]?.content)
        XCTAssertTrue(content.title.contains("Haircut"), content.title)
        XCTAssertTrue(content.body.contains("Carlos"), content.body)
    }

    func testRemindersThatWouldBeLateAreSkipped() async {
        scheduler.status = .authorized
        let store = makeStore(defaults: makeDefaults())
        let saved = appointment(at: soon)
        store.save(saved, remind: true)
        await store.settle()
        // 45 minutes away: too late for "tomorrow" and for "in an hour".
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testNoPermissionPromptWhenNoReminderIsAhead() async {
        scheduler.status = .notDetermined
        let store = makeStore(defaults: makeDefaults())
        store.save(appointment(at: soon), remind: true)
        await store.settle()
        // Nothing could be sent, so there's nothing to ask permission for.
        XCTAssertEqual(scheduler.permissionRequests, 0)
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertFalse(store.remindersPermissionDenied)
    }

    func testNoRemindersWhenTurnedOff() async {
        scheduler.status = .authorized
        let store = makeStore(defaults: makeDefaults())
        store.save(appointment(at: friday), remind: false)
        await store.settle()
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertEqual(scheduler.permissionRequests, 0)
    }

    func testAsksForPermissionTheFirstTime() async {
        scheduler.status = .notDetermined
        let store = makeStore(defaults: makeDefaults())
        store.save(appointment(at: friday), remind: true)
        await store.settle()
        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertEqual(scheduler.pending.count, 2)
    }

    func testDeniedPermissionIsReported() async {
        scheduler.status = .notDetermined
        scheduler.grantsPermission = false
        let store = makeStore(defaults: makeDefaults())
        let saved = appointment(at: friday)
        store.save(saved, remind: true)
        await store.settle()
        XCTAssertTrue(store.remindersPermissionDenied)
        XCTAssertTrue(scheduler.pending.isEmpty)
        // The appointment itself is still saved.
        XCTAssertEqual(store.next, saved)
    }

    func testHourBeforeReminderIsOnlyPromisedWhenItCanBeSent() async {
        scheduler.status = .authorized
        let store = makeStore(defaults: makeDefaults())
        let reminded = appointment(at: friday)
        let notReminded = appointment(at: friday.addingTimeInterval(2 * 60 * 60))
        let tooSoon = appointment(at: soon)
        store.save(reminded, remind: true)
        store.save(notReminded, remind: false)
        store.save(tooSoon, remind: true)
        await store.settle()

        // The app sends it, so the calendar event can skip its own alarm.
        XCTAssertTrue(store.willSendHourBeforeReminder(for: reminded.id))
        // Reminders off, or 45 minutes away: the calendar's alarm is the only one.
        XCTAssertFalse(store.willSendHourBeforeReminder(for: notReminded.id))
        XCTAssertFalse(store.willSendHourBeforeReminder(for: tooSoon.id))
        XCTAssertFalse(store.willSendHourBeforeReminder(for: UUID()))
    }

    func testHourBeforeReminderIsNotPromisedWithNotificationsOff() async {
        scheduler.status = .notDetermined
        scheduler.grantsPermission = false
        let store = makeStore(defaults: makeDefaults())
        let saved = appointment(at: friday)
        store.save(saved, remind: true)
        await store.settle()

        // Still wanted, but it can't come through.
        XCTAssertTrue(store.isReminding(saved.id))
        XCTAssertTrue(store.remindersPermissionDenied)
        XCTAssertFalse(store.willSendHourBeforeReminder(for: saved.id))
    }

    func testRemovingCancelsItsReminders() async {
        scheduler.status = .authorized
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let saved = appointment(at: friday)
        store.save(saved, remind: true)
        await store.settle()
        XCTAssertEqual(scheduler.pending.count, 2)

        store.remove(saved.id)
        await store.settle()
        XCTAssertTrue(store.appointments.isEmpty)
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertTrue(makeStore(defaults: defaults).appointments.isEmpty)
    }

    func testRefreshDropsOldAppointments() async {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let old = appointment(at: september)
        let recent = appointment(at: monday)
        let upcoming = appointment(at: friday)
        store.save(old, remind: false)
        store.save(recent, remind: false)
        store.save(upcoming, remind: false)
        store.refresh()
        await store.settle()

        XCTAssertEqual(store.appointments.map(\.id), [recent.id, upcoming.id])
        XCTAssertEqual(makeStore(defaults: defaults).appointments.map(\.id), [recent.id, upcoming.id])
    }

    func testUnreadableDataStartsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "appointments.v1")
        XCTAssertTrue(makeStore(defaults: defaults).appointments.isEmpty)
    }

    func testIdentifiersAreUniquePerAppointmentAndKind() {
        let first = UUID(), second = UUID()
        let all = AppointmentStore.identifiers(for: first) + AppointmentStore.identifiers(for: second)
        XCTAssertEqual(Set(all).count, 4)
        XCTAssertTrue(all.allSatisfy { $0.hasPrefix(AppointmentStore.identifierPrefix) })
        XCTAssertFalse(all.contains { $0.hasPrefix(ReminderIdentifiers.prefix) })
    }
}
