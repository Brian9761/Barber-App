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
        checkout.receiptEmail = "client@example.com"
        checkout.charge()
        await checkout.waitUntilSettled()

        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Expected paid, got \(checkout.phase)") }
        XCTAssertEqual(receipt.amountCents, 5500)
        XCTAssertTrue(receipt.isTestMode, "The simulated reader is always test mode")
        XCTAssertEqual(receipt.receiptEmail, "client@example.com")
        XCTAssertEqual(api.createdPayments, 1)
        XCTAssertEqual(harness.server.payments.last?.receiptEmail, "client@example.com", "The receipt email goes to the server with the PaymentIntent")
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
        checkout.receiptEmail = "client@example.com"
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
