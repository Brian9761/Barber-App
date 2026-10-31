import SwiftUI
import UIKit

/// An appointment on a card: where it stands ("Booked", "Cancelled by the shop", "Completed"), the
/// day and time, the service with the barber, the price and length, and what can be done with it,
/// each as its own button: Add to Calendar, Directions, Cancel appointment (after a confirmation),
/// or Remove once it's over or cancelled.
///
/// Appointments saved from Squire before this version are read-only: the card says to call the
/// shop to change them.
struct AppointmentCard: View {
    let appointment: SavedAppointment
    /// "Next appointment" on Home; "Upcoming" in a list.
    var isNext = false

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var store
    @State private var isConfirmingCancel = false
    @State private var isConfirmingRemove = false
    @State private var isCancelling = false
    @State private var cancelError: String?
    private let calendar = AppData.bookingCalendar

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appointmentCard")
        .confirmationDialog("Cancel this appointment?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel appointment", role: .destructive, action: cancel)
                .accessibilityIdentifier("confirmCancelAppointment")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("\(appointment.title), \(calendar.dateTimeLabel(for: appointment.start)). The shop sees it right away.")
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
        .alert("Couldn't cancel", isPresented: Binding(get: { cancelError != nil }, set: { if !$0 { cancelError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelError ?? "")
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

            actions(isOn: isOn, now: now)
        }
    }

    /// What the client should know beyond the status.
    private func note(isOn: Bool) -> String? {
        if appointment.origin == .squire {
            return "Booked on Squire before this version of the app. To change or cancel it, call the shop."
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
                    isConfirmingCancel = true
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

    private func cancel() {
        guard !isCancelling else { return }
        isCancelling = true
        Task {
            defer { isCancelling = false }
            do {
                try await store.cancel(appointment.id)
                UIAccessibility.post(notification: .announcement, argument: "Appointment cancelled.")
            } catch let error as AppointmentActionError {
                cancelError = error.userMessage
            } catch {
                cancelError = error.asAPIError.userMessage
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
