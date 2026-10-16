import UserNotifications
import XCTest
@testable import IzzyClipz

/// Stands in for the system notification center.
final class FakeNotificationScheduler: NotificationScheduling {
    var status: UNAuthorizationStatus = .notDetermined
    var grantsPermission = true
    var failsToAdd = false
    private(set) var permissionRequests = 0
    private(set) var pending: [String: UNNotificationRequest] = [:]

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }

    func add(_ request: UNNotificationRequest) async throws {
        if failsToAdd { throw CocoaError(.featureUnsupported) }
        pending[request.identifier] = request
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            pending[identifier] = nil
        }
    }
}

@MainActor
final class ReminderStoreTests: XCTestCase {
    private let scheduler = FakeNotificationScheduler()
    // Friday, October 16, 2026, noon in Oceanside.
    private let now = Date(timeIntervalSince1970: 1_792_177_200)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func makeDefaults() -> UserDefaults {
        let suite = "ReminderStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(defaults: UserDefaults? = nil) -> ReminderStore {
        ReminderStore(scheduler: scheduler, defaults: defaults ?? makeDefaults(), calendar: calendar, now: { [now] in now })
    }

    func testStartsOffWithSensibleDefaults() {
        let store = makeStore()
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.intervalWeeks, ReminderPlanner.defaultIntervalWeeks)
        XCTAssertEqual(store.lastCut, now)
        XCTAssertNil(store.nextReminder)
    }

    func testEnablingAsksForPermissionAndSchedules() async throws {
        let store = makeStore()
        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled, "The toggle should flip immediately")
        await store.settle()

        XCTAssertEqual(scheduler.permissionRequests, 1)
        XCTAssertEqual(store.permission, .allowed)
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(scheduler.pending.count, ReminderIdentifiers.queueLength)
        XCTAssertEqual(store.upcoming.count, ReminderIdentifiers.queueLength)

        // Three weeks after today's cut, at 10 AM.
        let first = try XCTUnwrap(scheduler.pending[ReminderIdentifiers.all[0]])
        let trigger = try XCTUnwrap(first.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertEqual(trigger.dateComponents.month, 11)
        XCTAssertEqual(trigger.dateComponents.day, 6)
        XCTAssertEqual(trigger.dateComponents.hour, 10)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(first.content.title, "Time for a fresh cut")
        XCTAssertEqual(first.content.body, "It's been 3 weeks since your last cut. Tap to book at Izzy Clipz.")
    }

    func testDoesNotAskTwiceOnceAllowed() async {
        scheduler.status = .authorized
        let store = makeStore()
        store.setEnabled(true)
        await store.settle()
        store.setInterval(weeks: 4)
        await store.settle()
        XCTAssertEqual(scheduler.permissionRequests, 0)
    }

    func testDenyingPermissionTurnsRemindersOff() async {
        scheduler.grantsPermission = false
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        store.setEnabled(true)
        await store.settle()

        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.permission, .denied)
        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: "reminders.enabled"))
    }

    func testDisablingRemovesReminders() async {
        let store = makeStore()
        store.setEnabled(true)
        await store.settle()
        store.setEnabled(false)
        await store.settle()

        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertTrue(store.upcoming.isEmpty)
    }

    func testChangingTheScheduleReschedules() async throws {
        let store = makeStore()
        store.setEnabled(true)
        store.setInterval(weeks: 2)
        store.setLastCut(calendar.date(byAdding: .day, value: -7, to: now)!)
        await store.settle()

        let first = try XCTUnwrap(store.nextReminder)
        let parts = calendar.dateComponents([.month, .day, .hour], from: first.date)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 23)
        XCTAssertEqual(parts.hour, 10)
        XCTAssertEqual(first.weeksSinceCut, 2)
        XCTAssertEqual(scheduler.pending.count, ReminderIdentifiers.queueLength)
    }

    func testRapidChangesEndWithTheLatestSettings() async {
        let store = makeStore()
        for weeks in [2, 3, 4, 5, 6, 4] {
            store.setEnabled(true)
            store.setInterval(weeks: weeks)
        }
        store.setEnabled(false)
        store.setEnabled(true)
        await store.settle()

        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.intervalWeeks, 4)
        XCTAssertEqual(store.nextReminder?.weeksSinceCut, 4)
        XCTAssertEqual(scheduler.pending.count, ReminderIdentifiers.queueLength)
    }

    func testSettingsAreRemembered() async {
        let defaults = makeDefaults()
        let cut = calendar.date(byAdding: .day, value: -3, to: now)!
        let store = makeStore(defaults: defaults)
        store.setEnabled(true)
        store.setInterval(weeks: 5)
        store.setLastCut(cut)
        await store.settle()

        let reopened = makeStore(defaults: defaults)
        XCTAssertTrue(reopened.isEnabled)
        XCTAssertEqual(reopened.intervalWeeks, 5)
        XCTAssertEqual(reopened.lastCut, cut)
    }

    func testLastCutCantBeInTheFuture() {
        let store = makeStore()
        store.setLastCut(now.addingTimeInterval(86_400))
        XCTAssertEqual(store.lastCut, now)
    }

    func testIgnoresIntervalsThatArentOffered() {
        let store = makeStore()
        store.setInterval(weeks: 9)
        XCTAssertEqual(store.intervalWeeks, ReminderPlanner.defaultIntervalWeeks)

        let defaults = makeDefaults()
        defaults.set(9, forKey: "reminders.intervalWeeks")
        XCTAssertEqual(makeStore(defaults: defaults).intervalWeeks, ReminderPlanner.defaultIntervalWeeks)
    }

    func testRefreshNoticesPermissionRevokedInSettings() async {
        let store = makeStore()
        store.setEnabled(true)
        await store.settle()
        XCTAssertFalse(scheduler.pending.isEmpty)

        scheduler.status = .denied
        store.refresh()
        await store.settle()

        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.permission, .denied)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testFailedSchedulingIsNotReportedAsScheduled() async {
        scheduler.failsToAdd = true
        let store = makeStore()
        store.setEnabled(true)
        await store.settle()
        XCTAssertTrue(store.upcoming.isEmpty)
    }
}
