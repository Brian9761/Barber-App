import SwiftUI
import UIKit

/// After booking: "You're booked", the appointment as the shop booked it (with the barber it
/// assigned for "Any barber"), the reminders switch, Add to Calendar and Done. It replaces the
/// booking steps, so going back can't book the same time twice.
struct BookedView: View {
    let appointmentID: String

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    private let calendar = AppData.bookingCalendar

    var body: some View {
        ScrollView {
            if let saved = appointments.appointment(withID: appointmentID) {
                content(saved)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.xl)
            } else {
                ErrorStateView(
                    title: "Couldn't show this appointment",
                    message: "It was booked, but it isn't on this iPhone anymore. Call the shop to check it."
                )
                .padding(Theme.gutter)
            }
        }
        .screenBackground()
        .navigationTitle("Booked")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .stickyBottomBar {
            Button {
                router.finishBooking()
            } label: {
                Text("Done")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("bookedDoneButton")
        }
        .sensoryFeedback(.success, trigger: appointmentID)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: "You're booked.")
        }
    }

    private func content(_ saved: SavedAppointment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Image(systemName: Symbol.success)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.go)
                    .accessibilityHidden(true)
                Text("You're booked")
                    .textRole(.displayL)
                    .foregroundStyle(Theme.bone)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("bookedTitle")
                Text("See you at \(AppData.shop.name). It's in your appointments on Home and in Book.")
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SummaryRow(label: "When", value: calendar.dateTimeLabel(for: saved.start), detail: BookingFlowCopy.timeZoneNote(at: saved.start))
                SummaryDivider()
                SummaryRow(label: "Service", value: saved.snapshot.serviceName, detail: "\(saved.snapshot.priceLabel) · \(saved.snapshot.durationLabel)")
                SummaryDivider()
                SummaryRow(label: "Barber", value: saved.barberName)
                SummaryDivider()
                SummaryRow(label: "Where", value: AppData.shop.address.streetLine, detail: AppData.shop.address.cityLine)
            }
            .card(padding: Theme.Space.xl)
            .accessibilityIdentifier("bookedSummary")

            BookingPayAtShopNote()

            if saved.problem == .tokenNotSaved {
                StaleDataNote(text: "This iPhone couldn't save the key that lets you cancel in the app after you close it. To change or cancel later, call the shop at \(AppData.shop.phone.display).")
            }

            AppointmentRemindersToggle(appointment: saved)

            Button {
                router.addToCalendar(saved.calendarEvent)
            } label: {
                Label("Add to Calendar", systemImage: Symbol.calendarAdd)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("addToCalendarButton")
        }
    }
}

/// "Remind me the day before and an hour before", and what happens when notifications are off.
struct AppointmentRemindersToggle: View {
    let appointment: SavedAppointment

    @Environment(AppointmentStore.self) private var appointments

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Toggle(isOn: Binding(
                get: { appointment.remind },
                set: { appointments.setReminders($0, for: appointment.id) }
            )) {
                Text("Remind me the day before and an hour before")
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.electric)
            .accessibilityIdentifier("appointmentRemindersToggle")

            if appointment.remind, appointments.remindersPermissionDenied {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Label("Notifications are off for \(AppData.shop.name), so reminders can't come through. You can turn them on in Settings.", systemImage: Symbol.remindersOff)
                        .textRole(.callout)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link(destination: url) {
                            Text("Open Settings")
                        }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("openSettingsButton")
                    }
                }
            }
        }
        .card(padding: Theme.Space.xl)
    }
}
