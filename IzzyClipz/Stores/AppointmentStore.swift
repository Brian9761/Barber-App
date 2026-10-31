import Foundation
import Observation
import UserNotifications

/// An appointment this iPhone knows about, as the shop's server last described it.
struct SavedAppointment: Codable, Hashable, Identifiable {
    enum Origin: String, Codable {
        /// Booked in this app: the server knows it, and this iPhone holds its manage token.
        case app
        /// Saved in an earlier version of the app after booking on Squire. Shown, read-only, until
        /// it's over; the shop has it, the server doesn't.
        case squire
    }

    /// Why the app can't keep this appointment up to date.
    enum Problem: String, Codable {
        /// The shop's server doesn't recognize it (or its token) any more.
        case notFound
        /// Its manage token isn't on this iPhone (e.g. restored from an unencrypted backup).
        case tokenMissing
        /// The token couldn't be saved securely when it was booked. It works until the app closes.
        case tokenNotSaved
    }

    var snapshot: IzzyAPI.Appointment
    var origin: Origin
    /// Whether the client wants the day-before and hour-before reminders.
    var remind: Bool
    /// When the shop's server last confirmed it.
    var checkedAt: Date?
    var problem: Problem?

    var id: String { snapshot.id }

    var start: Date { snapshot.start }
    var end: Date { snapshot.end }
    var status: IzzyAPI.AppointmentStatus { snapshot.status }

    /// Hasn't finished yet: it's later, or happening right now.
    func isUpcoming(at now: Date) -> Bool {
        snapshot.end > now
    }

    var isCancelledByShop: Bool {
        snapshot.status == .cancelled && snapshot.cancelledBy == .shop
    }

    /// Whether the client can cancel it from the app: booked here, not started, and this iPhone
    /// still has its token.
    func canCancelInApp(at now: Date) -> Bool {
        origin == .app && problem != .notFound && problem != .tokenMissing && snapshot.isCancellable(at: now)
    }

    /// "Carlos", or "the first available barber" for a Squire booking without one.
    var barberName: String {
        snapshot.barberId.isEmpty ? "the first available barber" : snapshot.barberName
    }

    /// "Haircut with Carlos".
    var title: String {
        "\(snapshot.serviceName) with \(barberName)"
    }

    /// For Add to Calendar.
    var calendarEvent: CalendarEvent {
        CalendarEvent(
            id: id,
            title: "\(snapshot.serviceName) at \(AppData.shop.name)",
            start: snapshot.start,
            end: snapshot.end,
            notes: [
                title,
                "\(snapshot.priceLabel) · \(DurationText.short(minutes: snapshot.durationMinutes)) · Pay at the shop",
                "To change or cancel, open the \(AppData.shop.name) app or call \(AppData.shop.phone.display).",
            ].joined(separator: "\n")
        )
    }

    /// The Kit's appointment, which the reminder planner words reminders for.
    var reminderAppointment: Appointment {
        Appointment(
            serviceID: snapshot.serviceId,
            serviceName: snapshot.serviceName,
            barberID: snapshot.barberId.isEmpty ? nil : snapshot.barberId,
            barberName: snapshot.barberName,
            start: snapshot.start,
            durationMinutes: max(snapshot.durationMinutes, 1),
            priceLabel: snapshot.priceLabel,
            createdAt: snapshot.createdAt
        )
    }
}

extension SavedAppointment {
    /// A v3 appointment, saved after booking on Squire, in the same shape as the server's. Its ID
    /// stays the same, so the reminders already scheduled for it are the ones kept up to date.
    init(squire appointment: Appointment, remind: Bool) {
        self.init(
            snapshot: IzzyAPI.Appointment(
                id: appointment.id.uuidString,
                offeringId: "",
                serviceId: appointment.serviceID,
                serviceName: appointment.serviceName,
                barberId: appointment.barberID ?? "",
                barberName: appointment.barberID == nil ? Appointment.firstAvailableName : appointment.barberName,
                start: appointment.start,
                end: appointment.end,
                durationMinutes: appointment.durationMinutes,
                priceLabel: appointment.priceLabel,
                customer: IzzyAPI.Customer(name: ""),
                createdAt: appointment.createdAt
            ),
            origin: .squire,
            remind: remind,
            checkedAt: nil,
            problem: nil
        )
    }
}

/// What Add to Calendar puts in the client's calendar.
struct CalendarEvent: Hashable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let notes: String
}

/// Why the app couldn't do something with an appointment, in words for the client.
enum AppointmentActionError: Error, Equatable {
    /// This iPhone can't manage it any more (its token is gone, or the server doesn't know it).
    case cannotManage
    /// The Keychain couldn't be read right now.
    case tokenUnreadable
    case server(APIError)

    var userMessage: String {
        switch self {
        case .cannotManage:
            return "This iPhone can't change this appointment anymore. Call the shop at \(AppData.shop.phone.display) to cancel it."
        case .tokenUnreadable:
            return "Unlock your iPhone and try again, or call the shop."
        case .server(let error):
            return error.userMessage
        }
    }
}

/// A booking this iPhone has sent and not yet seen confirmed, with the manage token it was sent
/// with. Kept (in the Keychain) so every try of that same booking sends the same token.
struct PendingBooking: Codable, Equatable {
    /// What tells a retry of it from a new booking: what the server compares
    /// (`IzzyAPI.NewAppointment.retryKey`, the target, start and number).
    let request: String
    let token: IzzyAPI.ManageToken
    /// When the appointment would start. After that there's nothing left to retry.
    let start: Date
}

/// The client's appointments: kept on this iPhone with their manage tokens (in the Keychain),
/// checked with the shop's server when the app opens and on pull to refresh, cancellable from the
/// app, and reminded about the day before and an hour before.
///
/// Appointments stay listed until 30 days after they end. Nothing is dropped because the server
/// couldn't be reached or didn't recognize it: those are shown with what went wrong instead.
///
/// It also keeps the token each booking is tried with until the booking is confirmed (see
/// `bookingToken(for:)`), so a retry after a lost answer can't book twice.
@MainActor
@Observable
final class AppointmentStore {
    private enum Keys {
        static let saved = "appointments.v2"
        /// v3's appointments, saved after booking on Squire.
        static let squire = "appointments.v1"
        static let squireReminding = "appointments.reminding.v1"
    }

    /// How long a finished appointment stays listed.
    static let keepDays = 30

    /// The Keychain item with the bookings not yet confirmed. Appointments' own tokens are kept
    /// under their IDs, which never look like this.
    static let pendingBookingsAccount = "pending-bookings"
    /// How many unconfirmed bookings are remembered at most (the most recent ones).
    static let maxPendingBookings = 10

    /// Every saved appointment, earliest first.
    private(set) var appointments: [SavedAppointment] = []
    /// Set when reminders were asked for but notifications are turned off.
    private(set) var remindersPermissionDenied = false
    private(set) var isRefreshing = false
    /// Why the last check with the shop failed; `nil` once one works.
    private(set) var refreshError: APIError?
    /// When the appointments were last checked with the shop.
    private(set) var lastRefreshed: Date?

    private let api: any ShopAPI
    private let tokens: SecretStore
    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults
    private let calendar: BookingCalendar
    private let now: () -> Date
    /// Tokens the Keychain wouldn't take, for this launch only (see `Problem.tokenNotSaved`).
    @ObservationIgnored private var unsavedTokens: [String: String] = [:]
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// The bookings not yet confirmed, read from the Keychain the first time they're needed. If
    /// the Keychain won't take them, this copy still covers retries until the app closes.
    @ObservationIgnored private var pendingBookings: [PendingBooking]?

    init(
        api: any ShopAPI,
        tokens: SecretStore,
        scheduler: NotificationScheduling,
        defaults: UserDefaults,
        calendar: BookingCalendar = AppData.bookingCalendar,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.tokens = tokens
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        if let data = defaults.data(forKey: Keys.saved),
           let stored = try? Self.decode(data) {
            appointments = stored
        }
        migrateSquireAppointments()
        prune()
        sortAppointments()
    }

    // MARK: Reading

    func appointment(withID id: String) -> SavedAppointment? {
        appointments.first { $0.id == id }
    }

    /// Appointments that haven't ended, soonest first, whatever their status.
    var upcoming: [SavedAppointment] {
        let current = now()
        return appointments.filter { $0.isUpcoming(at: current) }
    }

    /// Finished ones from the last 30 days, latest first.
    var past: [SavedAppointment] {
        let current = now()
        return Array(appointments.filter { !$0.isUpcoming(at: current) }.reversed())
    }

    /// The next appointment that's still on.
    var next: SavedAppointment? {
        upcoming.first { $0.status == .booked }
    }

    /// What Home shows now (see `homeAppointments(_:at:)`).
    var homeAppointments: [SavedAppointment] {
        Self.homeAppointments(upcoming, at: now())
    }

    /// What Home shows at `date`, soonest first: the next appointment that's on and, so the client
    /// hears about it, the first one the shop cancelled if it comes before that one (or nothing is
    /// on). A new booking never hides behind an older cancellation, and the next one that's on is
    /// always there.
    static func homeAppointments(_ appointments: [SavedAppointment], at date: Date) -> [SavedAppointment] {
        let upcoming = appointments.filter { $0.isUpcoming(at: date) }
        var shown = upcoming.first { $0.status == .booked }.map { [$0] } ?? []
        if let cancelled = upcoming.first(where: \.isCancelledByShop),
           cancelled.start < (shown.first?.start ?? .distantFuture) {
            shown.insert(cancelled, at: 0)
        }
        return shown
    }

    /// When the most recent appointment that's over started, for "time for a fresh cut"
    /// reminders. Cancelled ones and no-shows don't count.
    var latestFinishedStart: Date? {
        let current = now()
        return appointments
            .filter { !$0.isUpcoming(at: current) && ($0.status == .booked || $0.status == .completed) }
            .map(\.start)
            .max()
    }

    /// Whether this app will send the appointment's hour-before reminder, so Add to Calendar
    /// shouldn't add an alert of its own at the same time.
    func willSendHourBeforeReminder(for id: String) -> Bool {
        guard !remindersPermissionDenied else { return false }
        return pendingReminders(now: now()).contains { $0.appointmentID == id && $0.reminder.kind == .hourBefore }
    }

    // MARK: Booking

    /// Saves a booking the server just confirmed, with its token in the Keychain.
    @discardableResult
    func add(_ confirmation: IzzyAPI.BookingConfirmation, remind: Bool) -> SavedAppointment {
        var saved = SavedAppointment(snapshot: confirmation.appointment, origin: .app, remind: remind, checkedAt: now(), problem: nil)
        if !storeToken(confirmation.manageToken, for: saved.id) {
            // Never dropped silently: it's kept for this launch and the appointment says so.
            unsavedTokens[saved.id] = confirmation.manageToken
            saved.problem = .tokenNotSaved
        }
        upsert(saved)
        persist()
        sync()
        return saved
    }

    /// The manage token to book `request` with (`ShopAPI.book(_:token:)`).
    ///
    /// Every try of the same booking gets the same token: Try again after an error, a retry after
    /// fixing the name or note, and a retry after the app went to the background or was closed
    /// and opened again. So if an earlier try went through but its answer never arrived, the
    /// server recognizes the retry and answers with that appointment instead of booking it twice
    /// (or saying the time was just taken). "The same booking" is what the server compares: the
    /// service and barber as picked, the time and the number. A booking that differs in one of
    /// those gets a token of its own; a changed name or note doesn't, because with a new token
    /// the server would book a second appointment (or find the client's own time taken). Tokens
    /// are kept until `finishedBooking(_:)` or until the appointment's start has passed.
    func bookingToken(for request: IzzyAPI.NewAppointment) -> IzzyAPI.ManageToken {
        let key = Self.bookingKey(for: request)
        var pending = currentPendingBookings()
        if let known = pending.first(where: { $0.request == key }) {
            return known.token
        }
        let token = IzzyAPI.ManageToken.generate()
        pending.append(PendingBooking(request: key, token: token, start: request.start))
        savePendingBookings(Array(pending.suffix(Self.maxPendingBookings)))
        return token
    }

    /// The server has answered `request` with its appointment (saved with `add`): its token is
    /// the appointment's now, and the next booking, even of the same time, gets a new one.
    func finishedBooking(_ request: IzzyAPI.NewAppointment) {
        let key = Self.bookingKey(for: request)
        let pending = currentPendingBookings()
        guard pending.contains(where: { $0.request == key }) else { return }
        savePendingBookings(pending.filter { $0.request != key })
    }

    /// What tells a retry of a booking from a new one: exactly what the server compares when the
    /// same token comes back (the target, the start, the number in E.164), so a retry the server
    /// would answer with the earlier appointment always gets the earlier token.
    static func bookingKey(for request: IzzyAPI.NewAppointment) -> String {
        request.retryKey
    }

    func setReminders(_ remind: Bool, for id: String) {
        guard let index = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[index].remind = remind
        persist()
        sync()
    }

    /// Takes an appointment off the list: one that's finished or cancelled, or one saved from
    /// Squire (the shop handles changes to those). One booked here that's still on has to be
    /// cancelled first.
    func remove(_ id: String) {
        guard let saved = appointment(withID: id) else { return }
        let isOn = saved.status == .booked && saved.isUpcoming(at: now())
        guard saved.origin == .squire || !isOn else { return }
        forget([id])
        persist()
        sync()
    }

    // MARK: Checking with the shop

    /// Drops appointments that ended long ago and re-checks reminders. Call when the app becomes
    /// active (`refresh` then asks the server).
    func refreshLocally() {
        prune()
        _ = currentPendingBookings()
        persist()
        sync()
    }

    /// Asks the shop's server about each appointment booked here that's still on or just ended: it
    /// may have been cancelled by the shop, completed or moved back. At most once a minute unless
    /// `force` (pull to refresh).
    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        if !force, let lastRefreshed, now().timeIntervalSince(lastRefreshed) < 60 { return }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        let current = now()
        let candidates = appointments.filter { saved in
            saved.origin == .app && saved.problem != .notFound
                && (saved.isUpcoming(at: current) || saved.end > current.addingTimeInterval(-24 * 60 * 60))
        }
        guard !candidates.isEmpty else {
            lastRefreshed = current
            refreshError = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        var failure: APIError?
        checking: for saved in candidates {
            let id = saved.id
            switch token(for: id) {
            case .unreadable:
                continue
            case .missing:
                setProblem(.tokenMissing, for: id)
            case .found(let token):
                let asked = now()
                do {
                    let fresh = try await api.appointment(id: id, manageToken: token)
                    update(id) { saved in
                        // Cancelled from the app while this was on its way: that answer is newer.
                        guard (saved.checkedAt ?? .distantPast) <= asked else { return }
                        saved.snapshot = fresh
                        saved.checkedAt = self.now()
                        if saved.problem != .tokenNotSaved { saved.problem = nil }
                    }
                } catch where error.isCancellation {
                    return
                } catch {
                    let apiError = error.asAPIError
                    if Self.isUnknownToServer(apiError) {
                        setProblem(.notFound, for: id)
                    } else {
                        failure = apiError
                        // Offline: every other one would fail the same way.
                        if apiError == .offline { break checking }
                    }
                }
            }
        }
        refreshError = failure
        lastRefreshed = now()
        persist()
        sync()
    }

    /// Cancels an appointment booked in the app. Cancelling again after an answer was lost, when
    /// the first try went through, finds it cancelled and succeeds.
    func cancel(_ id: String) async throws {
        guard let saved = appointment(withID: id), saved.origin == .app else { throw AppointmentActionError.cannotManage }
        let token: String
        switch self.token(for: id) {
        case .found(let found): token = found
        case .missing:
            setProblem(.tokenMissing, for: id)
            persist()
            throw AppointmentActionError.cannotManage
        case .unreadable:
            throw AppointmentActionError.tokenUnreadable
        }
        do {
            let cancelled = try await api.cancelAppointment(id: id, manageToken: token)
            update(id) { saved in
                saved.snapshot = cancelled
                saved.checkedAt = self.now()
            }
            persist()
            sync()
        } catch {
            let apiError = error.asAPIError
            if Self.isUnknownToServer(apiError) {
                setProblem(.notFound, for: id)
                persist()
                throw AppointmentActionError.cannotManage
            }
            if apiError == .notCancellable {
                // It changed at the shop (or has started): show how it is now.
                if let fresh = try? await api.appointment(id: id, manageToken: token) {
                    update(id) { saved in
                        saved.snapshot = fresh
                        saved.checkedAt = self.now()
                    }
                    persist()
                    sync()
                    // Cancelled by the client (that takes this appointment's token): an earlier
                    // try went through but its answer was lost. It's cancelled, as asked.
                    if fresh.status == .cancelled, fresh.cancelledBy == .customer { return }
                }
            }
            throw AppointmentActionError.server(apiError)
        }
    }

    /// Waits for pending notification work. For tests.
    func settle() async {
        await syncTask?.value
    }

    // MARK: Reminders

    static func identifiers(for id: String) -> [String] {
        AppointmentReminderKind.allCases.map { identifier(for: id, kind: $0) }
    }

    static func identifier(for id: String, kind: AppointmentReminderKind) -> String {
        "\(identifierPrefix)\(id)-\(kind.rawValue)"
    }

    static let identifierPrefix = "appointment-"

    // MARK: Private

    private enum TokenLookup {
        case found(String)
        case missing
        case unreadable
    }

    private func token(for id: String) -> TokenLookup {
        if let token = unsavedTokens[id] { return .found(token) }
        do {
            if let token = try tokens.secret(for: id) { return .found(token) }
            return .missing
        } catch {
            return .unreadable
        }
    }

    /// The bookings not yet confirmed whose time hasn't come, dropping the ones whose has.
    private func currentPendingBookings() -> [PendingBooking] {
        if pendingBookings == nil {
            // Unreadable (the iPhone hasn't been unlocked since it restarted) counts as none.
            let stored = try? tokens.secret(for: Self.pendingBookingsAccount)
            pendingBookings = stored.flatMap { try? IzzyAPI.makeDecoder().decode([PendingBooking].self, from: Data($0.utf8)) } ?? []
        }
        let all = pendingBookings ?? []
        let current = now()
        let live = all.filter { $0.start > current }
        if live.count != all.count {
            savePendingBookings(live)
        }
        return live
    }

    private func savePendingBookings(_ pending: [PendingBooking]) {
        pendingBookings = pending
        if pending.isEmpty {
            try? tokens.removeSecret(for: Self.pendingBookingsAccount)
        } else if let data = try? IzzyAPI.makeEncoder().encode(pending) {
            try? tokens.setSecret(String(decoding: data, as: UTF8.self), for: Self.pendingBookingsAccount)
        }
    }

    /// Saves a token, trying twice: the Keychain can fail once and work the next time.
    private func storeToken(_ token: String, for id: String) -> Bool {
        for _ in 0..<2 {
            if (try? tokens.setSecret(token, for: id)) != nil { return true }
        }
        return false
    }

    private static func isUnknownToServer(_ error: APIError) -> Bool {
        if error == .unauthorized { return true }
        if case .server(let code, _, _) = error, code == IzzyAPI.ErrorCode.notFound { return true }
        return false
    }

    private func setProblem(_ problem: SavedAppointment.Problem, for id: String) {
        update(id) { $0.problem = problem }
    }

    private func update(_ id: String, _ change: (inout SavedAppointment) -> Void) {
        guard let index = appointments.firstIndex(where: { $0.id == id }) else { return }
        change(&appointments[index])
        sortAppointments()
    }

    private func upsert(_ saved: SavedAppointment) {
        appointments.removeAll { $0.id == saved.id }
        appointments.append(saved)
        sortAppointments()
    }

    private func sortAppointments() {
        appointments.sort { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id < rhs.id
        }
    }

    /// Drops appointments that ended more than `keepDays` ago, with their tokens and reminders.
    private func prune() {
        let cutoff = now().addingTimeInterval(-TimeInterval(Self.keepDays) * 24 * 60 * 60)
        forget(appointments.filter { $0.end < cutoff }.map(\.id))
    }

    private func forget(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            try? tokens.removeSecret(for: id)
            unsavedTokens[id] = nil
        }
        scheduler.removePendingRequests(withIdentifiers: ids.flatMap(Self.identifiers(for:)))
        let gone = Set(ids)
        appointments.removeAll { gone.contains($0.id) }
    }

    /// v3 kept appointments booked on Squire under another key. The ones still ahead come along,
    /// read-only, with their reminder setting; the rest are over and aren't needed.
    private func migrateSquireAppointments() {
        guard let data = defaults.data(forKey: Keys.squire) else { return }
        let reminding = Set(defaults.stringArray(forKey: Keys.squireReminding) ?? [])
        let current = now()
        let old = (try? AppointmentPlanner.decode(data)) ?? []
        for appointment in old where appointment.isUpcoming(at: current) {
            let id = appointment.id.uuidString
            guard !appointments.contains(where: { $0.id == id }) else { continue }
            appointments.append(SavedAppointment(squire: appointment, remind: reminding.contains(id)))
        }
        // Their reminders were scheduled under the same IDs; finished ones' are cleared here.
        let dropped = old.filter { !$0.isUpcoming(at: current) }.map(\.id.uuidString)
        scheduler.removePendingRequests(withIdentifiers: dropped.flatMap(Self.identifiers(for:)))
        defaults.removeObject(forKey: Keys.squire)
        defaults.removeObject(forKey: Keys.squireReminding)
        persist()
    }

    private func persist() {
        if let data = try? Self.encode(appointments) {
            defaults.set(data, forKey: Keys.saved)
        }
    }

    static func encode(_ appointments: [SavedAppointment]) throws -> Data {
        try IzzyAPI.makeEncoder().encode(appointments)
    }

    /// Reads what `encode` wrote. One entry that can't be read doesn't lose the rest.
    static func decode(_ data: Data) throws -> [SavedAppointment] {
        try IzzyAPI.makeDecoder().decode([LossyEntry].self, from: data).compactMap(\.value)
    }

    private struct LossyEntry: Decodable {
        let value: SavedAppointment?

        init(from decoder: Decoder) throws {
            value = try? SavedAppointment(from: decoder)
        }
    }

    /// Makes the scheduled notifications match the saved appointments. Each sync waits for the
    /// previous one, so the latest state always wins.
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

        // The client may have spent a while on the permission alert, and appointments may have
        // changed meanwhile: plan from what's true now.
        let current = now()
        for (appointmentID, reminder) in pendingReminders(now: current) {
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

    /// The reminders still ahead for appointments that are on and want them.
    private func pendingReminders(now current: Date) -> [(appointmentID: String, reminder: AppointmentReminder)] {
        appointments
            .filter { $0.isUpcoming(at: current) && $0.remind && $0.status == .booked }
            .flatMap { saved in
                AppointmentPlanner.reminders(
                    for: saved.reminderAppointment,
                    shopName: AppData.shop.name,
                    address: AppData.shop.address.street,
                    calendar: calendar,
                    now: current
                )
                .map { (appointmentID: saved.id, reminder: $0) }
            }
    }
}

/// Grants every notification request without asking. UI tests use it so a system permission
/// alert never covers the screen.
final class AlwaysAllowedNotificationScheduler: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
}
