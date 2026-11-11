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
        XCTAssertEqual(appointment.noShowFee, IzzyAPI.NoShowFee(amountCents: 3500, fullPrice: true, status: .none, lateCancelWindowMinutes: 60))
        XCTAssertEqual(appointment.noShowFee?.amountLabel, "$35")
        XCTAssertEqual(appointment.noShowFee?.title, "No-show fee")
        XCTAssertEqual(appointment.noShowFee?.lateCancelStarts(before: appointment.start), utc(2026, 11, 2, 17))

        let owner = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json")).appointments
        XCTAssertNil(owner[0].card)
        XCTAssertNil(owner[0].noShowFee)
        XCTAssertEqual(owner[1].card?.label, "Mastercard •••• 4444")
        XCTAssertEqual(
            owner[1].noShowFee,
            IzzyAPI.NoShowFee(amountCents: 4500, fullPrice: true, status: .charged, chargedAt: utc(2026, 11, 2, 19, 5), lateCancelWindowMinutes: 60, reason: .noShow)
        )
        XCTAssertTrue(owner[1].noShowFee?.isCharged == true)
        // A client who cancelled half an hour before: a late cancellation the owner may charge.
        XCTAssertEqual(
            owner[3].noShowFee,
            IzzyAPI.NoShowFee(amountCents: 3500, fullPrice: true, customerCancelledAt: utc(2026, 11, 2, 22, 30), lateCancelWindowMinutes: 60, reason: .lateCancel)
        )
        XCTAssertEqual(owner[3].noShowFee?.title, "Late cancellation fee")
        XCTAssertEqual(owner[3].chargeableFee(at: utc(2026, 11, 2, 22, 31)), .lateCancel)

        let declined = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("no-show-fee-declined.json")).appointment
        XCTAssertEqual(declined.noShowFee?.status, .declined)
        XCTAssertEqual(declined.noShowFee?.message, "The card was declined: there isn't enough money on it.")
        XCTAssertEqual(declined.noShowFee?.reason, .noShow)
    }

    func testTheShopsViewSaysWhenAVisitWasFirstCompleted() throws {
        // The server's own answers: marked done at 11:05 AM, and a new booking not completed yet.
        let updated = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try serverFixture("owner-appointment-updated.json")).appointment
        XCTAssertEqual(updated.completedAt, utc(2026, 11, 2, 19, 5))
        XCTAssertEqual(try encodeAPI(updated)["completedAt"], .string("2026-11-02T19:05:00Z"))
        let created = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try serverFixture("owner-appointment-created.json")).appointment
        XCTAssertNil(created.completedAt)
        XCTAssertEqual(try encodeAPI(created)["completedAt"], .null, "the shop's view has it, null or not")

        // The client's own view, and a server from before it, don't have it, and don't get it back either.
        let mine = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("appointment.json")).appointment
        XCTAssertNil(mine.completedAt)
        XCTAssertNil(try encodeAPI(mine)["completedAt"])
        let older = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json")).appointments
        XCTAssertEqual(older.map(\.completedAt), [nil, nil, nil, nil])
        XCTAssertNil(try encodeAPI(older[0])["completedAt"])
        // Whether the field was there isn't part of the value.
        var members = try XCTUnwrap(JSONSerialization.jsonObject(with: try IzzyAPI.makeEncoder().encode(created)) as? [String: Any])
        XCTAssertNotNil(members.removeValue(forKey: "completedAt"))
        let withoutIt = try decoder.decode(IzzyAPI.Appointment.self, from: try JSONSerialization.data(withJSONObject: members))
        XCTAssertNil(try encodeAPI(withoutIt)["completedAt"])
        XCTAssertEqual(withoutIt, created)
        // Constructed, it's written once it's set.
        var made = withoutIt
        made.completedAt = utc(2026, 11, 2, 19, 5)
        XCTAssertEqual(try encodeAPI(made)["completedAt"], .string("2026-11-02T19:05:00Z"))
    }

    func testAFeeFromAServerBeforeLateCancellations() throws {
        let old = try decodeAPI(IzzyAPI.NoShowFee.self, #"{ "amountCents": 2000, "status": "none", "chargedAt": null, "message": null }"#)
        XCTAssertEqual(old, IzzyAPI.NoShowFee(amountCents: 2000))
        XCTAssertFalse(old.fullPrice, "unknown, so the warnings just give the amount")
        XCTAssertNil(old.lateCancelStarts(before: utc(2026, 11, 2, 18)), "cancelling is free until the start")
        // Written back with the new keys, as null (and false).
        XCTAssertEqual(try encodeAPI(old), .object([
            "amountCents": .number(2000), "fullPrice": .bool(false), "status": .string("none"), "chargedAt": .null, "message": .null,
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
        XCTAssertEqual(try encodeAPI(IzzyAPI.NoShowFee(amountCents: 2000, fullPrice: true, status: .needsAction, message: "Ask them to pay at the shop.", reason: .lateCancel)), .object([
            "amountCents": .number(2000), "fullPrice": .bool(true), "status": .string("needsAction"), "chargedAt": .null, "message": .string("Ask them to pay at the shop."),
            "customerCancelledAt": .null, "lateCancelWindowMinutes": .null, "reason": .string("lateCancel"),
        ]))
    }

    func testWhenTheOwnerCanChargeTheFee() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let end = appointment.end
        XCTAssertFalse(appointment.canChargeNoShowFee(at: end.addingTimeInterval(3_600)), "still booked")
        appointment.status = .noShow
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start.addingTimeInterval(-60)), "hasn't started")
        XCTAssertFalse(appointment.canChargeNoShowFee(at: start), "hasn't ended")
        XCTAssertFalse(appointment.canChargeNoShowFee(at: end.addingTimeInterval(-60)), "a minute before the end")
        XCTAssertTrue(appointment.canChargeNoShowFee(at: end))
        XCTAssertTrue(appointment.canChargeNoShowFee(at: end.addingTimeInterval(60)), "a minute after the end")
        for status in [IzzyAPI.NoShowFeeStatus.none, .pending, .declined, .needsAction] {
            appointment.noShowFee?.status = status
            XCTAssertTrue(appointment.canChargeNoShowFee(at: end.addingTimeInterval(600)), "\(status)")
        }
        appointment.noShowFee?.status = .charged
        XCTAssertFalse(appointment.canChargeNoShowFee(at: end.addingTimeInterval(600)), "charged once")
        appointment.noShowFee?.status = .none
        appointment.card = nil
        XCTAssertFalse(appointment.canChargeNoShowFee(at: end.addingTimeInterval(600)), "no card")
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = nil
        XCTAssertFalse(appointment.canChargeNoShowFee(at: end.addingTimeInterval(600)), "no fee")
        XCTAssertEqual(appointment.feeCase(at: end.addingTimeInterval(600)), .refused("This booking has no card on file, so there's no fee to charge."))
        XCTAssertNil(appointment.feeDeadline, "no fee, no deadline")
    }

    /// No new try more than 7 days after the start; a try already pending can still be checked.
    func testTheFeeCanBeChargedUntil7DaysAfterTheStart() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let deadline = start.addingTimeInterval(7 * 24 * 3_600)
        XCTAssertEqual(appointment.feeDeadline, deadline)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeDeadline(start: start), utc(2026, 11, 9, 18))
        appointment.status = .noShow
        XCTAssertEqual(appointment.chargeableFee(at: deadline.addingTimeInterval(-60)), .noShow, "7 days less a minute")
        XCTAssertEqual(appointment.chargeableFee(at: deadline), .noShow, "exactly 7 days still counts")
        XCTAssertNil(appointment.chargeableFee(at: deadline.addingTimeInterval(60)), "7 days and a minute")
        XCTAssertEqual(appointment.feeCase(at: deadline.addingTimeInterval(60)), .refused(IzzyAPI.NoShowRule.feeDeadlineMessage))
        XCTAssertEqual(IzzyAPI.NoShowRule.feeDeadlineMessage, "It's more than 7 days after the appointment, so the fee can't be charged.")
        XCTAssertFalse(IzzyAPI.NoShowRule.isPastFeeDeadline(start: start, now: deadline))
        XCTAssertTrue(IzzyAPI.NoShowRule.isPastFeeDeadline(start: start, now: deadline.addingTimeInterval(1)))
        // Still booked a week later: the deadline's the reason, not "mark a no-show first".
        appointment.status = .booked
        XCTAssertEqual(appointment.feeCase(at: deadline.addingTimeInterval(60)), .refused(IzzyAPI.NoShowRule.feeDeadlineMessage))
        XCTAssertEqual(appointment.feeCase(at: deadline.addingTimeInterval(-60)), .refused("Mark the appointment as a no-show first."))
        // A late cancellation too.
        appointment.status = .cancelled
        appointment.cancelledBy = .customer
        appointment.noShowFee?.customerCancelledAt = start.addingTimeInterval(-30 * 60)
        XCTAssertEqual(appointment.chargeableFee(at: deadline.addingTimeInterval(-60)), .lateCancel)
        XCTAssertNil(appointment.chargeableFee(at: deadline.addingTimeInterval(60)))
        // A pending try is still checked (the server only asks Stripe how it went).
        appointment.noShowFee?.status = .pending
        appointment.noShowFee?.reason = .lateCancel
        XCTAssertEqual(appointment.chargeableFee(at: deadline.addingTimeInterval(86_400)), .lateCancel)
    }

    /// The shop marks a booking with a card on file a no-show only once it has ended, and never once it's completed.
    func testWhenTheShopCanMarkANoShow() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let end = appointment.end
        XCTAssertEqual(appointment.noShowMarkRefusal(at: end.addingTimeInterval(-60)), "You can mark a no-show once the appointment has ended.")
        XCTAssertFalse(appointment.canBeMarkedNoShow(at: end.addingTimeInterval(-60)))
        XCTAssertNil(appointment.noShowMarkRefusal(at: end.addingTimeInterval(60)))
        XCTAssertTrue(appointment.canBeMarkedNoShow(at: end.addingTimeInterval(60)))
        XCTAssertNil(appointment.noShowMarkRefusal(at: end), "at the end")
        appointment.status = .completed
        XCTAssertEqual(appointment.noShowMarkRefusal(at: end.addingTimeInterval(60)), "This appointment was marked completed, so it can't become a no-show.")
        XCTAssertFalse(appointment.canBeMarkedNoShow(at: end.addingTimeInterval(60)))
        // Without a card there's no fee, so it can be marked whenever, as before.
        appointment.card = nil
        XCTAssertNil(appointment.noShowMarkRefusal(at: end.addingTimeInterval(-3_600)))
        XCTAssertTrue(appointment.canBeMarkedNoShow(at: end.addingTimeInterval(-3_600)))
        appointment.status = .noShow
        XCTAssertFalse(appointment.canBeMarkedNoShow(at: end), "already one")
    }

    /// An earlier try with no final answer: "Check again" is always there, whatever happened since,
    /// because the server then only asks Stripe how that try went.
    func testAPendingFeeCanAlwaysBeCheckedAgain() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let later = appointment.start.addingTimeInterval(3_600)
        appointment.status = .noShow
        appointment.noShowFee?.status = .pending
        appointment.noShowFee?.reason = .noShow
        XCTAssertEqual(appointment.chargeableFee(at: later), .noShow)
        XCTAssertTrue(appointment.isFeePending)
        // The client walked in late: reopened, then completed. Still something to check.
        appointment.status = .completed
        XCTAssertEqual(appointment.feeCase(at: later), .refused("The appointment is marked completed, so there's no fee to charge."))
        XCTAssertEqual(appointment.chargeableFee(at: later), .noShow)
        XCTAssertTrue(appointment.canChargeNoShowFee(at: later))
        // A late cancellation's try keeps its own reason.
        appointment.noShowFee?.reason = .lateCancel
        XCTAssertEqual(appointment.chargeableFee(at: later), .lateCancel)
        // Settled as not charged (the server found nothing at Stripe): nothing to do on a completed visit.
        appointment.noShowFee?.status = .none
        appointment.noShowFee?.reason = nil
        XCTAssertNil(appointment.chargeableFee(at: later))
        XCTAssertFalse(appointment.isFeePending)
        // Without a card on file there's never anything to check.
        appointment.noShowFee?.status = .pending
        appointment.card = nil
        XCTAssertNil(appointment.chargeableFee(at: later))
        XCTAssertFalse(appointment.isFeePending)
        XCTAssertEqual(
            IzzyAPI.NoShowRule.nothingChargedMessage("Mark the appointment as a no-show first."),
            "Nothing was charged. Mark the appointment as a no-show first."
        )
    }

    func testWhichFeeTheOwnerCanCharge() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let minutes = { (m: Double) in start.addingTimeInterval(m * 60) }
        XCTAssertNil(appointment.chargeableFee(at: minutes(60)))
        XCTAssertEqual(appointment.feeCase(at: minutes(60)), .refused("Mark the appointment as a no-show first."))
        appointment.status = .noShow
        XCTAssertEqual(appointment.feeCase(at: minutes(-1)), .refused("The appointment hasn't ended yet, so it can't be a no-show."))
        XCTAssertEqual(appointment.feeCase(at: minutes(44)), .refused("The appointment hasn't ended yet, so it can't be a no-show."))
        XCTAssertNil(appointment.chargeableFee(at: minutes(20)), "it started, but a client who comes before the end isn't a no-show")
        XCTAssertEqual(appointment.chargeableFee(at: minutes(46)), .noShow)

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
        let full = "Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price."
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-120)))
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-60)), "exactly an hour before is still free")
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-59)), full)
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-1)), full)
        XCTAssertNil(appointment.lateCancelWarning(at: start), "it can't be cancelled in the app once it starts")
        appointment.noShowFee?.lateCancelWindowMinutes = 90
        XCTAssertEqual(
            appointment.lateCancelWarning(at: minutes(-80)),
            "Cancelling now, less than 90 minutes before your appointment, may be charged $35, the full service price."
        )
        // Less than the full price (say 50%, or a flat fee): just the amount.
        appointment.noShowFee?.lateCancelWindowMinutes = 60
        appointment.noShowFee?.amountCents = 1_750
        appointment.noShowFee?.fullPrice = false
        XCTAssertEqual(appointment.lateCancelWarning(at: minutes(-30)), "Cancelling now, less than 1 hour before your appointment, may be charged $17.50.")
        appointment.noShowFee?.amountCents = 3_500
        appointment.noShowFee?.fullPrice = true
        appointment.noShowFee?.lateCancelWindowMinutes = nil
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "late cancellations weren't in the agreed policy")
        appointment.noShowFee?.lateCancelWindowMinutes = 60
        appointment.status = .cancelled
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "already cancelled")
        appointment.status = .booked
        appointment.card = nil
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-10)), "no card on file")
    }

    /// The time the server counts is the client's first one: the warning follows it.
    func testTheWarningCountsFromTheFirstTimeTheClientCancelled() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let minutes = { (m: Double) in start.addingTimeInterval(m * 60) }
        // Cancelled the day before (free), then reopened by the shop: cancelling again at 9:30 is still free.
        appointment.noShowFee?.customerCancelledAt = minutes(-24 * 60)
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-30)))
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-1)))
        // Asked inside the window before (the shop had marked it then), then reopened: it's late, whenever it goes through.
        appointment.noShowFee?.customerCancelledAt = minutes(-40)
        XCTAssertEqual(
            appointment.lateCancelWarning(at: minutes(-20)),
            "Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price."
        )
        // Exactly an hour before counts as free, then too.
        appointment.noShowFee?.customerCancelledAt = minutes(-60)
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-5)))
    }

    /// What the reminders say about cancelling late comes from the booking's own terms.
    func testTheTermsForTheReminders() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        XCTAssertEqual(appointment.lateCancelTerms, LateCancelTerms(windowMinutes: 60, feeLabel: "$35", bookedAt: appointment.createdAt))
        appointment.noShowFee?.lateCancelWindowMinutes = 90
        appointment.noShowFee?.amountCents = 1_750
        XCTAssertEqual(appointment.lateCancelTerms, LateCancelTerms(windowMinutes: 90, feeLabel: "$17.50", bookedAt: appointment.createdAt))

        // Late cancellations weren't in the agreed policy: nothing to say.
        appointment.noShowFee?.lateCancelWindowMinutes = nil
        XCTAssertNil(appointment.lateCancelTerms)
        // The client cancelled (or asked to) before: the first time decides, so nothing to say.
        appointment.noShowFee?.lateCancelWindowMinutes = 60
        appointment.noShowFee?.customerCancelledAt = appointment.start.addingTimeInterval(-24 * 60 * 60)
        XCTAssertNil(appointment.lateCancelTerms)
        // No card on file, or no fee.
        appointment.noShowFee?.customerCancelledAt = nil
        XCTAssertNotNil(appointment.lateCancelTerms)
        appointment.card = nil
        XCTAssertNil(appointment.lateCancelTerms)
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = nil
        XCTAssertNil(appointment.lateCancelTerms)
    }

    /// A time booked inside the window is free to cancel for 15 minutes after booking.
    func testCancellingWithin15MinutesOfBookingIsFree() throws {
        var appointment = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        let start = appointment.start
        let minutes = { (m: Double) in start.addingTimeInterval(m * 60) }
        appointment.createdAt = minutes(-35) // booked 35 minutes before, inside the 1-hour window
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-35)))
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-21)), "14 minutes after booking")
        XCTAssertNil(appointment.lateCancelWarning(at: minutes(-20)), "exactly 15 minutes after booking")
        XCTAssertEqual(
            appointment.lateCancelWarning(at: minutes(-19)),
            "Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price.",
            "16 minutes after booking"
        )
        // Once cancelled: within the grace period it's free, after it a late cancellation.
        appointment.status = .cancelled
        appointment.cancelledBy = .customer
        appointment.noShowFee?.customerCancelledAt = minutes(-21)
        XCTAssertEqual(appointment.feeCase(at: minutes(1)), .refused("The client cancelled within 15 minutes of booking, so there's no fee."))
        XCTAssertNil(appointment.chargeableFee(at: minutes(1)))
        appointment.noShowFee?.customerCancelledAt = minutes(-19)
        XCTAssertEqual(appointment.chargeableFee(at: minutes(1)), .lateCancel)
        // The rule itself, with and without the booking time.
        XCTAssertFalse(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: minutes(-21), lateCancelWindowMinutes: 60, createdAt: minutes(-35)))
        XCTAssertTrue(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: minutes(-19), lateCancelWindowMinutes: 60, createdAt: minutes(-35)))
        XCTAssertTrue(IzzyAPI.NoShowRule.cancelledLate(start: start, customerCancelledAt: minutes(-21), lateCancelWindowMinutes: 60), "without it, no grace")
        XCTAssertEqual(IzzyAPI.NoShowRule.lateCancelGraceMinutes, 15)
    }

    /// A time less than the window away can't be cancelled for free once it's booked: the booking
    /// steps say so for the time the client picked.
    func testATimeInsideTheWindowSaysCancellingItMayBeCharged() throws {
        let policy = IzzyAPI.NoShowPolicy(required: true, minFeeCents: 3_500, maxFeeCents: 3_500, policyText: "…", lateCancelWindowMinutes: 60)
        let now = utc(2026, 11, 3, 17, 15) // 9:15 AM
        let start = { (minutes: Double) in now.addingTimeInterval(minutes * 60) }
        let notice = "This time is less than 1 hour away, so cancelling it more than 15 minutes after booking may be charged $35."
        XCTAssertEqual(policy.lateCancelNotice(start: start(30), now: now), notice, "the first time a booking can take")
        XCTAssertEqual(policy.lateCancelNotice(start: start(45), now: now), notice)
        XCTAssertEqual(policy.lateCancelNotice(start: start(59), now: now), notice)
        XCTAssertNil(policy.lateCancelNotice(start: start(60), now: now), "an hour away: the usual rule (more than 1 hour before is free)")
        XCTAssertNil(policy.lateCancelNotice(start: start(120), now: now))
        // Any barber: the range of their fees. A longer window: its own words.
        var anyBarber = policy
        anyBarber.minFeeCents = 5_500
        anyBarber.maxFeeCents = 6_000
        anyBarber.lateCancelWindowMinutes = 90
        XCTAssertEqual(
            anyBarber.lateCancelNotice(start: start(75), now: now),
            "This time is less than 90 minutes away, so cancelling it more than 15 minutes after booking may be charged $55–$60."
        )
        // Late cancellations off, or no card needed: nothing to say.
        var noLateFee = policy
        noLateFee.lateCancelWindowMinutes = nil
        XCTAssertNil(noLateFee.lateCancelNotice(start: start(30), now: now))
        XCTAssertNil(IzzyAPI.NoShowPolicy.notRequired.lateCancelNotice(start: start(30), now: now))
        // The rule itself is the server's late cancellation, with now as the cancel time (the grace period aside).
        XCTAssertTrue(IzzyAPI.NoShowRule.cancellingMayBeCharged(start: start(59), now: now, windowMinutes: 60))
        XCTAssertFalse(IzzyAPI.NoShowRule.cancellingMayBeCharged(start: start(60), now: now, windowMinutes: 60))
        XCTAssertFalse(IzzyAPI.NoShowRule.cancellingMayBeCharged(start: start(10), now: now, windowMinutes: nil))
        XCTAssertEqual(
            IzzyAPI.NoShowRule.lateCancelNotice(windowMinutes: 2_880, feeLabel: "$80"),
            "This time is less than 48 hours away, so cancelling it more than 15 minutes after booking may be charged $80."
        )
        // From the server's policy fixture.
        let served = try decoder.decode(IzzyAPI.NoShowPolicy.self, from: try kitFixture("no-show-policy.json"))
        XCTAssertEqual(
            served.lateCancelNotice(start: start(40), now: now),
            "This time is less than 1 hour away, so cancelling it more than 15 minutes after booking may be charged $55–$60."
        )
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
            message: "Cancelling less than 1 hour before your appointment, or not showing up, may be charged the full service price ($55–$60). Cancelling in the app more than 1 hour before is free."
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

        let notStarted = APIError(code: "not_started", message: "You can mark a no-show once the appointment has ended.", status: 409)
        XCTAssertEqual(notStarted, .server(code: IzzyAPI.ErrorCode.notStarted, message: "You can mark a no-show once the appointment has ended.", status: 409))
        XCTAssertEqual(notStarted.userMessage, "You can mark a no-show once the appointment has ended.")
        XCTAssertFalse(notStarted.isRetryable)
        let completed = APIError(code: "already_completed", message: "This appointment was marked completed, so it can't become a no-show.", status: 409)
        XCTAssertEqual(completed, .server(code: IzzyAPI.ErrorCode.alreadyCompleted, message: IzzyAPI.NoShowRule.completedNoShowMessage, status: 409))
        XCTAssertEqual(completed.userMessage, "This appointment was marked completed, so it can't become a no-show.")
        XCTAssertFalse(completed.isRetryable)

        let warning = "Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price."
        let lateFee = APIError.fromResponse(status: 409, body: Data(#"{"error":{"code":"late_cancel_fee","message":"\#(warning)"}}"#.utf8))
        XCTAssertEqual(lateFee, .lateCancelFee(message: warning))
        XCTAssertEqual(lateFee.code, "late_cancel_fee")
        XCTAssertEqual(IzzyAPI.ErrorCode.lateCancelFee, "late_cancel_fee")
        XCTAssertEqual(lateFee.userMessage, warning)
        XCTAssertFalse(lateFee.isRetryable, "trying again only helps once the client agreed")
        XCTAssertEqual(APIError.lateCancelFee(message: "").userMessage, "Cancelling now, this close to your appointment, may be charged a fee.")
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

        /// A late cancellation with the booking time: the 15-minute grace period.
        struct LateCancel: Decodable {
            let start: Date
            let createdAt: Date
            let cancelledAt: Date
            let lateCancelWindowMinutes: Int
            let late: Bool
        }

        struct Notice: Decodable {
            let lateCancelWindowMinutes: Int
            let feeLabel: String
            let notice: String
        }

        let fees: [Fee]
        let policies: [Policy]
        let windows: [Window]
        let graceMinutes: Int
        let lateCancels: [LateCancel]
        let notices: [Notice]
    }

    func testTheKitMatchesTheServersRule() throws {
        let url = TestPaths.repository.appendingPathComponent("server/test/fixtures/no-show-rule.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No server rule fixture at \(url.path); the server's tests write it.")
        }
        let document = try IzzyAPI.makeDecoder().decode(RuleDocument.self, from: data)
        XCTAssertGreaterThan(document.fees.count, 50)
        // Flat fees are capped at the price: a $20 flat fee on a $5 service is $5.
        XCTAssertTrue(document.fees.contains { $0.settings.feeMode == .flat && $0.settings.flatCents == 2_000 && $0.priceCents == 500 && $0.feeCents == 500 })
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
        // The grace period: the same late cancellations as the server, with the booking time.
        XCTAssertEqual(document.graceMinutes, IzzyAPI.NoShowRule.lateCancelGraceMinutes)
        XCTAssertGreaterThan(document.lateCancels.count, 10)
        XCTAssertTrue(document.lateCancels.contains { $0.late } && document.lateCancels.contains { !$0.late })
        for c in document.lateCancels {
            XCTAssertEqual(
                IzzyAPI.NoShowRule.cancelledLate(
                    start: c.start, customerCancelledAt: c.cancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes, createdAt: c.createdAt
                ),
                c.late,
                "booked \(c.createdAt), cancelled \(c.cancelledAt), window \(c.lateCancelWindowMinutes)"
            )
        }
        // The line for a time already inside the window, word for word.
        XCTAssertFalse(document.notices.isEmpty)
        for n in document.notices {
            XCTAssertEqual(IzzyAPI.NoShowRule.lateCancelNotice(windowMinutes: n.lateCancelWindowMinutes, feeLabel: n.feeLabel), n.notice)
        }
    }

    struct FeeCasesDocument: Decodable {
        struct Case: Decodable {
            let name: String
            let status: IzzyAPI.AppointmentStatus
            let cancelledBy: IzzyAPI.CancelledBy?
            let start: Date
            let end: Date
            let createdAt: Date
            let customerCancelledAt: Date?
            let lateCancelWindowMinutes: Int?
            let reason: IzzyAPI.NoShowFeeReason?
            let refusal: String?
            let cancelledLate: Bool
        }

        /// The same rule at a given moment: what the server answers a charge then.
        struct ClockCase: Decodable {
            let name: String
            let status: IzzyAPI.AppointmentStatus
            let cancelledBy: IzzyAPI.CancelledBy?
            let start: Date
            let end: Date
            let createdAt: Date
            let customerCancelledAt: Date?
            let lateCancelWindowMinutes: Int?
            let now: Date
            let reason: IzzyAPI.NoShowFeeReason?
            let refusal: String?
        }

        struct Deadline: Decodable {
            let days: Int
            let message: String
        }

        struct CancelWarning: Decodable {
            let lateCancelWindowMinutes: Int
            let amountCents: Int
            let fullPrice: Bool
            let warning: String
        }

        struct NothingCharged: Decodable {
            let refusal: String
            let message: String
        }

        let cases: [Case]
        let clock: [ClockCase]
        let notEnded: String
        let deadline: Deadline
        let graceMinutes: Int
        let nothingCharged: NothingCharged
        let cancelWarnings: [CancelWarning]
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
        XCTAssertEqual(document.notEnded, IzzyAPI.NoShowRule.notEndedMessage)
        XCTAssertEqual(document.deadline.days, IzzyAPI.NoShowRule.feeDeadlineDays)
        XCTAssertEqual(document.deadline.message, IzzyAPI.NoShowRule.feeDeadlineMessage)
        XCTAssertEqual(document.graceMinutes, IzzyAPI.NoShowRule.lateCancelGraceMinutes)
        XCTAssertEqual(IzzyAPI.NoShowRule.nothingChargedMessage(document.nothingCharged.refusal), document.nothingCharged.message)
        let template = try IzzyAPI.makeDecoder().decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json")).appointment
        func appointment(
            status: IzzyAPI.AppointmentStatus, cancelledBy: IzzyAPI.CancelledBy?, start: Date, end: Date, createdAt: Date,
            customerCancelledAt: Date?, lateCancelWindowMinutes: Int?
        ) -> IzzyAPI.Appointment {
            var appointment = template
            appointment.status = status
            appointment.cancelledBy = cancelledBy
            appointment.start = start
            appointment.end = end
            appointment.createdAt = createdAt
            appointment.noShowFee?.customerCancelledAt = customerCancelledAt
            appointment.noShowFee?.lateCancelWindowMinutes = lateCancelWindowMinutes
            return appointment
        }
        for c in document.cases {
            let expected: IzzyAPI.NoShowRule.FeeCase = c.reason.map { .chargeable($0) } ?? .refused(c.refusal ?? "")
            XCTAssertEqual(
                IzzyAPI.NoShowRule.feeCase(
                    status: c.status, cancelledBy: c.cancelledBy, start: c.start,
                    customerCancelledAt: c.customerCancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes, createdAt: c.createdAt
                ),
                expected,
                c.name
            )
            // The same through an appointment, after its end (a no-show needs that).
            let booking = appointment(
                status: c.status, cancelledBy: c.cancelledBy, start: c.start, end: c.end, createdAt: c.createdAt,
                customerCancelledAt: c.customerCancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes
            )
            XCTAssertEqual(booking.feeCase(at: c.end.addingTimeInterval(600)), expected, c.name)
            XCTAssertEqual(booking.chargeableFee(at: c.end.addingTimeInterval(600)), c.reason, c.name)
            if c.reason == .noShow {
                XCTAssertEqual(booking.feeCase(at: c.end.addingTimeInterval(-60)), .refused(document.notEnded), c.name)
            }
            XCTAssertEqual(
                IzzyAPI.NoShowRule.cancelledLate(
                    start: c.start, customerCancelledAt: c.customerCancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes, createdAt: c.createdAt
                ),
                c.cancelledLate,
                c.name
            )
            // The booking steps' notice uses the same window, with the time the client picks as the cancel
            // time; the grace period then gives 15 minutes after booking.
            if let cancelledAt = c.customerCancelledAt {
                XCTAssertEqual(
                    IzzyAPI.NoShowRule.cancellingMayBeCharged(start: c.start, now: cancelledAt, windowMinutes: c.lateCancelWindowMinutes),
                    IzzyAPI.NoShowRule.cancelledLate(start: c.start, customerCancelledAt: cancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes),
                    c.name
                )
            }
        }
        XCTAssertTrue(document.cases.contains { $0.cancelledLate } && document.cases.contains { !$0.cancelledLate })
        // At a given moment: the end of the appointment and the 7-day deadline, exactly as the server answers.
        XCTAssertGreaterThan(document.clock.count, 10)
        for c in document.clock {
            let expected: IzzyAPI.NoShowRule.FeeCase = c.reason.map { .chargeable($0) } ?? .refused(c.refusal ?? "")
            let booking = appointment(
                status: c.status, cancelledBy: c.cancelledBy, start: c.start, end: c.end, createdAt: c.createdAt,
                customerCancelledAt: c.customerCancelledAt, lateCancelWindowMinutes: c.lateCancelWindowMinutes
            )
            XCTAssertEqual(booking.feeCase(at: c.now), expected, c.name)
            XCTAssertEqual(booking.chargeableFee(at: c.now), c.reason, c.name)
        }

        // The warning before a late cancellation, in the server's words (also its 409 late_cancel_fee).
        XCTAssertGreaterThan(document.cancelWarnings.count, 5)
        XCTAssertTrue(document.cancelWarnings.contains { $0.fullPrice } && document.cancelWarnings.contains { !$0.fullPrice })
        for w in document.cancelWarnings {
            XCTAssertEqual(
                IzzyAPI.NoShowRule.lateCancelWarning(windowMinutes: w.lateCancelWindowMinutes, feeCents: w.amountCents, fullPrice: w.fullPrice),
                w.warning
            )
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
        // Never more than the service's price: a $25 flat fee on a $16 service is $16, a $20 one on a $5 service is $5.
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(16), settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_500)), 1_600)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(5), settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_000)), 500)
        XCTAssertEqual(IzzyAPI.NoShowRule.feeCents(for: .dollars(40), settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_000)), 2_000)
        XCTAssertEqual(IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_000).feeCents(for: .dollars(5)), 500, "the owner's preview")
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
            message: "Cancelling less than 1 hour before your appointment, or not showing up, may be charged the full service price ($40). Cancelling in the app more than 1 hour before is free."
        ))
        XCTAssertEqual(IzzyAPI.NoShowRule.warning(minFeeCents: 2_500, maxFeeCents: 2_500, settings: IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_500, lateCancelWindowMinutes: 120)).title, "Late Cancellation & No-Show Fee")
        XCTAssertEqual(IzzyAPI.NoShowRule.warning(minFeeCents: 4_000, maxFeeCents: 4_000, settings: IzzyAPI.NoShowSettings(lateCancelEnabled: false)), IzzyAPI.NoShowWarning(
            title: "No-Show Fee",
            message: "Not showing up may be charged the full service price ($40). Cancelling in the app before your appointment is free."
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

    func testRemovingTheCardSendsTheTokenAndReadsWhatHappened() async throws {
        let token = IzzyAPI.CardToken.generate()
        StubURLProtocol.reply { _ in .fixture("card-deletion.json") }
        let scheduled = try await client.deleteCard(token: token)
        XCTAssertEqual(scheduled, IzzyAPI.CardDeletion(status: .scheduled, message: "Your card will be deleted as soon as your appointments no longer need it."))
        let sent = try only()
        XCTAssertEqual(sent.method, "DELETE")
        XCTAssertEqual(sent.path, "/api/cards")
        XCTAssertEqual(sent.header("X-Card-Token"), token.rawValue)
        XCTAssertNil(sent.header("Authorization"), "public, even from a client with an owner key")
        XCTAssertNil(sent.body)

        StubURLProtocol.reply { _ in .json(200, #"{"cardDeletion":{"status":"deleted","message":"Your saved card is deleted. It can't be charged any more."}}"#) }
        let deleted = try await client.deleteCard(token: token)
        XCTAssertEqual(deleted.status, .deleted)
        // A status this version doesn't know never reads as deleted.
        StubURLProtocol.reply { _ in .json(200, #"{"cardDeletion":{"status":"queued","message":"Soon."}}"#) }
        let unknown = try await client.deleteCard(token: token)
        XCTAssertEqual(unknown.status, .scheduled)
        // No card under that token: the server's 404, as an APIError.
        StubURLProtocol.reply { _ in .json(404, #"{"error":{"code":"not_found","message":"We couldn't find that card."}}"#) }
        do {
            _ = try await client.deleteCard(token: token)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: "not_found", message: "We couldn't find that card.", status: 404))
        }
    }

    /// A conformer (an app's fake) that doesn't implement it yet answers like a server without it.
    func testAShopAPIWithoutCardDeletionAnswersNotFound() async throws {
        struct Older: ShopAPI {
            func health() async throws -> IzzyAPI.Health { throw CancellationError() }
            func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { throw CancellationError() }
            func book(_ appointment: IzzyAPI.NewAppointment, token: IzzyAPI.ManageToken) async throws -> IzzyAPI.BookingConfirmation { throw CancellationError() }
            func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment { throw CancellationError() }
            func cancelAppointment(id: String, manageToken: String, acceptLateCancelFee: Bool) async throws -> IzzyAPI.Appointment { throw CancellationError() }
            func reviews() async throws -> IzzyAPI.ReviewsResponse { throw CancellationError() }
            func products() async throws -> [IzzyAPI.Product] { throw CancellationError() }
            func noShowPolicy(for target: IzzyAPI.BookingTarget) async throws -> IzzyAPI.NoShowPolicy { throw CancellationError() }
            func startCardCheckout(for target: IzzyAPI.BookingTarget, token: IzzyAPI.CardToken) async throws -> IzzyAPI.CardCheckout { throw CancellationError() }
            func saveCard(sessionId: String, token: IzzyAPI.CardToken) async throws -> IzzyAPI.SavedCard { throw CancellationError() }
        }
        do {
            _ = try await Older().deleteCard(token: .generate())
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: IzzyAPI.ErrorCode.notFound, message: "This isn't available here yet.", status: 404))
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

    func testCancellingInsideTheWindowAsksFirstThenSendsTheClientsYes() async throws {
        let id = "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b"
        let warning = "Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price."
        StubURLProtocol.reply { _ in .json(409, #"{"error":{"code":"late_cancel_fee","message":"\#(warning)"}}"#) }
        do {
            _ = try await client.cancelAppointment(id: id, manageToken: "token-abc_123")
            XCTFail("expected late_cancel_fee")
        } catch let error as APIError {
            XCTAssertEqual(error, .lateCancelFee(message: warning))
        }
        var sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/appointments/\(id)/cancel")
        XCTAssertEqual(sent.json, .object([:]), "no yes until the client gave one")

        // The client read it and cancels anyway.
        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        let cancelled = try await client.cancelAppointment(id: id, manageToken: "token-abc_123", acceptLateCancelFee: true)
        XCTAssertEqual(cancelled.status, .cancelled)
        sent = try only()
        XCTAssertEqual(sent.path, "/api/appointments/\(id)/cancel")
        XCTAssertEqual(sent.header("X-Manage-Token"), "token-abc_123")
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
        XCTAssertNil(sent.header("Authorization"))
        XCTAssertEqual(sent.json, .object(["acceptLateCancelFee": .bool(true)]))

        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        _ = try await client.cancelAppointment(id: id, manageToken: "token-abc_123", acceptLateCancelFee: false)
        XCTAssertEqual(try only().json, .object([:]))
        XCTAssertEqual(
            IzzyAPI.Endpoints.cancelAppointment(id: id, manageToken: "t", acceptLateCancelFee: true).body,
            Data(#"{"acceptLateCancelFee":true}"#.utf8)
        )
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
