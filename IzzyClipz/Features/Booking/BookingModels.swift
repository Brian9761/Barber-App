import Foundation
import Observation

/// The open times for one booking choice, from the shop's live calendar, loaded a stretch of days
/// at a time and kept by shop day (`DaySlots.date`, never the UTC date).
///
/// Days before today, after the booking window and on days the shop is closed are known without
/// asking. Every other day is "not loaded" until the server has answered for it, then "open" (with
/// its times) or "no openings".
@MainActor
@Observable
final class AvailabilityLoader {
    enum DayStatus: Equatable {
        case past
        case closed
        /// After the last day that can be booked.
        case tooFar
        /// Not asked yet, being asked, or the request failed.
        case notLoaded
        case noOpenings
        case open([IzzyAPI.Slot])

        var isBookable: Bool {
            if case .open = self { return true }
            return false
        }
    }

    /// Days per request: two weeks at a time.
    static let chunkDays = 14

    let target: IzzyAPI.BookingTarget
    /// Shop day → its open times, for every day the server has answered for.
    private(set) var slotsByDay: [LocalDate: [IzzyAPI.Slot]] = [:]
    private(set) var isLoading = false
    /// Why the last request failed; `nil` once one works.
    private(set) var error: APIError?
    /// When the last answer arrived.
    private(set) var loadedAt: Date?

    private let api: any ShopAPI
    private let calendar: BookingCalendar
    private let now: () -> Date
    @ObservationIgnored private var queue: Task<Void, Never>?

    init(target: IzzyAPI.BookingTarget, api: any ShopAPI, calendar: BookingCalendar = AppData.bookingCalendar, now: @escaping () -> Date = Date.init) {
        self.target = target
        self.api = api
        self.calendar = calendar
        self.now = now
    }

    /// Today in the shop.
    var today: LocalDate {
        LocalDate(calendar.day(containing: now()))
    }

    /// The last day that can be booked.
    var lastDay: LocalDate {
        LocalDate(calendar.lastBookableDay(now: now()))
    }

    func status(of day: LocalDate) -> DayStatus {
        if day < today { return .past }
        if day > lastDay { return .tooFar }
        if calendar.clock.schedule.hours(on: day.weekday) == nil { return .closed }
        guard let slots = slotsByDay[day] else { return .notLoaded }
        return slots.isEmpty ? .noOpenings : .open(slots)
    }

    /// The times on `day`, or `nil` when they aren't known yet.
    func slots(on day: LocalDate) -> [IzzyAPI.Slot]? {
        if case .open(let slots) = status(of: day) { return slots }
        if status(of: day) == .notLoaded { return nil }
        return []
    }

    /// The first day from `start` on with open times, among the days already loaded.
    func firstOpenDay(onOrAfter start: LocalDate) -> LocalDate? {
        slotsByDay.keys.filter { $0 >= start && status(of: $0).isBookable }.min()
    }

    /// Whether the last answer is older than `maxAge` seconds (or there's none).
    func isStale(maxAge: TimeInterval) -> Bool {
        guard let loadedAt else { return true }
        return now().timeIntervalSince(loadedAt) > maxAge
    }

    /// Loads the days of `page` that can be booked and haven't been loaded.
    func load(_ page: MonthPage) async {
        guard let range = bookableRange(of: page) else { return }
        await enqueue { await self.fetch(range.lowerBound, through: range.upperBound, skippingLoaded: true) }
    }

    /// Asks again for every bookable day of `page`, replacing what was there as answers arrive (so
    /// nothing blanks out meanwhile).
    func reload(_ page: MonthPage) async {
        guard let range = bookableRange(of: page) else { return }
        await enqueue { await self.fetch(range.lowerBound, through: range.upperBound, skippingLoaded: false) }
    }

    /// The days of `page` from today to the last bookable day.
    func bookableRange(of page: MonthPage) -> ClosedRange<LocalDate>? {
        guard let firstDay = page.days.first, let lastOfMonth = page.days.last else { return nil }
        let start = max(LocalDate(firstDay), today)
        let end = min(LocalDate(lastOfMonth), lastDay)
        return start <= end ? start...end : nil
    }

    /// Requests run one after another, so answers for the same days can't arrive out of order.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        queue = task
        await task.value
    }

    private func fetch(_ start: LocalDate, through end: LocalDate, skippingLoaded: Bool) async {
        isLoading = true
        defer { isLoading = false }
        var day = start
        while day <= end {
            if skippingLoaded, slotsByDay[day] != nil {
                day = day.adding(days: 1)
                continue
            }
            // Up to two weeks, never past `end`.
            var count = 0
            var cursor = day
            while cursor <= end, count < min(Self.chunkDays, IzzyAPI.availabilityDaysRange.upperBound) {
                count += 1
                cursor = cursor.adding(days: 1)
            }
            do {
                let response = try await api.availability(IzzyAPI.AvailabilityQuery(target: target, from: day, days: count))
                // Every day asked for is known now, even one the server left out.
                for offset in 0..<count {
                    slotsByDay[day.adding(days: offset)] = []
                }
                for daySlots in response.days {
                    slotsByDay[daySlots.date] = daySlots.slots.sorted { $0.start < $1.start }
                }
                error = nil
                loadedAt = now()
            } catch where error.isCancellation {
                return
            } catch {
                self.error = error.asAPIError
                return
            }
            day = day.adding(days: count)
        }
    }
}

extension BookingDraft {
    /// What the server is sent to book it.
    var request: IzzyAPI.NewAppointment {
        IzzyAPI.NewAppointment(target: plan.choice.target, start: plan.start, customer: customer.newCustomer, note: note)
    }
}

/// Books an appointment, saves it, and turns what can go wrong into a plain message with a way
/// forward.
///
/// Every try of the same booking is sent with the same manage token (kept by the appointment
/// store until the booking is confirmed), so Try again after a lost answer gets the appointment
/// that went through instead of booking twice or finding the client's own time taken.
@MainActor
@Observable
final class BookingSubmitter {
    /// Why a booking didn't go through, and what the review step offers next.
    enum Failure: Equatable {
        /// The time was taken, or can't be booked anymore: back to the times.
        case timeGone(String)
        /// The shop couldn't be reached: try again, or call.
        case offline(String)
        /// A limit, in the server's words: too many tries from one network (wait, or call), or
        /// a number that already has 3 upcoming appointments (cancel one, or call).
        case rateLimited(String)
        /// The server turned down the name or number: back to the details.
        case details(String)
        /// Anything else: try again, or call.
        case other(String)

        var message: String {
            switch self {
            case .timeGone(let text), .offline(let text), .rateLimited(let text), .details(let text), .other(let text):
                return text
            }
        }

        var canRetry: Bool {
            switch self {
            case .offline, .other: return true
            case .timeGone, .rateLimited, .details: return false
            }
        }
    }

    private(set) var isBooking = false
    private(set) var failure: Failure?

    private let api: any ShopAPI
    private let appointments: AppointmentStore
    private let calendar: BookingCalendar

    init(api: any ShopAPI, appointments: AppointmentStore, calendar: BookingCalendar = AppData.bookingCalendar) {
        self.api = api
        self.appointments = appointments
        self.calendar = calendar
    }

    /// Books `draft` and saves it with its token and reminders. Returns the saved appointment, or
    /// `nil` with `failure` set. A second call while one is running does nothing, so a double tap
    /// can't book twice.
    func book(_ draft: BookingDraft) async -> SavedAppointment? {
        guard !isBooking else { return nil }
        isBooking = true
        failure = nil
        defer { isBooking = false }
        let request = draft.request
        let token = appointments.bookingToken(for: request)
        let confirmation: IzzyAPI.BookingConfirmation
        do {
            confirmation = try await api.book(request, token: token)
        } catch where error.isCancellation {
            return nil
        } catch {
            failure = Self.failure(for: error.asAPIError, start: draft.plan.start, calendar: calendar)
            return nil
        }
        let saved = appointments.add(confirmation, remind: true)
        appointments.finishedBooking(request)
        guard saved.status == .booked else {
            // A retry found the booking an earlier try made, but it has been cancelled since.
            failure = .timeGone(Self.noLongerBooked(saved, calendar: calendar))
            return nil
        }
        return saved
    }

    /// Why a booking the server already had isn't on any more.
    static func noLongerBooked(_ saved: SavedAppointment, calendar: BookingCalendar) -> String {
        let time = calendar.timeLabel(for: saved.start)
        if saved.isCancelledByShop {
            return "Your booking for \(time) went through, but the shop has cancelled it since. Pick another time, or call the shop."
        }
        return "Your booking for \(time) went through, but it isn't on any more. Pick another time, or call the shop."
    }

    func clearFailure() {
        failure = nil
    }

    static func failure(for error: APIError, start: Date, calendar: BookingCalendar) -> Failure {
        let time = calendar.timeLabel(for: start)
        switch error {
        case .slotTaken:
            return .timeGone("Someone just booked \(time). Pick another time.")
        case .tooSoon:
            return .timeGone("\(time) is too soon to book now. Pick a later time.")
        case .outsideHours:
            return .timeGone("\(time) is outside the shop's hours. Pick another time.")
        case .tooFar:
            return .timeGone("That day is too far ahead to book. Pick an earlier day.")
        case .offline:
            return .offline(error.userMessage)
        case .rateLimited:
            // The server's own sentence: which limit it was and what helps.
            return .rateLimited(error.userMessage)
        case .server(let code, let message, _) where code == IzzyAPI.ErrorCode.invalidRequest:
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .details(text.isEmpty ? "Check your name and number, then try again." : text)
        default:
            return .other(error.userMessage)
        }
    }
}
