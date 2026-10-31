import SwiftUI

/// An appointment on an `ink3` card: the day and time, the service with the barber, and the price
/// and length.
struct AppointmentSummaryCard: View {
    let appointment: SavedAppointment
    private let calendar = AppData.bookingCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(calendar.dateTimeLabel(for: appointment.start))
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Text(appointment.title)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(appointment.snapshot.priceLabel) · \(appointment.snapshot.durationLabel) · Pay at the shop")
                .textRole(.detail)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("appointmentCard")
    }
}
