import SwiftUI

/// Step 5: everything on one card (each part with "Change"), the note that nothing is paid now,
/// and the screen's one red, "Book appointment".
///
/// If booking fails, the card under the button says why in plain words and offers the way
/// forward: a taken time goes back to the times (refreshed), a problem with the details goes back
/// to them, being offline says it isn't confirmed yet (it may have gone through) and offers "Try
/// again" (which won't book it twice) and "Call the shop", and a limit says which one (in the
/// server's words) with the client's appointments, where one can be cancelled.
struct BookingReviewView: View {
    let draft: BookingDraft

    @Environment(\.shopAPI) private var api
    @Environment(AppointmentStore.self) private var appointments
    @State private var submitter: BookingSubmitter?

    var body: some View {
        Group {
            if let submitter {
                BookingReviewScreen(draft: draft, submitter: submitter)
            } else {
                Theme.ink.ignoresSafeArea()
            }
        }
        .bookingStepChrome(title: "Review")
        .onAppear {
            if submitter == nil {
                submitter = BookingSubmitter(api: api, appointments: appointments)
            }
        }
    }
}

private struct BookingReviewScreen: View {
    let draft: BookingDraft
    let submitter: BookingSubmitter

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    private let calendar = AppData.bookingCalendar

    private var plan: BookingPlan { draft.plan }
    private var choice: BookingChoice { draft.plan.choice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BookingStepHeader(step: 5, title: "Review and book")
                summary
                BookingPayAtShopNote()
                if let failure = submitter.failure {
                    BookingFailureCard(
                        failure: failure,
                        isRetrying: submitter.isBooking,
                        onRetry: book,
                        onPickAnotherTime: pickAnotherTime,
                        onEditDetails: { router.returnToDetails() },
                        // A number at the limit of upcoming appointments can cancel one of them.
                        onSeeAppointments: appointments.next == nil ? nil : { router.finishBooking() }
                    )
                }
                Text("You can cancel in the app any time before your appointment starts.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .stickyBottomBar {
            Button(action: book) {
                HStack(spacing: Theme.Space.s) {
                    if submitter.isBooking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(submitter.isBooking ? "Booking…" : "Book appointment")
                }
            }
            .buttonStyle(.primary(trailingSymbol: submitter.isBooking ? nil : Symbol.checkmark))
            .disabled(submitter.isBooking)
            .accessibilityHint("Books it with the shop. No payment now.")
            .accessibilityIdentifier("bookAppointmentButton")
        }
        // Leaving while it books would lose the confirmation.
        .navigationBarBackButtonHidden(submitter.isBooking)
        .interactiveDismissDisabled(submitter.isBooking)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SummaryRow(
                label: "Service",
                value: choice.serviceName,
                detail: [choice.priceLabel, choice.durationLabel].joined(separator: " · "),
                onChange: { router.startBooking(keepingDetails: true) },
                identifier: "service"
            )
            SummaryDivider()
            SummaryRow(
                label: "Barber",
                value: choice.barberName,
                detail: barberDetail,
                onChange: changeBarber,
                identifier: "barber"
            )
            SummaryDivider()
            SummaryRow(
                label: "Day and time",
                value: calendar.dateTimeLabel(for: plan.start),
                detail: BookingFlowCopy.timeZoneNote(at: plan.start),
                onChange: pickAnotherTime,
                identifier: "time"
            )
            SummaryDivider()
            SummaryRow(
                label: "Your details",
                value: draft.customer.trimmedName,
                detail: draft.customer.displayPhone,
                onChange: { router.returnToDetails() },
                identifier: "details"
            )
            if !draft.note.isEmpty {
                SummaryDivider()
                SummaryRow(label: "Note for your barber", value: draft.note, onChange: { router.returnToDetails() }, identifier: "note")
            }
        }
        .card(padding: Theme.Space.xl)
        .disabled(submitter.isBooking)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookingSummary")
    }

    private var barberDetail: String? {
        if let note = choice.note { return note }
        guard choice.barberID == nil else { return nil }
        return "The shop books whoever is free first: \(BookingFlowCopy.list(choice.anyBarberNames))."
    }

    /// Back to "Pick a barber" for this service, however the client got here.
    private func changeBarber() {
        router.startBooking(serviceID: choice.serviceID, keepingDetails: true)
    }

    private func pickAnotherTime() {
        router.returnToTimes(message: nil, droppedStart: nil)
    }

    /// Books it. "Try again" comes back here too, and sends the same booking with the same token,
    /// so a try that went through but whose answer was lost is found, not booked twice.
    private func book() {
        Task {
            guard let saved = await submitter.book(draft) else {
                if case .timeGone(let message)? = submitter.failure {
                    // Back to the times, which reload without the time that's gone.
                    router.returnToTimes(message: message, droppedStart: plan.start)
                }
                if let message = submitter.failure?.message {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
                return
            }
            router.showBooked(appointmentID: saved.id)
        }
    }
}

/// "No payment now — you'll pay at the shop", with how.
struct BookingPayAtShopNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            Image(systemName: Symbol.payment)
                .font(.title3)
                .foregroundStyle(Theme.electric)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("No payment now — you'll pay at the shop")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BookingFlowCopy.payAtShop)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payAtShopNote")
    }
}

/// Why the booking didn't go through, and what to do next.
private struct BookingFailureCard: View {
    let failure: BookingSubmitter.Failure
    let isRetrying: Bool
    let onRetry: () -> Void
    let onPickAnotherTime: () -> Void
    let onEditDetails: () -> Void
    /// Back to the client's appointments (the Book tab's first screen); `nil` when there are none.
    let onSeeAppointments: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.warning)
                    .font(.title3)
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(failure.title)
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    Text(failure.message)
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = failure.retryNote {
                        Text(note)
                            .textRole(.body)
                            .foregroundStyle(Theme.smoke)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bookingError")

            switch failure {
            case .offline, .other:
                Button(action: onRetry) {
                    Text(isRetrying ? "Trying again…" : "Try again")
                }
                .buttonStyle(.secondary)
                .disabled(isRetrying)
                .accessibilityIdentifier("retryBookingButton")
            case .timeGone:
                Button("Pick another time", action: onPickAnotherTime)
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("pickAnotherTimeButton")
            case .details:
                Button("Edit your details", action: onEditDetails)
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("editDetailsButton")
            case .rateLimited:
                if let onSeeAppointments {
                    Button("See your appointments", action: onSeeAppointments)
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("seeAppointmentsButton")
                }
            }
            CallButton {
                Label("Call the shop", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("bookingCallButton")
        }
        .card(padding: Theme.Space.xl)
    }
}
