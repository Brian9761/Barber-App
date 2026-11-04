import Foundation
import Observation

/// What the client is asked before cancelling an appointment in the app: the appointment, and,
/// when cancelling now may be charged (inside the late-cancellation window the booking agreed to),
/// the warning first. "Cancel appointment" / "Keep appointment".
struct CancelQuestion: Equatable {
    static let title = "Cancel this appointment?"
    static let confirmButton = "Cancel appointment"
    static let keepButton = "Keep appointment"

    let message: String
    /// The message says cancelling now may be charged, so confirming sends `acceptLateCancelFee`.
    let warnsOfFee: Bool

    /// Asked when the client taps Cancel appointment at `now`: "Cancelling now, less than 1 hour
    /// before your appointment, may be charged $45, the full service price. Haircut with Carlos,
    /// Today at 2:30 PM." inside the window; otherwise what's being cancelled, and that it's free
    /// for a booking with a card on file.
    static func asking(about saved: SavedAppointment, at now: Date, calendar: BookingCalendar) -> CancelQuestion {
        let what = "\(saved.title), \(calendar.dateTimeLabel(for: saved.start))."
        if let warning = saved.snapshot.lateCancelWarning(at: now) {
            return CancelQuestion(message: "\(warning) \(what)", warnsOfFee: true)
        }
        let free = saved.snapshot.card != nil ? " Cancelling now is free." : ""
        return CancelQuestion(message: "\(what) The shop sees it right away.\(free)", warnsOfFee: false)
    }

    /// Asked again when the shop's server says cancelling now may be charged (its clock decides:
    /// the phone's may be off, or the minute turned while the first question was open).
    static func serverWarning(_ error: APIError, about saved: SavedAppointment, calendar: BookingCalendar) -> CancelQuestion {
        CancelQuestion(
            message: "\(error.userMessage) \(saved.title), \(calendar.dateTimeLabel(for: saved.start)).",
            warnsOfFee: true
        )
    }
}

/// Cancelling one appointment from its card: the question first (with the late-cancellation
/// warning when cancelling now may be charged), then the cancellation. If the shop's server says
/// cancelling now may be charged after all, nothing has changed: the client is asked again, with
/// the server's warning, and only a yes to that sends `acceptLateCancelFee`.
@MainActor
@Observable
final class AppointmentCancelling {
    enum Outcome: Equatable {
        case cancelled
        /// The server wants the client to confirm a late-cancellation fee: `question` asks.
        case askedAgain
        case failed
        /// Already cancelling, or the appointment isn't there any more.
        case ignored
    }

    /// The question on screen, `nil` when none is.
    private(set) var question: CancelQuestion?
    private(set) var isCancelling = false
    /// Why the last try didn't cancel it, in words for the client.
    private(set) var error: String?

    let appointmentID: String

    @ObservationIgnored private let store: AppointmentStore
    @ObservationIgnored private let calendar: BookingCalendar
    @ObservationIgnored private let now: () -> Date
    /// How long the second question waits, so the first one's dialog has finished closing (SwiftUI
    /// can drop a dialog asked for while the last one is still going away).
    @ObservationIgnored private let pauseBeforeAskingAgain: Duration

    init(
        appointmentID: String,
        store: AppointmentStore,
        calendar: BookingCalendar = AppData.bookingCalendar,
        now: @escaping () -> Date = Date.init,
        pauseBeforeAskingAgain: Duration = .milliseconds(600)
    ) {
        self.appointmentID = appointmentID
        self.store = store
        self.calendar = calendar
        self.now = now
        self.pauseBeforeAskingAgain = pauseBeforeAskingAgain
    }

    /// The client tapped Cancel appointment: the question, worked out now.
    func ask() {
        guard !isCancelling, let saved = store.appointment(withID: appointmentID) else { return }
        error = nil
        question = .asking(about: saved, at: now(), calendar: calendar)
    }

    /// The dialog closed (Keep appointment, or a tap outside it).
    func dismissQuestion() {
        question = nil
    }

    /// The client said yes to `asked`: cancels it, agreeing to a late-cancellation fee only if
    /// `asked` warned of one.
    @discardableResult
    func confirm(_ asked: CancelQuestion) async -> Outcome {
        guard !isCancelling, let saved = store.appointment(withID: appointmentID) else { return .ignored }
        question = nil
        error = nil
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await store.cancel(appointmentID, acceptLateCancelFee: asked.warnsOfFee)
            return .cancelled
        } catch AppointmentActionError.server(let apiError) where Self.isLateCancelQuestion(apiError) && !asked.warnsOfFee {
            if pauseBeforeAskingAgain > .zero {
                try? await Task.sleep(for: pauseBeforeAskingAgain)
            }
            question = .serverWarning(apiError, about: saved, calendar: calendar)
            return .askedAgain
        } catch let failure as AppointmentActionError {
            error = failure.userMessage
            return .failed
        } catch {
            self.error = error.asAPIError.userMessage
            return .failed
        }
    }

    func clearError() {
        error = nil
    }

    private static func isLateCancelQuestion(_ error: APIError) -> Bool {
        if case .lateCancelFee = error { return true }
        return false
    }
}
