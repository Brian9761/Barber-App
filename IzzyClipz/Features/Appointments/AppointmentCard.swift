import SwiftUI
import UIKit

/// An appointment on a card: where it stands ("Booked", "Cancelled by the shop", "Completed"), the
/// day and time, the service with the barber, the price and length, and what can be done with it,
/// each as its own button: Add to Calendar, Directions, Cancel appointment (after a confirmation),
/// or Remove once it's over or cancelled.
///
/// A booking with a card on file (no-show protection) says so, and says when a fee was charged.
/// Cancelling it inside the late-cancellation window warns first that it may be charged; if the
/// shop's server says so instead (its clock decides), the client is asked again with its words.
///
/// Appointments saved by the previous version (booked on Squire) are read-only: the card says to call the
/// shop to change them.
struct AppointmentCard: View {
    let appointment: SavedAppointment
    /// "Next appointment" on Home; "Upcoming" in a list.
    var isNext = false

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var store
    @State private var isConfirmingRemove = false
    /// Cancelling it: the question, and the request. Made when the card first shows.
    @State private var cancelling: AppointmentCancelling?
    private let calendar = AppData.bookingCalendar

    private var isCancelling: Bool { cancelling?.isCancelling ?? false }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appointmentCard")
        .onAppear {
            if cancelling?.appointmentID != appointment.id {
                cancelling = AppointmentCancelling(appointmentID: appointment.id, store: store)
            }
        }
        .confirmationDialog(
            CancelQuestion.title,
            isPresented: Binding(
                get: { cancelling?.question != nil },
                set: { if !$0 { cancelling?.dismissQuestion() } }
            ),
            titleVisibility: .visible,
            presenting: cancelling?.question
        ) { question in
            Button(CancelQuestion.confirmButton, role: .destructive) {
                cancel(question)
            }
            .accessibilityIdentifier("confirmCancelAppointment")
            Button(CancelQuestion.keepButton, role: .cancel) {}
        } message: { question in
            Text(question.message)
        }
        .confirmationDialog("Remove this appointment from the list?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.remove(appointment.id)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(appointment.origin == .squire
                 ? "This only removes it from the app. To change or cancel the booking, call the shop at \(AppData.shop.phone.display)."
                 : "It only comes off this iPhone's list.")
        }
        .alert("Couldn't cancel", isPresented: Binding(get: { cancelling?.error != nil }, set: { if !$0 { cancelling?.clearError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelling?.error ?? "")
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let isOn = appointment.status == .booked && appointment.isUpcoming(at: now)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                AppointmentStatusLabel(appointment: appointment, isNext: isNext, now: now)
                Text(calendar.dateTimeLabel(for: appointment.start))
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .strikethrough(appointment.status == .cancelled, color: Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                Text(appointment.title)
                    .textRole(.callout)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(appointment.snapshot.priceLabel) · \(appointment.snapshot.durationLabel)" + (isOn ? " · Pay at the shop" : ""))
                    .textRole(.detail)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("appointmentSummary")

            if let note = note(isOn: isOn) {
                Text(note)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appointmentNote")
            }

            if isOn, let line = NoShowCopy.cardOnFileLine(appointment.snapshot) {
                Label(line, systemImage: Symbol.payment)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appointmentCardOnFile")
            }
            if let charged = NoShowCopy.feeChargedLine(appointment.snapshot) {
                Label(charged, systemImage: Symbol.payment)
                    .textRole(.caption)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appointmentFeeCharged")
            }

            actions(isOn: isOn, now: now)
        }
    }

    /// What the client should know beyond the status.
    private func note(isOn: Bool) -> String? {
        if appointment.origin == .squire {
            return "Booked before this version of the app, so it can only be changed by phone. Call the shop to change or cancel it."
        }
        switch appointment.problem {
        case .notFound?, .tokenMissing?:
            return "This iPhone can't check this appointment with the shop anymore. Call the shop if anything changed."
        case .tokenNotSaved?:
            return "This iPhone couldn't save the key to manage it after the app closes. Call the shop to change it later."
        case nil:
            break
        }
        if appointment.isCancelledByShop {
            return "The shop cancelled this appointment. Book another time, or call the shop."
        }
        return nil
    }

    @ViewBuilder private func actions(isOn: Bool, now: Date) -> some View {
        if isOn {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { calendarAndDirections }
                VStack(spacing: Theme.Space.m) { calendarAndDirections }
            }
            if appointment.canCancelInApp(at: now) {
                Button(role: .destructive) {
                    // Worked out when it's tapped: a late-cancellation warning if cancelling now may be charged.
                    cancelling?.ask()
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        if isCancelling {
                            ProgressView()
                        }
                        Text(isCancelling ? "Cancelling…" : "Cancel appointment")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.textLink(color: Theme.caution))
                .disabled(isCancelling)
                .accessibilityIdentifier("cancelAppointmentButton")
            } else {
                CallButton {
                    Label("Call the shop to change it", systemImage: Symbol.call)
                }
                .buttonStyle(.tertiary)
                .accessibilityIdentifier("appointmentCallButton")
            }
            if appointment.origin == .squire {
                removeButton
            }
        } else {
            if appointment.isCancelledByShop, appointment.isUpcoming(at: now) {
                Button {
                    router.startBooking(serviceID: appointment.snapshot.serviceId)
                } label: {
                    Text("Book another time")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("bookAgainButton")
            }
            removeButton
        }
    }

    @ViewBuilder private var calendarAndDirections: some View {
        Button {
            router.addToCalendar(appointment.calendarEvent)
        } label: {
            Label("Add to Calendar", systemImage: Symbol.calendarAdd)
        }
        .buttonStyle(.tertiary)
        .accessibilityHint("\(appointment.title), \(calendar.dateTimeLabel(for: appointment.start))")
        .accessibilityIdentifier("appointmentAddToCalendar")

        DirectionsButton {
            Label("Directions", systemImage: Symbol.directions)
        }
        .buttonStyle(.tertiary)
        .accessibilityIdentifier("appointmentDirections")
    }

    private var removeButton: some View {
        Button("Remove from this list") {
            isConfirmingRemove = true
        }
        .buttonStyle(.textLink(color: Theme.smoke))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("removeAppointmentButton")
    }

    /// The client said yes to `question`.
    private func cancel(_ question: CancelQuestion) {
        guard let cancelling else { return }
        Task {
            switch await cancelling.confirm(question) {
            case .cancelled:
                UIAccessibility.post(notification: .announcement, argument: "Appointment cancelled.")
            case .askedAgain:
                if let message = cancelling.question?.message {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            case .failed, .ignored:
                break
            }
        }
    }
}

/// "Next appointment", "Upcoming", "Cancelled by the shop", "Cancelled", "Completed", "Missed",
/// with a colored dot (and the words, so it never depends on color).
private struct AppointmentStatusLabel: View {
    let appointment: SavedAppointment
    let isNext: Bool
    let now: Date

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .textRole(.label)
                .foregroundStyle(Theme.bone)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("appointmentStatus")
    }

    private var text: String {
        switch appointment.status {
        case .booked:
            if !appointment.isUpcoming(at: now) { return "Finished" }
            if appointment.start <= now { return "Happening now" }
            return isNext ? "Next appointment" : "Booked"
        case .cancelled:
            return appointment.isCancelledByShop ? "Cancelled by the shop" : "Cancelled"
        case .completed:
            return "Completed"
        case .noShow:
            return "Missed"
        }
    }

    private var color: Color {
        switch appointment.status {
        case .booked: return appointment.isUpcoming(at: now) ? Theme.go : Theme.smoke
        case .cancelled: return Theme.caution
        case .completed: return Theme.electric
        case .noShow: return Theme.smoke
        }
    }
}
