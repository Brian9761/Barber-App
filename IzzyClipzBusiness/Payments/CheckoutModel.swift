import Foundation
import IzzyClipzKit
import Observation

/// Take payment, a checkout: the ticket (who it's for, who sold it, the services, products and
/// amounts, the total), how the client pays, and what happens then.
///
/// Cash and other ways (Squire, Zelle, Cash App…) are recorded as a sale right away
/// (`OwnerAPI.recordSale`), with an `Idempotency-Key` kept for the same sale, so Record again after
/// a lost answer never records it twice.
///
/// A card goes through Tap to Pay, with the ticket sent along so the server records the sale once
/// the payment goes through:
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
        /// The Tap to Pay screen is up, then (once the card is read) Stripe
        /// authorizes it: see `isProcessing`.
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
        /// Saving a cash or other sale.
        case recording(IzzyAPI.SaleMethod)
        /// The cash or other sale is saved.
        case recorded(SaleReceipt)
        /// The server turned the sale down (it says why): nothing was saved.
        case recordFailed(String)
        /// No answer came back: the sale may be saved. Record again (with the same key) finds out.
        case recordUnknown(String)

        var isInFlight: Bool {
            switch self {
            case .preparing, .creating, .collecting, .confirming, .recording: return true
            default: return false
            }
        }
    }

    /// Emailing the receipt of a card payment that went through (Song-Beverly: offered after the
    /// payment, optional, and the address is never kept).
    enum ReceiptEmailState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    struct Receipt: Equatable {
        let amountCents: Int
        let paymentIntentId: String?
        /// The simulated reader: no card was read at all.
        let isTestMode: Bool
        /// A real reader with Stripe's test keys: no real money moved, and
        /// Stripe doesn't email receipts.
        var stripeTestMode = false
        /// What Stripe shows as the payment's description.
        let title: String?
        /// The sale the server records with it (not for practice payments, which go nowhere).
        var sale: SaleReceipt?

        /// "Email a receipt (optional)" is offered: a real payment Stripe can email a receipt for.
        var offersReceiptEmail: Bool { paymentIntentId != nil && !stripeTestMode }
    }

    /// The PaymentIntent this checkout charges, kept across retries.
    struct ActivePayment: Equatable {
        let paymentIntentId: String?
        let clientSecret: String
        let request: IzzyAPI.NewPayment
        let isPractice: Bool
        /// Set when nobody knows whether the card went through.
        var needsCheck = false
        /// The ticket as it was charged, for the receipt (the one on screen may have changed since,
        /// while a payment waits to be checked).
        var ticket: CheckoutTicket?
    }

    // MARK: State

    /// The ticket on screen.
    var ticket: CheckoutTicket
    /// A note for a card payment: its description at Stripe, sent as typed instead of what was sold.
    var note = ""
    private(set) var phase: Phase = .editing
    /// "Email a receipt (optional)" after a card payment. The address itself is never kept.
    private(set) var receiptEmailState: ReceiptEmailState = .idle
    /// A problem with what was entered, shown above the button.
    var validationMessage: String?

    private(set) var stripe: IzzyAPI.StripeStatus?
    /// How the server takes card payments (`GET /api/owner/me`'s `connection`): with Stripe Connect,
    /// cards wait for the shop's own Stripe account.
    private(set) var connection: IzzyAPI.StripeConnectionSummary?
    private(set) var practiceRequested = false

    /// Today's successful payments, newest first.
    private(set) var todaysPayments: [IzzyAPI.Payment] = []
    private(set) var paymentsError: String?
    private(set) var isLoadingPayments = false
    /// Payments from an earlier run that turned out to have gone through,
    /// so the owner doesn't charge the customer again.
    var recoveryNotice: String?

    @ObservationIgnored private(set) var active: ActivePayment?
    @ObservationIgnored private var flowTask: Task<Void, Never>?
    /// Reloading today's payments after one went through. Separate from the
    /// payment itself, so the next payment can start while the list loads.
    @ObservationIgnored private var paymentsTask: Task<Void, Never>?
    /// Bumped by every load of today's payments. Loads can overlap (the
    /// reloads after two quick payments, pull to refresh), so a slow answer
    /// for an older load never replaces a newer one.
    @ObservationIgnored private var paymentsGeneration = 0
    /// Telling Stripe about PaymentIntents given up on, one after another and
    /// never while the reader is busy with a payment (it does one thing at a time).
    @ObservationIgnored private var abandoning: Task<Void, Never>?
    @ObservationIgnored private var isSyncingPending = false
    /// The cash or other sale last sent and its `Idempotency-Key`: recording the same sale again
    /// (after an answer that never came) sends the same key, so it's never saved twice. A changed
    /// ticket gets a new key, and so does the next sale once this one is saved.
    @ObservationIgnored private var saleAttempt: (retryKey: String, key: IzzyAPI.IdempotencyKey)?

    let terminal: any PaymentTerminal
    let practiceTerminal: SimulatedPaymentTerminal
    @ObservationIgnored private let api: any OwnerAPI
    let shopTime: ShopTime
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let pending: PendingPayments
    @ObservationIgnored private let usesSampleServer: Bool
    @ObservationIgnored private let deviceSupportsTapToPay: Bool
    /// The menu: the barbers, their services and prices.
    let catalog: Catalog
    /// Where the last barber chosen on this iPhone is kept (Sold by's default).
    @ObservationIgnored private let defaults: UserDefaults?
    /// Called after a payment for an appointment succeeded, with its ID.
    @ObservationIgnored var onPaid: ((String) -> Void)?
    /// Called after a sale was saved: cash or other, or a card payment that went through with its
    /// ticket (Today's sales and the schedule changed).
    @ObservationIgnored var onSaleRecorded: (() -> Void)?
    /// Called when a payment connected real Tap to Pay (the first time on
    /// this iPhone, that's its setup).
    @ObservationIgnored var onReaderConnected: (() -> Void)?
    /// Called when Tap to Pay on iPhone is tapped before the server said
    /// whether Stripe is set up, so the app checks again.
    @ObservationIgnored var onStatusNeeded: (() -> Void)?

    init(
        api: any OwnerAPI,
        shopTime: ShopTime,
        clock: @escaping () -> Date,
        terminal: any PaymentTerminal,
        practiceTerminal: SimulatedPaymentTerminal,
        pending: PendingPayments,
        usesSampleServer: Bool,
        deviceSupportsTapToPay: Bool,
        catalog: Catalog = .izzyClipz,
        defaults: UserDefaults? = nil
    ) {
        self.api = api
        self.shopTime = shopTime
        self.clock = clock
        self.terminal = terminal
        self.practiceTerminal = practiceTerminal
        self.pending = pending
        self.usesSampleServer = usesSampleServer
        self.deviceSupportsTapToPay = deviceSupportsTapToPay
        self.catalog = catalog
        self.defaults = defaults
        let last = defaults?.string(forKey: Self.lastBarberKey)
        ticket = CheckoutTicket(barberId: last.flatMap { catalog.barber(withID: $0) != nil ? $0 : nil })
    }

    var mode: Mode {
        if practiceRequested { return .practice(.chosen) }
        guard let stripe else { return .checking }
        guard stripe.configured else {
            // Stripe Connect: the shop's own account isn't taking card payments yet.
            if let connection, connection.mode == .connect, connection.status != .active {
                return .unavailable(.stripeNotConnected(connection.status))
            }
            return .unavailable(.stripeNotConfigured)
        }
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

    /// Stripe's status from `GET /api/owner/me`, and how the server takes card payments.
    func update(stripe: IzzyAPI.StripeStatus?, connection: IzzyAPI.StripeConnectionSummary? = nil) {
        self.stripe = stripe
        self.connection = connection
    }

    static let stillCheckingMessage = "Still checking whether card payments are set up. Try again in a moment."

    /// A check of Stripe's status with the server finished, so "Still
    /// checking…" is out of date: either a card on Take payment says what's
    /// wrong, or Tap to Pay on iPhone works.
    func statusCheckFinished() {
        if validationMessage == Self.stillCheckingMessage { validationMessage = nil }
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

    // MARK: The ticket

    /// Checking out an appointment (Schedule → appointment → Check out): its client, sold by its
    /// barber, with its service at its price. Ignored while a payment is running.
    @discardableResult
    func start(for appointment: IzzyAPI.Appointment) -> Bool {
        guard phase == .editing || isFinished else { return false }
        if isFinished { reset() }
        ticket = CheckoutTicket(appointment: appointment, catalog: catalog, shopTime: shopTime, now: clock())
        note = ""
        validationMessage = nil
        return true
    }

    /// Something extra for a client whose appointment is already paid (a product, a tip): a walk-in
    /// ticket with their name, sold by their barber, not tied to the appointment.
    @discardableResult
    func startExtra(for appointment: IzzyAPI.Appointment) -> Bool {
        guard phase == .editing || isFinished else { return false }
        if isFinished { reset() }
        ticket = CheckoutTicket(barberId: appointment.barberId)
        ticket.walkInName = appointment.customer.name
        note = ""
        validationMessage = nil
        return true
    }

    /// "Not for this appointment": the ticket stays, for a walk-in with the same name.
    func forgetAppointment() {
        guard phase == .editing else { return }
        ticket.forgetAppointment()
    }

    /// Sold by: the barber who gets credit, kept as the default for the next walk-in on this iPhone.
    func chooseBarber(_ id: String) {
        guard phase == .editing, catalog.barber(withID: id) != nil else { return }
        ticket.barberId = id
        defaults?.set(id, forKey: Self.lastBarberKey)
        if validationMessage == CheckoutTicket.noBarberMessage { validationMessage = nil }
    }

    static let lastBarberKey = "lastSoldByBarberId"

    /// The barber who gets credit, by name: "Izzy".
    var barberName: String? {
        ticket.barberId.flatMap { catalog.barber(withID: $0)?.name }
    }

    /// The total on screen: the ticket's.
    var amountCents: Int { ticket.totalCents }

    private var isFinished: Bool {
        switch phase {
        case .succeeded, .recorded: return true
        default: return false
        }
    }

    // MARK: Cash and other

    /// Records the ticket as a sale paid in cash or another way, after the owner confirmed it.
    func record(_ method: IzzyAPI.SaleMethod) {
        guard phase == .editing, method != .card else { return }
        validationMessage = nil
        if let problem = ticket.problem(for: method) {
            validationMessage = problem
            return
        }
        let sale = ticket.newSale(method: method)
        guard flowTask == nil else { return }
        phase = .recording(method)
        start { await self.save(sale) }
    }

    /// Record again after an error: the same sale with the same key.
    func recordAgain() {
        switch phase {
        case .recordFailed, .recordUnknown:
            guard flowTask == nil else { return }
            let sale = ticket.newSale(method: lastRecordedMethod ?? .cash)
            phase = .recording(sale.method)
            start { await self.save(sale) }
        default:
            break
        }
    }

    /// The method of the sale being recorded, for Record again.
    @ObservationIgnored private var lastRecordedMethod: IzzyAPI.SaleMethod?

    /// The key to send `sale` with: the last one if this is the same sale again.
    func saleKey(for sale: IzzyAPI.NewSale) -> IzzyAPI.IdempotencyKey {
        if let saleAttempt, saleAttempt.retryKey == sale.retryKey { return saleAttempt.key }
        let key = IzzyAPI.IdempotencyKey.generate()
        saleAttempt = (sale.retryKey, key)
        return key
    }

    private func save(_ sale: IzzyAPI.NewSale) async {
        lastRecordedMethod = sale.method
        phase = .recording(sale.method)
        let key = saleKey(for: sale)
        do {
            let saved = try await api.recordSale(sale, idempotencyKey: key)
            saleAttempt = nil
            if let barberId = sale.barberId { defaults?.set(barberId, forKey: Self.lastBarberKey) }
            phase = .recorded(SaleReceipt(sale: saved))
            onSaleRecorded?()
        } catch is CancellationError {
            phase = .recordUnknown(Self.saleUnknownMessage)
        } catch {
            if ScheduleStore.chargeOutcomeIsUnknown(error) {
                let reason: String
                if case .offline? = error as? APIError {
                    reason = "We couldn't reach the server."
                } else {
                    reason = ErrorText.message(for: error)
                }
                phase = .recordUnknown("\(reason) \(Self.saleUnknownMessage)")
            } else {
                // The server's own answer (a 400 or 409): nothing was saved, and a fixed ticket is a new sale.
                saleAttempt = nil
                phase = .recordFailed(ErrorText.message(for: error))
            }
        }
    }

    static let saleUnknownMessage = "We don't know yet if the sale was saved. Record again: the same sale is never saved twice. If you change the ticket first, check Today's sales so it isn't recorded twice."

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
        if let problem = ticket.problem(for: .card) {
            validationMessage = problem
            return
        }
        if case .unavailable(let issue) = mode {
            validationMessage = issue.message
            return
        }
        if case .checking = mode {
            validationMessage = Self.stillCheckingMessage
            // The last check may have failed (offline at launch): check again now.
            onStatusNeeded?()
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNote.count <= 200 else {
            validationMessage = "Keep the note to 200 characters or fewer."
            return
        }
        // Never the client's name in the description (it's kept at Stripe): what was sold and who
        // sold it, or the owner's own note, as typed.
        let request = IzzyAPI.NewPayment(
            amountCents: ticket.totalCents,
            description: trimmedNote.isEmpty ? ticket.paymentDescription(barberName: barberName) : trimmedNote,
            appointmentId: ticket.appointmentId,
            sale: ticket.newSale(method: .card)
        )
        let charged = ticket
        start { await self.run(request, ticket: charged) }
    }

    /// Tries the same PaymentIntent again (after a decline, a cancellation or
    /// an error).
    func retry() {
        guard let active, !active.needsCheck else { return }
        switch phase {
        case .declined, .cancelled, .failed, .notPaid:
            start { await self.run(active.request, ticket: active.ticket) }
        default:
            break
        }
    }

    /// "Try again" on an error screen: the same PaymentIntent when there is
    /// one, otherwise a fresh start with what's entered.
    func tryAgain() {
        if case .recordFailed = phase {
            recordAgain()
            return
        }
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

    /// The card was read: Stripe is authorizing it, or the server is checking
    /// it. The screen says Processing.
    var isProcessing: Bool {
        switch phase {
        case .confirming: return true
        case .collecting: return currentTerminal.state == .processing
        default: return false
        }
    }

    /// Whether Cancel can still stop the payment: while Tap to Pay gets ready
    /// or waits for the card, not once the card is read.
    var canCancel: Bool {
        switch phase {
        case .preparing: return true
        case .collecting: return !isProcessing
        default: return false
        }
    }

    /// Stops connecting or waiting for the card.
    func cancel() {
        guard canCancel else { return }
        currentTerminal.cancel()
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

    /// After a sale or payment (Done): a clean slate for the next client, sold by the last barber
    /// chosen on this iPhone.
    func reset() {
        guard !phase.isInFlight else { return }
        if let active, !active.needsCheck {
            discard(active)
        }
        let last = defaults?.string(forKey: Self.lastBarberKey)
        ticket = CheckoutTicket(barberId: last.flatMap { catalog.barber(withID: $0) != nil ? $0 : nil } ?? ticket.barberId)
        note = ""
        saleAttempt = nil
        receiptEmailState = .idle
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

    /// Waits for the running payment step (and the list it reloads), for tests.
    func waitUntilSettled() async {
        await flowTask?.value
        await paymentsTask?.value
    }

    private func run(_ request: IzzyAPI.NewPayment, ticket charged: CheckoutTicket?) async {
        let mode = self.mode
        let terminal = currentTerminal
        let isPractice: Bool
        switch mode {
        case .practice: isPractice = true
        case .live, .sampleServer: isPractice = false
        case .checking, .unavailable: phase = .editing; return
        }

        // Anything given up on earlier is settled with Stripe first.
        await abandoning?.value

        // 1. The reader. Already connected to this location, it's ready at
        // once; otherwise it connects (or moves to the shop's new location).
        if terminal.state != .ready { phase = .preparing }
        do {
            try await terminal.prepare(locationId: locationId ?? "practice")
        } catch {
            phase = failurePhase(for: error)
            return
        }
        if case .live = mode { onReaderConnected?() }

        // 2. The PaymentIntent: the one already made for exactly this, or a new one.
        let payment: ActivePayment
        if let active, active.request == request, active.isPractice == isPractice {
            payment = active
        } else {
            // Shows "Starting the payment" (no Cancel) while the old
            // PaymentIntent is let go: Cancel couldn't stop that wait.
            phase = .creating
            if let active {
                discard(active)
                await abandoning?.value
            }
            if isPractice {
                payment = ActivePayment(paymentIntentId: nil, clientSecret: "practice_\(UUID().uuidString)", request: request, isPractice: true, ticket: charged)
            } else {
                do {
                    let created = try await api.createPayment(request)
                    pending.add(created.paymentIntentId, at: clock())
                    payment = ActivePayment(
                        paymentIntentId: created.paymentIntentId, clientSecret: created.clientSecret, request: request, isPractice: false, ticket: charged
                    )
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
                title: payment.request.description
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
                var stripeTestMode = false
                if case .live(_, let testKeys) = mode { stripeTestMode = testKeys }
                let barberName = payment.request.sale?.barberId.flatMap { catalog.barber(withID: $0)?.name }
                receiptEmailState = .idle
                phase = .succeeded(Receipt(
                    amountCents: recorded.amountCents, paymentIntentId: recorded.id, isTestMode: mode.isTestMode,
                    stripeTestMode: stripeTestMode,
                    title: payment.request.description,
                    sale: payment.request.sale != nil ? payment.ticket.map { SaleReceipt(ticket: $0, method: .card, barberName: barberName ?? "") } : nil
                ))
                if let barberId = payment.request.sale?.barberId { defaults?.set(barberId, forKey: Self.lastBarberKey) }
                if let appointmentId = recorded.appointmentId ?? payment.request.appointmentId {
                    onPaid?(appointmentId)
                }
                if payment.request.sale != nil { onSaleRecorded?() }
                // Not awaited: the payment is done, and Tap to Pay must work
                // for the next customer even while the list is slow to load.
                paymentsTask = Task { await self.loadPayments() }
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
        let previous = abandoning
        abandoning = Task {
            await previous?.value
            await terminal.abandon(clientSecret: secret)
        }
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
        paymentsGeneration += 1
        let requested = paymentsGeneration
        isLoadingPayments = true
        defer { if requested == paymentsGeneration { isLoadingPayments = false } }
        do {
            let today = shopTime.day(containing: clock())
            let payments = try await api.payments(on: today)
            guard requested == paymentsGeneration else { return }
            // Only money that came in: PaymentIntents the customer never paid stay out.
            todaysPayments = payments.filter(\.isSucceeded).sorted { $0.createdAt > $1.createdAt }
            paymentsError = nil
        } catch is CancellationError {
            return
        } catch {
            guard requested == paymentsGeneration else { return }
            paymentsError = Self.message(for: error)
        }
    }

    var todaysTotalCents: Int {
        todaysPayments.reduce(0) { $0 + $1.amountCents }
    }

    /// The part of today's total that's no-show and late cancellation fees charged to cards on file.
    var todaysFeesCents: Int {
        todaysPayments.filter(\.kind.isFee).reduce(0) { $0 + $1.amountCents }
    }

    /// Asks the server about payments left unconfirmed by an earlier run (the
    /// app closed mid-payment, the network dropped).
    func syncPendingPayments() async {
        guard !pending.entries.isEmpty, !isSyncingPending else { return }
        isSyncingPending = true
        defer { isSyncingPending = false }
        let now = clock()
        var changed = false
        var recovered: [Int] = []
        // Oldest first, each looked at again just before it's checked: the
        // payment on screen, or one it just finished meanwhile, isn't from earlier.
        for (id, created) in pending.entries.sorted(by: { $0.value < $1.value }) {
            guard pending.entries[id] != nil, id != active?.paymentIntentId else { continue }
            do {
                let payment = try await api.completePayment(id: id)
                if payment.isSucceeded || payment.status == "canceled" {
                    pending.remove(id)
                    changed = changed || payment.isSucceeded
                    if payment.isSucceeded { recovered.append(payment.amountCents) }
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
        if !recovered.isEmpty {
            let amounts = recovered.map(Money.amount).joined(separator: ", ")
            recoveryNotice = recovered.count == 1
                ? "A \(amounts) card payment from earlier went through and is now recorded. Don't charge it again."
                : "\(recovered.count) card payments from earlier went through (\(amounts)) and are now recorded. Don't charge them again."
        }
        if changed { await loadPayments() }
    }

    // MARK: Email a receipt

    /// "Email a receipt (optional)" after a card payment went through: Stripe emails the client a
    /// receipt (`POST /api/owner/payments/:id/receipt`). The address goes to the server and on to
    /// Stripe only: it isn't kept here, or on the server.
    func emailReceipt(to email: String) async {
        guard case .succeeded(let receipt) = phase, receipt.offersReceiptEmail, let id = receipt.paymentIntentId else { return }
        guard receiptEmailState != .sending else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(address) else {
            receiptEmailState = .failed("Check the email address: it should look like name@example.com.")
            return
        }
        receiptEmailState = .sending
        do {
            _ = try await api.sendReceipt(paymentId: id, email: address)
            receiptEmailState = .sent
        } catch is CancellationError {
            receiptEmailState = .idle
        } catch {
            receiptEmailState = .failed(Self.message(for: error))
        }
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
