import SwiftUI

/// Step 4: the pick on a bone ticket, and the hand-off to Squire, the shop's booking system, where
/// the real slot is confirmed. The Squire link carries the barber and the service, not the time,
/// so the hand-off card says exactly what to pick there. The screen's one red is "Confirm on
/// Squire".
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
        .bookingStepChrome(step: 4, name: "Review", title: "Review")
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            BookingStepTitle(step: 4, name: "Review", title: "Review & confirm")

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                BookingTicket(
                    kicker: "Your pick",
                    start: plan.start,
                    serviceName: plan.choice.serviceName,
                    withBarber: BookingFlowCopy.withBarber(plan.choice),
                    priceLabel: plan.choice.priceLabel,
                    durationMinutes: plan.choice.durationMinutes
                )
                if let note = plan.choice.note {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isTooSoon(now: now) {
                BookingReviewSoonWarning(timeLabel: timeLabel, hasPassed: plan.start <= now, onPickAnother: pickAnotherTime)
            }

            BookingReviewHandoff(instruction: instruction, timeZoneNote: BookingFlowCopy.timeZoneNote(at: plan.start))

            VStack(spacing: Theme.Space.s) {
                Button {
                    router.openSquire(plan.choice.request, plan: plan)
                } label: {
                    Text("Confirm on Squire")
                }
                .buttonStyle(.primary(trailingSymbol: Symbol.external, drips: true))
                .accessibilityHint("Opens Squire, the shop's booking system")
                .accessibilityIdentifier("confirmOnSquireButton")

                Text("After you confirm, come back here to save it.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xxl)
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

    /// What to do on Squire, in plain words: "Squire opens with Carlos and Haircut picked. Choose
    /// Thu, Oct 29 at 2:30 PM, or the closest open time."
    private var instruction: String {
        let choice = plan.choice
        let opens: String
        if choice.barberID == nil {
            opens = "Squire opens with \(choice.serviceName) picked, for whoever's free first."
        } else {
            opens = "Squire opens with \(choice.barberName) and \(choice.serviceName) picked."
        }
        return "\(opens) Choose \(dayLabel) at \(timeLabel), or the closest open time."
    }

    /// Back to the calendar to choose again.
    private func pickAnotherTime() {
        guard let last = router.bookingPath.last, case .review = last else { return }
        router.bookingPath.removeLast()
    }
}

/// "LAST STEP · ON SQUIRE": what Squire opens with and what to pick there. The time isn't held
/// anywhere until it's confirmed on Squire, and the card says so.
private struct BookingReviewHandoff: View {
    let instruction: String
    let timeZoneNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Kicker("Last step · on Squire")
            Text(instruction)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let base = "Squire is the shop's booking system. Nothing is booked until you confirm there with your name and number."
        guard let timeZoneNote else { return base }
        return "\(base) \(timeZoneNote)"
    }
}

/// The picked time has passed or is about to: an `ink3` card with the caution icon and a bone
/// "Pick another time" button.
private struct BookingReviewSoonWarning: View {
    let timeLabel: String
    let hasPassed: Bool
    let onPickAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.warning)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(hasPassed ? "That time has passed" : "That time is coming up fast")
                        .textRole(.callout)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Button(action: onPickAnother) {
                Text("Pick another time")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("pickAnotherTimeButton")
        }
        .card(padding: Theme.Space.xl)
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

    /// "Times are in Oceanside time (Pacific).", but only when this iPhone is
    /// set to another time zone, where shop times could pass for local ones.
    static func timeZoneNote(at date: Date) -> String? {
        let shopOffset = AppData.shop.timeZone.secondsFromGMT(for: date)
        guard TimeZone.current.secondsFromGMT(for: date) != shopOffset else { return nil }
        return "Times are in Oceanside time (Pacific)."
    }
}
