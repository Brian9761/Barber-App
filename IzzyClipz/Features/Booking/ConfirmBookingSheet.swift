import SwiftUI
import UIKit

/// "Did you book it?", shown when Squire closes after the client picked a
/// time in the app. Saving keeps the appointment on this iPhone: it shows on
/// Home and in the Book tab, with optional reminders.
///
/// A still barber pole sits at the top. The form's one red is "Save appointment"; once saved, the
/// form fades out, the pole spins once (not with Reduce Motion) and "BOOKED" appears in the drip
/// face, the screen's only red text, over the ticket.
struct ConfirmBookingSheet: View {
    let plan: BookingPlan

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                // Overlapping, so the form and the saved state cross-fade in place.
                ZStack(alignment: .top) {
                    if let saved {
                        ConfirmBookingSuccess(
                            appointment: saved,
                            remind: remind,
                            notificationsOff: appointments.remindersPermissionDenied,
                            onAddToCalendar: { router.addToCalendar(saved) },
                            onDone: { dismiss() }
                        )
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        form
                            .transition(AnyTransition.opacity)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.xxl)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("confirmBookingSheet")
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(saved == nil ? .hidden : .visible)
        // A pull on the form mustn't count as "I didn't book"; that button is the way out.
        .interactiveDismissDisabled(saved == nil)
        .sensoryFeedback(.success, trigger: saved != nil) { _, isSaved in
            isSaved
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: Theme.Space.xxl) {
            VStack(spacing: Theme.Space.s) {
                Text("Did you book it?")
                    .textRole(.displayL)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Save it to see it on Home and get a reminder.")
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            ConfirmBookingChoiceRow(choice: plan.choice)
            details
            actions
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Kicker("Day and time")
                DatePicker(
                    "Day and time",
                    selection: $start,
                    in: range,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(Theme.electric)
                .environment(\.timeZone, AppData.shop.timeZone)
                .accessibilityIdentifier("appointmentDatePicker")
                Text(pickedTimeText)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                if isOutsideOpeningHours {
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        Image(systemName: Symbol.warning)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.caution)
                            .accessibilityHidden(true)
                        Text("The shop isn't open then. Check the day and time Squire gave you.")
                            .textRole(.callout)
                            .foregroundStyle(Theme.bone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let zone = BookingFlowCopy.timeZoneNote(at: start) {
                    Text(zone)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .accessibilityHidden(true)

            Toggle(isOn: $remind) {
                Text("Remind me the day before and an hour before")
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.electric)
            .accessibilityIdentifier("remindMeToggle")
        }
        .card(padding: Theme.Space.xl)
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.xxs) {
            Button(action: save) {
                Text("Save appointment")
            }
            .buttonStyle(.primary(trailingSymbol: nil))
            .accessibilityIdentifier("saveAppointmentButton")
            .padding(.bottom, Theme.Space.xs)

            Button {
                dismiss()
            } label: {
                Text("I didn't book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.textLink(color: Theme.bone))
            .accessibilityIdentifier("notBookedButton")

            Button {
                // Comes back with the time as the client left it here.
                router.openSquire(plan.choice.request, plan: BookingPlan(choice: plan.choice, start: start))
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Text("Open Squire again")
                    Image(systemName: Symbol.external)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityLabel("Open Squire again")
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

/// What's being saved, on an `ink3` row: the barber's monogram (or the service's symbol for "first
/// available"), "Haircut with Carlos", and the price and length in mono.
private struct ConfirmBookingChoiceRow: View {
    let choice: BookingChoice

    var body: some View {
        HStack(spacing: 14) {
            if let barber = choice.barberID.flatMap({ AppData.catalog.barber(withID: $0) }) {
                MonogramTile(barber: barber, side: 48)
            } else {
                ServiceIcon(symbol: AppData.catalog.service(withID: choice.serviceID)?.symbol ?? Symbol.services, size: 48)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(choice.serviceName) \(BookingFlowCopy.withBarber(choice))")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(choice.priceLabel) · \(choice.durationLabel)")
                    .textRole(.detail)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.cardPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(choice.serviceName) \(BookingFlowCopy.withBarber(choice)), \(choice.priceLabel.spokenRanges), \(choice.durationLabel.spokenRanges)"
        )
    }
}

/// Shown once the appointment is saved: "BOOKED", the ticket, the reminders, Add to Calendar and Done.
private struct ConfirmBookingSuccess: View {
    let appointment: Appointment
    let remind: Bool
    let notificationsOff: Bool
    let onAddToCalendar: () -> Void
    let onDone: () -> Void

    private let calendar = AppData.bookingCalendar

    var body: some View {
        VStack(spacing: Theme.Space.xxl) {
            Text("Booked")
                .textRole(.displayXL)
                .foregroundStyle(Theme.hotRed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The paint drips hang below the baseline.
                .padding(.bottom, Theme.Space.xxs)
                .accessibilityLabel("Booked. Appointment saved.")
                .accessibilityAddTraits(.isHeader)

            BookingTicket(
                kicker: "Saved on this iPhone",
                start: appointment.start,
                serviceName: appointment.serviceName,
                withBarber: BookingFlowCopy.withBarber(for: appointment),
                priceLabel: appointment.priceLabel,
                durationMinutes: appointment.durationMinutes
            )

            reminderNote

            VStack(spacing: Theme.Space.xxs) {
                Button(action: onAddToCalendar) {
                    Label("Add to Calendar", systemImage: Symbol.calendarAdd)
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("addToCalendarButton")
                .padding(.bottom, Theme.Space.xs)

                Button(action: onDone) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.textLink(color: Theme.bone))
                .accessibilityIdentifier("confirmDoneButton")
            }
        }
    }

    @ViewBuilder private var reminderNote: some View {
        if remind {
            if notificationsOff {
                ConfirmBookingNotificationsOff()
            } else if let text = reminderText {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: Symbol.remindersOn)
                        .foregroundStyle(Theme.electric)
                        .accessibilityHidden(true)
                    Text(text)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textRole(.callout)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
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

/// Reminders were asked for, but notifications are off for the app: an `ink3` card with the
/// caution icon and a bone "Open Settings" button.
private struct ConfirmBookingNotificationsOff: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: Symbol.remindersOff)
                    .font(.headline)
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                Text("Notifications are off for \(AppData.shop.name), so reminders can't come through. You can turn them on in Settings.")
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("openSettingsButton")
            }
        }
        .card(padding: Theme.Space.xl)
    }
}
