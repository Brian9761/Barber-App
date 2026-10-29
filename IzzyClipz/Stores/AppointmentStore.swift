import Foundation
import Observation
import UserNotifications

/// Appointments the client saved after booking on Squire, and their
/// "tomorrow" and "in an hour" reminders.
///
/// Everything stays on this iPhone. Squire remains the real booking; this is
/// the client's own note of it.
@MainActor
@Observable
final class AppointmentStore {
    private enum Keys {
        static let appointments = "appointments.v1"
        static let reminding = "appointments.reminding.v1"
    }

    /// Every saved appointment, earliest first, including recent past ones.
    private(set) var appointments: [Appointment] = []
    /// Set when reminders were asked for but notifications are turned off.
    private(set) var remindersPermissionDenied = false

    @ObservationIgnored private var reminding: Set<UUID> = []
    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults
    private let calendar: BookingCalendar
    private let now: () -> Date
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(
        scheduler: NotificationScheduling,
        defaults: UserDefaults,
        calendar: BookingCalendar = AppData.bookingCalendar,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        if let data = defaults.data(forKey: Keys.appointments),
           let stored = try? AppointmentPlanner.decode(data) {
            appointments = AppointmentPlanner.pruned(stored, now: now()).sorted { $0.start < $1.start }
        }
        let ids = defaults.stringArray(forKey: Keys.reminding) ?? []
        reminding = Set(ids.compactMap(UUID.init(uuidString:)))
            .intersection(appointments.map(\.id))
    }

    /// Appointments that haven't ended yet, soonest first.
    var upcoming: [Appointment] {
        AppointmentPlanner.upcoming(appointments, now: now())
    }

    var next: Appointment? { upcoming.first }

    /// When the most recent appointment that's already over started. Used as
    /// the client's last cut for "time for a fresh cut" reminders.
    var latestFinishedStart: Date? {
        AppointmentPlanner.latestFinishedStart(appointments, now: now())
    }

    func isReminding(_ id: UUID) -> Bool {
        reminding.contains(id)
    }

    func save(_ appointment: Appointment, remind: Bool) {
        appointments.removeAll { $0.id == appointment.id }
        appointments.append(appointment)
        appointments.sort { $0.start < $1.start }
        if remind {
            reminding.insert(appointment.id)
        } else {
            reminding.remove(appointment.id)
        }
        persist()
        sync()
    }

    func remove(_ id: UUID) {
        appointments.removeAll { $0.id == id }
        reminding.remove(id)
        scheduler.removePendingRequests(withIdentifiers: Self.identifiers(for: id))
        persist()
        sync()
    }

    /// Drops old appointments and re-checks reminders. Call when the app becomes active.
    func refresh() {
        let pruned = AppointmentPlanner.pruned(appointments, now: now())
        if pruned.count != appointments.count {
            let removed = Set(appointments.map(\.id)).subtracting(pruned.map(\.id))
            appointments = pruned
            reminding.subtract(removed)
            persist()
        }
        sync()
    }

    /// Waits for pending work. For tests.
    func settle() async {
        await syncTask?.value
    }

    static func identifiers(for id: UUID) -> [String] {
        AppointmentReminderKind.allCases.map { identifier(for: id, kind: $0) }
    }

    static func identifier(for id: UUID, kind: AppointmentReminderKind) -> String {
        "\(identifierPrefix)\(id.uuidString)-\(kind.rawValue)"
    }

    static let identifierPrefix = "appointment-"

    // MARK: Private

    private func persist() {
        if let data = try? AppointmentPlanner.encode(appointments) {
            defaults.set(data, forKey: Keys.appointments)
        }
        defaults.set(reminding.map(\.uuidString).sorted(), forKey: Keys.reminding)
    }

    /// Makes the scheduled notifications match the saved appointments. Each
    /// sync waits for the previous one, so the latest state always wins.
    private func sync() {
        let previous = syncTask
        syncTask = Task { [weak self] in
            await previous?.value
            await self?.performSync()
        }
    }

    private func performSync() async {
        // Clear everything this store may have scheduled, then add back what's wanted.
        scheduler.removePendingRequests(withIdentifiers: appointments.flatMap { Self.identifiers(for: $0.id) })

        // Only ask for permission when there's a reminder still ahead to send.
        guard !pendingReminders(now: now()).isEmpty else {
            remindersPermissionDenied = false
            return
        }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            let granted = (try? await scheduler.requestAuthorization()) ?? false
            status = granted ? .authorized : .denied
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            remindersPermissionDenied = false
        default:
            remindersPermissionDenied = true
            return
        }

        // The client may have spent a while on the permission alert, and
        // appointments may have changed meanwhile: plan from what's true now.
        let current = now()
        for (appointmentID, reminder) in pendingReminders(now: current) {
            // Removed, or reminders turned off, while an earlier one was being added.
            guard reminding.contains(appointmentID) else { continue }
            let interval = reminder.date.timeIntervalSince(current)
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: Self.identifier(for: appointmentID, kind: reminder.kind),
                content: content,
                // An absolute moment, so a trip to another time zone doesn't move it.
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            // One failed reminder shouldn't drop the rest.
            try? await scheduler.add(request)
        }
    }

    /// The reminders still ahead for upcoming appointments that want them.
    private func pendingReminders(now current: Date) -> [(appointmentID: UUID, reminder: AppointmentReminder)] {
        upcoming
            .filter { reminding.contains($0.id) }
            .flatMap { appointment in
                AppointmentPlanner.reminders(
                    for: appointment,
                    shopName: AppData.shop.name,
                    address: AppData.shop.address.street,
                    calendar: calendar,
                    now: current
                )
                .map { (appointmentID: appointment.id, reminder: $0) }
            }
    }
}

/// Grants every notification request without asking. UI tests use it so a
/// system permission alert never covers the screen.
final class AlwaysAllowedNotificationScheduler: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
}
