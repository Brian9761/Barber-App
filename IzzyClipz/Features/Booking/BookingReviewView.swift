import SwiftUI

/// Step 4: everything the client picked, and the hand-off to Squire, where
/// the real slot is confirmed.
struct BookingReviewView: View {
    let plan: BookingPlan

    @Environment(AppRouter.self) private var router
    private let calendar = AppData.bookingCalendar

    /// A time this close to now may be gone by the time the client confirms.
    private static let soonMinutes = 15

    var body: some View {
        ScrollView {
            // Re-checked every minute, so the warning shows up if the client lingers.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
        }
        .screenBackground()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                step: 4,
                of: 4,
                title: "Review & confirm",
                subtitle: "Check the details, then confirm your time on Squire."
            )

            BookingReviewSummary(plan: plan)

            if isTooSoon(now: now) {
                BookingReviewSoonWarning(timeLabel: timeLabel, hasPassed: plan.start <= now, onPickAnother: pickAnotherTime)
            }

            InfoCallout(title: "Last step: confirm on Squire", message: calloutMessage, symbol: Symbol.calendarClock)

            Button {
                router.openSquire(plan.choice.request, plan: plan)
            } label: {
                Label("Confirm on Squire", systemImage: Symbol.external)
            }
            .buttonStyle(.primary)
            .accessibilityHint("Opens Squire, the shop's booking system")
            .accessibilityIdentifier("confirmOnSquireButton")

            Text("After you confirm, come back here to save it on your phone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.gutter)
    }

    private func isTooSoon(now: Date) -> Bool {
        plan.start < now.addingTimeInterval(TimeInterval(Self.soonMinutes) * 60)
    }

    private var dayLabel: String {
        calendar.shortLabel(for: calendar.day(containing: plan.start))
    }

    private var timeLabel: String {
        calendar.timeLabel(for: plan.start)
    }

    /// What to do on Squire, in plain words.
    private var calloutMessage: String {
        let choice = plan.choice
        let opens: String
        if choice.barberID == nil {
            opens = "It opens with \(choice.serviceName) already picked, with whoever's free first."
        } else {
            opens = "It opens with \(choice.barberName) and \(choice.serviceName) already picked."
        }
        return "Squire is the shop's booking system. \(opens) Choose \(dayLabel) at \(timeLabel), or the closest open time, and confirm with your name and number."
    }

    /// Back to the calendar to choose again.
    private func pickAnotherTime() {
        guard let last = router.bookingPath.last, case .review = last else { return }
        router.bookingPath.removeLast()
    }
}

/// Service, barber, day, time, price and length, one per row.
private struct BookingReviewSummary: View {
    let plan: BookingPlan
    private let calendar = AppData.bookingCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BookingReviewRow(title: "Service", value: plan.choice.serviceName)
            Divider()
            BookingReviewRow(title: "Barber", value: plan.choice.barberName)
            Divider()
            BookingReviewRow(title: "Day", value: calendar.shortLabel(for: calendar.day(containing: plan.start)))
            Divider()
            BookingReviewRow(title: "Time", value: calendar.timeLabel(for: plan.start))
            Divider()
            BookingReviewRow(title: "Price", value: plan.choice.priceLabel, valueColor: Theme.red)
            Divider()
            BookingReviewRow(title: "Length", value: plan.choice.durationLabel)
            if let note = plan.choice.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .card()
    }
}

/// "Service ........ Haircut", stacking at large text sizes.
private struct BookingReviewRow: View {
    let title: String
    let value: String
    var valueColor: Color = Theme.ink

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }

    private var titleText: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Theme.secondaryText)
    }

    private var valueText: some View {
        Text(value)
            .font(.body.weight(.semibold))
            .foregroundStyle(valueColor)
    }
}

/// The picked time is in the past or about to be.
private struct BookingReviewSoonWarning: View {
    let timeLabel: String
    let hasPassed: Bool
    let onPickAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Symbol.warning)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.soon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasPassed ? "That time has passed" : "That time is coming up fast")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Button(action: onPickAnother) {
                Label("Pick Another Time", systemImage: Symbol.calendar)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("pickAnotherTimeButton")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soon.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.soon.opacity(0.35)))
    }

    private var message: String {
        if hasPassed {
            return "\(timeLabel) is already over. Go back to the calendar and pick a later time."
        }
        return "\(timeLabel) is only minutes away and may be gone by the time you confirm. A later time is a safer bet."
    }
}

// MARK: - Shared by the booking steps

/// Wording the booking screens share.
enum BookingFlowCopy {
    /// "with Carlos", or "with whoever's free first".
    static func withBarber(_ choice: BookingChoice) -> String {
        choice.barberID == nil ? "with whoever's free first" : "with \(choice.barberName)"
    }

    /// "with Carlos", or "with the first available barber".
    static func withBarber(for appointment: Appointment) -> String {
        appointment.barberID == nil ? "with the first available barber" : "with \(appointment.barberName)"
    }

    /// "Carlos's", or "the barbers'".
    static func barberPossessive(_ choice: BookingChoice) -> String {
        choice.barberID == nil ? "the barbers'" : "\(choice.barberName)'s"
    }
}

/// What's being booked: the service icon and name, who with, how long, and
/// the price in red.
struct BookingChoiceCard: View {
    let choice: BookingChoice

    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(symbol: symbol, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(choice.serviceName)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(BookingFlowCopy.withBarber(choice)) · \(choice.durationLabel)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(choice.priceLabel)
                .font(.headline)
                .foregroundStyle(Theme.red)
                .multilineTextAlignment(.trailing)
        }
        .card(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.serviceName) \(BookingFlowCopy.withBarber(choice)), \(choice.priceLabel), \(choice.durationLabel)")
    }

    private var symbol: String {
        AppData.catalog.service(withID: choice.serviceID)?.symbol ?? Symbol.services
    }
}
