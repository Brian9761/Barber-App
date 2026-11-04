import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Charging the fee agreed at booking to a card on file, for a no-show or a late cancellation:
/// what an appointment's details say and offer (`FeePanel`), the labels on the schedule and in
/// Payments today, the schedule's charge (asked once, never twice, every answer shown), and the
/// sample server answering like the real one.
@MainActor
final class NoShowFeeTests: XCTestCase {
    /// Kim (10 AM, a no-show), Lee (11:30 AM, cancelled in the app at 10:50 AM) and Nia (2:30 PM,
    /// booked), all booked online with Visa 4242 for a $35 haircut with Flowxbori.
    private func cardsOnFile() -> FakeServer.Options {
        var options = FakeServer.Options()
        options.noShowWithCard = true
        options.lateCancelWithCard = true
        options.upcomingWithCard = true
        return options
    }

    /// The details' fee section at `now` (the tests' 11:05 AM unless given).
    private func panel(_ appointment: IzzyAPI.Appointment, at now: Date? = nil) -> FeePanel? {
        FeePanel(appointment: appointment, now: now ?? TestClock.now, shopTime: TestClock.shopTime)
    }

    private func makeStore(_ api: any OwnerAPI, now: Date? = nil) -> ScheduleStore {
        let moment = now ?? TestClock.now
        return ScheduleStore(api: api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { moment })
    }

    // MARK: What the details say

    func testAnAppointmentWithoutACardHasNoFeeAndCanBeMarkedANoShowAsBefore() throws {
        let harness = Harness(options: cardsOnFile())
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        XCTAssertNil(panel(andre))
        XCTAssertTrue(andre.canMarkNoShow(at: TestClock.now), "booked at the shop: no card, so no wait for the start")
        XCTAssertNil(FeePanel.reopenWarning(for: andre, now: TestClock.now))
        XCTAssertNil(FeePanel.noShowHint(for: andre, now: TestClock.now, shopTime: TestClock.shopTime))
        XCTAssertFalse(andre.isCancelledLate)
        let sam = try XCTUnwrap(harness.appointment(named: "Sam Sample"))
        XCTAssertFalse(sam.isCancelledLate, "cancelled in the app, but without a card on file")
        XCTAssertNil(panel(sam))
    }

    func testANoShowWithACardOffersToChargeItsFeeAndAsksFirst() throws {
        let harness = Harness(options: cardsOnFile())
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        let panel = try XCTUnwrap(panel(kim))
        XCTAssertEqual(panel.cardLabel, "Visa •••• 4242")
        XCTAssertEqual(panel.feeLabel, "$35 (the full service price)")
        XCTAssertEqual(panel.agreement, "For not showing up, or cancelling less than 1 hour before.")
        XCTAssertEqual(panel.status, .notCharged(note: nil))
        XCTAssertEqual(panel.footer, "Nothing is charged until you confirm, and a fee is only ever charged once.")
        let action = try XCTUnwrap(panel.action)
        XCTAssertEqual(action.title, "Charge no-show fee ($35)")
        XCTAssertFalse(action.checksAgain)
        XCTAssertEqual(action.confirmation, FeePanel.Confirmation(
            title: "Charge $35 to Kim Sample's Visa •••• 4242?",
            message: "No-show fee for Haircut with Flowxbori, Mon, Nov 2 at 10 AM. The client agreed to it when booking.",
            button: "Charge $35"
        ))
        XCTAssertNil(FeePanel.reopenWarning(for: kim, now: TestClock.now), "a reopened no-show can be marked again")
    }

    func testALateCancellationOffersItsFeeRightAway() throws {
        let harness = Harness(options: cardsOnFile())
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        XCTAssertTrue(lee.isCancelledLate)
        XCTAssertGreaterThan(lee.start, TestClock.now, "before the start")
        let panel = try XCTUnwrap(panel(lee))
        XCTAssertEqual(panel.status, .notCharged(note: nil))
        let action = try XCTUnwrap(panel.action)
        XCTAssertEqual(action.title, "Charge late cancellation fee ($35)")
        XCTAssertEqual(action.confirmation, FeePanel.Confirmation(
            title: "Charge $35 to Lee Sample's Visa •••• 4242?",
            message: "Late cancellation fee for Haircut with Flowxbori, Mon, Nov 2 at 11:30 AM: the client cancelled at 10:50 AM, less than 1 hour before. They agreed to it when booking.",
            button: "Charge $35"
        ))
        XCTAssertEqual(
            FeePanel.reopenWarning(for: lee, now: TestClock.now),
            "Once it's reopened, the $35 late cancellation fee can't be charged any more."
        )
    }

    func testWhenNoFeeCanBeChargedTheDetailsSayWhy() async throws {
        let harness = Harness(options: cardsOnFile())
        // Nia's haircut hasn't started.
        let nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        XCTAssertFalse(nia.canMarkNoShow(at: TestClock.now))
        XCTAssertEqual(
            FeePanel.noShowHint(for: nia, now: TestClock.now, shopTime: TestClock.shopTime),
            "You can mark a no-show once the appointment starts at 2:30 PM. Until then, the client can still cancel in the app."
        )
        XCTAssertEqual(panel(nia)?.status, .notCharged(note: "If the client doesn't come, you can mark a no-show once the appointment has started. Then you can charge the fee."))
        XCTAssertNil(panel(nia)?.action)
        XCTAssertNil(panel(nia)?.footer)
        // Once it has started.
        let later = TestClock.at(14, 35)
        XCTAssertTrue(nia.canMarkNoShow(at: later))
        XCTAssertNil(FeePanel.noShowHint(for: nia, now: later, shopTime: TestClock.shopTime))
        XCTAssertEqual(panel(nia, at: later)?.status, .notCharged(note: "If the client didn't come, mark a no-show. Then you can charge the fee."))
        XCTAssertNil(panel(nia, at: later)?.action)

        // Kim came after all: nothing to explain.
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        _ = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        let came = try await harness.api.setStatus(.completed, ofAppointment: kim.id)
        XCTAssertEqual(panel(came)?.status, .notCharged(note: nil))
        XCTAssertNil(panel(came)?.action)

        // Lee's late cancellation reopened by the shop, then cancelled by the shop.
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let reopened = try await harness.api.setStatus(.booked, ofAppointment: lee.id)
        XCTAssertEqual(panel(reopened)?.status, .notCharged(note: "The client cancelled this booking in the app, so there's no fee."))
        XCTAssertNil(panel(reopened)?.action)
        XCTAssertFalse(reopened.isCancelledLate)
        let shopCancelled = try await harness.api.setStatus(.cancelled, ofAppointment: lee.id)
        XCTAssertEqual(panel(shopCancelled)?.status, .notCharged(note: "The shop cancelled this booking, so there's no fee."))
        XCTAssertFalse(shopCancelled.isCancelledLate)

        // Cancelled in time: free.
        var early = lee
        early.noShowFee?.customerCancelledAt = TestClock.at(10, 30)
        XCTAssertFalse(early.isCancelledLate)
        XCTAssertEqual(panel(early)?.status, .notCharged(note: "The client cancelled at least 1 hour before, so there's no fee."))
        XCTAssertNil(panel(early)?.action)
        XCTAssertNil(FeePanel.reopenWarning(for: early, now: TestClock.now))

        // Marked a no-show before it started (before the server refused that).
        XCTAssertEqual(panel(kim, at: TestClock.at(9, 30))?.status, .notCharged(note: "The appointment hasn't started yet, so it can't be a no-show."))
        XCTAssertNil(panel(kim, at: TestClock.at(9, 30))?.action)
    }

    func testDeclinedNeedingTheClientAndUnconfirmedFees() throws {
        let harness = Harness(options: cardsOnFile())
        var kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        kim.noShowFee?.status = .declined
        kim.noShowFee?.message = "The card was declined: there isn't enough money on it."
        var panel = try XCTUnwrap(panel(kim))
        XCTAssertEqual(panel.status, .declined("The card was declined: there isn't enough money on it."))
        XCTAssertEqual(panel.action?.title, "Charge again ($35)")
        XCTAssertEqual(panel.action?.confirmation?.title, "Charge $35 to Kim Sample's Visa •••• 4242?", "asked again")
        XCTAssertEqual(panel.footer, "You can try the card again later, or ask the client to pay at the shop.")
        kim.noShowFee?.message = nil
        XCTAssertEqual(self.panel(kim)?.status, .declined("The bank declined the card."))

        kim.noShowFee?.status = .needsAction
        kim.noShowFee?.message = FakeServer.authenticationMessage
        panel = try XCTUnwrap(self.panel(kim))
        XCTAssertEqual(panel.status, .needsClient(FakeServer.authenticationMessage))
        XCTAssertEqual(panel.action?.title, "Charge again ($35)")
        XCTAssertNil(panel.footer)

        kim.noShowFee?.status = .pending
        kim.noShowFee?.message = nil
        panel = try XCTUnwrap(self.panel(kim))
        XCTAssertEqual(panel.status, .pending(FeePanel.pendingMessage))
        XCTAssertEqual(panel.action, FeePanel.Action(title: "Check again", confirmation: nil))
        XCTAssertEqual(panel.action?.checksAgain, true, "it only finishes the try that was confirmed")
        // Even once the visit is marked completed: Check again settles it with the server.
        kim.status = .completed
        XCTAssertEqual(self.panel(kim)?.action?.title, "Check again")
    }

    func testAChargedFeeSaysWhenAndWhereRefundsAreMade() throws {
        let harness = Harness(options: cardsOnFile())
        var kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        kim.noShowFee?.status = .charged
        kim.noShowFee?.chargedAt = TestClock.now
        let panel = try XCTUnwrap(panel(kim))
        XCTAssertEqual(panel.status, .charged(title: "No-show fee charged", detail: "$35 to Visa •••• 4242, Mon, Nov 2 at 11:05 AM."))
        XCTAssertNil(panel.action, "never twice")
        XCTAssertEqual(panel.footer, "Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee.")
        XCTAssertEqual(
            FeePanel.reopenWarning(for: kim, now: TestClock.now),
            "The $35 no-show fee stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        lee.noShowFee?.status = .charged
        lee.noShowFee?.reason = .lateCancel
        lee.noShowFee?.chargedAt = nil
        XCTAssertEqual(self.panel(lee)?.status, .charged(title: "Late cancellation fee charged", detail: "$35 to Visa •••• 4242."))
        XCTAssertEqual(
            FeePanel.reopenWarning(for: lee, now: TestClock.now),
            "The $35 late cancellation fee stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
    }

    func testWhatTheFeeIsForAndHowMuch() throws {
        let harness = Harness(options: cardsOnFile())
        var kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        kim.noShowFee?.amountCents = 1_750
        kim.noShowFee?.fullPrice = false
        kim.noShowFee?.lateCancelWindowMinutes = nil
        var panel = try XCTUnwrap(panel(kim))
        XCTAssertEqual(panel.feeLabel, "$17.50")
        XCTAssertEqual(panel.agreement, "For not showing up. Cancelling in the app before the start is free.")
        XCTAssertEqual(panel.action?.title, "Charge no-show fee ($17.50)")
        XCTAssertEqual(panel.action?.confirmation?.button, "Charge $17.50")
        kim.noShowFee?.lateCancelWindowMinutes = 120
        XCTAssertEqual(self.panel(kim)?.agreement, "For not showing up, or cancelling less than 2 hours before.")
        // A fee without the card's details (never sent by the server): still named plainly.
        kim.card = nil
        panel = try XCTUnwrap(self.panel(kim))
        XCTAssertEqual(panel.cardLabel, "Card on file")
        XCTAssertNil(panel.action, "the Kit only charges a card it knows")
    }

    // MARK: Labels

    func testTheScheduleLabelsCardsFeesAndLateCancellations() async throws {
        let harness = Harness(options: cardsOnFile())
        func badges(_ name: String) throws -> [String] {
            AppointmentBadges(appointment: try XCTUnwrap(harness.appointment(named: name))).spoken
        }
        XCTAssertEqual(try badges("Marcus Sample"), ["Completed", "Paid $40.00"])
        XCTAssertEqual(try badges("Jay Sample"), ["No-show"])
        XCTAssertEqual(try badges("Sam Sample"), ["Cancelled"])
        XCTAssertEqual(try badges("Andre Sample"), ["Booked"])
        XCTAssertEqual(try badges("Kim Sample"), ["No-show", "Card on file"])
        XCTAssertEqual(try badges("Lee Sample"), ["Cancelled late", "Card on file"])
        XCTAssertEqual(try badges("Nia Sample"), ["Booked", "Card on file"])

        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(AppointmentBadges(appointment: kim).items.map(\.tone), [.status(.noShow), .card])
        _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(try badges("Kim Sample"), ["No-show", "No-show fee $35 charged"])
        XCTAssertEqual(AppointmentBadges(appointment: try XCTUnwrap(harness.appointment(named: "Kim Sample"))).items.last?.tone, .feeCharged)
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        _ = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(try badges("Lee Sample"), ["Cancelled late", "Late cancellation fee $35 charged"])

        var other = kim
        for (status, text, tone) in [
            (IzzyAPI.NoShowFeeStatus.declined, "Fee declined", AppointmentBadges.Tone.feeDeclined),
            (.needsAction, "Fee needs the client", .feeWaiting),
            (.pending, "Fee not confirmed", .feeWaiting),
        ] {
            other.noShowFee?.status = status
            XCTAssertEqual(AppointmentBadges(appointment: other).items.last, AppointmentBadges.Item(text: text, tone: tone))
        }
        // A card without a fee (never sent by the server) still says it's on file.
        other.noShowFee = nil
        XCTAssertEqual(AppointmentBadges(appointment: other).spoken, ["No-show", "Card on file"])
    }

    func testPaymentsTodayLabelsTheFees() {
        let inPerson = IzzyAPI.Payment(id: "pi_1", amountCents: 4_000, description: "Haircut with Izzy", status: "succeeded", createdAt: TestClock.now)
        XCTAssertNil(inPerson.feeLabel)
        XCTAssertEqual(inPerson.listTitle, "Haircut with Izzy")
        let plain = IzzyAPI.Payment(id: "pi_2", amountCents: 500, status: "succeeded", createdAt: TestClock.now)
        XCTAssertEqual(plain.listTitle, "Card payment")
        let noShow = IzzyAPI.Payment(
            id: "pi_3", amountCents: 2_500, description: "No-show fee: Haircut with Julian, Tue, Nov 3 at 11:00 AM",
            status: "succeeded", createdAt: TestClock.now, kind: .noShowFee
        )
        XCTAssertEqual(noShow.feeLabel, "No-show fee")
        XCTAssertEqual(noShow.listTitle, "Haircut with Julian, Tue, Nov 3 at 11:00 AM", "the label already says what it is")
        let lateCancel = IzzyAPI.Payment(
            id: "pi_4", amountCents: 2_500, description: "Late cancellation fee: Haircut with Flowxbori, Tue, Nov 3 at 1:00 PM",
            status: "succeeded", createdAt: TestClock.now, kind: .lateCancelFee
        )
        XCTAssertEqual(lateCancel.feeLabel, "Late cancellation fee")
        XCTAssertEqual(lateCancel.listTitle, "Haircut with Flowxbori, Tue, Nov 3 at 1:00 PM")
        let bare = IzzyAPI.Payment(id: "pi_5", amountCents: 2_500, status: "succeeded", createdAt: TestClock.now, kind: .noShowFee)
        XCTAssertEqual(bare.listTitle, "No-show fee")
        let other = IzzyAPI.Payment(id: "pi_6", amountCents: 2_500, description: "Fee for Kim", status: "succeeded", createdAt: TestClock.now, kind: .lateCancelFee)
        XCTAssertEqual(other.listTitle, "Fee for Kim")
    }

    func testPaymentsTodayCountsFeesThatWentThroughOnly() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        _ = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        let checkout = CheckoutModel(
            api: harness.api, shopTime: TestClock.shopTime, clock: { TestClock.now },
            terminal: SimulatedPaymentTerminal(stepDelay: .zero), practiceTerminal: SimulatedPaymentTerminal(stepDelay: .zero),
            pending: PendingPayments(defaults: makeDefaults()), usesSampleServer: true, deviceSupportsTapToPay: true
        )
        await checkout.loadPayments()
        XCTAssertEqual(checkout.todaysPayments.map(\.amountCents), [3_500, 4_000], "Kim's fee, then Marcus's cut; Lee's declined fee isn't money in")
        XCTAssertEqual(checkout.todaysPayments.map(\.kind), [.noShowFee, .inPerson])
        XCTAssertEqual(checkout.todaysTotalCents, 7_500)
        XCTAssertEqual(checkout.todaysFeesCents, 3_500)
    }

    // MARK: Charging from the schedule

    func testChargingAFeeShowsItRightAwayAndUpdatesPaymentsToday() async throws {
        let harness = Harness(options: cardsOnFile())
        let api = ScriptedAPI(base: harness.api)
        let store = makeStore(api)
        await store.refresh()
        var charged: [String] = []
        store.onFeeCharged = { charged.append($0.customer.name) }
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })

        let updated = try await XCTUnwrapAsync(await store.chargeFee(for: kim))
        XCTAssertEqual(updated.noShowFee?.status, .charged)
        XCTAssertEqual(store.appointment(withID: kim.id)?.noShowFee?.status, .charged, "the details show it at once")
        XCTAssertTrue(store.chargingFee.isEmpty)
        XCTAssertNil(store.feeError(for: updated))
        XCTAssertEqual(charged, ["Kim Sample"])
        XCTAssertEqual(api.charges, [kim.id])
        XCTAssertNil(panel(try XCTUnwrap(store.appointment(withID: kim.id)))?.action, "no second charge offered")
        let fees = harness.server.payments.filter { $0.payment.kind.isFee }
        XCTAssertEqual(fees.map(\.payment.status), ["succeeded"])
    }

    func testTwoTapsAtOnceChargeOnce() async throws {
        let harness = Harness(options: cardsOnFile())
        let api = ScriptedAPI(base: harness.api)
        let gate = AsyncGate()
        api.chargeHandler = { [base = api.base] id in
            await gate.wait()
            return try await base.chargeNoShowFee(appointmentId: id)
        }
        let store = makeStore(api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let first = Task { await store.chargeFee(for: kim) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.chargingFee.contains(kim.id), "the button shows it's charging")
        let second = await store.chargeFee(for: kim)
        XCTAssertNil(second, "ignored while the first one runs")
        await gate.open()
        let result = await first.value
        XCTAssertEqual(result?.noShowFee?.status, .charged)
        XCTAssertEqual(api.charges.count, 1)
        XCTAssertEqual(harness.server.payments.filter { $0.payment.kind.isFee }.count, 1)
    }

    func testADeclineIsAnAnswerAndChargingAgainIsANewTry() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        var charged = 0
        store.onFeeCharged = { _ in charged += 1 }
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let declined = try await XCTUnwrapAsync(await store.chargeFee(for: kim))
        XCTAssertEqual(declined.noShowFee?.status, .declined)
        XCTAssertNil(store.feeError(for: declined), "a decline isn't an error: Stripe answered")
        XCTAssertEqual(charged, 0)
        let shown = try XCTUnwrap(panel(declined))
        XCTAssertEqual(shown.status, .declined(FakeServer.insufficientFundsMessage))
        XCTAssertEqual(AppointmentBadges(appointment: declined).spoken.last, "Fee declined")

        let again = try await XCTUnwrapAsync(await store.chargeFee(for: declined))
        XCTAssertEqual(again.noShowFee?.status, .charged)
        XCTAssertEqual(charged, 1)
    }

    func testAFeeThatNeedsTheClientSaysToAskThemToPayAtTheShop() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .needsAction
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let lee = try XCTUnwrap(store.appointments.first { $0.customer.name == "Lee Sample" })
        let answer = try await XCTUnwrapAsync(await store.chargeFee(for: lee))
        XCTAssertEqual(answer.noShowFee?.status, .needsAction)
        XCTAssertEqual(answer.noShowFee?.reason, .lateCancel)
        XCTAssertEqual(panel(answer)?.status, .needsClient(FakeServer.authenticationMessage))
        XCTAssertTrue(FakeServer.authenticationMessage.hasSuffix("Ask them to pay at the shop."))
    }

    func testAChargeWithoutAnAnswerShowsCheckAgainThenItIsCharged() async throws {
        var options = cardsOnFile()
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let none = await store.chargeFee(for: kim)
        XCTAssertNil(none)
        // The day was loaded again: the fee waits for Stripe, with Check again.
        let waiting = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(
            store.feeError(for: waiting),
            "We couldn't reach Stripe. Please try again. We don't know yet if the card was charged. Try again in a moment: the fee is never charged twice."
        )
        XCTAssertEqual(waiting.noShowFee?.status, .pending)
        XCTAssertEqual(panel(waiting)?.action?.title, "Check again")
        XCTAssertEqual(AppointmentBadges(appointment: waiting).spoken.last, "Fee not confirmed")

        let charged = try await XCTUnwrapAsync(await store.chargeFee(for: waiting))
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertNil(store.feeError(for: charged), "the error goes with the next try")
        XCTAssertNil(store.feeError(for: waiting), "even for the appointment as it was")
        XCTAssertEqual(harness.server.payments.filter { $0.payment.kind.isFee }.count, 1)
    }

    func testOfflineSaysNobodyKnowsYet() async throws {
        let harness = Harness(options: cardsOnFile())
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        harness.server.options.offline = true
        let none = await store.chargeFee(for: kim)
        XCTAssertNil(none)
        XCTAssertEqual(
            store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))),
            "We couldn't reach the server. We don't know yet if the card was charged. Try again in a moment: the fee is never charged twice."
        )
        XCTAssertEqual(store.refreshError, APIError.offline.userMessage, "it tried to load the day again")
        XCTAssertEqual(store.appointment(withID: kim.id)?.noShowFee?.status, IzzyAPI.NoShowFeeStatus.none, "what was shown stays")
    }

    func testARefusalSaysWhyInTheServersWords() async throws {
        var options = cardsOnFile()
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let jay = try XCTUnwrap(store.appointments.first { $0.customer.name == "Jay Sample" })
        _ = await store.chargeFee(for: jay)
        XCTAssertEqual(store.feeError(for: jay), "This booking has no card on file, so there's no fee to charge.")

        // Kim's try never reached Stripe, then Kim came after all: Check again settles it as not charged.
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        _ = await store.chargeFee(for: kim)
        _ = await store.setStatus(.booked, for: kim)
        let came = try XCTUnwrap(store.appointment(withID: kim.id))
        _ = await store.setStatus(.completed, for: came)
        let completed = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(panel(completed)?.action?.title, "Check again")
        _ = await store.chargeFee(for: completed)
        let settled = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(store.feeError(for: settled), "Nothing was charged. Mark the appointment as a no-show first.")
        XCTAssertEqual(settled.noShowFee?.status, IzzyAPI.NoShowFeeStatus.none, "loaded again: settled as not charged")
        XCTAssertNil(panel(settled)?.action)
        XCTAssertFalse(harness.server.payments.contains { $0.payment.kind.isFee })
    }

    func testAnErrorShowsOnlyWhileTheAppointmentStandsTheSame() async throws {
        var options = cardsOnFile()
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        _ = await store.chargeFee(for: kim)
        let waiting = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertNotNil(store.feeError(for: waiting))
        // Stripe's answer arrives some other way (the webhook, or Check again on another iPhone).
        _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        await store.refresh()
        let charged = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertNil(store.feeError(for: charged), "no old \"we don't know yet\" under \"charged\"")
        XCTAssertEqual(panel(charged)?.status, .charged(title: "No-show fee charged", detail: "$35 to Visa •••• 4242, Mon, Nov 2 at 11:05 AM."))

        // A refusal stays until the appointment changes: here, the owner reopens Jay's appointment.
        let jay = try XCTUnwrap(store.appointments.first { $0.customer.name == "Jay Sample" })
        _ = await store.chargeFee(for: jay)
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: jay.id))))
        await store.refresh()
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: jay.id))), "a refresh changes nothing")
        _ = await store.setStatus(.booked, for: jay)
        XCTAssertNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: jay.id))))
    }

    func testReopeningAFeeStripeHasntConfirmedSaysItMayHaveGoneThrough() throws {
        let harness = Harness(options: cardsOnFile())
        var kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        kim.noShowFee?.status = .pending
        kim.noShowFee?.reason = .noShow
        XCTAssertEqual(
            FeePanel.reopenWarning(for: kim, now: TestClock.now),
            "Stripe hasn't confirmed the $35 no-show fee yet. If it went through, reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        lee.noShowFee?.status = .pending
        lee.noShowFee?.reason = .lateCancel
        XCTAssertEqual(
            FeePanel.reopenWarning(for: lee, now: TestClock.now),
            "Stripe hasn't confirmed the $35 late cancellation fee yet. If it went through, reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
        // A declined late cancellation can still be charged until it's reopened.
        lee.noShowFee?.status = .declined
        XCTAssertEqual(
            FeePanel.reopenWarning(for: lee, now: TestClock.now),
            "Once it's reopened, the $35 late cancellation fee can't be charged any more."
        )
        lee.noShowFee?.status = .needsAction
        XCTAssertEqual(
            FeePanel.reopenWarning(for: lee, now: TestClock.now),
            "Once it's reopened, the $35 late cancellation fee can't be charged any more."
        )
        // A declined no-show can be marked again after reopening: nothing to say.
        kim.noShowFee?.status = .declined
        XCTAssertNil(FeePanel.reopenWarning(for: kim, now: TestClock.now))
    }

    func testTheNoShowHintSaysTheDayForAnotherDay() throws {
        let harness = Harness(options: cardsOnFile())
        var nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        let tomorrow = TestClock.today.adding(days: 1)
        nia.start = TestClock.at(14, 30, on: tomorrow)
        nia.end = TestClock.at(15, 15, on: tomorrow)
        XCTAssertEqual(
            FeePanel.noShowHint(for: nia, now: TestClock.now, shopTime: TestClock.shopTime),
            "You can mark a no-show once the appointment starts on Tue, Nov 3 at 2:30 PM. Until then, the client can still cancel in the app."
        )
        // Not for a booking without a card, nor once it's not booked.
        var walkIn = nia
        walkIn.card = nil
        walkIn.noShowFee = nil
        XCTAssertNil(FeePanel.noShowHint(for: walkIn, now: TestClock.now, shopTime: TestClock.shopTime))
        nia.status = .completed
        XCTAssertNil(FeePanel.noShowHint(for: nia, now: TestClock.now, shopTime: TestClock.shopTime))
    }

    func testFeeErrorMessages() {
        let unknown = "We don't know yet if the card was charged. Try again in a moment: the fee is never charged twice."
        XCTAssertEqual(ScheduleStore.feeErrorMessage(for: APIError.offline), "We couldn't reach the server. \(unknown)")
        XCTAssertEqual(
            ScheduleStore.feeErrorMessage(for: APIError.server(code: IzzyAPI.ErrorCode.serverError, message: "Stripe is busy.", status: 502)),
            "Stripe is busy. \(unknown)"
        )
        XCTAssertEqual(
            ScheduleStore.feeErrorMessage(for: APIError.server(code: APIError.networkErrorCode, message: "", status: 0)),
            "We couldn't reach the shop's server. Try again in a moment, or call the shop. \(unknown)"
        )
        XCTAssertEqual(
            ScheduleStore.feeErrorMessage(for: APIError.server(code: IzzyAPI.ErrorCode.notChargeable, message: "The shop cancelled this booking, so there's no fee.", status: 409)),
            "The shop cancelled this booking, so there's no fee."
        )
        XCTAssertEqual(ScheduleStore.feeErrorMessage(for: APIError.notConfigured(APIError.Feature.stripe)), APIError.notConfigured(APIError.Feature.stripe).userMessage)
        XCTAssertEqual(ScheduleStore.feeErrorMessage(for: APIError.unauthorized), APIError.unauthorized.userMessage)
    }

    func testANoShowWithACardWaitsForTheStartThenCanBeCharged() async throws {
        let harness = Harness(options: cardsOnFile())
        let store = makeStore(harness.api)
        await store.refresh()
        let nia = try XCTUnwrap(store.appointments.first { $0.customer.name == "Nia Sample" })
        let early = await store.setStatus(.noShow, for: nia)
        XCTAssertFalse(early)
        XCTAssertEqual(store.actionError, "You can mark a no-show once the appointment has started.")
        XCTAssertEqual(store.appointment(withID: nia.id)?.status, .booked)

        let later = Harness(options: cardsOnFile(), now: TestClock.at(14, 35))
        let laterStore = makeStore(later.api, now: TestClock.at(14, 35))
        await laterStore.refresh()
        let started = try XCTUnwrap(laterStore.appointments.first { $0.customer.name == "Nia Sample" })
        XCTAssertTrue(started.canMarkNoShow(at: laterStore.now))
        let marked = await laterStore.setStatus(.noShow, for: started)
        XCTAssertTrue(marked)
        let noShow = try XCTUnwrap(laterStore.appointment(withID: nia.id))
        XCTAssertEqual(panel(noShow, at: laterStore.now)?.action?.title, "Charge no-show fee ($35)")
        let charged = try await XCTUnwrapAsync(await laterStore.chargeFee(for: noShow))
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertEqual(charged.noShowFee?.reason, .noShow)
    }

    // MARK: The sample server

    func testTheSampleServerDeclinesLikeTheServer() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        let declined = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(declined.noShowFee?.status, .declined)
        XCTAssertEqual(declined.noShowFee?.message, "The card was declined: there isn't enough money on it.")
        XCTAssertEqual(declined.noShowFee?.reason, .noShow)
        XCTAssertNil(declined.noShowFee?.chargedAt)
        XCTAssertEqual(declined.payment, .unpaid)
        XCTAssertNil(harness.server.options.nextFeeAnswer, "Stripe said no once")
        let payments = try await harness.api.payments(on: TestClock.today)
        let tried = try XCTUnwrap(payments.first { $0.kind == .noShowFee })
        XCTAssertEqual(tried.status, "requires_payment_method", "listed with Stripe's status, so it isn't money in")
        XCTAssertEqual(tried.description, "No-show fee: Haircut with Flowxbori, Mon, Nov 2 at 10:00 AM")
        XCTAssertFalse(tried.isSucceeded)

        let charged = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertNil(charged.noShowFee?.message)
        XCTAssertEqual(charged.noShowFee?.chargedAt, TestClock.now)
        let after = try await harness.api.payments(on: TestClock.today)
        XCTAssertEqual(after.filter { $0.kind == .noShowFee }.map(\.status).sorted(), ["requires_payment_method", "succeeded"], "a new try, a new PaymentIntent")
    }

    func testTheSampleServerNeedsTheClientLikeTheServer() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .needsAction
        let harness = Harness(options: options)
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let answer = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(answer.noShowFee?.status, .needsAction)
        XCTAssertEqual(
            answer.noShowFee?.message,
            "The client's bank wants them to approve this charge, so it can't go through from here. Ask them to pay at the shop."
        )
        XCTAssertEqual(answer.noShowFee?.reason, .lateCancel)
        XCTAssertEqual(answer.chargeableFee(at: TestClock.now), .lateCancel, "it can be tried again")
        let payments = try await harness.api.payments(on: TestClock.today)
        XCTAssertEqual(payments.first { $0.kind == .lateCancelFee }?.status, "requires_payment_method")
        XCTAssertEqual(payments.first { $0.kind == .lateCancelFee }?.description, "Late cancellation fee: Haircut with Flowxbori, Mon, Nov 2 at 11:30 AM")
    }

    func testTheSampleUpcomingBookingWithACard() throws {
        var options = FakeServer.Options()
        options.upcomingWithCard = true
        let harness = Harness(options: options)
        let nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        XCTAssertEqual(nia.status, .booked)
        XCTAssertEqual(nia.start, TestClock.at(14, 30))
        XCTAssertEqual(nia.barberName, "Flowxbori")
        XCTAssertEqual(nia.card, IzzyAPI.CardOnFile(brand: "visa", last4: "4242"))
        XCTAssertEqual(nia.noShowFee, IzzyAPI.NoShowFee(amountCents: 3_500, fullPrice: true, lateCancelWindowMinutes: 60, reason: nil))
        XCTAssertNil(nia.chargeableFee(at: TestClock.now))
        XCTAssertNil(harness.appointment(named: "Kim Sample"), "only the option asked for")
    }

    func testFeeDescriptionsAreWordedLikeTheServers() throws {
        let harness = Harness(options: cardsOnFile())
        var kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        for (hour, minute, clock) in [(10, 0, "10:00 AM"), (11, 30, "11:30 AM"), (12, 0, "12:00 PM"), (14, 5, "2:05 PM"), (0, 30, "12:30 AM")] {
            kim.start = TestClock.at(hour, minute)
            XCTAssertEqual(
                FakeServer.feeDescription(kim, reason: .noShow, shopTime: TestClock.shopTime),
                "No-show fee: Haircut with Flowxbori, Mon, Nov 2 at \(clock)"
            )
        }
        kim.serviceName = String(repeating: "x", count: 300)
        XCTAssertEqual(FakeServer.feeDescription(kim, reason: .lateCancel, shopTime: TestClock.shopTime).count, 200, "cut to 200 like the server's")
    }

    func testLaunchArgumentsSetUpTheSampleServer() throws {
        func server(_ arguments: Set<String>) throws -> FakeServer {
            guard case .sample(let server) = AppEnvironment.sample(arguments: arguments).backend else {
                throw XCTSkip("not the sample server")
            }
            return server
        }
        let plain = try server([])
        XCTAssertFalse(plain.options.noShowWithCard || plain.options.lateCancelWithCard || plain.options.upcomingWithCard)
        XCTAssertNil(plain.options.nextFeeAnswer)
        XCTAssertFalse(plain.options.nextFeeChargeFails)
        XCTAssertTrue(plain.appointments.allSatisfy { $0.card == nil }, "the usual day has no cards on file")

        let cards = try server([LaunchArgument.cardsOnFile])
        XCTAssertTrue(cards.options.noShowWithCard && cards.options.lateCancelWithCard && cards.options.upcomingWithCard)
        XCTAssertEqual(Set(cards.appointments.filter { $0.card != nil }.map(\.customer.name)), ["Kim Sample", "Lee Sample", "Nia Sample"])

        XCTAssertEqual(try server([LaunchArgument.cardsOnFile, LaunchArgument.noShowDeclined]).options.nextFeeAnswer, .declined)
        XCTAssertEqual(try server([LaunchArgument.noShowNeedsAction]).options.nextFeeAnswer, .needsAction)
        XCTAssertTrue(try server([LaunchArgument.noShowUnreachable]).options.nextFeeChargeFails)
        XCTAssertEqual(LaunchArgument.cardsOnFile, "-fake-cards-on-file")
        XCTAssertEqual(LaunchArgument.noShowDeclined, "-fake-no-show-declined")
        XCTAssertEqual(LaunchArgument.noShowNeedsAction, "-fake-no-show-needs-action")
        XCTAssertEqual(LaunchArgument.noShowUnreachable, "-fake-no-show-unreachable")
    }

    func testTheWorkspaceReloadsPaymentsTodayWhenAFeeIsCharged() async throws {
        let environment = AppEnvironment.sample(arguments: [LaunchArgument.cardsOnFile], stepDelay: .zero)
        let workspace = Workspace(environment: environment, ownerKey: FakeServer.ownerKey, status: nil)
        await workspace.schedule.refresh()
        await workspace.checkout.loadPayments()
        XCTAssertEqual(workspace.checkout.todaysFeesCents, 0)
        let kim = try XCTUnwrap(workspace.schedule.appointments.first { $0.customer.name == "Kim Sample" })
        _ = await workspace.schedule.chargeFee(for: kim)
        let listed = await eventually { workspace.checkout.todaysFeesCents == 3_500 }
        XCTAssertTrue(listed, "Payments today lists the fee")
        XCTAssertTrue(workspace.checkout.todaysPayments.contains { $0.kind == .noShowFee })
    }
}

/// `XCTUnwrap` for a value an `async` call returns.
func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let unwrapped = try await value()
    return try XCTUnwrap(unwrapped, file: file, line: line)
}
