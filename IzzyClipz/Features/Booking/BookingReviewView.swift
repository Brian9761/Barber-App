import SwiftUI

/// Step 5: everything on one card (each part with "Change"), the note that nothing is paid now,
/// and the screen's one red, "Book appointment".
///
/// With no-show protection (the shop's server says this booking needs a card), Review also shows
/// the "Full Service Cancellation & No-Show Fee" notice and a "Card on file" section: the card on
/// this iPhone with Change, or Add a card (Stripe's own page), and the policy the client agrees to
/// by booking. Book appointment waits until there's a card that can hold this appointment.
///
/// If booking fails, the card under the button says why in plain words and offers the way
/// forward: a taken time goes back to the times (refreshed), a problem with the details goes back
/// to them, being offline says it isn't confirmed yet (it may have gone through) and offers "Try
/// again" (which won't book it twice) and "Call the shop", and a limit says which one (in the
/// server's words) with the client's appointments, where one can be cancelled.
struct BookingReviewView: View {
    let draft: BookingDraft

    @Environment(\.shopAPI) private var api
    @Environment(\.cardSaver) private var cardSaver
    @Environment(AppointmentStore.self) private var appointments
    @Environment(SavedCardStore.self) private var cards
    @Environment(NoShowPolicyStore.self) private var policies
    @State private var submitter: BookingSubmitter?
    @State private var cardSetup: CardSetup?

    var body: some View {
        Group {
            if let submitter, let cardSetup {
                BookingReviewScreen(draft: draft, submitter: submitter, cardSetup: cardSetup)
            } else {
                Theme.ink.ignoresSafeArea()
            }
        }
        // Starting over while it books would leave its answer nowhere to show.
        .bookingStepChrome(title: "Review", showsStartOver: !(submitter?.isBooking ?? false) && !(cardSetup?.isWorking ?? false))
        .onAppear {
            if submitter == nil {
                submitter = BookingSubmitter(api: api, appointments: appointments, cards: cards, policies: policies)
            }
            if cardSetup == nil {
                cardSetup = CardSetup(api: api, saver: cardSaver ?? WebCardSaver(), cards: cards, policies: policies)
            }
        }
    }
}

private struct BookingReviewScreen: View {
    let draft: BookingDraft
    let submitter: BookingSubmitter
    let cardSetup: CardSetup

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    @Environment(SavedCardStore.self) private var cards
    @Environment(NoShowPolicyStore.self) private var policies
    @Environment(\.scenePhase) private var scenePhase
    /// Set when the time comes inside the late-cancellation window, so the note about it shows then.
    @State private var noticeClock = Date.distantPast
    private let calendar = AppData.bookingCalendar

    private var plan: BookingPlan { draft.plan }
    private var choice: BookingChoice { draft.plan.choice }

    /// What no-show protection asks of this booking right now.
    private var requirement: NoShowRequirement {
        NoShowRequirement(entry: policies.entry(for: choice.target), cards: cards, start: plan.start)
    }

    private var isBusy: Bool { submitter.isBooking || cardSetup.isWorking }

    /// When "This time is less than 1 hour away…" starts to show.
    private var noticeTimer: LateCancelNoticeTimer {
        LateCancelNoticeTimer(policy: requirement.policy, start: plan.start)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BookingStepHeader(step: 5, title: "Review and book")
                summary
                // Worked out from the clock now; `noticeTimer` brings it back when the time comes
                // inside the late-cancellation window.
                if let warning = NoShowWarningContent(policy: requirement.policy, start: plan.start, now: max(noticeClock, Date())) {
                    NoShowWarningCard(content: warning)
                }
                ReviewCardSection(requirement: requirement, setup: cardSetup, onAddCard: addCard)
                    .disabled(submitter.isBooking)
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
                if requirement.policy == nil {
                    // With a card on file, the notice above says when cancelling is free.
                    Text("You can cancel in the app any time before your appointment starts.")
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .stickyBottomBar {
            Button(action: book) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.s) {
                        if submitter.isBooking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(submitter.isBooking ? "Booking…" : "Book appointment")
                    }
                    if !submitter.isBooking, let note = requirement.bookButtonNote {
                        Text(note)
                            .textRole(.caption)
                    }
                }
            }
            .buttonStyle(.primary(trailingSymbol: submitter.isBooking ? nil : Symbol.checkmark))
            .disabled(isBusy || requirement.blocksBooking)
            .accessibilityLabel(submitter.isBooking ? "Booking…" : "Book appointment")
            .accessibilityValue(submitter.isBooking ? "" : (requirement.bookButtonNote ?? ""))
            .accessibilityHint(requirement.policy == nil ? "Books it with the shop. No payment now." : "Books it with the shop. Nothing is charged now.")
            .accessibilityIdentifier("bookAppointmentButton")
        }
        // Leaving while it books would lose the confirmation.
        .navigationBarBackButtonHidden(isBusy)
        .interactiveDismissDisabled(isBusy)
        .task {
            // Usually already here from the times; asked again when it's more than a minute old.
            await policies.load(choice.target)
        }
        .task(id: noticeTimer) {
            // The time comes inside the late-cancellation window while the client looks: say so
            // from that moment.
            guard let wait = noticeTimer.wait(now: Date()), (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
            noticeClock = Date()
            if let notice = requirement.policy?.lateCancelNotice(start: plan.start, now: noticeClock) {
                UIAccessibility.post(notification: .announcement, argument: notice)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isBusy {
                Task { await policies.load(choice.target) }
            }
        }
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
        .disabled(isBusy)
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

    /// Stripe's card page, then the card is kept on this iPhone (for next time with "Remember me").
    private func addCard() {
        Task {
            guard let card = await cardSetup.addCard(for: choice.target, remember: draft.remember) else {
                if let failure = cardSetup.failure {
                    UIAccessibility.post(notification: .announcement, argument: failure)
                }
                return
            }
            // A card was what the last try was missing.
            if case .cardNeeded? = submitter.failure {
                submitter.clearFailure()
            }
            UIAccessibility.post(notification: .announcement, argument: NoShowCopy.cardAdded(card))
        }
    }

    /// Books it, with the card and the policy on screen when the booking needs them. "Try again"
    /// comes back here too, and sends the same booking with the same token, so a try that went
    /// through but whose answer was lost is found, not booked twice.
    ///
    /// Once it's booked, "You're booked" shows even if the client has left this review (for
    /// another booking started from Services, say): they haven't seen it yet, and booking that
    /// time again would make a second appointment. A try that didn't go through leaves the flow
    /// on screen alone once its review is gone.
    private func book() {
        let asked = requirement
        guard !asked.blocksBooking, !cardSetup.isWorking else { return }
        Task {
            if let saved = await submitter.book(draft, noShow: asked.agreement) {
                router.showBooked(appointmentID: saved.id)
                return
            }
            guard router.isShowing(.review(draft)) else { return }
            if case .timeGone(let message)? = submitter.failure {
                // Back to the times, which reload without the time that's gone.
                router.returnToTimes(message: message, droppedStart: plan.start)
            }
            if let message = submitter.failure?.message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
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
            case .cardNeeded, .policyChanged:
                // The card section above has what to do: add a card, or check the new policy and book.
                EmptyView()
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
