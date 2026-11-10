import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Take payment: the server creates the PaymentIntent, the terminal takes the
/// card, the server confirms. Only "succeeded" is paid, retries reuse the
/// same PaymentIntent, and an unknown outcome is checked before anything else.
@MainActor
final class CheckoutModelTests: XCTestCase {
    private var harness: Harness!
    private var api: ScriptedAPI!
    private var terminal: SimulatedPaymentTerminal!
    private var practice: SimulatedPaymentTerminal!
    private var pending: PendingPayments!
    private var paidAppointments: [String] = []

    override func setUp() async throws {
        harness = Harness()
        api = ScriptedAPI(base: harness.api)
        terminal = SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .zero)
        let server = harness.server
        terminal.onApproved = { server.cardApproved(clientSecret: $0) }
        practice = SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .zero)
        pending = PendingPayments(defaults: makeDefaults())
        paidAppointments = []
    }

    private func makeCheckout(stripe: IzzyAPI.StripeStatus? = .init(configured: true, mode: .test, locationId: "tml_sample"), sampleServer: Bool = true, deviceSupported: Bool = true) -> CheckoutModel {
        let checkout = CheckoutModel(
            api: api, shopTime: TestClock.shopTime, clock: { TestClock.now },
            terminal: terminal, practiceTerminal: practice, pending: pending,
            usesSampleServer: sampleServer, deviceSupportsTapToPay: deviceSupported
        )
        checkout.update(stripe: stripe)
        checkout.onPaid = { [weak self] id in self?.paidAppointments.append(id) }
        return checkout
    }

    private func charge(_ checkout: CheckoutModel, cents: Int) async {
        checkout.entry = AmountEntry(cents: cents)
        checkout.charge()
        await checkout.waitUntilSettled()
    }

    // MARK: Happy path

    func testHappyPathMarksTheAppointmentPaidOnlyAfterTheServerSaysSucceeded() async throws {
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        let checkout = makeCheckout()
        XCTAssertTrue(checkout.prefill(.init(appointment: andre, catalog: .izzyClipz)))
        XCTAssertEqual(checkout.entry.cents, 5500, "Izzy's Haircut & Beard is a fixed $55")
        checkout.charge()
        await checkout.waitUntilSettled()

        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 5500)
        XCTAssertTrue(receipt.isTestMode, "The simulated reader is always test mode")
        XCTAssertEqual(api.createdPayments, 1)
        XCTAssertNil(harness.server.payments.last?.receiptEmail, "No email goes with the payment: a receipt is offered once it went through")
        XCTAssertEqual(harness.appointment(named: "Andre Sample")?.payment.status, .paid)
        XCTAssertEqual(harness.appointment(named: "Andre Sample")?.payment.amountCents, 5500)
        XCTAssertEqual(paidAppointments, [andre.id])
        XCTAssertTrue(checkout.todaysPayments.contains { $0.amountCents == 5500 })
        XCTAssertTrue(pending.entries.isEmpty, "A confirmed payment is no longer pending")
        XCTAssertNil(checkout.active)

        checkout.reset()
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertEqual(checkout.entry.cents, 0)
        XCTAssertNil(checkout.appointment)
        XCTAssertEqual(checkout.receiptEmail, "")
    }

    func testTheRequestCarriesTheAmountNoteAndAppointment() async throws {
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        var sent: IzzyAPI.NewPayment?
        api.createPaymentHandler = { [api] request in
            sent = request
            return try await api!.base.createPayment(request)
        }
        let checkout = makeCheckout()
        checkout.prefill(.init(appointment: andre, catalog: .izzyClipz))
        checkout.entry = AmountEntry(cents: 6000)
        checkout.note = "  Plus a tip  "
        checkout.charge()
        await checkout.waitUntilSettled()
        XCTAssertEqual(sent?.amountCents, 6000)
        XCTAssertEqual(sent?.appointmentId, andre.id)
        XCTAssertEqual(sent?.description, "Plus a tip")
        XCTAssertNil(sent?.receiptEmail)
    }

    // MARK: Only "succeeded" is paid

    func testProcessingIsNotPaidAndBlocksANewChargeUntilChecked() async throws {
        harness.server.options.completeStatusOverride = "processing"
        let checkout = makeCheckout()
        await charge(checkout, cents: 2500)
        guard case .outcomeUnknown = checkout.phase else { return XCTFail("Expected a check, got \(checkout.phase)") }
        XCTAssertEqual(checkout.active?.needsCheck, true)
        XCTAssertEqual(pending.entries.count, 1, "Kept to check again later")
        XCTAssertTrue(paidAppointments.isEmpty)

        // Back to the amount and a second tap: no new PaymentIntent while the first is unknown.
        checkout.backToEditing()
        checkout.entry = AmountEntry(cents: 9900)
        checkout.charge()
        await checkout.waitUntilSettled()
        guard case .outcomeUnknown = checkout.phase else { return XCTFail("A new charge started before the last one was checked") }
        XCTAssertEqual(api.createdPayments, 1)

        // Stripe finishes: checking again shows it paid.
        harness.server.options.completeStatusOverride = nil
        checkout.checkAgain()
        await checkout.waitUntilSettled()
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 2500)
        XCTAssertTrue(pending.entries.isEmpty)
    }

    func testRequiresPaymentMethodIsNotPaidAndRetriesTheSamePaymentIntent() async {
        harness.server.options.completeStatusOverride = "requires_payment_method"
        let checkout = makeCheckout()
        await charge(checkout, cents: 4000)
        guard case .notPaid = checkout.phase else { return XCTFail("Expected not paid, got \(checkout.phase)") }
        XCTAssertTrue(checkout.todaysPayments.allSatisfy { $0.amountCents != 4000 })

        harness.server.options.completeStatusOverride = nil
        checkout.tryAgain()
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(api.createdPayments, 1, "The retry reused the PaymentIntent")
        XCTAssertEqual(Set(terminal.collectedSecrets).count, 1)
        XCTAssertEqual(terminal.collectedSecrets.count, 2)
    }

    func testAServerErrorAfterTheCardIsReadIsAnUnknownOutcome() async {
        var calls = 0
        api.completeHandler = { [api] id in
            calls += 1
            if calls == 1 { throw APIError.offline }
            return try await api!.base.completePayment(id: id)
        }
        let checkout = makeCheckout()
        await charge(checkout, cents: 3000)
        guard case .outcomeUnknown(let message) = checkout.phase else { return XCTFail("Expected a check, got \(checkout.phase)") }
        XCTAssertTrue(message.contains("couldn't confirm"))
        checkout.checkAgain()
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(api.createdPayments, 1)
    }

    func testCanceledInStripeStartsOver() async {
        harness.server.options.completeStatusOverride = "canceled"
        let checkout = makeCheckout()
        await charge(checkout, cents: 3000)
        guard case .notPaid = checkout.phase else { return XCTFail("Expected not paid, got \(checkout.phase)") }
        XCTAssertNil(checkout.active, "A cancelled PaymentIntent is never reused")
        XCTAssertTrue(pending.entries.isEmpty)
    }

    // MARK: Declined and cancelled

    func testDeclinedThenApprovedUsesOnePaymentIntent() async {
        terminal.automaticOutcome = .decline
        let checkout = makeCheckout()
        await charge(checkout, cents: 1250)
        guard case .declined = checkout.phase else { return XCTFail("Expected declined, got \(checkout.phase)") }
        XCTAssertNil(harness.server.payments.first { $0.payment.amountCents == 1250 && $0.payment.isSucceeded })

        terminal.automaticOutcome = .approve
        checkout.tryAgain()
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(api.createdPayments, 1)
    }

    func testCancelledGoesBackAndTheSameAmountReusesThePaymentIntent() async {
        terminal.automaticOutcome = .customerCancels
        let checkout = makeCheckout()
        await charge(checkout, cents: 2000)
        XCTAssertEqual(checkout.phase, .cancelled)
        checkout.backToEditing()
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertEqual(checkout.entry.cents, 2000, "The amount stays")

        terminal.automaticOutcome = .approve
        checkout.charge()
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(api.createdPayments, 1, "Same amount, same PaymentIntent")
    }

    func testChangingTheAmountAfterADeclineMakesANewPaymentIntentAndForgetsTheOld() async {
        terminal.automaticOutcome = .decline
        let checkout = makeCheckout()
        await charge(checkout, cents: 2000)
        let first = checkout.active?.paymentIntentId
        XCTAssertNotNil(first)
        checkout.backToEditing()

        terminal.automaticOutcome = .approve
        await charge(checkout, cents: 1800)
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 1800)
        XCTAssertEqual(api.createdPayments, 2)
        XCTAssertNotEqual(receipt.paymentIntentId, first)
        XCTAssertNil(pending.entries[first ?? ""], "The declined PaymentIntent isn't pending any more")
    }

    func testTwoQuickTapsStartOnePayment() async {
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 3500)
        checkout.charge()
        checkout.charge()
        checkout.charge()
        await checkout.waitUntilSettled()
        XCTAssertEqual(api.createdPayments, 1)
    }

    func testTheNextPaymentStartsWhileTodaysPaymentsAreStillLoading() async {
        // A slow shop connection: the payments list takes a while after each payment.
        var listIsSlow = true
        api.paymentsHandler = { @MainActor [api] day in
            while listIsSlow { try await Task.sleep(for: .milliseconds(10)) }
            return try await api!.base.payments(on: day)
        }
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 3500)
        checkout.charge()
        let paid = await eventually { if case .succeeded = checkout.phase { return true } else { return false } }
        XCTAssertTrue(paid, "Got \(checkout.phase)")
        let loading = await eventually { checkout.isLoadingPayments }
        XCTAssertTrue(loading, "The list is still loading")
        checkout.reset()

        // The next customer: Tap to Pay on iPhone starts their payment straight away.
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let started = await eventually(timeout: 2) { checkout.phase != .editing }
        XCTAssertTrue(started, "Tap to Pay on iPhone did nothing while the list was loading")
        listIsSlow = false
        await checkout.waitUntilSettled()
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 2000)
        XCTAssertEqual(api.createdPayments, 2)
        let loaded = await eventually { checkout.todaysPayments.contains { $0.amountCents == 2000 } }
        XCTAssertTrue(loaded, "The list still shows the new payment once it loads")
    }

    func testALateListFromBeforeTheLastPaymentDoesntReplaceTheNewerOne() async {
        await takeTwoPaymentsWhileTheFirstReloadAnswersLast { earlier in earlier }
    }

    func testALateListThatFailsDoesntPutAnErrorOverTheNewerOne() async {
        await takeTwoPaymentsWhileTheFirstReloadAnswersLast { _ in throw APIError.offline }
    }

    /// Takes $35, then $20. The list reload after the $35 reads the server
    /// straight away but answers (with `lateAnswer`) only after the reload
    /// after the $20 is done, as when the Wi-Fi drops and the phone moves to
    /// cellular. That late answer is out of date: the list keeps both payments.
    private func takeTwoPaymentsWhileTheFirstReloadAnswersLast(
        _ lateAnswer: @escaping ([IzzyAPI.Payment]) throws -> [IzzyAPI.Payment]
    ) async {
        var reloads = 0
        var releaseFirst = false
        var firstAnswered = false
        api.paymentsHandler = { @MainActor [api] day in
            reloads += 1
            let reload = reloads
            let payments = try await api!.base.payments(on: day)
            guard reload == 1 else { return payments }
            while !releaseFirst { try await Task.sleep(for: .milliseconds(10)) }
            defer { firstAnswered = true }
            return try lateAnswer(payments)
        }
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 3500)
        checkout.charge()
        let firstReload = await eventually { reloads == 1 }
        XCTAssertTrue(firstReload, "Got \(checkout.phase)")
        checkout.reset()

        await charge(checkout, cents: 2000)
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(reloads, 2)
        XCTAssertTrue(checkout.todaysPayments.contains { $0.amountCents == 3500 })
        XCTAssertTrue(checkout.todaysPayments.contains { $0.amountCents == 2000 })
        XCTAssertFalse(checkout.isLoadingPayments, "The newest list is in")

        releaseFirst = true
        let answered = await eventually { firstAnswered }
        XCTAssertTrue(answered)
        let replaced = await eventually(timeout: 0.3) {
            !checkout.todaysPayments.contains { $0.amountCents == 2000 } || checkout.paymentsError != nil
        }
        XCTAssertFalse(replaced, "The late answer replaced the newer list: \(checkout.todaysPayments.map(\.amountCents)), \(checkout.paymentsError ?? "no error")")
        XCTAssertTrue(checkout.todaysPayments.contains { $0.amountCents == 3500 })
        XCTAssertNil(checkout.paymentsError)
        XCTAssertFalse(checkout.isLoadingPayments)
    }

    // MARK: Not configured

    func testStripeNotConfiguredExplainsAndOffersPractice() async {
        let checkout = makeCheckout(stripe: .init(configured: false))
        XCTAssertEqual(checkout.mode, .unavailable(.stripeNotConfigured))
        await charge(checkout, cents: 2500)
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertEqual(checkout.validationMessage, TerminalIssue.stripeNotConfigured.message)
        XCTAssertEqual(api.createdPayments, 0)

        checkout.startPractice()
        XCTAssertEqual(checkout.mode, .practice(.chosen))
        XCTAssertTrue(checkout.mode.isTestMode)
        checkout.charge()
        await checkout.waitUntilSettled()
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected a test payment, got \(checkout.phase)") }
        XCTAssertTrue(receipt.isTestMode)
        XCTAssertEqual(api.createdPayments, 0, "Practice never reaches the server")
        XCTAssertFalse(harness.server.calls.contains("completePayment"))
        XCTAssertEqual(practice.collectedSecrets.count, 1)
        XCTAssertTrue(terminal.collectedSecrets.isEmpty)
    }

    func testAMissingLocationIsExplained() {
        let checkout = makeCheckout(stripe: .init(configured: true, mode: .live, locationId: nil))
        XCTAssertEqual(checkout.mode, .unavailable(.locationMissing))
        XCTAssertNil(checkout.locationId)
    }

    func testTheServerSayingNotConfiguredIsAPlainFailure() async {
        harness.server.options.stripeConfigured = false
        let checkout = makeCheckout()
        await charge(checkout, cents: 2500)
        XCTAssertEqual(checkout.phase, .failed(APIError.notConfigured(APIError.Feature.stripe).userMessage))
    }

    func testAnUnsupportedIPhoneIsPracticeOnlyAndLiveUsesTapToPay() {
        let live = IzzyAPI.StripeStatus(configured: true, mode: .live, locationId: "tml_1")
        XCTAssertEqual(makeCheckout(stripe: live, sampleServer: false, deviceSupported: false).mode, .practice(.deviceUnsupported))
        let real = makeCheckout(stripe: live, sampleServer: false, deviceSupported: true)
        XCTAssertEqual(real.mode, .live(locationId: "tml_1", stripeTestMode: false))
        XCTAssertFalse(real.mode.isTestMode)
        XCTAssertEqual(real.locationId, "tml_1")
        XCTAssertEqual(makeCheckout(stripe: nil).mode, .checking)
    }

    func testRealTapToPayWithStripeTestKeysSaysNoRealMoneyMoved() async {
        // The simulated reader stands in for Tap to Pay; the mode is the real one.
        let checkout = makeCheckout(stripe: .init(configured: true, mode: .test, locationId: "tml_1"), sampleServer: false, deviceSupported: true)
        var connected = 0
        checkout.onReaderConnected = { connected += 1 }
        XCTAssertEqual(checkout.mode, .live(locationId: "tml_1", stripeTestMode: true))
        await charge(checkout, cents: 3500)
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertFalse(receipt.isTestMode)
        XCTAssertTrue(receipt.stripeTestMode)
        XCTAssertEqual(connected, 1, "A payment that connects Tap to Pay counts as setting it up")
    }

    func testLiveKeysAreRealMoney() async {
        let checkout = makeCheckout(stripe: .init(configured: true, mode: .live, locationId: "tml_1"), sampleServer: false, deviceSupported: true)
        await charge(checkout, cents: 3500)
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertFalse(receipt.isTestMode)
        XCTAssertFalse(receipt.stripeTestMode)
    }

    func testCancelWhileTapToPayGetsReady() async {
        terminal = SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .milliseconds(200))
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let preparing = await eventually { checkout.phase == .preparing }
        XCTAssertTrue(preparing)
        checkout.cancel()
        await checkout.waitUntilSettled()
        XCTAssertEqual(checkout.phase, .cancelled)
        XCTAssertEqual(api.createdPayments, 0, "Nothing was created before the reader was ready")
    }

    func testCancelBeforeTheCardIsReadStopsThePayment() async {
        // The reader takes a moment before the card is read (Stripe looks the
        // payment up, then the customer taps): Cancel works all that time.
        terminal.stepDelay = .milliseconds(300)
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let collecting = await eventually { checkout.phase == .collecting }
        XCTAssertTrue(collecting, "Got \(checkout.phase)")
        checkout.cancel()
        await checkout.waitUntilSettled()
        XCTAssertEqual(checkout.phase, .cancelled, "Cancel stopped the payment")
        XCTAssertFalse(harness.server.payments.contains { $0.payment.isSucceeded && $0.payment.amountCents == 2000 }, "Nothing was charged")

        // Trying again uses the same PaymentIntent and goes through.
        checkout.tryAgain()
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(api.createdPayments, 1)
    }

    // MARK: Entry

    func testAmountsOutsideTheServersRangeAreExplained() async {
        let checkout = makeCheckout()
        await charge(checkout, cents: 49)
        XCTAssertEqual(checkout.validationMessage, Money.allowedRangeText)
        await charge(checkout, cents: 100_001)
        XCTAssertEqual(checkout.validationMessage, Money.allowedRangeText)
        XCTAssertEqual(api.createdPayments, 0)
    }

    func testALongNoteIsCaughtBeforeCharging() async {
        let checkout = makeCheckout()
        checkout.note = String(repeating: "n", count: 201)
        await charge(checkout, cents: 2000)
        XCTAssertEqual(checkout.validationMessage, "Keep the note to 200 characters or fewer.")
        XCTAssertEqual(api.createdPayments, 0)
    }

    func testABadReceiptEmailIsCaughtBeforeCharging() async {
        let checkout = makeCheckout()
        checkout.receiptEmail = "client at example"
        await charge(checkout, cents: 2000)
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertNotNil(checkout.validationMessage)
        XCTAssertEqual(api.createdPayments, 0)
        XCTAssertTrue(CheckoutModel.looksLikeEmail("a.b@example.co"))
        XCTAssertFalse(CheckoutModel.looksLikeEmail("a@b"))
        XCTAssertFalse(CheckoutModel.looksLikeEmail("a@@b.com"))
        XCTAssertFalse(CheckoutModel.looksLikeEmail("a b@c.com"))
    }

    func testPrefillUsesOnlyFixedCatalogPrices() throws {
        let catalog = Catalog.izzyClipz
        let lightener = try XCTUnwrap(catalog.offerings.first { $0.serviceID == "lightener" })
        let eyebrows = try XCTUnwrap(catalog.offerings.first { $0.serviceID == "eyebrows" })
        let server = harness.server
        let from = server.makeAppointment(offering: lightener, start: TestClock.at(15), customer: .init(name: "A Sample"))
        let included = server.makeAppointment(offering: eyebrows, start: TestClock.at(16), customer: .init(name: "B Sample"))
        let fromContext = CheckoutModel.AppointmentContext(appointment: from, catalog: catalog)
        XCTAssertNil(fromContext.suggestedCents, "\"From $80\" isn't the final price")
        XCTAssertEqual(fromContext.priceLabel, "From $80")
        XCTAssertNil(CheckoutModel.AppointmentContext(appointment: included, catalog: catalog).suggestedCents)

        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 1234)
        checkout.prefill(fromContext)
        XCTAssertEqual(checkout.entry.cents, 0, "No price is guessed")
        XCTAssertTrue(fromContext.title.contains("A Sample"))
    }

    func testPrefillWaitsForARunningPayment() async throws {
        terminal.automaticOutcome = nil
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let waiting = await eventually { self.terminal.pendingTap != nil }
        XCTAssertTrue(waiting)
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        XCTAssertFalse(checkout.prefill(.init(appointment: andre, catalog: .izzyClipz)))
        XCTAssertEqual(checkout.entry.cents, 2000)
        terminal.choose(.customerCancels)
        await checkout.waitUntilSettled()
        XCTAssertEqual(checkout.phase, .cancelled)
    }

    func testCancelDuringTheTapStopsWithoutCharging() async {
        terminal.automaticOutcome = nil
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let waiting = await eventually { checkout.phase == .collecting && self.terminal.pendingTap != nil }
        XCTAssertTrue(waiting)
        checkout.cancel()
        await checkout.waitUntilSettled()
        XCTAssertEqual(checkout.phase, .cancelled)
        XCTAssertFalse(harness.server.payments.contains { $0.payment.isSucceeded && $0.payment.amountCents == 2000 })
    }

    func testOnceTheCardIsReadTheScreenSaysProcessingAndCancelIsGone() async {
        terminal = SimulatedPaymentTerminal(stepDelay: .milliseconds(300))
        let server = harness.server
        terminal.onApproved = { server.cardApproved(clientSecret: $0) }
        let checkout = makeCheckout()
        checkout.entry = AmountEntry(cents: 2000)
        checkout.charge()
        let waiting = await eventually { self.terminal.pendingTap != nil }
        XCTAssertTrue(waiting)
        XCTAssertFalse(checkout.isProcessing, "Waiting for the card")
        XCTAssertTrue(checkout.canCancel)

        // The customer taps: the reader authorizes the card before the server checks it.
        terminal.choose(.approve)
        let processing = await eventually { checkout.isProcessing }
        XCTAssertTrue(processing, "Got \(checkout.phase)")
        XCTAssertEqual(checkout.phase, .collecting, "Still at the reader, before the server's check")
        XCTAssertEqual(terminal.state, .processing)
        XCTAssertFalse(checkout.canCancel, "No Cancel once the card is read")
        checkout.cancel()
        await checkout.waitUntilSettled()
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 2000)
        XCTAssertFalse(checkout.isProcessing)
        XCTAssertFalse(checkout.canCancel)
    }

    // MARK: Payments today and recovery

    func testTodaysPaymentsListOnlyWhatSucceeded() async {
        _ = try? await harness.api.createPayment(.init(amountCents: 999))
        let checkout = makeCheckout()
        await checkout.loadPayments()
        XCTAssertFalse(checkout.todaysPayments.isEmpty)
        XCTAssertTrue(checkout.todaysPayments.allSatisfy(\.isSucceeded))
        XCTAssertFalse(checkout.todaysPayments.contains { $0.amountCents == 999 }, "An unpaid PaymentIntent isn't money in")
        XCTAssertEqual(checkout.todaysTotalCents, checkout.todaysPayments.reduce(0) { $0 + $1.amountCents })
    }

    func testAPaymentLeftUnconfirmedIsRecoveredNextTime() async throws {
        // An earlier run created a PaymentIntent and the card went through,
        // but the app closed before the server confirmed it.
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        let created = try await harness.api.createPayment(.init(amountCents: 5500, appointmentId: andre.id))
        harness.server.cardApproved(clientSecret: created.clientSecret)
        pending.add(created.paymentIntentId, at: TestClock.now.addingTimeInterval(-600))
        let abandoned = try await harness.api.createPayment(.init(amountCents: 700))
        pending.add(abandoned.paymentIntentId, at: TestClock.now.addingTimeInterval(-3 * 86_400))
        let recent = try await harness.api.createPayment(.init(amountCents: 800))
        pending.add(recent.paymentIntentId, at: TestClock.now.addingTimeInterval(-60))

        let checkout = makeCheckout()
        await checkout.syncPendingPayments()
        XCTAssertNil(pending.entries[created.paymentIntentId])
        XCTAssertNil(pending.entries[abandoned.paymentIntentId], "Old and never paid: forgotten")
        XCTAssertNotNil(pending.entries[recent.paymentIntentId], "Recent and not paid yet: kept")
        XCTAssertEqual(harness.appointment(named: "Andre Sample")?.payment.status, .paid)
        XCTAssertEqual(paidAppointments, [andre.id])
        XCTAssertTrue(checkout.todaysPayments.contains { $0.id == created.paymentIntentId })
        XCTAssertEqual(checkout.recoveryNotice, "A $55.00 card payment from earlier went through and is now recorded. Don't charge it again.")
    }

    func testThePaymentJustTakenIsNeverReportedAsOneFromEarlier() async throws {
        // An older PaymentIntent that was never charged: the app closed after its decline.
        let older = try await harness.api.createPayment(.init(amountCents: 700))
        pending.add(older.paymentIntentId, at: TestClock.now.addingTimeInterval(-600))
        var checked: [String] = []
        var olderIsSlow = true
        api.completeHandler = { @MainActor [api] id in
            checked.append(id)
            if id == older.paymentIntentId {
                while olderIsSlow { try await Task.sleep(for: .milliseconds(10)) }
            }
            return try await api!.base.completePayment(id: id)
        }
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        terminal.automaticOutcome = nil
        let checkout = makeCheckout()
        checkout.prefill(.init(appointment: andre, catalog: .izzyClipz))
        checkout.charge()
        let waiting = await eventually { self.terminal.pendingTap != nil }
        XCTAssertTrue(waiting)
        let current = try XCTUnwrap(checkout.active?.paymentIntentId)

        // The app comes back to the foreground mid-payment (Notification Center was
        // pulled down): it checks what's pending, and the older one is slow to answer.
        let sync = Task { await checkout.syncPendingPayments() }
        let checkingOlder = await eventually { checked == [older.paymentIntentId] }
        XCTAssertTrue(checkingOlder, "Checked: \(checked)")

        // Meanwhile the customer taps and this payment goes through.
        terminal.choose(.approve)
        await checkout.waitUntilSettled()
        guard case .succeeded = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        olderIsSlow = false
        await sync.value

        XCTAssertNil(checkout.recoveryNotice, "The payment just taken isn't \"a card payment from earlier\"")
        XCTAssertEqual(paidAppointments, [andre.id], "Marked paid once")
        XCTAssertEqual(checked, [older.paymentIntentId, current], "The payment just taken was confirmed once, by itself")
        XCTAssertNotNil(pending.entries[older.paymentIntentId], "Recent and not paid: still kept")
    }

    func testPendingPaymentsStoreOnlyIDsAndDates() {
        let store = PendingPayments(defaults: makeDefaults())
        store.add("pi_1", at: TestClock.now)
        store.add("pi_2", at: TestClock.now)
        store.remove("pi_1")
        XCTAssertEqual(Array(store.entries.keys), ["pi_2"])
        XCTAssertEqual(store.entries["pi_2"]?.timeIntervalSince1970 ?? 0, TestClock.now.timeIntervalSince1970, accuracy: 0.001)
        store.removeAll()
        XCTAssertTrue(store.entries.isEmpty)
    }
}

/// The sample server's no-show protection answers like the real server's.
@MainActor
final class SampleServerNoShowTests: XCTestCase {
    func testSettingsStartOffAtTheFullPriceAndChangeOnlyWhatIsSent() async throws {
        let harness = Harness()
        let settings = try await harness.api.noShowSettings()
        XCTAssertEqual(settings, .default)
        XCTAssertEqual(settings, IzzyAPI.NoShowSettings(
            enabled: false, feeMode: .percent, percent: 100, flatCents: 2_000, lateCancelEnabled: true, lateCancelWindowMinutes: 60
        ), "off until the owner turns it on")
        let on = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(enabled: true))
        XCTAssertTrue(on.enabled)
        let flat = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(feeMode: .flat, flatCents: 2_500))
        XCTAssertEqual(flat, IzzyAPI.NoShowSettings(
            enabled: true, feeMode: .flat, percent: 100, flatCents: 2_500, lateCancelEnabled: true, lateCancelWindowMinutes: 60
        ))
        let window = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 120))
        XCTAssertEqual(window.lateCancelWindowMinutes, 120)
        let noLateFee = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelEnabled: false))
        XCTAssertFalse(noLateFee.lateCancelEnabled)
        XCTAssertEqual(noLateFee.lateCancelWindowMinutes, 120, "kept for when late cancellations are back on")
        let off = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(enabled: false))
        XCTAssertFalse(off.enabled)
        let reread = try await harness.api.noShowSettings()
        XCTAssertEqual(reread, off)
        XCTAssertEqual(harness.server.calls.suffix(3), ["updateNoShowSettings", "updateNoShowSettings", "noShowSettings"])
    }

    func testSettingsTurnDownWhatTheServerTurnsDown() async {
        let harness = Harness()
        for (update, message) in [
            (IzzyAPI.NoShowSettingsUpdate(percent: 0), "Pick a percentage from 1% to 100%."),
            (IzzyAPI.NoShowSettingsUpdate(percent: 101), "Pick a percentage from 1% to 100%."),
            (IzzyAPI.NoShowSettingsUpdate(flatCents: 49), "Pick a flat fee from $0.50 to $500."),
            (IzzyAPI.NoShowSettingsUpdate(enabled: false, flatCents: 50_001), "Pick a flat fee from $0.50 to $500."),
            (IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 29), "Pick a late-cancellation window from 30 minutes to 48 hours."),
            (IzzyAPI.NoShowSettingsUpdate(lateCancelEnabled: true, lateCancelWindowMinutes: 2_881), "Pick a late-cancellation window from 30 minutes to 48 hours."),
        ] {
            do {
                _ = try await harness.api.updateNoShowSettings(update)
                XCTFail("Expected a 400 for \(update)")
            } catch {
                XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.invalidRequest, message: message, status: 400))
            }
        }
        XCTAssertEqual(harness.server.noShowSettings, .default, "nothing changed")
        do {
            _ = try await harness.server.api(ownerKey: "wrong").noShowSettings()
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testChargingANoShowWithACardOnFileChargesOnceAndListsTheFee() async throws {
        var options = FakeServer.Options()
        options.noShowWithCard = true
        let harness = Harness(options: options)
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(kim.card?.label, "Visa •••• 4242")
        // The full price of the $35 haircut, and the 1-hour window the policy had.
        XCTAssertEqual(kim.noShowFee, IzzyAPI.NoShowFee(amountCents: 3_500, fullPrice: true, lateCancelWindowMinutes: 60, reason: .noShow))
        XCTAssertTrue(kim.canChargeNoShowFee(at: TestClock.now))
        XCTAssertEqual(kim.chargeableFee(at: TestClock.now), .noShow)

        let charged = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertEqual(charged.noShowFee?.reason, .noShow)
        XCTAssertEqual(charged.noShowFee?.chargedAt, TestClock.now)
        XCTAssertEqual(charged.payment, .unpaid, "a no-show fee isn't a payment for the service")
        XCTAssertFalse(charged.canChargeNoShowFee(at: TestClock.now))
        let payments = try await harness.api.payments(on: TestClock.today)
        let fee = try XCTUnwrap(payments.first { $0.kind == .noShowFee })
        XCTAssertEqual(fee.amountCents, 3_500)
        XCTAssertEqual(fee.description, "No-show fee: Haircut with Flowxbori, Mon, Nov 2 at 10:00 AM", "as the server words it")
        XCTAssertEqual(fee.appointmentId, kim.id)
        XCTAssertTrue(fee.isSucceeded)

        // Again: the same answer, no second charge.
        let again = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(again, charged)
        let afterAgain = try await harness.api.payments(on: TestClock.today)
        XCTAssertEqual(afterAgain.filter { $0.kind == .noShowFee }.count, 1)

        // Reopened and paid at the shop after all: only that payment counts as paid.
        _ = try await harness.api.setStatus(.completed, ofAppointment: kim.id)
        let intent = try await harness.api.createPayment(IzzyAPI.NewPayment(amountCents: 3_500, appointmentId: kim.id))
        harness.server.cardApproved(clientSecret: intent.clientSecret)
        _ = try await harness.api.completePayment(id: intent.paymentIntentId)
        let paid = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(paid.payment.amountCents, 3_500)
        XCTAssertEqual(paid.noShowFee?.status, .charged, "reopening doesn't refund")
    }

    func testOnlyANoShowWithACardThatHasEndedCanBeCharged() async throws {
        var options = FakeServer.Options()
        options.noShowWithCard = true
        let harness = Harness(options: options)
        func expect(_ id: String, _ expected: APIError, line: UInt = #line) async {
            do {
                _ = try await harness.api.chargeNoShowFee(appointmentId: id)
                XCTFail("Expected \(expected)", line: line)
            } catch {
                XCTAssertEqual(error as? APIError, expected, line: line)
            }
        }
        // Jay didn't come either, but booked by phone: no card on file.
        let jay = try XCTUnwrap(harness.appointment(named: "Jay Sample"))
        await expect(jay.id, .server(code: IzzyAPI.ErrorCode.notChargeable, message: "This booking has no card on file, so there's no fee to charge.", status: 409))
        await expect("00000000-0000-4000-8000-0000000000ff", .server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that appointment.", status: 404))
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        let reopened = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        XCTAssertNil(reopened.noShowFee?.reason)
        await expect(kim.id, .server(code: IzzyAPI.ErrorCode.notChargeable, message: "Mark the appointment as a no-show first.", status: 409))
        let markedAgain = try await harness.api.setStatus(.noShow, ofAppointment: kim.id)
        XCTAssertEqual(markedAgain.noShowFee?.reason, .noShow, "it has ended, so it can be a no-show again")

        // Kim's 10 AM haircut ends at 10:45. Marked a no-show before that (from before it was refused),
        // before her start or after it, the fee can't be charged: she may still come.
        for moment in [TestClock.at(9, 30), TestClock.at(10, 44)] {
            let early = Harness(options: options, now: moment)
            let kimEarly = try XCTUnwrap(early.appointment(named: "Kim Sample"))
            do {
                _ = try await early.api.chargeNoShowFee(appointmentId: kimEarly.id)
                XCTFail("Expected not_chargeable")
            } catch {
                XCTAssertEqual(error as? APIError, .server(
                    code: IzzyAPI.ErrorCode.notChargeable, message: "The appointment hasn't ended yet, so it can't be a no-show.", status: 409
                ))
            }
        }
        // Now a booking with a card on file can't be marked a no-show before it ends, a minute before
        // included; at its end it can.
        let early = Harness(options: options, now: TestClock.at(10, 44))
        let kimEarly = try XCTUnwrap(early.appointment(named: "Kim Sample"))
        _ = try await early.api.setStatus(.booked, ofAppointment: kimEarly.id)
        do {
            _ = try await early.api.setStatus(.noShow, ofAppointment: kimEarly.id)
            XCTFail("Expected not_started")
        } catch {
            XCTAssertEqual(error as? APIError, .server(
                code: IzzyAPI.ErrorCode.notStarted, message: "You can mark a no-show once the appointment has ended.", status: 409
            ))
        }
        XCTAssertEqual(early.appointment(named: "Kim Sample")?.status, .booked)
        let atTheEnd = Harness(options: options, now: TestClock.at(10, 45))
        let kimAtTheEnd = try XCTUnwrap(atTheEnd.appointment(named: "Kim Sample"))
        _ = try await atTheEnd.api.setStatus(.booked, ofAppointment: kimAtTheEnd.id)
        let ended = try await atTheEnd.api.setStatus(.noShow, ofAppointment: kimAtTheEnd.id)
        XCTAssertEqual(ended.status, .noShow)
        XCTAssertEqual(ended.chargeableFee(at: TestClock.at(10, 45)), .noShow)
        // A booking without a card can still be marked early, as before.
        let andre = try XCTUnwrap(early.appointment(named: "Andre Sample"))
        let andreNoShow = try await early.api.setStatus(.noShow, ofAppointment: andre.id)
        XCTAssertEqual(andreNoShow.status, .noShow)

        // Without Stripe on the server: 503, before anything else.
        options.stripeConfigured = false
        let noStripe = Harness(options: options)
        do {
            _ = try await noStripe.api.chargeNoShowFee(appointmentId: "anything")
            XCTFail("Expected stripe_not_configured")
        } catch {
            XCTAssertEqual(error as? APIError, .notConfigured(APIError.Feature.stripe))
        }
    }

    func testChargingALateCancellationRightAwayOnceAndLabelled() async throws {
        var options = FakeServer.Options()
        options.lateCancelWithCard = true
        let harness = Harness(options: options)
        // Lee cancelled in the app at 10:50, 40 minutes before the 11:30 haircut.
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        XCTAssertEqual(lee.status, .cancelled)
        XCTAssertEqual(lee.cancelledBy, .customer)
        XCTAssertEqual(lee.noShowFee, IzzyAPI.NoShowFee(
            amountCents: 3_500, fullPrice: true, customerCancelledAt: TestClock.at(10, 50), lateCancelWindowMinutes: 60, reason: .lateCancel
        ))
        // 11:05: before the start, and already chargeable.
        XCTAssertEqual(lee.chargeableFee(at: TestClock.now), .lateCancel)

        let charged = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertEqual(charged.noShowFee?.reason, .lateCancel)
        XCTAssertEqual(charged.status, .cancelled)
        XCTAssertNil(charged.chargeableFee(at: TestClock.now))
        let payments = try await harness.api.payments(on: TestClock.today)
        let fee = try XCTUnwrap(payments.first { $0.kind == .lateCancelFee })
        XCTAssertEqual(fee.amountCents, 3_500)
        XCTAssertEqual(fee.description, "Late cancellation fee: Haircut with Flowxbori, Mon, Nov 2 at 11:30 AM", "as the server words it")
        XCTAssertEqual(fee.kind.title, "Late cancellation fee")
        XCTAssertEqual(payments.filter(\.kind.isFee).count, 1)
        // Again: the same answer, no second charge; reopening doesn't refund.
        let again = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(again, charged)
        let reopened = try await harness.api.setStatus(.booked, ofAppointment: lee.id)
        XCTAssertEqual(reopened.noShowFee?.status, .charged)
        XCTAssertEqual(reopened.noShowFee?.reason, .lateCancel)
        let paymentsAfter = try await harness.api.payments(on: TestClock.today)
        XCTAssertEqual(paymentsAfter.filter(\.kind.isFee).count, 1)
    }

    func testALateCancellationTheShopReopenedOrCancelledIsNeverCharged() async throws {
        var options = FakeServer.Options()
        options.lateCancelWithCard = true
        let harness = Harness(options: options)
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        func expect(_ message: String, line: UInt = #line) async {
            do {
                _ = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
                XCTFail("Expected not_chargeable", line: line)
            } catch {
                XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.notChargeable, message: message, status: 409), line: line)
            }
        }
        let reopened = try await harness.api.setStatus(.booked, ofAppointment: lee.id)
        XCTAssertNil(reopened.noShowFee?.reason)
        XCTAssertEqual(reopened.noShowFee?.customerCancelledAt, TestClock.at(10, 50), "when the client cancelled is kept")
        await expect("The client cancelled this booking in the app, so there's no fee.")
        let cancelled = try await harness.api.setStatus(.cancelled, ofAppointment: lee.id)
        XCTAssertEqual(cancelled.cancelledBy, .shop)
        await expect("The shop cancelled this booking, so there's no fee.")
        let payments = try await harness.api.payments(on: TestClock.today)
        XCTAssertTrue(payments.allSatisfy { !$0.kind.isFee })
    }

    func testTheUsualSampleDayHasNoCardsOnFile() {
        let harness = Harness()
        XCTAssertTrue(harness.server.appointments.allSatisfy { $0.card == nil && $0.noShowFee == nil })
        XCTAssertNil(harness.appointment(named: "Kim Sample"))
        XCTAssertNil(harness.appointment(named: "Lee Sample"))
    }

    /// The charge never reached Stripe: the fee waits as pending, and Check again charges it (once)
    /// while Kim is still a no-show.
    func testAChargeThatNeverReachedStripeWaitsThenCheckAgainChargesIt() async throws {
        var options = FakeServer.Options()
        options.noShowWithCard = true
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        do {
            _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
            XCTFail("Expected Stripe to be out of reach")
        } catch {
            XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.serverError, message: "We couldn't reach Stripe. Please try again.", status: 500))
        }
        let waiting = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(waiting.noShowFee?.status, .pending)
        XCTAssertEqual(waiting.noShowFee?.reason, .noShow)
        XCTAssertTrue(waiting.isFeePending, "the button reads Check again")
        XCTAssertEqual(waiting.chargeableFee(at: TestClock.now), .noShow)
        let before = try await harness.api.payments(on: TestClock.today)
        XCTAssertFalse(before.contains { $0.kind.isFee }, "nothing was charged yet")

        let charged = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertEqual(charged.noShowFee?.reason, .noShow)
        XCTAssertFalse(charged.isFeePending)
        let after = try await harness.api.payments(on: TestClock.today)
        XCTAssertEqual(after.filter(\.kind.isFee).count, 1)
    }

    /// Kim walked in late after a charge that never reached Stripe: the visit is completed, and Check
    /// again settles the fee as not charged, so no fee stays pending on a completed visit.
    func testCheckAgainOnACompletedVisitSettlesTheFeeAsNotCharged() async throws {
        var options = FakeServer.Options()
        options.noShowWithCard = true
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        _ = try? await harness.api.chargeNoShowFee(appointmentId: kim.id)
        _ = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        let completed = try await harness.api.setStatus(.completed, ofAppointment: kim.id)
        XCTAssertEqual(completed.noShowFee?.status, .pending)
        XCTAssertEqual(completed.noShowFee?.reason, .noShow, "what the waiting try was for")
        XCTAssertEqual(completed.chargeableFee(at: TestClock.now), .noShow, "Check again is still there")
        func expect(_ message: String, line: UInt = #line) async {
            do {
                _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
                XCTFail("Expected not_chargeable", line: line)
            } catch {
                XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.notChargeable, message: message, status: 409), line: line)
            }
        }
        await expect("Nothing was charged. The appointment is marked completed, so there's no fee to charge.")
        let settled = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(settled.noShowFee?.status, IzzyAPI.NoShowFeeStatus.none)
        XCTAssertNil(settled.noShowFee?.reason)
        XCTAssertNil(settled.chargeableFee(at: TestClock.now))
        XCTAssertFalse(settled.isFeePending)
        let payments = try await harness.api.payments(on: TestClock.today)
        XCTAssertFalse(payments.contains { $0.kind.isFee })
        // Asked again: the plain answer.
        await expect("The appointment is marked completed, so there's no fee to charge.")
        // She came, so the visit never becomes a no-show, even reopened: nothing more can be charged.
        func expectNoNoShow(line: UInt = #line) async {
            do {
                _ = try await harness.api.setStatus(.noShow, ofAppointment: kim.id)
                XCTFail("Expected already_completed", line: line)
            } catch {
                XCTAssertEqual(error as? APIError, .server(
                    code: IzzyAPI.ErrorCode.alreadyCompleted, message: "This appointment was marked completed, so it can't become a no-show.", status: 409
                ), line: line)
            }
        }
        await expectNoNoShow()
        _ = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        await expectNoNoShow()
        XCTAssertEqual(harness.appointment(named: "Kim Sample")?.status, .booked)
        await expect("Mark the appointment as a no-show first.")
        let after = try await harness.api.payments(on: TestClock.today)
        XCTAssertFalse(after.contains { $0.kind.isFee })
    }
}
