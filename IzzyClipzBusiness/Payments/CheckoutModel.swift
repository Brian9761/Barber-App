import Foundation
import IzzyClipzKit
import Observation

/// Take payment: the amount, the optional note and receipt email, and the
/// whole card flow.
///
/// 1. The server creates the PaymentIntent (`OwnerAPI.createPayment`), so the
///    amount can't change afterwards.
/// 2. The terminal takes the card (Tap to Pay on iPhone, or the simulated
///    reader in test mode).
/// 3. The app asks the server to confirm with Stripe
///    (`OwnerAPI.completePayment`). Only a "succeeded" answer shows Paid.
///
/// Double charges are designed out: one checkout uses one PaymentIntent for
/// every retry (a PaymentIntent can only succeed once), a new one is made only
/// when what's charged changes and the old one surely wasn't charged, and
/// when nobody knows whether a card went through, the app checks with the
/// server before anything else.
@MainActor
@Observable
final class CheckoutModel {
    // MARK: Modes

    enum PracticeReason: Equatable {
        /// The owner chose test mode.
        case chosen
        /// This iPhone can't do Tap to Pay (the Simulator, an older iPhone).
        case deviceUnsupported
    }

    /// How payments are taken right now.
    enum Mode: Equatable {
        /// Waiting for the server to say whether Stripe is set up.
        case checking
        /// Real Tap to Pay on iPhone. With Stripe's test keys no real money
        /// moves, but the real reader and Stripe are used.
        case live(locationId: String, stripeTestMode: Bool)
        /// The in-memory sample server with the simulated reader (UI tests,
        /// previews).
        case sampleServer(locationId: String)
        /// The simulated reader, and nothing is sent to the server.
        case practice(PracticeReason)
        /// Payments can't be taken; says why. Practice is offered.
        case unavailable(TerminalIssue)

        /// Whether the screen must say "Test mode — no real charge".
        var isTestMode: Bool {
            switch self {
            case .sampleServer, .practice: return true
            case .checking, .live, .unavailable: return false
            }
        }
    }

    // MARK: Phases

    enum Phase: Equatable {
        /// Entering the amount.
        case editing
        /// Connecting Tap to Pay; the terminal's state has the progress.
        case preparing
        /// Asking the server for a PaymentIntent.
        case creating
        /// The Tap to Pay screen is up.
        case collecting
        /// The card was read; the server is checking with Stripe.
        case confirming
        case succeeded(Receipt)
        case declined(String)
        case cancelled
        case failed(String)
        /// The card may have been charged: check before anything else.
        case outcomeUnknown(String)
        /// The server says the payment isn't complete: no money was taken.
        case notPaid(String)

        var isInFlight: Bool {
            switch self {
            case .preparing, .creating, .collecting, .confirming: return true
            default: return false
            }
        }
    }

    struct Receipt: Equatable {
        let amountCents: Int
        let paymentIntentId: String?
        let isTestMode: Bool
        let receiptEmail: String?
        let title: String?
    }

    /// The appointment a payment is for.
    struct AppointmentContext: Equatable {
        let id: String
        /// "Haircut with Izzy for Marcus Sample".
        let title: String
        /// The catalog's fixed price, when there is one.
        let suggestedCents: Int?
        /// "$35", "From $80".
        let priceLabel: String
        let alreadyPaidCents: Int?
    }

    /// The PaymentIntent this checkout charges, kept across retries.
    struct ActivePayment: Equatable {
        let paymentIntentId: String?
        let clientSecret: String
        let request: IzzyAPI.NewPayment
        let isPractice: Bool
        /// Set when nobody knows whether the card went through.
        var needsCheck = false
    }

    // MARK: State

    var entry = AmountEntry()
    var note = ""
    var receiptEmail = ""
    private(set) var appointment: AppointmentContext?
    private(set) var phase: Phase = .editing
    /// A problem with what was entered, shown above the button.
    var validationMessage: String?

    private(set) var stripe: IzzyAPI.StripeStatus?
    private(set) var practiceRequested = false

    /// Today's successful payments, newest first.
    private(set) var todaysPayments: [IzzyAPI.Payment] = []
    private(set) var paymentsError: String?
    private(set) var isLoadingPayments = false

    @ObservationIgnored private(set) var active: ActivePayment?
    @ObservationIgnored private var flowTask: Task<Void, Never>?

    let terminal: any PaymentTerminal
    let practiceTerminal: SimulatedPaymentTerminal
    @ObservationIgnored private let api: any OwnerAPI
    let shopTime: ShopTime
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let pending: PendingPayments
    @ObservationIgnored private let usesSampleServer: Bool
    @ObservationIgnored private let deviceSupportsTapToPay: Bool
    /// Called after a payment for an appointment succeeded, with its ID.
    @ObservationIgnored var onPaid: ((String) -> Void)?

    init(
        api: any OwnerAPI,
        shopTime: ShopTime,
        clock: @escaping () -> Date,
        terminal: any PaymentTerminal,
        practiceTerminal: SimulatedPaymentTerminal,
        pending: PendingPayments,
        usesSampleServer: Bool,
        deviceSupportsTapToPay: Bool
    ) {
        self.api = api
        self.shopTime = shopTime
        self.clock = clock
        self.terminal = terminal
        self.practiceTerminal = practiceTerminal
        self.pending = pending
        self.usesSampleServer = usesSampleServer
        self.deviceSupportsTapToPay = deviceSupportsTapToPay
    }

    var mode: Mode {
        if practiceRequested { return .practice(.chosen) }
        guard let stripe else { return .checking }
        guard stripe.configured else { return .unavailable(.stripeNotConfigured) }
        guard let location = stripe.locationId, !location.isEmpty else { return .unavailable(.locationMissing) }
        if usesSampleServer { return .sampleServer(locationId: location) }
        guard deviceSupportsTapToPay else { return .practice(.deviceUnsupported) }
        return .live(locationId: location, stripeTestMode: stripe.mode == .test)
    }

    /// The reader the current mode uses.
    var currentTerminal: any PaymentTerminal {
        if case .practice = mode { return practiceTerminal }
        return terminal
    }

    /// The Stripe Terminal location to connect to, when payments are real.
    var locationId: String? {
        switch mode {
        case .live(let locationId, _), .sampleServer(let locationId): return locationId
        default: return nil
        }
    }

    /// Stripe's status from `GET /api/owner/me`.
    func update(stripe: IzzyAPI.StripeStatus?) {
        self.stripe = stripe
    }

    /// Switches to the simulated reader: nothing is sent to the server.
    func startPractice() {
        guard !phase.isInFlight else { return }
        if let active, !active.isPractice, !active.needsCheck {
            discard(active)
        }
        practiceRequested = true
        validationMessage = nil
    }

    func stopPractice() {
        guard !phase.isInFlight else { return }
        if let active, active.isPractice { self.active = nil }
        practiceRequested = false
    }

    /// Connects Tap to Pay ahead of time (at sign in, and whenever the app
    /// comes back to the foreground), as Apple asks, so the first payment
    /// doesn't wait.
    func warmUp() async {
        guard !phase.isInFlight, let locationId, !currentTerminal.state.isBusy else { return }
        if currentTerminal.state == .ready { return }
        try? await currentTerminal.prepare(locationId: locationId)
    }

    // MARK: Prefilling

    /// Starts a payment for an appointment: its fixed price is filled in (the
    /// owner can change it). Ignored while a payment is running.
    @discardableResult
    func prefill(_ context: AppointmentContext) -> Bool {
        guard phase == .editing || isFinished else { return false }
        if isFinished { reset() }
        appointment = context
        entry = AmountEntry(cents: context.suggestedCents ?? 0)
        validationMessage = nil
        return true
    }

    func clearAppointment() {
        guard phase == .editing else { return }
        appointment = nil
    }

    private var isFinished: Bool {
        if case .succeeded = phase { return true }
        return false
    }

    // MARK: Charging

    /// The Tap to Pay on iPhone button.
    func charge() {
        guard phase == .editing else { return }
        validationMessage = nil
        if let active, active.needsCheck {
            // The last card may have gone through: settle that first.
            phase = .outcomeUnknown("We still don't know if the last card was charged. Check it before taking another payment.")
            return
        }
        guard entry.isChargeable else {
            validationMessage = Money.allowedRangeText
            return
        }
        let email = receiptEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty, !Self.looksLikeEmail(email) {
            validationMessage = "Check the receipt email address, or leave it empty."
            return
        }
        if case .unavailable(let issue) = mode {
            validationMessage = issue.message
            return
        }
        if case .checking = mode {
            validationMessage = "Still checking whether card payments are set up. Try again in a moment."
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = IzzyAPI.NewPayment(
            amountCents: entry.cents,
            description: trimmedNote.isEmpty ? appointment?.title : trimmedNote,
            appointmentId: appointment?.id,
            receiptEmail: email.isEmpty ? nil : email
        )
        start { await self.run(request) }
    }

    /// Tries the same PaymentIntent again (after a decline, a cancellation or
    /// an error).
    func retry() {
        guard let active, !active.needsCheck else { return }
        switch phase {
        case .declined, .cancelled, .failed, .notPaid:
            start { await self.run(active.request) }
        default:
            break
        }
    }

    /// "Try again" on an error screen: the same PaymentIntent when there is
    /// one, otherwise a fresh start with what's entered.
    func tryAgain() {
        if let active, !active.needsCheck {
            retry()
        } else if active == nil {
            switch phase {
            case .failed, .cancelled, .declined, .notPaid:
                phase = .editing
                charge()
            default:
                break
            }
        }
    }

    /// Asks the server again whether the last payment went through.
    func checkAgain() {
        guard let active else { return }
        switch phase {
        case .outcomeUnknown, .notPaid, .failed:
            start { await self.confirm(active) }
        default:
            break
        }
    }

    /// Stops connecting or waiting for the card.
    func cancel() {
        switch phase {
        case .preparing, .collecting:
            currentTerminal.cancel()
        default:
            break
        }
    }

    /// Back to the amount after a decline, cancellation or error. The same
    /// PaymentIntent is reused if the owner charges the same thing again.
    func backToEditing() {
        guard !phase.isInFlight else { return }
        if isFinished {
            reset()
        } else {
            phase = .editing
        }
    }

    /// After a successful payment: a clean slate for the next customer.
    func reset() {
        guard !phase.isInFlight else { return }
        if let active, !active.needsCheck {
            discard(active)
        }
        entry = AmountEntry()
        note = ""
        receiptEmail = ""
        appointment = nil
        validationMessage = nil
        phase = .editing
    }

    private func start(_ work: @escaping @MainActor () async -> Void) {
        guard flowTask == nil else { return }
        flowTask = Task {
            await work()
            self.flowTask = nil
        }
    }

    /// Waits for the running payment step, for tests.
    func waitUntilSettled() async {
        await flowTask?.value
    }

    private func run(_ request: IzzyAPI.NewPayment) async {
        let mode = self.mode
        let terminal = currentTerminal
        let isPractice: Bool
        switch mode {
        case .practice: isPractice = true
        case .live, .sampleServer: isPractice = false
        case .checking, .unavailable: phase = .editing; return
        }

        // 1. The reader. Practice and the simulated reader connect instantly.
        if terminal.state != .ready {
            phase = .preparing
            do {
                try await terminal.prepare(locationId: locationId ?? "practice")
            } catch {
                phase = failurePhase(for: error)
                return
            }
        }

        // 2. The PaymentIntent: the one already made for exactly this, or a new one.
        let payment: ActivePayment
        if let active, active.request == request, active.isPractice == isPractice {
            payment = active
        } else {
            if let active { discard(active) }
            phase = .creating
            if isPractice {
                payment = ActivePayment(paymentIntentId: nil, clientSecret: "practice_\(UUID().uuidString)", request: request, isPractice: true)
            } else {
                do {
                    let created = try await api.createPayment(request)
                    pending.add(created.paymentIntentId, at: clock())
                    payment = ActivePayment(paymentIntentId: created.paymentIntentId, clientSecret: created.clientSecret, request: request, isPractice: false)
                } catch {
                    phase = .failed(Self.message(for: error))
                    return
                }
            }
            active = payment
        }

        // 3. The card.
        phase = .collecting
        do {
            _ = try await terminal.collect(amountCents: request.amountCents, clientSecret: payment.clientSecret)
        } catch let error as TerminalError {
            switch error {
            case .cancelled:
                phase = .cancelled
            case .declined(let message):
                phase = .declined(message)
            case .outcomeUnknown:
                active?.needsCheck = !payment.isPractice
                phase = payment.isPractice ? .failed(error.message) : .outcomeUnknown(error.message)
            case .mismatch(let message):
                // The PaymentIntent can't be used: forget it (it wasn't charged).
                if let active { discard(active) }
                phase = .failed(message)
            case .unavailable, .failed:
                phase = .failed(error.message)
            }
            return
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }

        // 4. The server checks with Stripe.
        await confirm(payment)
    }

    private func confirm(_ payment: ActivePayment) async {
        if payment.isPractice {
            active = nil
            phase = .succeeded(Receipt(
                amountCents: payment.request.amountCents, paymentIntentId: nil, isTestMode: true,
                receiptEmail: nil, title: payment.request.description
            ))
            return
        }
        guard let paymentIntentId = payment.paymentIntentId else { return }
        phase = .confirming
        do {
            let recorded = try await api.completePayment(id: paymentIntentId)
            if recorded.isSucceeded {
                pending.remove(paymentIntentId)
                active = nil
                phase = .succeeded(Receipt(
                    amountCents: recorded.amountCents, paymentIntentId: recorded.id, isTestMode: mode.isTestMode,
                    receiptEmail: payment.request.receiptEmail, title: payment.request.description
                ))
                if let appointmentId = recorded.appointmentId ?? payment.request.appointmentId {
                    onPaid?(appointmentId)
                }
                await loadPayments()
            } else if recorded.status == "processing" {
                active?.needsCheck = true
                phase = .outcomeUnknown("Stripe is still processing this payment. Check again in a moment before taking another payment.")
            } else if recorded.status == "canceled" {
                pending.remove(paymentIntentId)
                active = nil
                phase = .notPaid("This payment was cancelled in Stripe, so no money was taken. Start a new payment.")
            } else {
                active?.needsCheck = false
                phase = .notPaid("Stripe says this payment isn't complete, so no money was taken. Try the card again.")
            }
        } catch {
            active?.needsCheck = true
            phase = .outcomeUnknown("The card was read, but the server couldn't confirm the payment: \(Self.message(for: error)) Check again before taking another payment.")
        }
    }

    /// Forgets a PaymentIntent that surely wasn't charged, and tells Stripe.
    private func discard(_ payment: ActivePayment) {
        if active == payment { active = nil }
        guard !payment.isPractice else { return }
        if let id = payment.paymentIntentId { pending.remove(id) }
        let terminal = self.terminal
        let secret = payment.clientSecret
        Task { await terminal.abandon(clientSecret: secret) }
    }

    private func failurePhase(for error: Error) -> Phase {
        if let terminalError = error as? TerminalError {
            if terminalError == .cancelled { return .cancelled }
            return .failed(terminalError.message)
        }
        return .failed(Self.message(for: error))
    }

    // MARK: Today's payments

    func loadPayments() async {
        isLoadingPayments = true
        defer { isLoadingPayments = false }
        do {
            let today = shopTime.day(containing: clock())
            let payments = try await api.payments(on: today)
            // Only money that came in: PaymentIntents the customer never paid stay out.
            todaysPayments = payments.filter(\.isSucceeded).sorted { $0.createdAt > $1.createdAt }
            paymentsError = nil
        } catch is CancellationError {
            return
        } catch {
            paymentsError = Self.message(for: error)
        }
    }

    var todaysTotalCents: Int {
        todaysPayments.reduce(0) { $0 + $1.amountCents }
    }

    /// Asks the server about payments left unconfirmed by an earlier run (the
    /// app closed mid-payment, the network dropped).
    func syncPendingPayments() async {
        guard !pending.entries.isEmpty else { return }
        let now = clock()
        var changed = false
        for (id, created) in pending.entries where id != active?.paymentIntentId {
            do {
                let payment = try await api.completePayment(id: id)
                if payment.isSucceeded || payment.status == "canceled" {
                    pending.remove(id)
                    changed = changed || payment.isSucceeded
                    if payment.isSucceeded, let appointmentId = payment.appointmentId { onPaid?(appointmentId) }
                } else if now.timeIntervalSince(created) > PendingPayments.maximumAge {
                    pending.remove(id)
                }
            } catch let error as APIError where error.code == IzzyAPI.ErrorCode.notFound {
                pending.remove(id)
            } catch {
                // Offline or Stripe busy: try again next time.
            }
        }
        if changed { await loadPayments() }
    }

    // MARK: Helpers

    static func message(for error: Error) -> String {
        ErrorText.message(for: error)
    }

    /// A light check that catches typos; the server checks properly.
    static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !text.contains(where: \.isWhitespace)
        else { return false }
        return true
    }
}

extension CheckoutModel.AppointmentContext {
    /// The context for an appointment: its fixed catalog price is suggested;
    /// "from" prices and included services aren't, since the final amount
    /// depends on the work.
    init(appointment: IzzyAPI.Appointment, catalog: Catalog) {
        let offering = catalog.offering(withID: appointment.offeringId)
        let suggested: Int?
        if let price = offering?.price, price.kind == .fixed, price.cents > 0 {
            suggested = price.cents
        } else {
            suggested = nil
        }
        self.init(
            id: appointment.id,
            title: "\(appointment.serviceName) with \(appointment.barberName) for \(appointment.customer.name)",
            suggestedCents: suggested,
            priceLabel: offering?.price.label ?? appointment.priceLabel,
            alreadyPaidCents: appointment.payment.status == .paid ? appointment.payment.amountCents : nil
        )
    }
}
