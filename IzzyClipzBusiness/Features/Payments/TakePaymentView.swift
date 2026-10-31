import IzzyClipzKit
import SwiftUI

/// Take payment: the amount on a keypad (filled in from an appointment when
/// it has a fixed price), an optional note and receipt email, and the
/// "Tap to Pay on iPhone" button, always visible at the bottom.
struct TakePaymentView: View {
    @Bindable var checkout: CheckoutModel
    let workspace: Workspace
    @State private var showsDetails = false
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let notice = checkout.recoveryNotice {
                        HStack(alignment: .top) {
                            InlineMessage(text: notice, systemImage: "checkmark.circle.fill", color: .green)
                            Spacer(minLength: 0)
                            Button {
                                checkout.recoveryNotice = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                            }
                            .accessibilityLabel("Dismiss")
                        }
                        .accessibilityIdentifier("recoveryNotice")
                    }
                    modeSection
                    readerStatus
                    if let appointment = checkout.appointment {
                        appointmentCard(appointment)
                    }
                    amount
                    AmountKeypad(entry: $checkout.entry)
                    details
                    if let message = checkout.validationMessage {
                        InlineMessage(text: message, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("paymentValidation")
                    }
                    todaysPayments
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                tapToPayButton
            }
            .navigationTitle("Take payment")
            // A small title leaves room for the keypad, the note and the button on one screen.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PaymentsLink.self) { _ in
                PaymentsTodayView(checkout: checkout)
            }
            .fullScreenCover(isPresented: Binding(get: { checkout.phase != .editing }, set: { _ in })) {
                PaymentProgressView(checkout: checkout, workspace: workspace)
            }
            .task {
                await workspace.recheckStatusIfNeeded()
                await checkout.loadPayments()
                await checkout.syncPendingPayments()
            }
        }
    }

    // MARK: Mode

    @ViewBuilder
    private var modeSection: some View {
        switch checkout.mode {
        case .checking:
            if let problem = workspace.paymentsStatusError {
                // The check with the server failed: say why, and offer to check again.
                IssueCard(issue: TerminalIssue(title: "Can't check card payments", message: problem)) {
                    Button("Check again") { Task { await workspace.refreshStatus() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("checkStripeAgain")
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startPractice")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("paymentsStatusUnknown")
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking card payments…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unavailable(let issue):
            IssueCard(issue: issue) {
                Button("Practice in test mode") { checkout.startPractice() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startPractice")
                Button("Check again") { Task { await workspace.refreshStatus() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("checkStripeAgain")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paymentsUnavailable")
        case .practice(let reason):
            VStack(alignment: .leading, spacing: 8) {
                TestModeBanner()
                switch reason {
                case .deviceUnsupported:
                    Text("This iPhone can't take Tap to Pay, so payments here are practice only and aren't sent to Stripe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .chosen:
                    HStack {
                        Text("Practice payments aren't sent to Stripe or recorded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Leave test mode") { checkout.stopPractice() }
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: BusinessTheme.minimumTapSize)
                            .accessibilityIdentifier("stopPractice")
                    }
                }
            }
        case .sampleServer:
            TestModeBanner()
        case .live(_, let stripeTestMode):
            if stripeTestMode {
                TestModeBanner(text: "Stripe test mode — only test cards, no real money")
            }
            if !workspace.hasSetUpTapToPay {
                IssueCard(issue: TerminalIssue(
                    title: "Set up Tap to Pay on iPhone",
                    message: "Accept cards, Apple Pay and other digital wallets with just this iPhone. The first time, Apple asks the shop's owner to accept its terms."
                ), symbol: "wave.3.right.circle.fill", tint: BusinessTheme.red) {
                    Button {
                        Task { await workspace.setUpTapToPay() }
                    } label: {
                        if workspace.isSettingUpTapToPay { ProgressView() } else { Text("Set up Tap to Pay on iPhone") }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setUpTapToPay")
                }
            }
        }
    }

    /// Progress while Apple configures the iPhone, and readiness.
    @ViewBuilder
    private var readerStatus: some View {
        if case .live = checkout.mode {
            switch checkout.currentTerminal.state {
            case .preparing(let progress):
                ReaderProgress(progress: progress)
            case .reconnecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reconnecting Tap to Pay…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .unavailable(let issue):
                IssueCard(issue: issue) {
                    if issue.canRetry {
                        Button("Try again") { Task { await workspace.setUpTapToPay() } }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.bordered)
                }
            case .ready:
                Label("Tap to Pay is ready", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .collecting, .processing:
                EmptyView()
            }
        }
    }

    // MARK: Amount

    private func appointmentCard(_ appointment: CheckoutModel.AppointmentContext) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title).font(.subheadline.weight(.semibold))
                if appointment.suggestedCents == nil {
                    Text("Price \(appointment.priceLabel): enter the final amount.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Price \(appointment.priceLabel). Change the amount if needed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let paid = appointment.alreadyPaidCents {
                    Text("Already paid \(Money.amount(paid)).")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                checkout.clearAppointment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
            }
            .accessibilityLabel("Not for this appointment")
            .accessibilityIdentifier("clearAppointment")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paymentAppointment")
    }

    private var amount: some View {
        Text(Money.amount(checkout.entry.cents))
            .font(.system(size: amountSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityLabel("Amount")
            .accessibilityValue(Money.spoken(checkout.entry.cents))
            .accessibilityIdentifier("paymentAmount")
    }

    private var details: some View {
        DisclosureGroup(isExpanded: $showsDetails) {
            VStack(spacing: 12) {
                TextField("Note (optional), e.g. pomade", text: $checkout.note)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("paymentNote")
                TextField("Receipt email (optional)", text: $checkout.receiptEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("receiptEmail")
                Text("Stripe emails the receipt to the customer when the payment goes through.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
        } label: {
            Text(detailsTitle)
                .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .accessibilityIdentifier("paymentDetails")
    }

    private var detailsTitle: String {
        let hasNote = !checkout.note.trimmingCharacters(in: .whitespaces).isEmpty
        let hasEmail = !checkout.receiptEmail.trimmingCharacters(in: .whitespaces).isEmpty
        switch (hasNote, hasEmail) {
        case (false, false): return "Add a note or email receipt"
        case (true, false): return "Note added"
        case (false, true): return "Email receipt added"
        case (true, true): return "Note and email receipt added"
        }
    }

    private var todaysPayments: some View {
        NavigationLink(value: PaymentsLink()) {
            HStack {
                Label("Payments today", systemImage: "list.bullet.rectangle")
                Spacer()
                if checkout.isLoadingPayments && checkout.todaysPayments.isEmpty {
                    ProgressView()
                } else {
                    Text("\(Money.amount(checkout.todaysTotalCents)) · \(checkout.todaysPayments.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .frame(minHeight: BusinessTheme.minimumTapSize)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payments today, \(Money.spoken(checkout.todaysTotalCents)) from \(checkout.todaysPayments.count) payments")
        .accessibilityIdentifier("paymentsTodayLink")
    }

    /// Apple's label, no Apple logo, never disabled: an invalid amount explains itself.
    private var tapToPayButton: some View {
        Button {
            checkout.charge()
        } label: {
            Label("Tap to Pay on iPhone", systemImage: "wave.3.right.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityHint("Charges \(Money.spoken(checkout.entry.cents)).")
        .accessibilityIdentifier("tapToPayButton")
    }
}

struct PaymentsLink: Hashable {}

/// Why payments can't be taken, with buttons for what to do.
struct IssueCard<Actions: View>: View {
    let issue: TerminalIssue
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = BusinessTheme.caution
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(issue.title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions() }
                VStack(alignment: .leading, spacing: 8) { actions() }
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

/// "Getting Tap to Pay ready… 40%".
struct ReaderProgress: View {
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress {
                ProgressView(value: progress) {
                    Text("Getting Tap to Pay ready… \(Int((progress * 100).rounded()))%")
                        .font(.footnote)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting Tap to Pay ready…").font(.footnote)
                }
            }
            Text("The first time can take a minute or two. You can start a payment anyway.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readerProgress")
    }
}
