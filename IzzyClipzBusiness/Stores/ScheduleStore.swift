import Foundation
import IzzyClipzKit
import Observation

/// One day of the shop's schedule: appointments in every status and blocked
/// time, for everyone or one barber.
@MainActor
@Observable
final class ScheduleStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The shop day on screen.
    private(set) var day: LocalDate
    /// One barber's ID, or `nil` for everyone.
    var barberFilter: String?
    private(set) var appointments: [IzzyAPI.Appointment] = []
    private(set) var timeOff: [IzzyAPI.TimeOff] = []
    private(set) var loadState: LoadState = .idle
    private(set) var lastUpdated: Date?
    /// The latest refresh failed while older data is still on screen.
    private(set) var refreshError: String?
    /// Appointments being changed right now (their buttons are disabled).
    private(set) var updating: Set<String> = []
    /// Time off being removed right now.
    private(set) var removingTimeOff: Set<String> = []
    /// A change that didn't work, for an alert.
    var actionError: String?

    let shopTime: ShopTime
    let catalog: Catalog
    /// How often the schedule refreshes by itself while it's on screen.
    static let refreshInterval: Duration = .seconds(60)
    @ObservationIgnored private let api: any OwnerAPI
    @ObservationIgnored private let clock: () -> Date
    /// Bumped by every refresh, so a slow answer for an older request (or
    /// another day) never replaces a newer one.
    @ObservationIgnored private var generation = 0
    /// The schedule shows today and the owner hasn't moved to another day, so
    /// a new day moves it on too (see `catchUpToToday()`).
    @ObservationIgnored private var followsToday = true

    init(api: any OwnerAPI, shopTime: ShopTime, catalog: Catalog, clock: @escaping () -> Date) {
        self.api = api
        self.shopTime = shopTime
        self.catalog = catalog
        self.clock = clock
        self.day = shopTime.day(containing: clock())
    }

    var today: LocalDate { shopTime.day(containing: clock()) }
    var now: Date { clock() }

    // MARK: Days

    func select(_ day: LocalDate) {
        followsToday = day == today
        guard day != self.day else { return }
        self.day = day
        generation += 1
        appointments = []
        timeOff = []
        refreshError = nil
        lastUpdated = nil
        loadState = .idle
    }

    /// After the app sat open overnight, today's schedule moves on to the new
    /// today. Another day the owner picked stays (it says "Yesterday", with
    /// Back to today). The screen calls this on every auto-refresh (see
    /// `autoRefresh(isShowingAnAppointment:)`) and when the owner goes back
    /// from an appointment's details. `true` when the day changed.
    @discardableResult
    func catchUpToToday() -> Bool {
        let today = self.today
        if day == today {
            followsToday = true
            return false
        }
        guard followsToday else { return false }
        select(today)
        return true
    }

    /// One auto-refresh, when the schedule appears or the app comes back and
    /// then every minute: a new day moves the schedule on (the screen's refresh
    /// then starts again for that day), otherwise the day loads again. While an
    /// appointment's details are open the day stays, so the appointment doesn't
    /// turn into "not found"; going back moves on.
    func autoRefresh(isShowingAnAppointment: Bool) async {
        if !isShowingAnAppointment, catchUpToToday() { return }
        await refresh()
    }

    func showToday() { select(today) }
    func showNextDay() { select(day.adding(days: 1)) }
    func showPreviousDay() { select(day.adding(days: -1)) }

    /// The date picker's value, in the shop's time zone.
    var dayAsDate: Date {
        get { shopTime.noon(on: day) }
        set { select(shopTime.day(containing: newValue)) }
    }

    // MARK: Loading

    /// Loads the day again. Keeps what's on screen if it fails.
    func refresh() async {
        generation += 1
        let requested = generation
        let day = self.day
        if loadState != .loaded { loadState = .loading }
        do {
            async let appointments = api.appointments(on: day)
            async let timeOff = api.timeOff(from: day, to: day)
            let (loadedAppointments, loadedTimeOff) = try await (appointments, timeOff)
            guard requested == generation, day == self.day else { return }
            self.appointments = loadedAppointments.sorted(by: Self.inScheduleOrder)
            self.timeOff = loadedTimeOff.sorted { $0.start < $1.start }
            lastUpdated = clock()
            refreshError = nil
            loadState = .loaded
        } catch is CancellationError {
            if requested == generation, loadState == .loading { loadState = .idle }
        } catch {
            guard requested == generation, day == self.day else { return }
            let message = ErrorText.message(for: error)
            if loadState == .loaded {
                refreshError = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    /// By start time, then barber, so two barbers' 10 AM clients stay put.
    static func inScheduleOrder(_ lhs: IzzyAPI.Appointment, _ rhs: IzzyAPI.Appointment) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.barberName != rhs.barberName { return lhs.barberName < rhs.barberName }
        return lhs.id < rhs.id
    }

    // MARK: What's shown

    var barbers: [Barber] { catalog.barbers }

    var filterTitle: String {
        guard let barberFilter, let barber = catalog.barber(withID: barberFilter) else { return "Everyone" }
        return barber.name
    }

    var visibleAppointments: [IzzyAPI.Appointment] {
        guard let barberFilter else { return appointments }
        return appointments.filter { $0.barberId == barberFilter }
    }

    /// Blocks for the filtered barber plus whole-shop blocks.
    var visibleTimeOff: [IzzyAPI.TimeOff] {
        guard let barberFilter else { return timeOff }
        return timeOff.filter { $0.barberId == nil || $0.barberId == barberFilter }
    }

    /// "4 booked · 1 completed".
    var summary: String {
        let visible = visibleAppointments
        let booked = visible.filter { $0.status == .booked }.count
        let completed = visible.filter { $0.status == .completed }.count
        var parts = ["\(booked) booked"]
        if completed > 0 { parts.append("\(completed) completed") }
        return parts.joined(separator: " · ")
    }

    func appointment(withID id: String) -> IzzyAPI.Appointment? {
        appointments.first { $0.id == id }
    }

    func barberName(for barberID: String?) -> String {
        guard let barberID else { return "Whole shop" }
        return catalog.barber(withID: barberID)?.name ?? barberID
    }

    // MARK: Changes

    /// Marks an appointment completed, no-show, cancelled (by the shop) or
    /// booked again. `true` when it worked.
    @discardableResult
    func setStatus(_ status: IzzyAPI.AppointmentStatus, for appointment: IzzyAPI.Appointment) async -> Bool {
        guard !updating.contains(appointment.id) else { return false }
        updating.insert(appointment.id)
        defer { updating.remove(appointment.id) }
        do {
            let updated = try await api.setStatus(status, ofAppointment: appointment.id)
            // A refresh that started before this change would bring the old status back.
            generation += 1
            replace(updated)
            return true
        } catch is CancellationError {
            return false
        } catch APIError.slotTaken {
            actionError = "Another appointment is booked at that time now, so this one can't be reopened."
            return false
        } catch {
            actionError = ErrorText.message(for: error)
            return false
        }
    }

    /// A booking made in New booking: shown right away if it's on this day.
    func didBook(_ appointment: IzzyAPI.Appointment) {
        guard shopTime.day(containing: appointment.start) == day else { return }
        replace(appointment)
    }

    private func replace(_ appointment: IzzyAPI.Appointment) {
        if let index = appointments.firstIndex(where: { $0.id == appointment.id }) {
            appointments[index] = appointment
        } else if shopTime.day(containing: appointment.start) == day {
            appointments.append(appointment)
        }
        appointments.sort(by: Self.inScheduleOrder)
    }

    /// Blocks time for a barber (or the whole shop). Throws a plain message.
    func addTimeOff(barberId: String?, start: Date, end: Date, reason: String) async throws {
        guard end > start else { throw ScheduleError(message: "The end has to be after the start.") }
        do {
            let block = try await api.createTimeOff(IzzyAPI.NewTimeOff(barberId: barberId, start: start, end: end, reason: reason))
            generation += 1
            let dayStart = shopTime.startOfDay(day)
            let dayEnd = shopTime.startOfDay(day.adding(days: 1))
            if block.start < dayEnd, dayStart < block.end {
                timeOff.append(block)
                timeOff.sort { $0.start < $1.start }
            }
        } catch {
            throw ScheduleError(message: ErrorText.message(for: error))
        }
    }

    // MARK: Blocked time

    /// The first and last shop days a block covers (one that ends at midnight
    /// doesn't cover the next day).
    private func days(of block: IzzyAPI.TimeOff) -> (first: LocalDate, last: LocalDate) {
        let first = shopTime.day(containing: block.start)
        return (first, max(first, shopTime.day(containing: block.end.addingTimeInterval(-1))))
    }

    /// Whether a block runs into other days than the one on screen: a few days
    /// off, or past midnight.
    func runsIntoOtherDays(_ block: IzzyAPI.TimeOff) -> Bool {
        let (first, last) = days(of: block)
        return first != day || last != day
    }

    /// When a block is: "1 PM – 2 PM" when it's all on the day on screen,
    /// otherwise with the days, "Tue, Nov 3 at 10 AM – Fri, Nov 6 at 7 PM".
    func timeText(for block: IzzyAPI.TimeOff) -> String {
        guard runsIntoOtherDays(block) else { return shopTime.timeRange(block.start, block.end) }
        return "\(shopTime.dayAndTime(block.start)) – \(shopTime.dayAndTime(block.end))"
    }

    /// What Remove asks before it removes a block. Removing takes the whole
    /// block away, so one that runs into other days says so.
    func removalQuestion(for block: IzzyAPI.TimeOff) -> (message: String, button: String) {
        let what = "\(barberName(for: block.barberId)), \(timeText(for: block))."
        guard runsIntoOtherDays(block) else {
            return ("\(what) Clients can book this time again.", "Remove blocked time")
        }
        let shown = shopTime.relativeDay(day, today: today)
        let thisDay = ["Today", "Tomorrow", "Yesterday"].contains(shown) ? shown.lowercased() : shown
        return ("\(what) This removes the whole block, not just \(thisDay). Clients can book all of it again.", "Remove the whole block")
    }

    func removeTimeOff(_ block: IzzyAPI.TimeOff) async {
        guard !removingTimeOff.contains(block.id) else { return }
        removingTimeOff.insert(block.id)
        defer { removingTimeOff.remove(block.id) }
        do {
            try await api.deleteTimeOff(id: block.id)
            generation += 1
            timeOff.removeAll { $0.id == block.id }
        } catch let error as APIError where error.code == IzzyAPI.ErrorCode.notFound {
            // Already gone (removed on another phone).
            timeOff.removeAll { $0.id == block.id }
        } catch is CancellationError {
            return
        } catch {
            actionError = ErrorText.message(for: error)
        }
    }

    /// Block time's starting values: the next half hour today (while the shop
    /// is open), otherwise opening time on the day on screen; one hour long.
    func defaultBlockTimes() -> (start: Date, end: Date) {
        let open = shopTime.openInterval(on: day)
        var start = open?.start ?? shopTime.date(on: day, hour: 10, minute: 0) ?? shopTime.noon(on: day)
        if day == today, let open {
            let halfHour: TimeInterval = 30 * 60
            let next = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / halfHour).rounded(.up) * halfHour)
            if next > start, next < open.end { start = next }
        }
        return (start, start.addingTimeInterval(3_600))
    }

    /// Booked appointments a block would overlap: the barber's, or everyone's for the whole shop.
    func appointmentsOverlapping(_ block: IzzyAPI.TimeOff) -> [IzzyAPI.Appointment] {
        appointments.filter { appointment in
            appointment.status == .booked
                && (block.barberId == nil || block.barberId == appointment.barberId)
                && appointment.start < block.end && block.start < appointment.end
        }
    }
}

struct ScheduleError: Error, Equatable, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
