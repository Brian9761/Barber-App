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
        XCTAssertTrue(andre.canMarkNoShow(at: TestClock.now), "booked at the shop: no card, so no wait for the end")
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
        XCTAssertEqual(FeePanel.reopenWarning(for: lee, now: TestClock.now), Self.reopenLateCancelWarning)
    }

    /// What Reopen says first for a late cancellation that can still be charged.
    private static let reopenLateCancelWarning = "Once it's reopened, the $35 late cancellation fee can't be charged any more. "
        + "The client cancelled in the app, so a no-show fee can't be charged either."
    /// What Reopen says first for a booking the client cancelled in the app in time.
    private static let reopenCancelledInAppWarning = "The client cancelled this booking in the app, so once it's reopened, it can't be charged a no-show fee. "
        + "To keep a no-show fee, ask them to book again in the app instead."

    func testALateCancellationOnAnotherDaySaysWhichDay() throws {
        let harness = Harness(options: cardsOnFile())
        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        // Booked with a 24-hour window: Lee's Monday 11:30 AM haircut, cancelled Sunday at 3 PM.
        lee.noShowFee?.lateCancelWindowMinutes = 1_440
        lee.noShowFee?.customerCancelledAt = TestClock.at(15, 0, on: TestClock.today.adding(days: -1))
        XCTAssertTrue(lee.isCancelledLate)
        XCTAssertEqual(
            panel(lee)?.action?.confirmation?.message,
            "Late cancellation fee for Haircut with Flowxbori, Mon, Nov 2 at 11:30 AM: the client cancelled on Sun, Nov 1 at 3 PM, "
                + "less than 24 hours before. They agreed to it when booking."
        )
        // Cancelled the same day: the time says it all.
        lee.noShowFee?.customerCancelledAt = TestClock.at(9, 15)
        XCTAssertEqual(
            panel(lee)?.action?.confirmation?.message,
            "Late cancellation fee for Haircut with Flowxbori, Mon, Nov 2 at 11:30 AM: the client cancelled at 9:15 AM, "
                + "less than 24 hours before. They agreed to it when booking."
        )
    }

    func testReopeningABookingTheClientCancelledSaysANoShowFeeIsGone() async throws {
        let harness = Harness(options: cardsOnFile())
        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        // Cancelled the day before, in time (free); then the client calls to have the time back.
        lee.noShowFee?.customerCancelledAt = TestClock.at(10, 0, on: TestClock.today.adding(days: -1))
        XCTAssertNil(lee.chargeableFee(at: TestClock.now))
        XCTAssertEqual(FeePanel.reopenWarning(for: lee, now: TestClock.now), Self.reopenCancelledInAppWarning)
        // Also once the shop cancelled it after the client did: the server still keeps that they did.
        var shopToo = lee
        shopToo.cancelledBy = .shop
        XCTAssertEqual(FeePanel.reopenWarning(for: shopToo, now: TestClock.now), Self.reopenCancelledInAppWarning)
        // Not for one only the shop cancelled: reopened, it can still be a no-show.
        var shopOnly = shopToo
        shopOnly.noShowFee?.customerCancelledAt = nil
        XCTAssertNil(FeePanel.reopenWarning(for: shopOnly, now: TestClock.now))
        // Nor without a card on file, nor for a visit that isn't cancelled (reopening it changes nothing).
        var noCard = lee
        noCard.card = nil
        XCTAssertNil(FeePanel.reopenWarning(for: noCard, now: TestClock.now))
        var completed = lee
        completed.status = .completed
        completed.cancelledBy = nil
        XCTAssertNil(FeePanel.reopenWarning(for: completed, now: TestClock.now))

        // What the warning says is what the sample server (like the server) does: Lee cancelled late,
        // the owner reopens her booking, and she doesn't come (her 11:30 AM haircut ended at 12:15 PM).
        let later = TestClock.at(12, 20)
        let after = Harness(options: cardsOnFile(), now: later)
        let lateCancel = try XCTUnwrap(after.appointment(named: "Lee Sample"))
        XCTAssertEqual(FeePanel.reopenWarning(for: lateCancel, now: later), Self.reopenLateCancelWarning)
        _ = try await after.api.setStatus(.booked, ofAppointment: lateCancel.id)
        let noShow = try await after.api.setStatus(.noShow, ofAppointment: lateCancel.id)
        XCTAssertNil(noShow.chargeableFee(at: later))
        XCTAssertNil(panel(noShow, at: later)?.action)
        do {
            _ = try await after.api.chargeNoShowFee(appointmentId: lateCancel.id)
            XCTFail("a client who cancelled in the app is never charged a no-show fee")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, IzzyAPI.ErrorCode.notChargeable)
        }
    }

    func testThePaymentRowSaysAChargedFeeApartFromTheService() async throws {
        let harness = Harness(options: cardsOnFile())
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        var summary = PaymentSummary(appointment: andre)
        XCTAssertEqual(summary.title, "Not paid yet")
        XCTAssertEqual(summary.value, andre.priceLabel)
        XCTAssertNil(summary.feeNote)
        summary = PaymentSummary(appointment: try XCTUnwrap(harness.appointment(named: "Marcus Sample")))
        XCTAssertEqual(summary.title, "Paid")
        XCTAssertEqual(summary.value, "$40.00")
        XCTAssertNil(summary.feeNote)

        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(PaymentSummary(appointment: kim).title, "Not paid yet", "nothing charged yet")
        // Charged: the service still isn't paid, and the fee is said apart, so it isn't taken again.
        let charged = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        summary = PaymentSummary(appointment: charged)
        XCTAssertEqual(summary.title, "Service not paid")
        XCTAssertEqual(summary.value, "$35")
        XCTAssertEqual(summary.feeNote, "The $35 no-show fee was charged to the card on file.")
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let lateFee = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(PaymentSummary(appointment: lateFee).feeNote, "The $35 late cancellation fee was charged to the card on file.")
        // Only a fee Stripe charged counts.
        for status in [IzzyAPI.NoShowFeeStatus.declined, .needsAction, .pending, .none] {
            var other = charged
            other.noShowFee?.status = status
            XCTAssertEqual(PaymentSummary(appointment: other).title, "Not paid yet", "\(status)")
            XCTAssertNil(PaymentSummary(appointment: other).feeNote, "\(status)")
        }
        // Paid for the service as well: Paid, and the fee still said apart.
        var paidToo = charged
        paidToo.payment = IzzyAPI.AppointmentPayment(status: .paid, amountCents: 3_500, paidAt: TestClock.now)
        summary = PaymentSummary(appointment: paidToo)
        XCTAssertEqual(summary.title, "Paid")
        XCTAssertEqual(summary.value, "$35.00")
        XCTAssertEqual(summary.feeNote, "The $35 no-show fee was charged to the card on file.")
    }

    func testTurningProtectionOffKeepsTheFeesOfBookingsMadeWithACard() async throws {
        let harness = Harness(options: cardsOnFile())
        XCTAssertTrue(harness.server.noShowSettings.enabled, "the sample clients booked with it on")
        // Like the server, a fee follows the terms its booking was made with, never today's settings.
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(enabled: false, lateCancelEnabled: false))
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(panel(kim)?.action?.title, "Charge no-show fee ($35)")
        let charged = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        XCTAssertEqual(lee.noShowFee?.lateCancelWindowMinutes, 60, "the window it was booked with")
        XCTAssertEqual(panel(lee)?.action?.title, "Charge late cancellation fee ($35)")
        let lateFee = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(lateFee.noShowFee?.status, .charged)
        XCTAssertEqual(lateFee.noShowFee?.reason, .lateCancel)
        XCTAssertTrue(NoShowSettingsStore.offFooter.contains("you can still charge it"), "Settings says so")
    }

    func testWhenNoFeeCanBeChargedTheDetailsSayWhy() async throws {
        let harness = Harness(options: cardsOnFile())
        // Nia's 2:30 PM haircut hasn't ended (it ends at 3:15 PM), before its start or after it.
        let nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        for moment in [TestClock.now, TestClock.at(14, 35), TestClock.at(15, 14)] {
            XCTAssertFalse(nia.canMarkNoShow(at: moment))
            XCTAssertEqual(
                FeePanel.noShowHint(for: nia, now: moment, shopTime: TestClock.shopTime),
                "You can mark a no-show once the appointment ends at 3:15 PM. Until then, the client may still come."
            )
            XCTAssertEqual(
                panel(nia, at: moment)?.status,
                .notCharged(note: "If the client doesn't come, you can mark a no-show once the appointment has ended. Then you can charge the fee.")
            )
            XCTAssertNil(panel(nia, at: moment)?.action)
            XCTAssertNil(panel(nia, at: moment)?.footer)
        }
        // Once it has ended.
        let later = TestClock.at(15, 15)
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

        // Cancelled in time: free, and once reopened it can't be charged a no-show fee either.
        var early = lee
        early.noShowFee?.customerCancelledAt = TestClock.at(10, 30)
        XCTAssertFalse(early.isCancelledLate)
        XCTAssertEqual(panel(early)?.status, .notCharged(note: "The client cancelled at least 1 hour before, so there's no fee."))
        XCTAssertNil(panel(early)?.action)
        XCTAssertEqual(FeePanel.reopenWarning(for: early, now: TestClock.now), Self.reopenCancelledInAppWarning)

        // Marked a no-show before it ended (before the server refused that): her 10 AM haircut ends at 10:45.
        for moment in [TestClock.at(9, 30), TestClock.at(10, 44)] {
            XCTAssertEqual(panel(kim, at: moment)?.status, .notCharged(note: "The appointment hasn't ended yet, so it can't be a no-show."))
            XCTAssertNil(panel(kim, at: moment)?.action)
        }
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
        // Even once the visit is marked completed: Check again settles it with the server, and
        // then it only asks Stripe, so it says so.
        kim.status = .completed
        XCTAssertEqual(self.panel(kim)?.action?.title, "Check again")
        XCTAssertEqual(self.panel(kim)?.status, .pending(FeePanel.pendingCheckOnlyMessage))
    }

    func testCheckAgainSaysItCanStillSendTheChargeUntilTheAppointmentIsReopened() throws {
        // It finishes the try: Stripe first, then the same charge again if Stripe never got it.
        XCTAssertEqual(
            FeePanel.pendingMessage,
            "Stripe hasn't confirmed this charge yet. Check again finishes it: if it went through, it shows as charged, "
                + "and if Stripe never got it, it's sent now. To not charge it, reopen the appointment first."
        )
        XCTAssertFalse(FeePanel.pendingMessage.contains("to see if"), "it's not only a look")
        XCTAssertEqual(
            FeePanel.pendingCheckOnlyMessage,
            "Stripe hasn't confirmed this charge yet. Check again asks Stripe how it went: if it went through, it shows as charged, and if not, nothing is charged."
        )
        let harness = Harness(options: cardsOnFile())
        for name in ["Kim Sample", "Lee Sample"] {
            var appointment = try XCTUnwrap(harness.appointment(named: name))
            let reason = appointment.chargeableFee(at: TestClock.now)
            appointment.noShowFee?.status = .pending
            appointment.noShowFee?.reason = reason
            XCTAssertEqual(panel(appointment)?.status, .pending(FeePanel.pendingMessage), "\(name) can still be charged")
            // Reopened: nothing more can be charged, so Check again only asks.
            appointment.status = .booked
            appointment.cancelledBy = nil
            XCTAssertEqual(panel(appointment)?.status, .pending(FeePanel.pendingCheckOnlyMessage), "\(name) reopened")
            XCTAssertEqual(panel(appointment)?.action?.title, "Check again")
        }
    }

    func testADeclinedFeeThatCantBeTriedAgainSaysWhyAndOffersNoTry() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let tryAgain = "You can try the card again later, or ask the client to pay at the shop."

        // Lee's late cancellation is declined: it can be tried again while it stays cancelled...
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let declined = try await harness.api.chargeNoShowFee(appointmentId: lee.id)
        XCTAssertEqual(panel(declined)?.footer, tryAgain)
        XCTAssertEqual(panel(declined)?.action?.title, "Charge again ($35)")
        // ...but not once the shop reopens it: no button, and no "try again".
        let reopened = try await harness.api.setStatus(.booked, ofAppointment: lee.id)
        let shown = try XCTUnwrap(panel(reopened))
        XCTAssertEqual(shown.status, .declined(FakeServer.insufficientFundsMessage), "what Stripe said stays")
        XCTAssertNil(shown.action)
        XCTAssertEqual(shown.footer, "The client cancelled this booking in the app, so there's no fee.")

        // Kim's no-show is declined, then she comes after all and the visit is completed.
        harness.server.options.nextFeeAnswer = .declined
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        let booked = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        // Reopened after the start: marking a no-show again makes it chargeable again.
        XCTAssertNil(panel(booked)?.action)
        XCTAssertEqual(panel(booked)?.footer, "If the client didn't come, mark a no-show. Then you can charge the fee.")
        let completed = try await harness.api.setStatus(.completed, ofAppointment: kim.id)
        XCTAssertNil(panel(completed)?.action)
        XCTAssertEqual(panel(completed)?.footer, "The appointment is marked completed, so there's no fee to charge.")

        // The same for a fee the client's bank wanted them to approve.
        var needsClient = reopened
        needsClient.noShowFee?.status = .needsAction
        needsClient.noShowFee?.message = FakeServer.authenticationMessage
        XCTAssertNil(panel(needsClient)?.action)
        XCTAssertEqual(panel(needsClient)?.footer, "The client cancelled this booking in the app, so there's no fee.")
        var stillCancelled = declined
        stillCancelled.noShowFee?.status = .needsAction
        XCTAssertNil(panel(stillCancelled)?.footer, "it can be tried again: the status says what to do")
        XCTAssertEqual(panel(stillCancelled)?.action?.title, "Charge again ($35)")
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
        // VoiceOver hears "ending in", not each dot.
        XCTAssertEqual(try badges("Kim Sample"), ["No-show", "Card on file, Visa ending in 4242"])
        XCTAssertEqual(try badges("Lee Sample"), ["Cancelled late", "Card on file, Visa ending in 4242"])
        XCTAssertEqual(try badges("Nia Sample"), ["Booked", "Card on file, Visa ending in 4242"])

        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        XCTAssertEqual(AppointmentBadges(appointment: kim).items.map(\.tone), [.status(.noShow), .card])
        // On screen, the card as the spec words it: "Card on file · Visa •••• 4242".
        XCTAssertEqual(AppointmentBadges(appointment: kim).items.map(\.text), ["No-show", "Card on file · Visa •••• 4242"])
        XCTAssertEqual(FeePanel.spokenCard(IzzyAPI.CardOnFile(brand: "amex", last4: "0005")), "American Express ending in 0005")
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
        XCTAssertEqual(AppointmentBadges(appointment: other).spoken, ["No-show", "Card on file, Visa ending in 4242"])
        XCTAssertEqual(AppointmentBadges(appointment: other).items.last?.text, "Card on file · Visa •••• 4242")
        // A fee without the card's details (never sent either): just "Card on file".
        var bare = kim
        bare.card = nil
        XCTAssertEqual(AppointmentBadges(appointment: bare).items.last, AppointmentBadges.Item(text: "Card on file", tone: .card))
        XCTAssertEqual(AppointmentBadges(appointment: bare).spoken, ["No-show", "Card on file"])
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

    /// The server charged the card, but its answer was lost on the way back (a dropped connection, a
    /// timeout). Loading the day again shows the fee charged: no "we don't know yet" under it, no
    /// second charge offered, and Payments today is told.
    func testAChargeWhoseAnswerIsLostShowsItChargedWithNoError() async throws {
        let harness = Harness(options: cardsOnFile())
        let api = ScriptedAPI(base: harness.api)
        api.chargeHandler = { [base = api.base] id in
            _ = try await base.chargeNoShowFee(appointmentId: id)
            throw APIError.offline
        }
        let store = makeStore(api)
        await store.refresh()
        var charged: [String] = []
        store.onFeeCharged = { charged.append($0.customer.name) }
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })

        let none = await store.chargeFee(for: kim)
        XCTAssertNil(none, "no answer came back")
        let shown = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(shown.noShowFee?.status, .charged, "the day was loaded again")
        XCTAssertNil(store.feeError(for: shown), "no \"we don't know yet\" under a fee Stripe charged")
        XCTAssertNil(store.feeError(for: kim), "nor for the appointment as it was")
        XCTAssertEqual(panel(shown)?.status, .charged(title: "No-show fee charged", detail: "$35 to Visa •••• 4242, Mon, Nov 2 at 11:05 AM."))
        XCTAssertNil(panel(shown)?.action, "no second charge offered")
        XCTAssertEqual(charged, ["Kim Sample"], "Payments today is told once")
        await store.refresh()
        XCTAssertEqual(charged, ["Kim Sample"], "and not again by the next refresh")
        XCTAssertNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
        XCTAssertEqual(harness.server.payments.filter { $0.payment.kind.isFee }.map(\.payment.status), ["succeeded"])

        // The same when the answer is a timeout from the server's host (a 504) after Stripe charged it.
        api.chargeHandler = { [base = api.base] id in
            _ = try await base.chargeNoShowFee(appointmentId: id)
            throw APIError.server(code: IzzyAPI.ErrorCode.serverError, message: "The server took too long to answer.", status: 504)
        }
        let lee = try XCTUnwrap(store.appointments.first { $0.customer.name == "Lee Sample" })
        _ = await store.chargeFee(for: lee)
        let leeShown = try XCTUnwrap(store.appointment(withID: lee.id))
        XCTAssertEqual(leeShown.noShowFee?.status, .charged)
        XCTAssertNil(store.feeError(for: leeShown))
        XCTAssertEqual(panel(leeShown)?.status, .charged(title: "Late cancellation fee charged", detail: "$35 to Visa •••• 4242, Mon, Nov 2 at 11:05 AM."))
        XCTAssertEqual(charged, ["Kim Sample", "Lee Sample"])
    }

    /// The same for Stripe's "no": the decline (or "needs the client") shows with its reason, and a
    /// "we don't know yet" would contradict it, so there's none.
    func testADeclineWhoseAnswerIsLostShowsTheDeclineWithNoError() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let api = ScriptedAPI(base: harness.api)
        api.chargeHandler = { [base = api.base] id in
            _ = try await base.chargeNoShowFee(appointmentId: id)
            throw APIError.offline
        }
        let store = makeStore(api)
        await store.refresh()
        var charged = 0
        store.onFeeCharged = { _ in charged += 1 }
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })

        _ = await store.chargeFee(for: kim)
        let declined = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(declined.noShowFee?.status, .declined)
        XCTAssertNil(store.feeError(for: declined), "Stripe's answer is on screen")
        XCTAssertEqual(panel(declined)?.status, .declined(FakeServer.insufficientFundsMessage))
        XCTAssertEqual(panel(declined)?.action?.title, "Charge again ($35)")
        XCTAssertEqual(charged, 0)

        // "Needs the client" after a lost answer reads the same way (a dropped connection this time).
        harness.server.options.nextFeeAnswer = .needsAction
        api.chargeHandler = { [base = api.base] id in
            _ = try await base.chargeNoShowFee(appointmentId: id)
            throw APIError.server(code: APIError.networkErrorCode, message: "", status: 0)
        }
        let lee = try XCTUnwrap(store.appointments.first { $0.customer.name == "Lee Sample" })
        _ = await store.chargeFee(for: lee)
        let needsClient = try XCTUnwrap(store.appointment(withID: lee.id))
        XCTAssertEqual(needsClient.noShowFee?.status, .needsAction)
        XCTAssertNil(store.feeError(for: needsClient))
        XCTAssertEqual(panel(needsClient)?.status, .needsClient(FakeServer.authenticationMessage))
    }

    /// Charge again on a declined fee, and the request never reaches the server: loaded again, the
    /// fee shows the earlier decline. Nothing is on its way (the server marks a try pending before it
    /// asks Stripe), so there's no "we don't know yet", and Charge again is still there.
    func testATryThatNeverReachedTheServerLeavesTheEarlierDeclineWithNoError() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let api = ScriptedAPI(base: harness.api)
        let store = makeStore(api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let declined = try await XCTUnwrapAsync(await store.chargeFee(for: kim))
        XCTAssertEqual(declined.noShowFee?.status, .declined)

        api.chargeHandler = { _ in throw APIError.offline }
        _ = await store.chargeFee(for: declined)
        let shown = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(shown.noShowFee?.status, .declined)
        XCTAssertNil(store.feeError(for: shown))
        XCTAssertEqual(panel(shown)?.action?.title, "Charge again ($35)")
        XCTAssertEqual(harness.server.payments.filter { $0.payment.kind.isFee }.map(\.payment.status), ["requires_payment_method"], "only the first try reached Stripe")
    }

    /// When the day can't be loaded again either, nobody knows what happened to the new try, so the
    /// message stays under the earlier decline, until a load shows the fee as the server has it.
    func testAWeDontKnowYetUnderADeclineGoesOnceTheDayLoads() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let declined = try await XCTUnwrapAsync(await store.chargeFee(for: kim))

        harness.server.options.offline = true
        _ = await store.chargeFee(for: declined)
        let unknown = "We couldn't reach the server. We don't know yet if the card was charged. Try again in a moment: the fee is never charged twice."
        XCTAssertEqual(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))), unknown)
        await store.refresh()
        XCTAssertEqual(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))), unknown, "still offline: nothing new to say")

        harness.server.options.offline = false
        await store.refresh()
        let loaded = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(loaded.noShowFee?.status, .declined, "the try never reached the server")
        XCTAssertNil(store.feeError(for: loaded), "loaded again: the decline on screen is what happened")
    }

    /// A refusal is the server's own answer, so it stays under a decline: here Kim was reopened on
    /// another iPhone, and Charge again on this one is turned down.
    func testARefusalStaysUnderADecline() async throws {
        var options = cardsOnFile()
        options.nextFeeAnswer = .declined
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        let declined = try await XCTUnwrapAsync(await store.chargeFee(for: kim))
        _ = try await harness.api.setStatus(.booked, ofAppointment: kim.id)

        _ = await store.chargeFee(for: declined)
        let reopened = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(reopened.status, .booked, "loaded again")
        XCTAssertEqual(reopened.noShowFee?.status, .declined)
        XCTAssertEqual(store.feeError(for: reopened), "Mark the appointment as a no-show first.")
        await store.refresh()
        XCTAssertEqual(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))), "Mark the appointment as a no-show first.", "a refresh changes nothing")
    }

    /// A fee Check again couldn't confirm, which Stripe confirms later (the webhook, or Check again
    /// on another iPhone): the next load shows it charged, the message goes, and Payments today is
    /// told once. Loading another day and coming back tells it nothing new.
    func testAFeeConfirmedLaterTellsPaymentsTodayOnce() async throws {
        var options = cardsOnFile()
        options.nextFeeChargeFails = true
        let harness = Harness(options: options)
        let store = makeStore(harness.api)
        await store.refresh()
        var charged: [String] = []
        store.onFeeCharged = { charged.append($0.customer.name) }
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        _ = await store.chargeFee(for: kim)
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))), "pending: nobody knows yet")
        XCTAssertEqual(charged, [])

        _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        await store.refresh()
        let confirmed = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(confirmed.noShowFee?.status, .charged)
        XCTAssertNil(store.feeError(for: confirmed))
        XCTAssertEqual(charged, ["Kim Sample"])
        await store.refresh()
        store.showNextDay()
        await store.refresh()
        store.showToday()
        await store.refresh()
        XCTAssertEqual(charged, ["Kim Sample"], "told once")
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
        let pending = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(panel(pending)?.status, .pending(FeePanel.pendingMessage), "Check again would send it now")
        _ = await store.setStatus(.booked, for: pending)
        let came = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertNil(store.feeError(for: came), "about the no-show as it stood")
        XCTAssertEqual(panel(came)?.status, .pending(FeePanel.pendingCheckOnlyMessage), "reopened: it only asks Stripe now")
        _ = await store.setStatus(.completed, for: came)
        let completed = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(panel(completed)?.action?.title, "Check again")
        XCTAssertEqual(panel(completed)?.status, .pending(FeePanel.pendingCheckOnlyMessage))
        _ = await store.chargeFee(for: completed)
        let settled = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(store.feeError(for: settled), "Nothing was charged. The appointment is marked completed, so there's no fee to charge.")
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

    func testAFeeErrorGoesWithAStatusChangeAndDoesntComeBack() async throws {
        let harness = Harness(options: cardsOnFile())
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        // Charged while offline: nobody knows yet whether it went through.
        harness.server.options.offline = true
        _ = await store.chargeFee(for: kim)
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
        harness.server.options.offline = false

        // Kim walks in late: the owner reopens her appointment...
        let reopened = await store.setStatus(.booked, for: try XCTUnwrap(store.appointment(withID: kim.id)))
        XCTAssertTrue(reopened)
        XCTAssertNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
        // ...then she leaves before her cut, and the owner marks a no-show again. Nothing was tried
        // since, so the old "we don't know yet" isn't shown again.
        let marked = await store.setStatus(.noShow, for: try XCTUnwrap(store.appointment(withID: kim.id)))
        XCTAssertTrue(marked)
        let again = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(again.status, .noShow)
        XCTAssertEqual(again.noShowFee?.status, IzzyAPI.NoShowFeeStatus.none, "stands as it did when the message was said")
        XCTAssertNil(store.feeError(for: again))
        await store.refresh()
        XCTAssertNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))), "nor after a refresh")
        XCTAssertEqual(panel(again)?.action?.title, "Charge no-show fee ($35)")

        // A status change that doesn't go through changes nothing: the message stays.
        harness.server.options.offline = true
        _ = await store.chargeFee(for: again)
        let failedChange = await store.setStatus(.booked, for: again)
        XCTAssertFalse(failedChange)
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
    }

    func testAFeeErrorGoesOnceARefreshShowsTheAppointmentChangedElsewhere() async throws {
        let harness = Harness(options: cardsOnFile())
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        harness.server.options.offline = true
        _ = await store.chargeFee(for: kim)
        harness.server.options.offline = false
        XCTAssertNotNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
        // On another iPhone, reopened (seen here by a refresh), then a no-show again.
        _ = try await harness.api.setStatus(.booked, ofAppointment: kim.id)
        await store.refresh()
        XCTAssertNil(store.feeError(for: try XCTUnwrap(store.appointment(withID: kim.id))))
        _ = try await harness.api.setStatus(.noShow, ofAppointment: kim.id)
        await store.refresh()
        let again = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(again.status, .noShow)
        XCTAssertNil(store.feeError(for: again), "gone for good once it no longer applied")
    }

    func testNoChargeWhileTheStatusIsChanging() async throws {
        let harness = Harness(options: cardsOnFile())
        let api = ScriptedAPI(base: harness.api)
        let gate = AsyncGate()
        api.setStatusHandler = { [base = api.base] status, id in
            await gate.wait()
            return try await base.setStatus(status, ofAppointment: id)
        }
        let store = makeStore(api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        // Kim walks in late: the owner reopens her no-show on a slow connection...
        let reopening = Task { await store.setStatus(.booked, for: kim) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.updating.contains(kim.id))
        XCTAssertEqual(store.appointment(withID: kim.id)?.status, .noShow, "still shown as a no-show")
        // ...and taps Charge (or confirms it) before the answer comes: nothing is sent.
        let charged = await store.chargeFee(for: kim)
        XCTAssertNil(charged)
        XCTAssertTrue(api.charges.isEmpty)
        XCTAssertTrue(store.chargingFee.isEmpty)
        await gate.open()
        let reopened = await reopening.value
        XCTAssertTrue(reopened)
        let booked = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(booked.status, .booked)
        XCTAssertEqual(booked.noShowFee?.status, IzzyAPI.NoShowFeeStatus.none, "not charged")
        XCTAssertFalse(harness.server.payments.contains { $0.payment.kind.isFee })
        XCTAssertNil(store.feeError(for: booked))
    }

    func testNoStatusChangeWhileTheFeeIsCharging() async throws {
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
        let charging = Task { await store.chargeFee(for: kim) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.chargingFee.contains(kim.id))
        let changed = await store.setStatus(.booked, for: kim)
        XCTAssertFalse(changed, "the server decides the fee by the status: no change meanwhile")
        XCTAssertFalse(harness.server.calls.contains("setStatus"))
        XCTAssertTrue(store.updating.isEmpty)
        await gate.open()
        let charged = await charging.value
        XCTAssertEqual(charged?.noShowFee?.status, .charged)
        XCTAssertEqual(store.appointment(withID: kim.id)?.status, .noShow)
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
        XCTAssertEqual(FeePanel.reopenWarning(for: lee, now: TestClock.now), Self.reopenLateCancelWarning)
        lee.noShowFee?.status = .needsAction
        XCTAssertEqual(FeePanel.reopenWarning(for: lee, now: TestClock.now), Self.reopenLateCancelWarning)
        // A declined no-show can be marked again after reopening: nothing to say.
        kim.noShowFee?.status = .declined
        XCTAssertNil(FeePanel.reopenWarning(for: kim, now: TestClock.now))
    }

    /// What "Cancel appointment" adds for a booking with a card on file: the shop cancelling is never
    /// charged, but once a fee is charged (or may have been), cancelling doesn't refund it.
    func testCancellingByTheShopSaysWhatHappensToTheFee() async throws {
        let harness = Harness(options: cardsOnFile())
        let nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        XCTAssertEqual(FeePanel.shopCancelNote(for: nia), "There's no fee when the shop cancels.")
        XCTAssertEqual(FeePanel.shopCancelNote(for: nia), FeePanel.noFeeWhenTheShopCancels)
        let walkIn = try XCTUnwrap(harness.server.appointments.first { $0.card == nil })
        XCTAssertNil(FeePanel.shopCancelNote(for: walkIn), "no card on file: nothing to say about a fee")

        // Kim's no-show fee is charged, then the owner reopens her appointment and cancels it.
        let store = makeStore(harness.api)
        await store.refresh()
        let kim = try XCTUnwrap(store.appointments.first { $0.customer.name == "Kim Sample" })
        _ = await store.chargeFee(for: kim)
        _ = await store.setStatus(.booked, for: try XCTUnwrap(store.appointment(withID: kim.id)))
        let reopened = try XCTUnwrap(store.appointment(withID: kim.id))
        XCTAssertEqual(reopened.status, .booked)
        XCTAssertEqual(
            FeePanel.shopCancelNote(for: reopened),
            "The $35 no-show fee stays charged: cancelling doesn't refund it. Refunds are made in the Stripe Dashboard."
        )

        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        lee.status = .booked
        lee.cancelledBy = nil
        lee.noShowFee?.reason = .lateCancel
        lee.noShowFee?.status = .charged
        XCTAssertEqual(
            FeePanel.shopCancelNote(for: lee),
            "The $35 late cancellation fee stays charged: cancelling doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
        lee.noShowFee?.status = .pending
        XCTAssertEqual(
            FeePanel.shopCancelNote(for: lee),
            "Stripe hasn't confirmed the $35 late cancellation fee yet. If it went through, cancelling doesn't refund it. Refunds are made in the Stripe Dashboard."
        )
        // Declined, or needing the client: nothing was charged, and cancelling is free.
        for status in [IzzyAPI.NoShowFeeStatus.none, .declined, .needsAction] {
            lee.noShowFee?.status = status
            XCTAssertEqual(FeePanel.shopCancelNote(for: lee), "There's no fee when the shop cancels.", "\(status)")
        }
        lee.noShowFee = nil
        XCTAssertEqual(FeePanel.shopCancelNote(for: lee), "There's no fee when the shop cancels.", "a card without a fee")
    }

    func testTheNoShowHintSaysTheDayForAnotherDay() throws {
        let harness = Harness(options: cardsOnFile())
        var nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        let tomorrow = TestClock.today.adding(days: 1)
        nia.start = TestClock.at(14, 30, on: tomorrow)
        nia.end = TestClock.at(15, 15, on: tomorrow)
        XCTAssertEqual(
            FeePanel.noShowHint(for: nia, now: TestClock.now, shopTime: TestClock.shopTime),
            "You can mark a no-show once the appointment ends on Tue, Nov 3 at 3:15 PM. Until then, the client may still come."
        )
        // A late appointment that ends after midnight: the day it ends.
        nia.start = TestClock.at(23, 30)
        nia.end = TestClock.at(0, 15, on: tomorrow)
        XCTAssertEqual(
            FeePanel.noShowHint(for: nia, now: TestClock.now, shopTime: TestClock.shopTime),
            "You can mark a no-show once the appointment ends on Tue, Nov 3 at 12:15 AM. Until then, the client may still come."
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

    func testANoShowWithACardWaitsForTheEndThenCanBeCharged() async throws {
        // Nia's 2:30 PM haircut ends at 3:15 PM: before that, before her start or after it, she may still come.
        for moment in [TestClock.now, TestClock.at(14, 35), TestClock.at(15, 14)] {
            let harness = Harness(options: cardsOnFile(), now: moment)
            let store = makeStore(harness.api, now: moment)
            await store.refresh()
            let nia = try XCTUnwrap(store.appointments.first { $0.customer.name == "Nia Sample" })
            XCTAssertFalse(nia.canMarkNoShow(at: store.now))
            let early = await store.setStatus(.noShow, for: nia)
            XCTAssertFalse(early)
            XCTAssertEqual(store.actionError, "You can mark a no-show once the appointment has ended.")
            XCTAssertEqual(store.appointment(withID: nia.id)?.status, .booked)
        }

        let later = Harness(options: cardsOnFile(), now: TestClock.at(15, 15))
        let laterStore = makeStore(later.api, now: TestClock.at(15, 15))
        await laterStore.refresh()
        let ended = try XCTUnwrap(laterStore.appointments.first { $0.customer.name == "Nia Sample" })
        XCTAssertTrue(ended.canMarkNoShow(at: laterStore.now))
        let marked = await laterStore.setStatus(.noShow, for: ended)
        XCTAssertTrue(marked)
        let noShow = try XCTUnwrap(laterStore.appointment(withID: ended.id))
        XCTAssertEqual(panel(noShow, at: laterStore.now)?.action?.title, "Charge no-show fee ($35)")
        let charged = try await XCTUnwrapAsync(await laterStore.chargeFee(for: noShow))
        XCTAssertEqual(charged.noShowFee?.status, .charged)
        XCTAssertEqual(charged.noShowFee?.reason, .noShow)
    }

    /// A client who came (the visit marked completed) is never a no-show, even once it's reopened:
    /// the server answers 409 `already_completed`, and the details say it in its words.
    func testACompletedVisitWithACardNeverBecomesANoShow() async throws {
        let harness = Harness(options: cardsOnFile(), now: TestClock.at(15, 30))
        let store = makeStore(harness.api, now: TestClock.at(15, 30))
        await store.refresh()
        let nia = try XCTUnwrap(store.appointments.first { $0.customer.name == "Nia Sample" })
        let completed = await store.setStatus(.completed, for: nia)
        XCTAssertTrue(completed)
        let reopened = await store.setStatus(.booked, for: try XCTUnwrap(store.appointment(withID: nia.id)))
        XCTAssertTrue(reopened)
        let booked = try XCTUnwrap(store.appointment(withID: nia.id))
        XCTAssertTrue(booked.canMarkNoShow(at: store.now), "the app can't see that it was completed: the server says so")
        let marked = await store.setStatus(.noShow, for: booked)
        XCTAssertFalse(marked)
        XCTAssertEqual(store.actionError, "This appointment was marked completed, so it can't become a no-show.")
        XCTAssertEqual(store.appointment(withID: nia.id)?.status, .booked)
        XCTAssertNil(panel(booked, at: store.now)?.action)
    }

    /// No fee can be charged more than 7 days after the appointment's start; exactly 7 days after still counts.
    func testAFeeCanBeChargedForSevenDays() throws {
        let harness = Harness(options: cardsOnFile())
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        let lastMoment = kim.start.addingTimeInterval(7 * 24 * 60 * 60)
        XCTAssertEqual(kim.feeDeadline, lastMoment)
        XCTAssertEqual(panel(kim, at: lastMoment)?.action?.title, "Charge no-show fee ($35)")
        let tooLate = lastMoment.addingTimeInterval(60)
        let deadline = "It's more than 7 days after the appointment, so the fee can't be charged."
        XCTAssertEqual(panel(kim, at: tooLate)?.status, .notCharged(note: deadline))
        XCTAssertNil(panel(kim, at: tooLate)?.action)
        XCTAssertNil(panel(kim, at: tooLate)?.footer)
        // A late cancellation too.
        let lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        let leeTooLate = lee.start.addingTimeInterval(7 * 24 * 60 * 60 + 60)
        XCTAssertEqual(panel(lee, at: leeTooLate)?.status, .notCharged(note: deadline))
        XCTAssertNil(panel(lee, at: leeTooLate)?.action)
        // Still booked a week on: it can be marked a no-show, but the fee can't be charged, and the details say so.
        let nia = try XCTUnwrap(harness.appointment(named: "Nia Sample"))
        let weekOn = nia.start.addingTimeInterval(7 * 24 * 60 * 60 + 60)
        XCTAssertTrue(nia.canMarkNoShow(at: weekOn))
        XCTAssertEqual(panel(nia, at: weekOn)?.status, .notCharged(note: deadline))
        XCTAssertNil(panel(nia, at: weekOn)?.action)
    }

    /// Cancelling within 15 minutes of booking is free, even inside the window: no "Cancelled late",
    /// no fee, and the details say why.
    func testCancellingWithin15MinutesOfBookingIsntLate() throws {
        let harness = Harness(options: cardsOnFile())
        var lee = try XCTUnwrap(harness.appointment(named: "Lee Sample"))
        // Lee cancelled at 10:50 AM, 40 minutes before her 11:30 AM haircut.
        lee.createdAt = TestClock.at(10, 35)
        XCTAssertFalse(lee.isCancelledLate, "15 minutes after booking")
        XCTAssertEqual(AppointmentBadges(appointment: lee).items.first?.text, "Cancelled")
        XCTAssertEqual(panel(lee)?.status, .notCharged(note: "The client cancelled within 15 minutes of booking, so there's no fee."))
        XCTAssertNil(panel(lee)?.action)
        XCTAssertEqual(FeePanel.reopenWarning(for: lee, now: TestClock.now), Self.reopenCancelledInAppWarning, "free, like cancelling in time")
        lee.createdAt = TestClock.at(10, 34)
        XCTAssertTrue(lee.isCancelledLate, "16 minutes after booking")
        XCTAssertEqual(AppointmentBadges(appointment: lee).items.first?.text, "Cancelled late")
        XCTAssertEqual(panel(lee)?.action?.title, "Charge late cancellation fee ($35)")
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
        XCTAssertTrue(harness.server.noShowSettings.enabled, "booked with protection on, and it's still on")
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
        XCTAssertFalse(plain.options.loseNextFeeAnswer)
        XCTAssertTrue(plain.appointments.allSatisfy { $0.card == nil }, "the usual day has no cards on file")
        XCTAssertEqual(plain.noShowSettings, .default, "protection off, as the server starts")

        let cards = try server([LaunchArgument.cardsOnFile])
        XCTAssertTrue(cards.options.noShowWithCard && cards.options.lateCancelWithCard && cards.options.upcomingWithCard)
        XCTAssertEqual(Set(cards.appointments.filter { $0.card != nil }.map(\.customer.name)), ["Kim Sample", "Lee Sample", "Nia Sample"])
        XCTAssertEqual(cards.noShowSettings, IzzyAPI.NoShowSettings(enabled: true), "on: Settings reads the same as those bookings")

        XCTAssertEqual(try server([LaunchArgument.cardsOnFile, LaunchArgument.noShowDeclined]).options.nextFeeAnswer, .declined)
        XCTAssertEqual(try server([LaunchArgument.noShowNeedsAction]).options.nextFeeAnswer, .needsAction)
        XCTAssertTrue(try server([LaunchArgument.noShowUnreachable]).options.nextFeeChargeFails)
        XCTAssertTrue(try server([LaunchArgument.noShowAnswerLost]).options.loseNextFeeAnswer)
        XCTAssertEqual(LaunchArgument.cardsOnFile, "-fake-cards-on-file")
        XCTAssertEqual(LaunchArgument.noShowDeclined, "-fake-no-show-declined")
        XCTAssertEqual(LaunchArgument.noShowNeedsAction, "-fake-no-show-needs-action")
        XCTAssertEqual(LaunchArgument.noShowUnreachable, "-fake-no-show-unreachable")
        XCTAssertEqual(LaunchArgument.noShowAnswerLost, "-fake-no-show-answer-lost")
    }

    /// `-fake-no-show-answer-lost`: the sample server charges (or declines, with `nextFeeAnswer`) and
    /// records it like the server, then the answer is lost once, as if the phone went offline.
    func testTheSampleServerCanLoseAFeesAnswerAfterRecordingIt() async throws {
        var options = cardsOnFile()
        options.loseNextFeeAnswer = true
        let harness = Harness(options: options)
        let kim = try XCTUnwrap(harness.appointment(named: "Kim Sample"))
        do {
            _ = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
            XCTFail("the answer should be lost")
        } catch let error as APIError {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertEqual(harness.appointment(named: "Kim Sample")?.noShowFee?.status, .charged, "recorded before the answer was lost")
        XCTAssertFalse(harness.server.options.loseNextFeeAnswer, "only once")
        let again = try await harness.api.chargeNoShowFee(appointmentId: kim.id)
        XCTAssertEqual(again.noShowFee?.status, .charged, "charging again answers as it is")
        XCTAssertEqual(harness.server.payments.filter { $0.payment.kind.isFee }.count, 1, "never twice")

        var declining = cardsOnFile()
        declining.loseNextFeeAnswer = true
        declining.nextFeeAnswer = .declined
        let other = Harness(options: declining)
        let lee = try XCTUnwrap(other.appointment(named: "Lee Sample"))
        do {
            _ = try await other.api.chargeNoShowFee(appointmentId: lee.id)
            XCTFail("the answer should be lost")
        } catch let error as APIError {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertEqual(other.appointment(named: "Lee Sample")?.noShowFee?.status, .declined)
        XCTAssertEqual(other.appointment(named: "Lee Sample")?.noShowFee?.message, FakeServer.insufficientFundsMessage)
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

    func testTheWorkspaceReloadsPaymentsTodayWhenAChargesAnswerWasLost() async throws {
        let environment = AppEnvironment.sample(arguments: [LaunchArgument.cardsOnFile, LaunchArgument.noShowAnswerLost], stepDelay: .zero)
        let workspace = Workspace(environment: environment, ownerKey: FakeServer.ownerKey, status: nil)
        await workspace.schedule.refresh()
        await workspace.checkout.loadPayments()
        XCTAssertEqual(workspace.checkout.todaysFeesCents, 0)
        let kim = try XCTUnwrap(workspace.schedule.appointments.first { $0.customer.name == "Kim Sample" })
        let answer = await workspace.schedule.chargeFee(for: kim)
        XCTAssertNil(answer, "the answer was lost")
        let shown = try XCTUnwrap(workspace.schedule.appointment(withID: kim.id))
        XCTAssertEqual(shown.noShowFee?.status, .charged)
        XCTAssertNil(workspace.schedule.feeError(for: shown))
        let listed = await eventually { workspace.checkout.todaysFeesCents == 3_500 }
        XCTAssertTrue(listed, "Payments today lists the fee")
    }
}

/// `XCTUnwrap` for a value an `async` call returns.
func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let unwrapped = try await value()
    return try XCTUnwrap(unwrapped, file: file, line: line)
}
