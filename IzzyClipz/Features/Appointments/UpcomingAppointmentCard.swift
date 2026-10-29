import SwiftUI

/// A saved appointment on a royal blue card, with Add to Calendar and
/// directions at hand.
///
/// It's the client's own note of a Squire booking, so "Remove" only takes it
/// out of the app; changes and cancellations go through the shop.
struct UpcomingAppointmentCard: View {
    let appointment: Appointment
    /// The soonest one reads "Next appointment"; later ones "Upcoming".
    var isNext = true

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    @State private var isConfirmingRemoval = false
    private let calendar = AppData.bookingCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                details
                Spacer(minLength: 0)
                moreMenu
            }
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackground }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upcomingAppointment")
        .confirmationDialog("Remove this appointment?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                withAnimation(.snappy) {
                    appointments.remove(appointment.id)
                }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("This only removes it from the app. To change or cancel the booking, call the shop at \(AppData.shop.phone.display).")
        }
    }

    // MARK: Parts

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isNext ? "NEXT APPOINTMENT" : "UPCOMING")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.8))
            Text(calendar.dateTimeLabel(for: appointment.start))
                .font(.display(.title))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(withLine)
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(appointment.priceLabel) · \(appointment.durationLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var moreMenu: some View {
        Menu {
            Link(destination: AppData.shop.phone.callURL) {
                Label("Call the shop", systemImage: Symbol.call)
            }
            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Label("Remove", systemImage: Symbol.remove)
            }
            .accessibilityIdentifier("removeAppointmentButton")
        } label: {
            Image(systemName: Symbol.more)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
        .accessibilityIdentifier("appointmentMoreButton")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(alignment: .leading, spacing: 10) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button {
            router.addToCalendar(appointment)
        } label: {
            UpcomingAppointmentActionLabel(title: "Add to Calendar", symbol: Symbol.calendarAdd)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("appointmentAddToCalendar")

        DirectionsButton {
            UpcomingAppointmentActionLabel(title: "Directions", symbol: Symbol.directions)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("appointmentDirections")
    }

    private var cardBackground: some View {
        ZStack {
            Theme.heroGradient
            StripeTexture(opacity: 0.07)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blueDeep.opacity(0.28), radius: 14, y: 6)
    }

    // MARK: Text

    /// "Haircut with Carlos".
    private var withLine: String {
        "\(appointment.serviceName) \(BookingFlowCopy.withBarber(for: appointment))"
    }

    private var accessibilitySummary: String {
        [
            isNext ? "Next appointment" : "Upcoming appointment",
            withLine,
            calendar.dateTimeLabel(for: appointment.start),
            appointment.priceLabel,
            DurationText.spoken(minutes: appointment.durationMinutes),
        ].joined(separator: ", ")
    }
}

/// A small white-outlined capsule for the card's actions.
private struct UpcomingAppointmentActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
    }
}
