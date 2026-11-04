import XCTest
@testable import IzzyClipzKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// No-show protection in the Kit: the models, the mirror of the server's fee rule and of which
/// fee a booking can be charged (both checked against the server's own cases), card tokens,
/// Stripe's way back to the app, and the client's requests.
final class NoShowModelTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testAnAppointmentWithACardOnFile() throws {
        let appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        XCTAssertEqual(appointment.card, IzzyAPI.CardOnFile(brand: "visa", last4: "4242"))
        XCTAssertEqual(appointment.card?.label, "Visa •••• 4242")
        XCTAssertEqual(appointment.noShowFee, IzzyAPI.NoShowFee(amountCents: 3500, status: .none, lateCancelWindowMinutes: 60))
        XCTAssertEqual(appointment.noShowFee?.amountLabel, "$35")
        XCTAssertEqual(appointment.noShowFee?.title, "No-show fee")
        XCTAssertEqual(appointment.noShowFee?.lateCancelStarts(before: appointment.start), utc(2026, 11, 2, 17))

        let owner = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json")).appointments
        XCTAssertNil(owner[0].card)
        XCTAssertNil(owner[0].noShowFee)
        XCTAssertEqual(owner[1].card?.label, "Mastercard •••• 4444")
        XCTAssertEqual(
            owner[1].noShowFee,
            IzzyAPI.NoShowFee(amountCents: 4500, status: .charged, chargedAt: utc(2026, 11, 2, 19, 5), lateCancelWindowMinutes: 60, reason: .noShow)
        )
        XCTAssertTrue(owner[1].noShowFee?.isCharged == true)
        // A client who cancelled half an hour before: a late cancellation the owner may charge.
        XCTAssertEqual(
            owner[3].noShowFee,
            IzzyAPI.NoShowFee(amountCents: 3500, customerCancelledAt: utc(2026, 11, 2, 22, 30), lateCancelWindowMinutes: 60, reason: .lateCancel)
        )
        XCTAssertEqual(owner[3].noShowFee?.title, "Late cancellation fee")
        XCTAssertEqual(owner[3].chargeableFee(at: utc(2026, 11, 2, 22, 31)), .lateCancel)

        let declined = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("no-show-fee-declined.json")).appointment
        XCTAssertEqual(declined.noShowFee?.status, .declined)
        XCTAssertEqual(declined.noShowFee?.message, "The card was declined: there isn't enough money on it.")
        XCTAssertEqual(declined.noShowFee?.reason, .noShow)
    }

    func testAFeeFromAServerBeforeLateCancellations() throws {
        let old = try decodeAPI(IzzyAPI.NoShowFee.self, #"{ "amountCents": 2000, "status": "none", "chargedAt": null, "message": null }"#)
        XCTAssertEqual(old, IzzyAPI.NoShowFee(amountCents: 2000))
        XCTAssertNil(old.lateCancelStarts(before: utc(2026, 11, 2, 18)), "cancelling is free until the start")
        // Written back with the new keys, as null.
        XCTAssertEqual(try encodeAPI(old), .object([
            "amountCents": .number(2000), "status": .string("none"), "chargedAt": .null, "message": .null,
            "customerCancelledAt": .null, "lateCancelWindowMinutes": .null, "reason": .null,
        ]))
        // A reason this version doesn't know reads as none.
        let future = try decodeAPI(
            IzzyAPI.NoShowFee.self,
            #"{ "amountCents": 2000, "status": "none", "chargedAt": null, "message": null, "customerCancelledAt": null, "lateCancelWindowMinutes": 60, "reason": "lateArrival" }"#
        )
        XCTAssertNil(future.reason)
        XCTAssertEqual(future.title, "No-show fee")
        XCTAssertEqual(IzzyAPI.NoShowFeeReason.allCases.map(\.rawValue), ["noShow", "lateCancel"])
        XCTAssertEqual(IzzyAPI.NoShowFeeReason.allCases.map(\.title), ["No-show fee", "Late cancellation fee"])
    }

    func testAnAppointmentFromAServerBeforeNoShowProtectionHasNoCard() throws {
        // The same appointment without the two new keys still decodes.
        var text = String(decoding: try kitFixture("booking-confirmation.json"), as: UTF8.self)
        text = text.replacingOccurrences(of: #","card": { "brand": "visa", "last4": "4242" }"#, with: "")
        let range = try XCTUnwrap(text.range(of: #""createdAt": "2026-10-31T17:05:09Z","#))
        let end = try XCTUnwrap(text.range(of: "\n  },", range: range.upperBound..<text.endIndex))
        text.replaceSubrange(range.lowerBound..<end.lowerBound, with: #""createdAt": "2026-10-31T17:05:09Z""#)
        let appointment = try decodeAPI(IzzyAPI.BookingConfirmation.self, text).appointment
        XCTAssertNil(appointment.card)
        XCTAssertNil(appointment.noShowFee)
        // And it's written back with both, as null, the way the server writes them now.
        let encoded = try encodeAPI(appointment)
        XCTAssertEqual(encoded["card"], .null)
        XCTAssertEqual(encoded["noShowFee"], .null)
    }

    func testFeeStatusesAndAnUnknownOneNeverReadsAsCharged() throws {
        XCTAssertEqual(IzzyAPI.NoShowFeeStatus.allCases.map(\.rawValue), ["none", "pending", "charged", "declined", "needsAction"])
        for status in IzzyAPI.NoShowFeeStatus.allCases {
            XCTAssertEqual(try decodeAPI(IzzyAPI.NoShowFeeStatus.self, "\"\(status.rawValue)\""), status)
        }
        XCTAssertEqual(try decodeAPI(IzzyAPI.NoShowFeeStatus.self, "\"refunded\""), .pending)
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowFee(amountCents: 2000, status: .needsAction, message: "Ask them to pay at the shop.", reason: .lateCancel)), .object([
            "amountCents": .number(2000), "status": .string("needsAction"), "chargedAt": .null, "message": .string("Ask them to pay at the shop."),
            "customerCancelledAt": .null, "lateCancelWindowMinutes": .null, "reason": .string("lateCancel"),
        ]))
    }

    func testWhenTheOwnerCanChargeTheFee() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(3_600)), "still booked")
        appointment.status = .noShow
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(-60)), "hasn't started")
        XCTAssertTrue(appointment.canChargeNoShowFee(at: start))
        for status in [IzzyAPI.NoShowFeeStatus.none, .pending, .declined, .needsAction] {
            appointment.noShowFee?.status = status
            XCTAssertTrue(appointment.canChargeNoShowFee(at: start.addingTimeInterval(600)), "\(status)")
        }
        appointment.noShowFee?.status = .charged
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(600)), "charged once")
        appointment.noShowFee?.status = .none
        appointment.card = nil
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(600)), "no card")
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = nil
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(600)), "no fee")
        XCTAssertEqual(appointment.feeCase(at: start.addingTimeInterval(600)), .refused("This booking has no card on file, so there's no fee to charge."))
    }

    func testWhichFeeTheOwnerCanCharge() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let minutes = { (m: Double) in start.addingTimeInterval(m * 60) }
        XCTAssertNil(appointment.chargeableFee(at: minutes(60)))
        XCTAssertEqual(appointment.feeCase(at: minutes(60)), .refused("Mark the appointment as a no-show first."))
        appointment.status = .noShow
        XCTAssertEqual(appointment.feeCase(at: minutes(-1)), .refused("The appointment hasn't started yet, so it can't be a no-show."))
        XCTAssertEqual(appointment.chargeableFee(at: minutes(20)), .noShow)

        // The client cancels in the app 30 minutes before: a late cancellation, chargeable right away.
        appointment.status = .cancelled
        appointment.cancelledBy = .customer
        appointment.noShowFee?.customerCancelledAt = minutes(-30)
        XCTAssertEqual(appointment.chargeableFee(at: minutes(-29)), .lateCancel)
        XCTAssertTrue(appointment.canChargeNoShowFee(at: minutes(-29)))
        appointment.noShowFee?.status = .charged
        XCTAssertNil(appointment.chargeableFee(at: minutes(-29)), "charged once")
        appointment.noShowFee?.status = .declined
        XCTAssertEqual(appointment.chargeableFee(at: minutes(-29)), .lateCancel, "a declined fee can be tried again")
        // Exactly an hour before is free.
        appointment.noShowFee?.customerCancelledAt = minutes(-60)
        XCTAssertEqual(appointment.feeCase(at: minutes(0)), .refused("The client cancelled at least 1 hour before, so there's no fee."))
        XCTAssertNil(appointment.chargeableFee(at: minutes(0)))
        // Booked while late cancellations were off: free however late.
        appointment.noShowFee?.customerCancelledAt = minutes(-5)
        appointment.noShowFee?.lateCancelWindowMinutes = nil
        XCTAssertEqual(appointment.feeCase(at: minutes(0)), .refused("The client cancelled this booking in the app, so there's no fee."))
        // The shop's cancellation, and a late one the shop reopened, are never charged.
        appointment.noShowFee?.lateCancelWindowMinutes = 60
        appointment.cancelledBy = .shop
        XCTAssertEqual(appointment.feeCase(at: minutes(0)), .refused("The shop cancelled this booking, so there's no fee."))
        appointment.status = .booked
        appointment.cancelledBy = nil
        XCTAssertEqual(appointment.feeCase(at: minutes(0)), .refused("The client cancelled this booking in the app, so there's no fee."))
        appointment.status = .noShow
        XCTAssertEqual(appointment.feeCase(at: minutes(20)), .refused("The client cancelled this booking in the app, so there's no fee."))
        XCTAssertFalse(appointment.canChargeNoShowFee(at: minutes(20)))
    }

    func testTheClientIsWarnedBeforeALateCancellation() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let minutes = { (m: Double) in start.addingTimeInterval(m * 60) }
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-120)))
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-60)), "exactly an hour before is still free")
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-59)), "Cancelling now, less than 1 hour before your appointment, may be charged $35.")
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-1)), "Cancelling now, less than 1 hour before your appointment, may be charged $35.")
        XCTAssertNil(appointment.lateCancelWarning(at: start), "it can't be cancelled in the app once it starts")
        appointment.noShowFee?.lateCancelWindowMinutes = 90
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-80)), "Cancelling now, less than 90 minutes before your appointment, may be charged $35.")
        appointment.noShowFee?.lateCancelWindowMinutes = nil
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "late cancellations weren't in the agreed policy")
        appointment.noShowFee?.lateCancelWindowMinutes = 60
        appointment.status = .cancelled
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "already cancelled")
        appointment.status = .booked
        appointment.card = nil
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "no card on file")
    }

    func testCardBrandNames() {
        let names = ["visa", "mastercard", "amex", "discover", "diners", "jcb", "unionpay", "cartes_bancaires", "eftpos_au", "link", "unknown", "VISA"]
            .map(IzzyAPI.cardBrandName)
        XCTAssertEqual(names, ["Visa", "Mastercard", "American Express", "Discover", "Diners Club", "JCB", "UnionPay", "Cartes Bancaires", "eftpos", "Link", "Card", "Visa"])
    }

    func testThePolicy() throws {
        let policy = try decoder.decode(IzzyAPI.NoShowPolicy.self, from: try kitFixture("no-show-policy.json"))
        XCTAssertTrue(policy.required)
        XCTAssertEqual(policy.feeLabel, "$55–$60")
        XCTAssertEqual(policy.lateCancelWindowMinutes, 60)
        XCTAssertTrue(policy.policyText?.contains("Cancelling in the app more than 1 hour before is free.") == true)
        XCTAssertEqual(policy.warning, IzzyAPI.NoShowWarning(
            title: "Full Service Cancellation & No-Show Fee",
            message: "Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($55–$60). Cancelling in the app more than 1 hour before is free."
        ))
        let single = IzzyAPI.NoShowPolicy(required: true, minFeeCents: 2000, maxFeeCents: 2000, policyText: "…")
        XCTAssertEqual(single.feeLabel, "$20")
        let none = try decoder.decode(IzzyAPI.NoShowPolicy.self, from: try kitFixture("no-show-policy-not-required.json"))
        XCTAssertEqual(none, .notRequired)
        XCTAssertNil(none.feeLabel)
        XCTAssertNil(none.warning)
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowPolicy.notRequired), .object([
            "required": .bool(false), "minFeeCents": .null, "maxFeeCents": .null, "policyText": .null,
            "lateCancelWindowMinutes": .null, "warning": .null,
        ]))
        // From a server before late cancellations and the warning.
        let old = try decodeAPI(IzzyAPI.NoShowPolicy.self, #"{ "required": true, "minFeeCents": 2000, "maxFeeCents": 2000, "policyText": "The policy." }"#)
        XCTAssertEqual(old, IzzyAPI.NoShowPolicy(required: true, minFeeCents: 2000, maxFeeCents: 2000, policyText: "The policy."))
    }

    func testASavedCardAndItsExpiry() throws {
        let card = try decoder.decode(IzzyAPI.SavedCardResponse.self, from: try kitFixture("card-saved.json")).card
        XCTAssertEqual(card, IzzyAPI.SavedCard(brand: "visa", last4: "4242", expMonth: 12, expYear: 2030))
        XCTAssertEqual(card.label, "Visa •••• 4242")
        XCTAssertEqual(card.expiryLabel, "Expires 12/30")
        XCTAssertEqual(IzzyAPI.SavedCard(brand: "amex", last4: "0005", expMonth: 3, expYear: 2031).expiryLabel, "Expires 3/31")

        let november = IzzyAPI.SavedCard(brand: "visa", last4: "0001", expMonth: 11, expYear: 2026)
        XCTAssertTrue(november.isValid(on: LocalDate("2026-11-30")!))
        XCTAssertFalse(november.isValid(on: LocalDate("2026-12-01")!))
        XCTAssertTrue(november.isValid(on: LocalDate("2025-12-31")!))
        XCTAssertFalse(november.isValid(on: LocalDate("2027-01-01")!))
        // By the shop's day: 11 PM on November 30 in Oceanside is already December 1 in UTC.
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertTrue(november.isValid(at: utc(2026, 12, 1, 7), in: pacific))
        XCTAssertFalse(november.isValid(at: utc(2026, 12, 1, 8), in: pacific))
    }

    func testCheckout() throws {
        let checkout = try decoder.decode(IzzyAPI.CardCheckout.self, from: try kitFixture("card-checkout.json"))
        XCTAssertEqual(checkout.url.absoluteString, "https://checkout.stripe.com/c/pay/cs_test_SampleSession01#sample")
        XCTAssertEqual(checkout.sessionId, "cs_test_SampleSession01")
        XCTAssertEqual(IzzyAPI.CardCheckout.callbackScheme, "izzyclipz")
        XCTAssertThrowsError(try decodeAPI(IzzyAPI.CardCheckout.self, #"{ "url": "javascript:alert(1)", "sessionId": "cs_test_x" }"#))
    }

    func testStripesWayBackToTheApp() {
        func result(_ text: String) -> IzzyAPI.CardCheckoutResult? {
            IzzyAPI.CardCheckoutResult(callbackURL: URL(string: text)!)
        }
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=cs_test_a1B2_c3"), .saved(sessionId: "cs_test_a1B2_c3"))
        XCTAssertEqual(result("IZZYCLIPZ://card-saved?session_id=cs_live_9"), .saved(sessionId: "cs_live_9"))
        XCTAssertEqual(result("izzyclipz://card-cancelled"), .cancelled)
        XCTAssertEqual(result("izzyclipz://card-failed"), .failed)
        // A saved link without a usable session id is a failure, not a card.
        XCTAssertEqual(result("izzyclipz://card-saved"), .failed)
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=pi_123"), .failed)
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=cs_"), .failed)
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=cs_test_%3Cx%3E"), .failed)
        // Not ours.
        XCTAssertNil(result("https://izzy-clipz-api.vercel.app/api/cards/return?session_id=cs_test_a"))
        XCTAssertNil(result("izzyclipz://booking"))
        XCTAssertNil(result("otherapp://card-saved?session_id=cs_test_a"))
    }

    func testCardTokensAreManageTokenShapedSecrets() throws {
        var generator = CountingGenerator()
        let token = IzzyAPI.CardToken.generate(using: &generator)
        XCTAssertEqual(token.rawValue.count, 43)
        XCTAssertNotNil(IzzyAPI.ManageToken(rawValue: token.rawValue))
        XCTAssertEqual(IzzyAPI.CardToken(rawValue: token.rawValue), token)
        XCTAssertNil(IzzyAPI.CardToken(rawValue: "short"))
        XCTAssertNil(IzzyAPI.CardToken(rawValue: String(token.rawValue.dropLast()) + "B"), "unused bits set")
        XCTAssertNotEqual(IzzyAPI.CardToken.generate(), IzzyAPI.CardToken.generate())
        XCTAssertEqual(String(describing: token), "CardToken(<redacted>)")
        let agreement = IzzyAPI.NoShowAgreement(cardToken: token, policyText: "The policy.")
        XCTAssertFalse(String(describing: agreement).contains(token.rawValue))
        // Kept in the Keychain as its raw value.
        let data = try JSONEncoder().encode(token)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"\(token.rawValue)\"")
        XCTAssertEqual(try JSONDecoder().decode(IzzyAPI.CardToken.self, from: data), token)
        XCTAssertThrowsError(try JSONDecoder().decode(IzzyAPI.CardToken.self, from: Data("\"nope\"".utf8)))
    }

    func testSettingsAndTheirUpdate() throws {
        let settings = try decoder.decode(IzzyAPI.NoShowSettingsResponse.self, from: try kitFixture("no-show-settings.json")).noShowSettings
        XCTAssertEqual(settings, .default)
        // Off until the owner turns it on; then the full price, and late cancellations within 1 hour.
        XCTAssertEqual(settings, IzzyAPI.NoShowSettings(
            enabled: false, feeMode: .percent, percent: 100, flatCents: 2_000, lateCancelEnabled: true, lateCancelWindowMinutes: 60
        ))
        // The preview: "A $40 haircut: $40".
        XCTAssertEqual(settings.feeCents(for: .dollars(40)), 4_000)
        XCTAssertNil(settings.feeCents(for: .includedWithCut))
        // From a server before late cancellations: it never charged them.
        let old = try decodeAPI(IzzyAPI.NoShowSettings.self, #"{ "enabled": true, "feeMode": "percent", "percent": 50, "flatCents": 2000 }"#)
        XCTAssertEqual(old, IzzyAPI.NoShowSettings(enabled: true, percent: 50, lateCancelEnabled: false))

        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowSettingsUpdate(percent: 40)), .object(["percent": .number(40)]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowSettingsUpdate()), .object([:]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowSettingsUpdate(lateCancelEnabled: false, lateCancelWindowMinutes: 120)), .object([
            "lateCancelEnabled": .bool(false), "lateCancelWindowMinutes": .number(120),
        ]))
        let edited = IzzyAPI.NoShowSettings(enabled: true, feeMode: .flat, percent: 30, flatCents: 2_500, lateCancelEnabled: false, lateCancelWindowMinutes: 180)
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowSettingsUpdate.replacing(with: edited)), .object([
            "enabled": .bool(true), "feeMode": .string("flat"), "percent": .number(30), "flatCents": .number(2_500),
            "lateCancelEnabled": .bool(false), "lateCancelWindowMinutes": .number(180),
        ]))
        XCTAssertEqual(IzzyAPI.NoShowSettingsUpdate.replacing(with: edited).applied(to: .default), edited)
        XCTAssertEqual(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 30).applied(to: edited), IzzyAPI.NoShowSettings(
            enabled: true, feeMode: .flat, percent: 30, flatCents: 2_500, lateCancelEnabled: false, lateCancelWindowMinutes: 30
        ))
        XCTAssertEqual(IzzyAPI.NoShowSettingsUpdate().applied(to: edited), edited)
        XCTAssertTrue(IzzyAPI.NoShowSettingsUpdate().isEmpty)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(enabled: true).isEmpty)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(lateCancelEnabled: false).isEmpty)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 60).isEmpty)
        XCTAssertTrue(IzzyAPI.NoShowSettingsUpdate(percent: 1, flatCents: 50).isValid)
        XCTAssertTrue(IzzyAPI.NoShowSettingsUpdate(percent: 100, flatCents: 50_000).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(percent: 0).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(percent: 101).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(flatCents: 49).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(flatCents: 50_001).isValid)
        XCTAssertTrue(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 30).isValid)
        XCTAssertTrue(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 2_880).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 29).isValid)
        XCTAssertFalse(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 2_881).isValid)
    }

    func testPaymentKinds() throws {
        let payments = try decoder.decode(IzzyAPI.PaymentsResponse.self, from: try kitFixture("payments.json")).payments
        XCTAssertEqual(payments.map(\.kind), [.inPerson, .noShowFee, .lateCancelFee])
        XCTAssertEqual(payments.map(\.kind.title), ["Card payment", "No-show fee", "Late cancellation fee"])
        XCTAssertEqual(payments.map(\.kind.isFee), [false, true, true])
        XCTAssertEqual(IzzyAPI.PaymentKind(feeReason: .noShow), .noShowFee)
        XCTAssertEqual(IzzyAPI.PaymentKind(feeReason: .lateCancel), .lateCancelFee)
        // From a server before no-show protection, or a kind this version doesn't know: in person.
        let old = #"{ "id": "pi_1", "amountCents": 500, "description": null, "appointmentId": null, "status": "succeeded", "createdAt": "2026-11-02T19:00:00Z" }"#
        XCTAssertEqual(try decodeAPI(IzzyAPI.Payment.self, old).kind, .inPerson)
        let future = old.replacingOccurrences(of: #""status""#, with: #""kind": "giftCard", "status""#)
        XCTAssertEqual(try decodeAPI(IzzyAPI.Payment.self, future).kind, .inPerson)
        XCTAssertEqual(try encodeAPI(IzzyAPI.Payment(id: "pi_1", amountCents: 500, status: "succeeded", createdAt: utc(2026, 11, 2, 19), kind: .noShowFee))["kind"], .string("noShowFee"))
    }

    func testTheNewErrorCodes() throws {
        let required = APIError.fromResponse(status: 400, body: Data(#"{"error":{"code":"card_required","message":"That card expires before your appointment. Add another card."}}"#.utf8))
        XCTAssertEqual(required, .cardRequired(message: "That card expires before your appointment. Add another card."))
        XCTAssertEqual(required.code, "card_required")
        XCTAssertEqual(required.userMessage, "That card expires before your appointment. Add another card.")
        XCTAssertFalse(required.isRetryable)
        XCTAssertEqual(APIError.cardRequired(message: " ").userMessage, "Add a card to book this time. You won't be charged now.")

        let changed = APIError(code: "policy_changed", message: "The no-show policy for this booking just changed. Check it and book again.", status: 409)
        XCTAssertEqual(changed, .policyChanged(message: "The no-show policy for this booking just changed. Check it and book again."))
        XCTAssertEqual(changed.code, IzzyAPI.ErrorCode.policyChanged)
        XCTAssertEqual(APIError.policyChanged(message: "").userMessage, "The no-show policy for this booking just changed. Check it and book again.")

        let notChargeable = APIError(code: "not_chargeable", message: "Mark the appointment as a no-show first.", status: 409)
        XCTAssertEqual(notChargeable, .server(code: IzzyAPI.ErrorCode.notChargeable, message: "Mark the appointment as a no-show first.", status: 409))
        XCTAssertEqual(notChargeable.userMessage, "Mark the appointment as a no-show first.")

        let notStarted = APIError(code: "not_started", message: "You can mark a no-show once the appointment has started.", status: 409)
        XCTAssertEqual(notStarted, .server(code: IzzyAPI.ErrorCode.notStarted, message: "You can mark a no-show once the appointment has started.", status: 409))
        XCTAssertEqual(notStarted.userMessage, "You can mark a no-show once the appointment has started.")
        XCTAssertFalse(notStarted.isRetryable)
    }
}

/// The Kit's copy of the fee rule and the policy wording must give exactly what the server does,
/// for every case the server's tests wrote down (`server/test/fixtures/no-show-rule.json`).
final class NoShowRuleTests: XCTestCase {
    struct RuleDocument: Decodable {
        struct Fee: Decodable {
            let settings: IzzyAPI.NoShowSettings
            let priceCents: Int
            let priceKind: String
            let feeCents: Int?
        }

        struct Policy: Decodable {
            let settings: IzzyAPI.NoShowSettings
            let minFeeCents: Int
            let maxFeeCents: Int
            let policyText: String
            let warning: IzzyAPI.NoShowWarning
        }

        struct Window: Decodable {
            let minutes: Int
            let label: String
        }

        let fees: [Fee]
        let policies: [Policy]
        let windows: [Window]
    }

    func testTheKitMatchesTheServersRule() throws {
        let url = TestPaths.repository.appendingPathComponent("server/test/fixtures/no-show-rule.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No server rule fixture at \(url.path); the server's tests write it.")
        }
        let document = try JSONDecoder().decode(RuleDocument.self, from: data)
        XCTAssertGreaterThan(document.fees.count, 50)
        XCTAssertGreaterThan(document.policies.count, 10)
        for fee in document.fees {
            let kit = IzzyAPI.NoShowRule.feeCents(priceCents: fee.priceCents, includedWithCut: fee.priceKind == "includedWithCut", settings: fee.settings)
            XCTAssertEqual(kit, fee.feeCents, "\(fee.priceKind) \(fee.priceCents)¢ with \(fee.settings)")
        }
        XCTAssertTrue(document.policies.contains { !$0.settings.lateCancelEnabled }, "both kinds of policy")
        XCTAssertTrue(document.policies.contains { $0.settings.lateCancelEnabled })
        for policy in document.policies {
            XCTAssertEqual(
                IzzyAPI.NoShowRule.policyText(minFeeCents: policy.minFeeCents, maxFeeCents: policy.maxFeeCents, settings: policy.settings),
                policy.policyText
            )
            XCTAssertEqual(
                IzzyAPI.NoShowRule.warning(minFeeCents: policy.minFeeCents, maxFeeCents: policy.maxFeeCents, settings: policy.settings),
                policy.warning
            )
        }
        XCTAssertGreaterThan(document.windows.count, 5)
        for window in document.windows {
            XCTAssertEqual(IzzyAPI.NoShowRule.windowLabel(minutes: window.minutes), window.label)
        }
    }

    struct FeeCasesDocument: Decodable {
        struct Case: Decodable {
            let name: String
            let status: IzzyAPI.AppointmentStatus
            let cancelledBy: IzzyAPI.CancelledBy?
            let start: Date
            let customerCancelledAt: Date?
            let lateCancelWindowMinutes: Int?
            let reason: IzzyAPI.NoShowFeeReason?
            let refusal: String?
        }

        let cases: [Case]
        let notStarted: String
    }

    /// Which fee a booking can be charged: the Kit (the Business app's charge button, and the
    /// fakes' answers) says exactly what the server does, for every case its tests wrote down.
    func testTheKitMatchesTheServersFeeCases() throws {
        let url = TestPaths.repository.appendingPathComponent("server/test/fixtures/fee-cases.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No server fee cases at \(url.path); the server's tests write them.")
        }
        let document = try IzzyAPI.makeDecoder().decode(FeeCasesDocument.self, from: data)
        XCTAssertGreaterThan(document.cases.count, 10)
        XCTAssertEqual(document.notStarted, IzzyAPI.NoShowRule.notStartedMessage)
        let template = try IzzyAPI.makeDecoder().decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        for c in document.cases {
            let expected: IzzyAPI.NoShowRule.FeeCase = c.reason.map { .chargeable($0) } ?? .refused(c.refusal ?? "")
            XCTAssertEqual(
                IzzyAPI.NoShowRule.feeCase(
                    status: c.status, cancelledBy: c.cancelledBy, start: c.start,
                    customerCancelledAt: c.customerCancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes
                ),
                expected,
                c.name
            )
            // The same through an appointment, after its start (a no-show needs that).
            var appointment = template
            appointment.status = c.status
            appointment.cancelledBy = c.cancelledBy
            appointment.start = c.start
            appointment.noShowFee?.customerCancelledAt = c.customerCancelledAt
            appointment.noShowFee?.lateCancelWindowMinutes = c.lateCancelWindowMinutes
            XCTAssertEqual(appointment.feeCase(at: c.start.addingTimeInterval(1_200)), expected, c.name)
            XCTAssertEqual(appointment.chargeableFee(at: c.start.addingTimeInterval(1_200)), c.reason, c.name)
            if c.reason == .noShow {
                XCTAssertEqual(appointment.feeCase(at: c.start.addingTimeInterval(-60)), .refused(document.notStarted), c.name)
            }
        }
    }

    func testTheRuleItself() {
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(35), settings: .default), 3_500, "the full price to start")
        let half = IzzyAPI.NoShowSettings(percent: 50)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(35), settings: half), 1_750)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(priceCents: 1_999, includedWithCut: false, settings: half), 1_000)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(priceCents: 99, includedWithCut: false, settings: half), 50)
        XCTAssertNil(IzzyAPI.NoShowRule.feeCents(priceCents: 98, includedWithCut: false, settings: half))
        XCTAssertNil(IzzyAPI.NoShowRule.feeCents(priceCents: 0, includedWithCut: false, settings: half))
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .startingAt(dollars: 80), settings: half), 4_000)
        XCTAssertNil(IzzyAPI.NoShowRule.feeCents(for: .includedWithCut, settings: IzzyAPI.NoShowSettings(feeMode: .flat)))
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(16), settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_500)), 2_500)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeLabel(minCents: 1_750, maxCents: 2_250), "$17.50–$22.50")
        XCTAssertEqual(
            IzzyAPI.NoShowRule.policyText(minFeeCents: 2_000, maxFeeCents: 2_000, settings: IzzyAPI.NoShowSettings(percent: 50, lateCancelEnabled: false)),
            "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $20 (50% of the service) to this card. Cancelling in the app before your appointment is free."
        )
        XCTAssertEqual(
            IzzyAPI.NoShowRule.policyText(minFeeCents: 4_000, maxFeeCents: 4_000, settings: .default),
            "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $40 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free."
        )
        XCTAssertEqual(IzzyAPI.NoShowRule.warning(minFeeCents: 4_000, maxFeeCents: 4_000, settings: .default), IzzyAPI.NoShowWarning(
            title: "Full Service Cancellation & No-Show Fee",
            message: "Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($40). Cancelling in the app more than 1 hour before is free."
        ))
        XCTAssertEqual(IzzyAPI.NoShowRule.warning(minFeeCents: 2_500, maxFeeCents: 2_500, settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_500, lateCancelWindowMinutes: 120)).title, "Late Cancellation & No-Show Fee")
        XCTAssertEqual(IzzyAPI.NoShowRule.warning(minFeeCents: 4_000, maxFeeCents: 4_000, settings: IzzyAPI.NoShowSettings(lateCancelEnabled: false)), IzzyAPI.NoShowWarning(
            title: "No-Show Fee",
            message: "Not showing up is charged the full service price ($40). Cancelling in the app before your appointment is free."
        ))
        XCTAssertEqual([30, 60, 90, 120, 2_880].map(IzzyAPI.NoShowRule.windowLabel(minutes:)), ["30 minutes", "1 hour", "90 minutes", "2 hours", "48 hours"])
        XCTAssertEqual(IzzyAPI.NoShowRule.lateCancelWindowRange, 30...2_880)
        let start = utc(2026, 11, 3, 18)
        XCTAssertTrue(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: start.addingTimeInterval(-3_599), lateCancelWindowMinutes: 60))
        XCTAssertFalse(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: start.addingTimeInterval(-3_600), lateCancelWindowMinutes: 60))
        XCTAssertFalse(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: start.addingTimeInterval(-60), lateCancelWindowMinutes: nil))
        XCTAssertFalse(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: nil, lateCancelWindowMinutes: 60))
    }
}

/// The client's no-show requests, checked byte for byte against the server's contract.
final class NoShowClientTests: XCTestCase {
    typealias Reply = StubURLProtocol.Reply
    let ownerKey = "owner-key-0123456789abcdef0123456789abcdef"
    var client: IzzyAPIClient!

    override func setUp() {
        super.setUp()
        client = IzzyAPIClient(baseURL: URL(string: "https://api.test")!, session: StubURLProtocol.session(), ownerKey: ownerKey)
        StubURLProtocol.reply { _ in Reply() }
    }

    func only(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Sent {
        let sent = StubURLProtocol.sent
        XCTAssertEqual(sent.count, 1, "requests sent", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    func testThePolicyForABarberOrAnyBarber() async throws {
        StubURLProtocol.reply { _ in .fixture("no-show-policy.json") }
        let policy = try await client.noShowPolicy(for: .anyBarber(serviceId: "haircut-and-beard"))
        XCTAssertEqual(policy.minFeeCents, 5_500)
        XCTAssertEqual(policy.warning?.title, "Full Service Cancellation & No-Show Fee")
        var sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/no-show-policy")
        XCTAssertEqual(sent.query, "serviceId=haircut-and-beard&barberId=any")
        XCTAssertNil(sent.header("Authorization"))
        XCTAssertNil(sent.body)

        StubURLProtocol.reply { _ in .fixture("no-show-policy-not-required.json") }
        _ = try await client.noShowPolicy(for: .offering(id: "carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb"))
        sent = try only()
        XCTAssertEqual(sent.query, "offeringId=carlos-rafael%2F0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb")
    }

    func testStartingACheckoutSendsTheCardTokenAndTheTarget() async throws {
        StubURLProtocol.reply { _ in .fixture("card-checkout.json", status: 201) }
        let token = IzzyAPI.CardToken.generate()
        let checkout = try await client.startCardCheckout(for: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"), token: token)
        XCTAssertEqual(checkout.sessionId, "cs_test_SampleSession01")
        let sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/cards/checkout")
        XCTAssertEqual(sent.header("X-Card-Token"), token.rawValue)
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
        XCTAssertNil(sent.header("Authorization"), "public, even from a client with an owner key")
        XCTAssertNil(sent.header("X-Manage-Token"))
        XCTAssertEqual(sent.json, .object(["offeringId": .string("flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a")]))

        StubURLProtocol.reply { _ in .fixture("card-checkout.json", status: 201) }
        _ = try await client.startCardCheckout(for: .anyBarber(serviceId: "haircut"), token: token)
        XCTAssertEqual(try only().json, .object(["serviceId": .string("haircut"), "barberId": .string("any")]))
    }

    func testSavingTheCardAnswers201Or200TheSameWay() async throws {
        let token = IzzyAPI.CardToken.generate()
        for status in [201, 200] {
            StubURLProtocol.reply { _ in .fixture("card-saved.json", status: status) }
            let card = try await client.saveCard(sessionId: "cs_test_SampleSession01", token: token)
            XCTAssertEqual(card.label, "Visa •••• 4242")
            let sent = try only()
            XCTAssertEqual(sent.method, "POST")
            XCTAssertEqual(sent.path, "/api/cards")
            XCTAssertEqual(sent.header("X-Card-Token"), token.rawValue)
            XCTAssertEqual(sent.json, .object(["sessionId": .string("cs_test_SampleSession01")]))
        }
        StubURLProtocol.reply { _ in .json(404, #"{"error":{"code":"not_found","message":"We couldn't find that card. Add it again."}}"#) }
        do {
            _ = try await client.saveCard(sessionId: "cs_test_x", token: token)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: "not_found", message: "We couldn't find that card. Add it again.", status: 404))
        }
    }

    func testAProtectedBookingSendsTheCardTokenAndTheExactPolicy() async throws {
        StubURLProtocol.reply { _ in .fixture("booking-confirmation.json", status: 201) }
        let manage = IzzyAPI.ManageToken.generate()
        let card = IzzyAPI.CardToken.generate()
        let policy = "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $27.50–$30 (50% of the service) to this card. Cancelling in the app before your appointment is free."
        let booking = IzzyAPI.NewAppointment(
            target: .anyBarber(serviceId: "haircut-and-beard"),
            start: utc(2026, 11, 2, 18),
            customer: IzzyAPI.NewCustomer(name: "Test Customer", phone: "(442) 555-0123"),
            noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: policy)
        )
        let confirmation = try await client.book(booking, token: manage)
        XCTAssertEqual(confirmation.appointment.card?.last4, "4242")
        let sent = try only()
        XCTAssertEqual(sent.header("X-Manage-Token"), manage.rawValue)
        XCTAssertEqual(sent.header("X-Card-Token"), card.rawValue)
        XCTAssertEqual(sent.json?["noShowPolicy"], .string(policy))
        // The en dash and the apostrophe travel as they are, so the server's comparison holds.
        XCTAssertTrue(String(decoding: try XCTUnwrap(sent.body), as: UTF8.self).contains("$27.50–$30"))
        XCTAssertFalse(String(decoding: try XCTUnwrap(sent.body), as: UTF8.self).contains(card.rawValue), "the card token is a header, not in the body")
        // The card isn't part of "the same booking".
        var withoutCard = booking
        withoutCard.noShow = nil
        XCTAssertEqual(booking.retryKey, withoutCard.retryKey)
    }

    func testABookingWithoutProtectionSendsNoCard() async throws {
        StubURLProtocol.reply { _ in .fixture("booking-confirmation.json", status: 201) }
        _ = try await client.book(IzzyAPI.NewAppointment(
            target: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"), start: utc(2026, 11, 2, 18),
            customer: IzzyAPI.NewCustomer(name: "Test Customer", phone: "4425550123")
        ), token: IzzyAPI.ManageToken.generate())
        let sent = try only()
        XCTAssertNil(sent.header("X-Card-Token"))
        XCTAssertNil(sent.json?["noShowPolicy"])
    }

    func testCardRequiredAndPolicyChangedComeBackTyped() async throws {
        let booking = IzzyAPI.NewAppointment(target: .anyBarber(serviceId: "haircut"), start: utc(2026, 11, 2, 18), customer: IzzyAPI.NewCustomer(name: "A", phone: "4425550123"))
        StubURLProtocol.reply { _ in .json(400, #"{"error":{"code":"card_required","message":"Add a card to book this time. You won't be charged now."}}"#) }
        do {
            _ = try await client.book(booking, token: .generate())
            XCTFail("expected card_required")
        } catch let error as APIError {
            XCTAssertEqual(error, .cardRequired(message: "Add a card to book this time. You won't be charged now."))
        }
        StubURLProtocol.reply { _ in .json(409, #"{"error":{"code":"policy_changed","message":"The no-show policy for this booking just changed. Check it and book again."}}"#) }
        do {
            _ = try await client.book(booking, token: .generate())
            XCTFail("expected policy_changed")
        } catch let error as APIError {
            XCTAssertEqual(error, .policyChanged(message: "The no-show policy for this booking just changed. Check it and book again."))
        }
    }

    func testChargingTheFeeAndTheSettingsCarryTheOwnerKey() async throws {
        StubURLProtocol.reply { _ in .fixture("no-show-fee-declined.json") }
        let appointment = try await client.chargeNoShowFee(appointmentId: "7d2e4f60-1a2b-4c3d-8e9f-0a1b2c3d4e5f")
        XCTAssertEqual(appointment.noShowFee?.status, .declined)
        var sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/owner/appointments/7d2e4f60-1a2b-4c3d-8e9f-0a1b2c3d4e5f/no-show-fee")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)
        XCTAssertEqual(sent.json, .object([:]))

        StubURLProtocol.reply { _ in .fixture("no-show-settings.json") }
        let settings = try await client.noShowSettings()
        XCTAssertEqual(settings, .default)
        sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/owner/no-show-settings")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)

        StubURLProtocol.reply { _ in .fixture("no-show-settings.json") }
        _ = try await client.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(feeMode: .flat, flatCents: 2_500))
        sent = try only()
        XCTAssertEqual(sent.method, "PATCH")
        XCTAssertEqual(sent.path, "/api/owner/no-show-settings")
        XCTAssertEqual(sent.json, .object(["feeMode": .string("flat"), "flatCents": .number(2_500)]))

        StubURLProtocol.reply { _ in .fixture("no-show-settings.json") }
        _ = try await client.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelEnabled: true, lateCancelWindowMinutes: 120))
        XCTAssertEqual(try only().json, .object(["lateCancelEnabled": .bool(true), "lateCancelWindowMinutes": .number(120)]))

        // Path segments are escaped like every id.
        StubURLProtocol.reply { _ in .fixture("no-show-fee-declined.json") }
        _ = try await client.chargeNoShowFee(appointmentId: "../me")
        XCTAssertEqual(try only().path, "/api/owner/appointments/..%2Fme/no-show-fee")
    }

    func testOwnerCallsWithoutAKeyNeverLeaveThePhone() async throws {
        let signedOut = client.withOwnerKey(nil)
        for call in [
            { _ = try await signedOut.chargeNoShowFee(appointmentId: "a") },
            { _ = try await signedOut.noShowSettings() },
            { _ = try await signedOut.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(enabled: false)) },
        ] as [() async throws -> Void] {
            do {
                try await call()
                XCTFail("expected unauthorized")
            } catch let error as APIError {
                XCTAssertEqual(error, .unauthorized)
            }
        }
        XCTAssertEqual(StubURLProtocol.sent.count, 0)
    }
}

/// A predictable "random" source for tests.
private struct CountingGenerator: RandomNumberGenerator {
    var state: UInt64 = 0x1234_5678

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
