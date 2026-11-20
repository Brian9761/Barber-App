#if canImport(CryptoKit)
import CryptoKit
#endif
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
    /// Whether the client wants the reminders: the day before and an hour before (and the one before
    /// free cancelling ends, for a booking whose late cancellations may be charged).
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
///
/// That Keychain item moves to a new iPhone with an encrypted backup, like the manage tokens, so it
/// never holds a card's key: that stays on this iPhone only (`SavedCardStore`).
struct PendingBooking: Equatable {
    /// What tells a retry of it from a new booking: what the server compares
    /// (`IzzyAPI.NewAppointment.retryKey`, the target, start and number).
    let request: String
    let token: IzzyAPI.ManageToken
    /// When the appointment would start. After that there's nothing left to retry.
    let start: Date
    /// The card the first try booked with and said not to keep (`keepCard: false`, Remember me
    /// off), as its key's digest (`IzzyAPI.CardToken.digest`), never the key: the server marked
    /// that card for deletion with that booking, and a retry that finds it keeps that choice,
    /// whatever the retry says. `nil` for one with Remember me on, or saved before.
    var cardNotKeptDigest: String?
}

extension PendingBooking: Codable {
    fileprivate enum CodingKeys: String, CodingKey {
        case request, token, start, cardNotKeptDigest
        /// What earlier versions saved instead of the digest: the card's key itself. It's read, as
        /// its digest, and never written.
        case cardNotKept
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(String.self, forKey: .request)
        token = try container.decode(IzzyAPI.ManageToken.self, forKey: .token)
        start = try container.decode(Date.self, forKey: .start)
        if let digest = try container.decodeIfPresent(String.self, forKey: .cardNotKeptDigest) {
            cardNotKeptDigest = digest
        } else {
            cardNotKeptDigest = try container.decodeIfPresent(String.self, forKey: .cardNotKept).map(IzzyAPI.CardToken.digest(ofKey:))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encode(token, forKey: .token)
        try container.encode(start, forKey: .start)
        try container.encodeIfPresent(cardNotKeptDigest, forKey: .cardNotKeptDigest)
    }

    /// Reads the list `AppointmentStore` keeps, as this version or an earlier one saved it.
    /// `heldCardKeys` says an entry held a card's key itself (an earlier version's `cardNotKept`),
    /// read as its digest: the list is to be saved again straight away, so the key leaves the
    /// Keychain item.
    static func decodeList(from data: Data) throws -> (bookings: [PendingBooking], heldCardKeys: Bool) {
        let entries = try IzzyAPI.makeDecoder().decode([Entry].self, from: data)
        return (entries.map(\.booking), entries.contains(where: \.heldCardKey))
    }

    /// One saved entry, and whether it held a card's key.
    private struct Entry: Decodable {
        let booking: PendingBooking
        let heldCardKey: Bool

        init(from decoder: Decoder) throws {
            booking = try PendingBooking(from: decoder)
            heldCardKey = try decoder.container(keyedBy: CodingKeys.self).contains(.cardNotKept)
        }
    }
}

extension IzzyAPI.CardToken {
    /// The key's SHA-256, as 64 lowercase hex digits: what an unconfirmed booking keeps instead of
    /// the key (`PendingBooking.cardNotKeptDigest`). It tells one card's key from another's, but the
    /// key can't be worked out from it, so it can't book with the card or delete it (the shop's
    /// server asks for the key itself).
    var digest: String { Self.digest(ofKey: rawValue) }

    /// `digest` for a key kept as text (as earlier versions saved it in `PendingBooking`).
    static func digest(ofKey key: String) -> String {
        let hex = Array("0123456789abcdef")
        return String(sha256(Data(key.utf8)).flatMap { [hex[Int($0 >> 4)], hex[Int($0 & 0x0f)]] })
    }

    #if canImport(CryptoKit)
    private static func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
    #else
    /// Only where CryptoKit isn't available: the Linux build of the app's logic and its unit tests
    /// (`PortableSHA256`). The app itself always uses CryptoKit.
    private static func sha256(_ data: Data) -> [UInt8] {
        PortableSHA256.hash(Array(data))
    }
    #endif
}

/// The client's appointments: kept on this iPhone with their manage tokens (in the Keychain),
/// checked with the shop's server when the app opens and on pull to refresh, cancellable from the
/// app, and reminded about the day before and an hour before (and, when cancelling late may be
/// charged, in time to cancel for free: see `AppointmentPlanner.reminders`).
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
        // The card's digest, not its key: this list goes into backups, and the key stays on this iPhone.
        let cardNotKept = request.keepCard == false ? request.noShow?.cardToken.digest : nil
        pending.append(PendingBooking(request: key, token: token, start: request.start, cardNotKeptDigest: cardNotKept))
        savePendingBookings(Array(pending.suffix(Self.maxPendingBookings)))
        return token
    }

    /// The card the first try of `request` said not to keep, while it's still unconfirmed, as its
    /// key's digest (`PendingBooking.cardNotKeptDigest`, to compare with `IzzyAPI.CardToken.digest`):
    /// a retry that finds that booking can't keep that card for next time.
    func cardNotKept(by request: IzzyAPI.NewAppointment) -> String? {
        let key = Self.bookingKey(for: request)
        return currentPendingBookings().first(where: { $0.request == key })?.cardNotKeptDigest
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
    ///
    /// Inside the late-cancellation window of a booking with a card on file, the server asks first
    /// (by its own clock): this throws `.server(.lateCancelFee(message:))` and nothing changes. Show
    /// that warning with "Cancel appointment" and "Keep appointment", and call again with
    /// `acceptLateCancelFee: true` if the client goes ahead. Pass `true` straight away only when
    /// the client already agreed to `snapshot.lateCancelWarning(at:)`.
    func cancel(_ id: String, acceptLateCancelFee: Bool = false) async throws {
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
            let cancelled = try await api.cancelAppointment(id: id, manageToken: token, acceptLateCancelFee: acceptLateCancelFee)
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
        var mayHoldCardKeys = false
        if pendingBookings == nil {
            // Unreadable (the iPhone hasn't been unlocked since it restarted) counts as none, and
            // is left for a later launch to read.
            let stored = try? tokens.secret(for: Self.pendingBookingsAccount)
            let read = stored.flatMap { try? PendingBooking.decodeList(from: Data($0.utf8)) }
            pendingBookings = read?.bookings ?? []
            // Saved by an earlier version, with a card's key in it: saved again now, with only the
            // key's digest, so the key leaves this Keychain item. A list this version can't make
            // sense of counts as none, as before, and goes too, in case it holds a key.
            mayHoldCardKeys = stored != nil && (read?.heldCardKeys ?? true)
        }
        let all = pendingBookings ?? []
        let current = now()
        let live = all.filter { $0.start > current }
        if mayHoldCardKeys || live.count != all.count {
            if !savePendingBookings(live), mayHoldCardKeys {
                // The Keychain wouldn't take the list without the key, and the one with it mustn't
                // stay. This launch still has the list (`pendingBookings`).
                try? tokens.removeSecret(for: Self.pendingBookingsAccount)
            }
        }
        return live
    }

    /// Keeps `pending` for this launch, and in the Keychain. Returns whether the Keychain took it.
    @discardableResult
    private func savePendingBookings(_ pending: [PendingBooking]) -> Bool {
        pendingBookings = pending
        if pending.isEmpty {
            return (try? tokens.removeSecret(for: Self.pendingBookingsAccount)) != nil
        }
        guard let data = try? IzzyAPI.makeEncoder().encode(pending) else { return false }
        return (try? tokens.setSecret(String(decoding: data, as: UTF8.self), for: Self.pendingBookingsAccount)) != nil
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

    /// The reminders still ahead for appointments that are on and want them. One booked with a card
    /// on file, under a policy that charges late cancellations, says until when cancelling is free
    /// (and gets one more reminder before then when the others would come too late).
    private func pendingReminders(now current: Date) -> [(appointmentID: String, reminder: AppointmentReminder)] {
        appointments
            .filter { $0.isUpcoming(at: current) && $0.remind && $0.status == .booked }
            .flatMap { saved in
                AppointmentPlanner.reminders(
                    for: saved.reminderAppointment,
                    shopName: AppData.shop.name,
                    address: AppData.shop.address.street,
                    calendar: calendar,
                    now: current,
                    lateCancel: saved.snapshot.lateCancelTerms
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

#if !canImport(CryptoKit)
/// SHA-256 (FIPS 180-4) for `IzzyAPI.CardToken.digest` where CryptoKit isn't available: only the
/// Linux build that runs the app's logic and its unit tests. Every build of the app uses CryptoKit,
/// and the unit tests check both against the same published digests.
private enum PortableSHA256 {
    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        // The message, a 1 bit, zeros up to 8 bytes short of a whole block, and its length in bits.
        var padded = message + [0x80]
        while padded.count % 64 != 56 { padded.append(0) }
        let bitCount = UInt64(message.count) * 8
        padded += (0..<8).reversed().map { UInt8(truncatingIfNeeded: bitCount >> (8 * UInt64($0))) }

        var schedule = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: padded.count, by: 64) {
            for i in 0..<16 {
                schedule[i] = padded[(block + 4 * i)..<(block + 4 * i + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            }
            for i in 16..<64 {
                let s0 = rotateRight(schedule[i - 15], 7) ^ rotateRight(schedule[i - 15], 18) ^ (schedule[i - 15] >> 3)
                let s1 = rotateRight(schedule[i - 2], 17) ^ rotateRight(schedule[i - 2], 19) ^ (schedule[i - 2] >> 10)
                schedule[i] = schedule[i - 16] &+ s0 &+ schedule[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, h) = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
            for i in 0..<64 {
                let sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ choice &+ roundConstants[i] &+ schedule[i]
                let sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ majority
                (h, g, f, e, d, c, b, a) = (g, f, e, d &+ temp1, c, b, a, temp1 &+ temp2)
            }
            for (i, word) in [a, b, c, d, e, f, g, h].enumerated() {
                state[i] = state[i] &+ word
            }
        }
        return state.flatMap { word in (0..<4).reversed().map { UInt8(truncatingIfNeeded: word >> (8 * UInt32($0))) } }
    }

    private static func rotateRight(_ word: UInt32, _ count: UInt32) -> UInt32 {
        word >> count | word << (32 - count)
    }
}
#endif
