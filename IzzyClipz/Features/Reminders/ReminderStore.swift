import Foundation
import Observation
import UserNotifications

/// The parts of `UNUserNotificationCenter` reminders need, so tests can swap in a fake.
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

final class SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

enum ReminderIdentifiers {
    static let prefix = "cut-reminder-"
    /// How many reminders are queued at once. The queue is topped up every
    /// time the app becomes active, so this only needs to cover long absences.
    static let queueLength = 4
    static let all = (0..<queueLength).map { "\(prefix)\($0)" }
}

/// "Time for a fresh cut" reminders: the client's settings, and keeping the
/// system's scheduled notifications in line with them.
@MainActor
@Observable
final class ReminderStore {
    enum Permission: Equatable {
        case unknown
        case allowed
        case denied
    }

    private enum Keys {
        static let enabled = "reminders.enabled"
        static let intervalWeeks = "reminders.intervalWeeks"
        static let lastCut = "reminders.lastCut"
    }

    private(set) var isEnabled: Bool
    private(set) var intervalWeeks: Int
    private(set) var lastCut: Date
    private(set) var permission: Permission = .unknown
    private(set) var upcoming: [ScheduledReminder] = []

    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(
        scheduler: NotificationScheduling,
        defaults: UserDefaults,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        isEnabled = defaults.bool(forKey: Keys.enabled)
        let storedInterval = defaults.integer(forKey: Keys.intervalWeeks)
        intervalWeeks = ReminderPlanner.intervalChoices.contains(storedInterval)
            ? storedInterval
            : ReminderPlanner.defaultIntervalWeeks
        if let stored = defaults.object(forKey: Keys.lastCut) as? Date {
            // A cut can't be in the future.
            lastCut = min(stored, now())
        } else {
            lastCut = now()
        }
    }

    var nextReminder: ScheduledReminder? { upcoming.first }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        sync()
    }

    func setInterval(weeks: Int) {
        guard ReminderPlanner.intervalChoices.contains(weeks) else { return }
        intervalWeeks = weeks
        defaults.set(weeks, forKey: Keys.intervalWeeks)
        sync()
    }

    func setLastCut(_ date: Date) {
        lastCut = min(date, now())
        defaults.set(lastCut, forKey: Keys.lastCut)
        sync()
    }

    /// Re-checks permission and tops up the queue. Call when the app becomes active.
    func refresh() {
        sync()
    }

    /// Waits for pending work. For tests.
    func settle() async {
        await syncTask?.value
    }

    /// Makes the system's notifications match the current settings.
    ///
    /// Changes can arrive faster than permission prompts and scheduling
    /// finish, so each sync waits for the previous one. Every sync reads the
    /// latest settings, so the last one always wins.
    private func sync() {
        let previous = syncTask
        syncTask = Task { [weak self] in
            await previous?.value
            await self?.performSync()
        }
    }

    private func performSync() async {
        var status = await scheduler.authorizationStatus()
        if isEnabled, status == .notDetermined {
            let granted = (try? await scheduler.requestAuthorization()) ?? false
            status = granted ? .authorized : .denied
        }
        permission = Self.permission(for: status)

        scheduler.removePendingRequests(withIdentifiers: ReminderIdentifiers.all)
        upcoming = []

        guard isEnabled else { return }
        guard permission == .allowed else {
            // Without permission nothing would ever show up, so don't pretend.
            isEnabled = false
            defaults.set(false, forKey: Keys.enabled)
            return
        }

        let planner = ReminderPlanner(calendar: calendar, hour: 10)
        let reminders = planner.upcoming(
            lastCut: lastCut,
            intervalWeeks: intervalWeeks,
            now: now(),
            count: ReminderIdentifiers.queueLength
        )
        var scheduled: [ScheduledReminder] = []
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = ReminderPlanner.title()
            content.body = ReminderPlanner.body(weeksSinceCut: reminder.weeksSinceCut, shopName: AppData.shop.name)
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let request = UNNotificationRequest(
                identifier: ReminderIdentifiers.all[index],
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await scheduler.add(request)
                scheduled.append(reminder)
            } catch {
                // Keep going: one failed reminder shouldn't drop the rest.
                continue
            }
        }
        upcoming = scheduled
    }

    private static func permission(for status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }
}
