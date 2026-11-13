import IzzyClipzKit
import SwiftUI

/// The checkout once it's paid: for a card, getting Tap to Pay ready, waiting for the card (Apple's
/// Tap to Pay screen is on top of this one), processing, and a clear result with what to do next,
/// with "Email a receipt (optional)" once it went through; for cash or another way, saving the sale
/// and its receipt ("Sold $60 · Cash · Izzy"). It can't be swiped away: every state has its own
/// buttons, so a payment is never left half done by accident.
struct PaymentProgressView: View {
    let checkout: CheckoutModel
    let workspace: Workspace
    /// The receipt's email field has the keyboard: its Send receipt is the action then, so the
    /// bar's Done (which closes this screen without sending) steps aside until the keyboard goes,
    /// instead of sitting over Send receipt just above the keyboard, and the page scrolls Send
    /// receipt into view above the keyboard (bringing the field into view alone left it behind the
    /// keyboard). Return sends too, and a swipe down closes the keyboard.
    @FocusState private var typingReceiptEmail: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { page in
                ScrollView {
                    VStack(spacing: 24) {
                        // About the card reader: a cash or other sale is saved the same way in test mode.
                        if checkout.mode.isTestMode, !isSale {
                            TestModeBanner()
                        }
                        content
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    buttons
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .onChange(of: typingReceiptEmail) { _, typing in
                    guard typing else { return }
                    Task {
                        // Once the keyboard is up: iOS brings only the field itself into view.
                        try? await Task.sleep(for: .milliseconds(500))
                        withAnimation { page.scrollTo(ReceiptEmailOffer.endID, anchor: .bottom) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    /// The simulated reader's "tap a card" request, while test mode waits for one.
    private var simulatedTap: (SimulatedPaymentTerminal, SimulatedPaymentTerminal.PendingTap)? {
        guard let simulated = checkout.currentTerminal as? SimulatedPaymentTerminal, let tap = simulated.pendingTap else { return nil }
        return (simulated, tap)
    }

    private var amountCents: Int { checkout.active?.request.amountCents ?? checkout.ticket.totalCents }

    /// A cash or other sale (not a card payment).
    private var isSale: Bool {
        switch checkout.phase {
        case .recording, .recorded, .recordFailed, .recordUnknown: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch checkout.phase {
        case .editing:
            EmptyView()
        case .preparing:
            if case .preparing(let progress?) = checkout.currentTerminal.state {
                StatusBlock(symbol: "wave.3.right.circle", title: "Getting Tap to Pay ready", detail: "The first time on this iPhone can take a minute or two.", id: "statusPreparing") {
                    ProgressView(value: progress)
                        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
                }
            } else {
                StatusBlock(symbol: "wave.3.right.circle", title: "Getting Tap to Pay ready", detail: "One moment.", id: "statusPreparing") {
                    ProgressView()
                }
            }
        case .creating:
            StatusBlock(symbol: "creditcard", title: "Starting the payment", detail: Money.amount(amountCents), id: "statusCreating") {
                ProgressView()
            }
        case .collecting:
            if checkout.isProcessing {
                // The card was read (Apple's screen has closed): don't ask for it again.
                processing
            } else if let pending = simulatedTap {
                SimulatedTapPanel(terminal: pending.0, amountCents: pending.1.amountCents)
            } else if case .preparing(let progress) = checkout.currentTerminal.state {
                // Reconnecting before the card can be read (after the app was in the background).
                StatusBlock(symbol: "wave.3.right.circle", title: "Getting Tap to Pay ready", detail: "One moment.", id: "statusPreparing") {
                    if let progress { ProgressView(value: progress) } else { ProgressView() }
                }
            } else if checkout.currentTerminal.state == .reconnecting {
                StatusBlock(symbol: "wave.3.right.circle", title: "Reconnecting Tap to Pay", detail: "One moment.", id: "statusPreparing") {
                    ProgressView()
                }
            } else {
                StatusBlock(
                symbol: "wave.3.right.circle.fill",
                title: "Waiting for the card",
                detail: [
                    "\(Money.amount(amountCents)). Hold the iPhone out so the customer can tap their card, phone or watch near the top.",
                    checkout.currentTerminal.readerMessage,
                ].compactMap { $0 }.joined(separator: "\n"),
                id: "statusCollecting"
                ) {
                    ProgressView()
                }
            }
        case .confirming:
            processing
        case .succeeded(let receipt):
            StatusBlock(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: receipt.isTestMode ? "Test payment approved" : "Paid \(Money.amount(receipt.amountCents))",
                detail: successDetail(receipt),
                id: "statusPaid"
            )
            if let sale = receipt.sale {
                SaleReceiptCard(receipt: sale)
            }
            if receipt.offersReceiptEmail {
                ReceiptEmailOffer(checkout: checkout, focus: $typingReceiptEmail)
            }
        case .recording(let method):
            StatusBlock(symbol: method == .cash ? "banknote" : "ellipsis.circle", title: "Saving the sale", detail: Money.amount(amountCents), id: "statusRecording") {
                ProgressView()
            }
        case .recorded(let receipt):
            StatusBlock(symbol: "checkmark.circle.fill", tint: .green, title: receipt.summary, detail: recordedDetail(receipt), id: "statusSold")
            SaleReceiptCard(receipt: receipt)
        case .recordFailed(let message):
            StatusBlock(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "The sale wasn't saved", detail: message, id: "statusRecordFailed")
        case .recordUnknown(let message):
            StatusBlock(symbol: "questionmark.circle.fill", tint: .orange, title: "Check the sale", detail: message, id: "statusRecordUnknown")
        case .declined(let message):
            StatusBlock(symbol: "xmark.octagon.fill", tint: .red, title: "Declined", detail: message, id: "statusDeclined")
        case .cancelled:
            StatusBlock(symbol: "xmark.circle", tint: .secondary, title: "Payment cancelled", detail: "No card was charged.", id: "statusCancelled")
        case .failed(let message):
            StatusBlock(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "The payment didn't go through", detail: message, id: "statusFailed")
        case .outcomeUnknown(let message):
            StatusBlock(symbol: "questionmark.circle.fill", tint: .orange, title: "Check the payment", detail: message, id: "statusUnknown")
        case .notPaid(let message):
            StatusBlock(symbol: "exclamationmark.circle.fill", tint: .orange, title: "Not paid", detail: message, id: "statusNotPaid")
        }
    }

    /// The same while Stripe authorizes the card and while the server checks it.
    private var processing: some View {
        StatusBlock(symbol: "hourglass", title: "Processing", detail: "Checking the payment with Stripe. Keep the app open.", id: "statusProcessing") {
            ProgressView()
        }
    }

    private func successDetail(_ receipt: CheckoutModel.Receipt) -> String {
        if receipt.isTestMode {
            return "\(Money.amount(receipt.amountCents)). Test mode: no card was charged."
        }
        var lines: [String] = []
        if let title = receipt.title { lines.append(title) }
        if receipt.stripeTestMode {
            lines.append("Stripe test mode: no real money moved, and Stripe doesn't email receipts in test mode.")
        }
        return lines.joined(separator: "\n")
    }

    private func recordedDetail(_ receipt: SaleReceipt) -> String {
        receipt.method == .cash
            ? "The cash sale is saved in Today's sales."
            : "The sale is saved in Today's sales. The app only records it: the money comes in the way the client paid."
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            switch checkout.phase {
            case .editing, .creating, .confirming:
                EmptyView()
            case .preparing, .collecting:
                // Test mode's panel has its own "Customer cancels". Once the
                // card is read, the payment can't be stopped.
                if simulatedTap == nil, checkout.canCancel {
                    secondary("Cancel", id: "cancelPayment") { checkout.cancel() }
                }
            case .succeeded:
                // Not while the receipt's email is being typed: Send receipt is the action then.
                if !typingReceiptEmail {
                    primary("Done", id: "paymentDone") {
                        checkout.reset()
                        if workspace.owesHowToTap {
                            // After this screen has gone, so Apple's sheet has something to show over.
                            Task {
                                try? await Task.sleep(for: .milliseconds(700))
                                await workspace.showHowToTap()
                            }
                        }
                    }
                }
            case .declined:
                primary("Try another card", id: "retryPayment") { checkout.tryAgain() }
                secondary("Cancel payment", id: "backToAmount") { checkout.backToEditing() }
            case .cancelled, .failed:
                primary("Try again", id: "retryPayment") { checkout.tryAgain() }
                secondary("Back", id: "backToAmount") { checkout.backToEditing() }
            case .outcomeUnknown:
                primary("Check the payment", id: "checkPayment") { checkout.checkAgain() }
                secondary("Back", id: "backToAmount") { checkout.backToEditing() }
            case .notPaid:
                primary("Try the card again", id: "retryPayment") { checkout.tryAgain() }
                secondary("Back", id: "backToAmount") { checkout.backToEditing() }
            case .recording:
                EmptyView()
            case .recorded:
                primary("Done", id: "saleDone") { checkout.reset() }
            case .recordFailed:
                // The server said why (it's in the message): usually the ticket needs a change.
                primary("Back to the ticket", id: "backToAmount") { checkout.backToEditing() }
                secondary("Try again", id: "retrySale") { checkout.recordAgain() }
            case .recordUnknown:
                primary("Record again", id: "recordAgain") { checkout.recordAgain() }
                secondary("Back to the ticket", id: "backToAmount") { checkout.backToEditing() }
            }
        }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityIdentifier(id)
    }
}

/// A big symbol, a title, a line of detail and an optional progress view.
private struct StatusBlock<Accessory: View>: View {
    let symbol: String
    var tint: Color = BusinessTheme.red
    let title: String
    let detail: String
    let id: String
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String, tint: Color = BusinessTheme.red, title: String, detail: String, id: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.id = id
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(id)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            accessory()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Test mode's stand-in for Apple's Tap to Pay screen: the owner picks what
/// the pretend card does. Nothing is read or charged.
struct SimulatedTapPanel: View {
    let terminal: SimulatedPaymentTerminal
    let amountCents: Int

    var body: some View {
        VStack(spacing: 20) {
            Text("Simulated Tap to Pay")
                .font(.headline)
            Text(Money.amount(amountCents))
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No card is read and nothing is charged. Pick what the test card does.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Approve test card") { terminal.choose(.approve) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("simulateApprove")
            HStack(spacing: 12) {
                Button("Decline test card") { terminal.choose(.decline) }
                    .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("simulateDecline")
                Button("Customer cancels") { terminal.choose(.customerCancels) }
                    .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("simulateCancel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulatedTapPanel")
    }
}

/// Today's card payments that went through, newest first, with the total: the ones taken in the
/// shop, and no-show and late cancellation fees charged to cards on file (labelled as such).
struct PaymentsTodayView: View {
    let checkout: CheckoutModel

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: Money.amount(checkout.todaysTotalCents))
                    .font(.headline)
                    .accessibilityIdentifier("paymentsTotal")
                if checkout.todaysFeesCents > 0 {
                    LabeledContent("No-show and late cancellation fees", value: Money.amount(checkout.todaysFeesCents))
                        .font(.subheadline)
                        .accessibilityIdentifier("paymentsFees")
                }
            } footer: {
                Text("Only payments that went through. Refunds and disputes are in the Stripe Dashboard.")
            }
            if let error = checkout.paymentsError {
                Section {
                    InlineMessage(text: error)
                }
            }
            Section("Today") {
                if checkout.todaysPayments.isEmpty {
                    Text(checkout.isLoadingPayments ? "Loading…" : "No card payments yet today.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(checkout.todaysPayments) { payment in
                        PaymentRow(payment: payment, checkout: checkout)
                    }
                }
            }
        }
        .navigationTitle("Card payments today")
        .refreshable { await checkout.loadPayments() }
    }
}

private struct PaymentRow: View {
    let payment: IzzyAPI.Payment
    let checkout: CheckoutModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let fee = payment.feeLabel {
                    Badge(text: fee, color: .purple)
                }
                Text(payment.listTitle)
                    .font(.body)
                Text(checkout.shopTime.time(payment.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.amount(payment.amountCents))
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .frame(minHeight: BusinessTheme.minimumTapSize)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(payment.kind.isFee ? "feePayment" : "cardPayment")
    }
}

/// "Email a receipt (optional)", once a card payment went through: Stripe emails the client a
/// receipt. The address is typed here only when the client asks for one, goes to Stripe, and isn't
/// kept in the app (it lives only on this screen).
struct ReceiptEmailOffer: View {
    let checkout: CheckoutModel
    /// Whether the email field has the keyboard (the screen's Done steps aside meanwhile).
    var focus: FocusState<Bool>.Binding
    /// The line under Send receipt: the page scrolls to it once the field has the keyboard, so the
    /// field, Send receipt and the line are all in view above the keyboard.
    static let endID = "receiptEmailEnd"
    @State private var showsField = false
    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch checkout.receiptEmailState {
            case .sent:
                Label("Receipt sent. Stripe is emailing it to the client.", systemImage: "envelope.badge.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("receiptSent")
            default:
                if showsField {
                    Text("Client's email")
                        .font(.headline)
                    TextField("name@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .focused(focus)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .accessibilityIdentifier("receiptEmailField")
                    if case .failed(let message) = checkout.receiptEmailState {
                        InlineMessage(text: message, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .accessibilityIdentifier("receiptError")
                    }
                    Button(action: send) {
                        HStack {
                            Text("Send receipt")
                            if checkout.receiptEmailState == .sending { ProgressView() }
                        }
                        .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checkout.receiptEmailState == .sending)
                    .accessibilityIdentifier("sendReceipt")
                    Text("Stripe emails the receipt. The app doesn't keep the address.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .id(Self.endID)
                } else {
                    Button {
                        showsField = true
                    } label: {
                        Label("Email a receipt (optional)", systemImage: "envelope")
                            .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("emailReceipt")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func send() {
        let address = email
        Task { await checkout.emailReceipt(to: address) }
    }
}
