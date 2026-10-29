import SwiftUI
import UIKit

/// "Did you book it?", shown when Squire closes after the client picked a
/// time in the app. Saving keeps the appointment on this iPhone: it shows on
/// Home and in the Book tab, with optional reminders.
struct ConfirmBookingSheet: View {
    let plan: BookingPlan

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    /// Fixed when the sheet opens, so the picker's limits don't drift.
    @State private var range: ClosedRange<Date>
    @State private var remind = true
    @State private var saved: Appointment?

    /// How far ahead an appointment can be saved.
    private static let maximumDaysAhead = 90

    init(plan: BookingPlan) {
        self.plan = plan
        let range = Self.pickerRange(now: Date())
        _range = State(initialValue: range)
        _start = State(initialValue: min(max(plan.start, range.lowerBound), range.upperBound))
    }

    /// From this minute to 90 days ahead.
    static func pickerRange(now: Date) -> ClosedRange<Date> {
        let minutes = (now.timeIntervalSinceReferenceDate / 60).rounded(.down)
        let lower = Date(timeIntervalSinceReferenceDate: minutes * 60)
        let upper = lower.addingTimeInterval(TimeInterval(maximumDaysAhead) * 24 * 60 * 60)
        return lower...upper
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Overlapping, so the form and the success state cross-fade in place.
                ZStack(alignment: .top) {
                    if let saved {
                        ConfirmBookingSuccess(
                            appointment: saved,
                            remind: remind,
                            notificationsOff: appointments.remindersPermissionDenied,
                            onAddToCalendar: { router.addToCalendar(saved) },
                            onDone: { dismiss() }
                        )
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        form
                            .transition(AnyTransition.opacity)
                    }
                }
                .padding(Theme.gutter)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("confirmBookingSheet")
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
        // A pull on the form mustn't count as "I didn't book"; that button is the way out.
        .interactiveDismissDisabled(saved == nil)
        .sensoryFeedback(.success, trigger: saved != nil) { _, isSaved in
            isSaved
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 24) {
            ConfirmBookingHeader()
            BookingChoiceCard(choice: plan.choice)
            details
            actions
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Day and time")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(pickedTimeText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker(
                    "Day and time",
                    selection: $start,
                    in: range,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(Theme.red)
                .environment(\.timeZone, AppData.shop.timeZone)
                .accessibilityIdentifier("appointmentDatePicker")
                if isOutsideOpeningHours {
                    Label {
                        Text("The shop isn't open then. Check the day and time Squire gave you.")
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: Symbol.warning)
                            .foregroundStyle(Theme.soon)
                    }
                    .font(.footnote.weight(.semibold))
                }
                if let zone = BookingFlowCopy.timeZoneNote(at: start) {
                    Text(zone)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Toggle(isOn: $remind) {
                Text("Remind me the day before and an hour before")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.red)
            .accessibilityIdentifier("remindMeToggle")
        }
        .card()
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save Appointment")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("saveAppointmentButton")

            Button {
                dismiss()
            } label: {
                Text("I didn't book")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("notBookedButton")

            Button {
                // Comes back with the time as the client left it here.
                router.openSquire(plan.choice.request, plan: BookingPlan(choice: plan.choice, start: start))
            } label: {
                Label("Open Squire again", systemImage: Symbol.external)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens Squire, the shop's booking system")
            .accessibilityIdentifier("openSquireAgainButton")
        }
    }

    /// The picked time is prefilled, unless it has passed: the picker can't go
    /// back that far, so it starts at the current minute instead.
    private var pickedTimeText: String {
        if plan.start < range.lowerBound {
            return "The time you picked has passed. Set the day and time Squire gave you."
        }
        return "This is the time you picked. If Squire gave you a different one, change it here."
    }

    /// Most likely an AM/PM slip: the shop is closed at that time.
    private var isOutsideOpeningHours: Bool {
        guard let open = AppData.clock.openInterval(onDayOf: start) else { return true }
        return start < open.start || start >= open.end
    }

    private func save() {
        // A second tap while the form fades out mustn't save it twice.
        guard saved == nil else { return }
        let appointment = plan.appointment(at: start)
        appointments.save(appointment, remind: remind)
        router.finishBooking()
        withAnimation(.snappy) {
            saved = appointment
        }
        UIAccessibility.post(notification: .announcement, argument: "Appointment saved. You're all set.")
    }
}

/// The calendar badge and "Did you book it?".
private struct ConfirmBookingHeader: View {
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: Symbol.calendarClock)
                .font(.system(size: badgeSize * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Theme.redGradient, in: Circle())
                .shadow(color: Theme.red.opacity(0.3), radius: 10, y: 5)
                .accessibilityHidden(true)
            Text("Did you book it?")
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Save your appointment to see it on Home and get a reminder.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Shown once the appointment is saved.
private struct ConfirmBookingSuccess: View {
    let appointment: Appointment
    let remind: Bool
    let notificationsOff: Bool
    let onAddToCalendar: () -> Void
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 76
    private let calendar = AppData.bookingCalendar

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: Symbol.checkmark)
                    .font(.system(size: badgeSize * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Theme.open, in: Circle())
                    .shadow(color: Theme.open.opacity(0.3), radius: 10, y: 5)
                    .accessibilityHidden(true)
                Text("You're all set")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                StripeBand(stripeWidth: 7)
                    .frame(width: 72, height: 6)
                    .clipShape(Capsule())
                Text(calendar.dateTimeLabel(for: appointment.start))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(appointment.serviceName) \(BookingFlowCopy.withBarber(for: appointment))")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(appointment.priceLabel) · \(appointment.durationLabel)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            reminderNote

            VStack(spacing: 12) {
                Button(action: onAddToCalendar) {
                    Label("Add to Calendar", systemImage: Symbol.calendarAdd)
                }
                .buttonStyle(.blue)
                .accessibilityIdentifier("addToCalendarButton")

                Button(action: onDone) {
                    Text("Done")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("confirmDoneButton")
            }
        }
    }

    @ViewBuilder private var reminderNote: some View {
        if remind {
            if notificationsOff {
                ConfirmBookingNotificationsOff()
            } else if let text = reminderText {
                Label(text, systemImage: Symbol.remindersOn)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Only promises the reminders that are still ahead.
    private var reminderText: String? {
        let kinds = AppointmentPlanner.reminders(
            for: appointment,
            shopName: AppData.shop.name,
            address: AppData.shop.address.street,
            calendar: calendar,
            now: Date()
        ).map(\.kind)
        if kinds.contains(.dayBefore) { return "We'll remind you the day before and an hour before." }
        if kinds.contains(.hourBefore) { return "We'll remind you an hour before." }
        return nil
    }
}

/// Reminders were asked for, but notifications are off for the app.
private struct ConfirmBookingNotificationsOff: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Symbol.remindersOff)
                    .font(.headline)
                    .foregroundStyle(Theme.soon)
                    .accessibilityHidden(true)
                Text("Notifications are off for \(AppData.shop.name), so reminders can't come through. You can turn them on in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("openSettingsButton")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soon.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
