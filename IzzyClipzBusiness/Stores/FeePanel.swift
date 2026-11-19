import Foundation
import IzzyClipzKit

/// An appointment's card on file and its fee (for a no-show or a late cancellation), as its
/// details show them: what the client agreed to when booking, what happened to the fee, and what
/// the owner can do now. Worked out from the appointment as the server sent it, so the details
/// read the same when they're opened again later.
///
/// Which fee can be charged is the server's rule, through the Kit (`Appointment.chargeableFee(at:)`):
/// a no-show, or a cancellation by the client less than the agreed window before the start (and
/// more than 15 minutes after booking), once the appointment's end has passed, up to 7 days after
/// the start, and never for a booking the shop cancelled, even reopened since. Only a fee Stripe
/// reported as succeeded shows as charged.
struct FeePanel: Equatable {
    /// "Visa •••• 4242".
    let cardLabel: String
    /// "$35", or "$35 (the full service price)".
    let feeLabel: String
    /// What the fee is for, as agreed: "For not showing up, or cancelling less than 1 hour before."
    let agreement: String
    let status: Status
    /// What the owner can do now, if anything.
    let action: Action?
    /// Under the section.
    let footer: String?
    /// For a charged fee whose receipt didn't go out (Stripe had no email for the client, or
    /// couldn't be asked): that, and how to send one, in plain words (the Kit's
    /// `NoShowFeeReceipt.unsentNote`, as the website says it). `nil` otherwise.
    let receiptNote: String?

    enum Status: Equatable {
        /// Nothing charged. `note` says why it can't be, or how it could be; `nil` when there's
        /// nothing to add.
        case notCharged(note: String?)
        /// Stripe reported it succeeded: "No-show fee charged" and "$35 to Visa •••• 4242, Mon, Nov 2 at 11:05 AM."
        case charged(title: String, detail: String)
        /// Stripe said no, and why.
        case declined(String)
        /// The client's bank wants them to approve the charge, which they can't from here.
        case needsClient(String)
        /// An earlier try has no final answer from Stripe yet.
        case pending(String)
    }

    struct Action: Equatable {
        /// "Charge no-show fee ($35)", "Charge late cancellation fee ($35)" or "Check again".
        let title: String
        /// Asked before every new charge. `nil` for Check again: it only finishes the try the owner
        /// already confirmed (the server never charges a fee twice). Finishing it can still send that
        /// charge, if Stripe never got it, which the panel says (`pendingMessage`).
        let confirmation: Confirmation?

        var checksAgain: Bool { confirmation == nil }
    }

    struct Confirmation: Equatable {
        /// "Charge $35 to Kim Sample's Visa •••• 4242?"
        let title: String
        let message: String
        /// "Charge $35".
        let button: String
    }

    /// An earlier try has no final answer from Stripe, and the booking can still be charged. Check
    /// again finishes that try, as the server does: it asks Stripe first, and sends the same charge
    /// (still at most once) only if Stripe never got it. Reopening first makes it only ask.
    static let pendingMessage = "Stripe hasn't confirmed this charge yet. Check again finishes it: if it went through, it shows as charged, and if Stripe never got it, it's sent now. To not charge it, reopen the appointment first."
    /// The same, once the booking can't be charged any more (reopened, or the visit completed):
    /// Check again only asks Stripe how that try went, and nothing more is charged.
    static let pendingCheckOnlyMessage = "Stripe hasn't confirmed this charge yet. Check again asks Stripe how it went: if it went through, it shows as charged, and if not, nothing is charged."

    /// Under a fee the bank turned down: the card isn't charged again (the server's rule), and the
    /// Cancellation & No-Show Policy promises the client written notice and at least 7 days to pay
    /// another way.
    static let turnedDownFooter =
        "The card isn't charged again. Tell the client in writing (a text, or an email if they gave one), and give them at least 7 days to pay the fee another way, for example at the shop."

    /// `nil` when the appointment has no card on file (booked at the shop, by phone, or before
    /// no-show protection was on). `others` are the day's appointments: a late cancellation whose
    /// time another client was booked into isn't charged (the policy's promise, and the server's
    /// rule, checked once the appointment has ended: before that, the note says when it can be).
    init?(appointment: IzzyAPI.Appointment, now: Date, shopTime: ShopTime, others: [IzzyAPI.Appointment] = []) {
        guard let fee = appointment.noShowFee else { return nil }
        let card = appointment.card?.label ?? "the card on file"
        cardLabel = appointment.card?.label ?? "Card on file"
        feeLabel = fee.fullPrice ? "\(fee.amountLabel) (the full service price)" : fee.amountLabel
        if let window = fee.lateCancelWindowMinutes {
            agreement = "For not showing up, or cancelling less than \(IzzyAPI.NoShowRule.windowLabel(minutes: window)) before."
        } else {
            agreement = "For not showing up. Cancelling in the app before the start is free."
        }
        let found = appointment.chargeableFee(at: now)
        let timeTaken = found == .lateCancel && appointment.timeTaken(among: others)
        let chargeable = timeTaken ? nil : found

        receiptNote = fee.status == .charged ? fee.receipt?.unsentNote : nil
        switch fee.status {
        case .charged:
            let when = fee.chargedAt.map { ", \(shopTime.dayAndTime($0))" } ?? ""
            status = .charged(title: "\(fee.title) charged", detail: "\(fee.amountLabel) to \(card)\(when).")
            footer = "Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee."
        case .declined:
            status = .declined(Self.text(fee.message, or: "The bank declined the card."))
            footer = Self.turnedDownFooter
        case .needsAction:
            status = .needsClient(Self.text(fee.message, or: "The client's bank wants them to approve this charge. Ask them to pay at the shop."))
            footer = Self.turnedDownFooter
        case .pending:
            if case .chargeable = appointment.feeCase(at: now) {
                status = .pending(Self.pendingMessage)
            } else {
                status = .pending(Self.pendingCheckOnlyMessage)
            }
            footer = nil
        case .none:
            status = .notCharged(note: timeTaken ? IzzyAPI.NoShowRule.timeTakenMessage : Self.note(for: appointment, now: now))
            footer = chargeable == nil
                ? nil
                : "Nothing is charged until you confirm, and a fee is only ever charged once."
        }

        if appointment.isFeePending {
            action = Action(title: "Check again", confirmation: nil)
        } else if let reason = chargeable {
            let amount = fee.amountLabel
            action = Action(title: "Charge \(reason.title.lowercased()) (\(amount))", confirmation: Confirmation(
                title: "Charge \(amount) to \(appointment.customer.name)'s \(card)?",
                message: Self.confirmationMessage(for: appointment, fee: fee, reason: reason, shopTime: shopTime),
                button: "Charge \(amount)"
            ))
        } else {
            action = nil
        }
    }

    /// Why a fee that wasn't charged can't be, or how it could be, in plain words.
    private static func note(for appointment: IzzyAPI.Appointment, now: Date) -> String? {
        guard case .refused(let refusal) = appointment.feeCase(at: now) else { return nil }
        // A client who cancelled in the app (or asked to) is never charged a no-show fee: say so first.
        if appointment.noShowFee?.customerCancelledAt != nil { return refusal }
        switch appointment.status {
        case .booked:
            // More than 7 days after the start, no fee can be charged any more: say that instead.
            if refusal == IzzyAPI.NoShowRule.feeDeadlineMessage { return refusal }
            // Completed before and reopened: it can't become a no-show, so there's no fee to charge.
            if appointment.completedBefore { return IzzyAPI.NoShowRule.completedNoShowMessage }
            // Cancelled by the shop before and reopened: there's never a fee ("The shop cancelled this
            // booking, so there's no fee.").
            if appointment.shopCancelledBefore { return refusal }
            return appointment.end > now
                ? "If the client doesn't come, you can mark a no-show once the appointment has ended. Then you can charge the fee."
                : "If the client didn't come, mark a no-show. Then you can charge the fee."
        case .completed:
            // The client came: there's nothing to explain.
            return nil
        case .noShow, .cancelled:
            return refusal
        }
    }

    private static func confirmationMessage(
        for appointment: IzzyAPI.Appointment,
        fee: IzzyAPI.NoShowFee,
        reason: IzzyAPI.NoShowFeeReason,
        shopTime: ShopTime
    ) -> String {
        let what = "\(appointment.serviceName) with \(appointment.barberName), \(shopTime.dayAndTime(appointment.start))"
        switch reason {
        case .noShow:
            return "No-show fee for \(what). The client agreed to it when booking."
        case .lateCancel:
            var message = "Late cancellation fee for \(what)"
            if let cancelled = fee.customerCancelledAt {
                // With its day when that's not the appointment's (a 24-hour window, say), so "3 PM"
                // isn't read as 3 PM on the appointment's day, after it.
                let sameDay = shopTime.day(containing: cancelled) == shopTime.day(containing: appointment.start)
                message += sameDay
                    ? ": the client cancelled at \(shopTime.time(cancelled))"
                    : ": the client cancelled on \(shopTime.dayAndTime(cancelled))"
                if let window = fee.lateCancelWindowMinutes {
                    message += ", less than \(IzzyAPI.NoShowRule.windowLabel(minutes: window)) before"
                }
            }
            // A walk-in rung up without an appointment can't be seen here: the policy promises no fee then too.
            return message + ". They agreed to it when booking. Don't charge it if another client, such as a walk-in, took this time."
        }
    }

    private static func text(_ message: String?, or fallback: String) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: Status changes

    /// What Reopen says first, when reopening changes something about the fee: a charged fee isn't
    /// refunded (refunds are made in the Stripe Dashboard), one Stripe hasn't confirmed yet may
    /// have gone through, a booking the shop cancelled can't be charged a fee once it's reopened
    /// (the server keeps that the shop cancelled it), a late cancellation that's reopened can't be
    /// charged any more (also before the appointment has ended, when it couldn't be charged yet),
    /// and a booking the client cancelled in the app can't be charged a no-show fee once it's
    /// reopened (the server keeps that they cancelled). `nil` when there's nothing to say.
    static func reopenWarning(for appointment: IzzyAPI.Appointment, now: Date) -> String? {
        guard let fee = appointment.noShowFee else { return nil }
        switch fee.status {
        case .charged:
            return "The \(fee.amountLabel) \(fee.title.lowercased()) stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        case .pending:
            return "Stripe hasn't confirmed the \(fee.amountLabel) \(fee.title.lowercased()) yet. If it went through, reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        case .none, .declined, .needsAction:
            // The shop cancelled it: once it's reopened, no fee can ever be charged for it.
            if appointment.shopCancelledBefore, appointment.status != .completed {
                return Self.reopenShopCancelledWarning
            }
            // A late cancellation that can be charged once the appointment has ended (or now, if it has).
            if appointment.chargeableFee(at: max(now, appointment.end)) == .lateCancel {
                return "Once it's reopened, the \(fee.amountLabel) late cancellation fee can't be charged any more. "
                    + "The client cancelled in the app, so a no-show fee can't be charged either."
            }
            // Cancelled in time (or by the shop after the client): free, and a no-show fee is gone too.
            if appointment.status == .cancelled, appointment.card != nil, fee.customerCancelledAt != nil {
                return "The client cancelled this booking in the app, so once it's reopened, it can't be charged a no-show fee. "
                    + "To keep a no-show fee, ask them to book again in the app instead."
            }
            // Marked done: the client came, and that stays (the server's completedAt), as the website says.
            if appointment.status == .completed, appointment.card != nil {
                return Self.reopenCompletedWarning
            }
            return nil
        }
    }

    /// What Reopen says first for a booking with a card on file that was marked done.
    static let reopenCompletedWarning =
        "It was marked done, so even once it's reopened, it can't be marked a no-show or charged a no-show fee: the client came."

    /// What Reopen says first for a booking with a card on file the shop cancelled (the server's
    /// `shopCancelledAt`): the Cancellation & No-Show Policy promises no fee once the shop cancels.
    static let reopenShopCancelledWarning =
        "The shop cancelled this booking, so once it's reopened, it can't be charged a fee. To keep a fee, ask the client to book again in the app instead."

    /// Under the status buttons of a booking with a card on file that hasn't ended: "Mark no-show"
    /// isn't offered yet, because until the start the client can still cancel in the app, and a
    /// client who comes before the end isn't a no-show. One that was completed before and reopened
    /// is never offered it, and says so in the server's words ("This appointment was marked
    /// completed, so it can't become a no-show."), nor is one the shop cancelled before it was
    /// reopened ("The shop cancelled this booking, so it can't become a no-show."). Worded as the
    /// website's Business area does.
    static func noShowHint(for appointment: IzzyAPI.Appointment, now: Date, shopTime: ShopTime) -> String? {
        guard appointment.status == .booked, !appointment.canMarkNoShow(at: now) else { return nil }
        if appointment.completedBefore { return IzzyAPI.NoShowRule.completedNoShowMessage }
        if appointment.shopCancelledBefore { return IzzyAPI.NoShowRule.shopCancelledNoShowMessage }
        let today = shopTime.day(containing: now) == shopTime.day(containing: appointment.end)
        let when = today ? "at \(shopTime.time(appointment.end))" : "on \(shopTime.dayAndTime(appointment.end))"
        let why = appointment.start > now
            ? "Until it starts, the client can still cancel in the app."
            : "A client who comes before then isn't a no-show."
        return "You can mark a no-show once the appointment ends \(when). \(why)"
    }

    /// Added to "Cancel appointment"'s question for a booking with a card on file: the shop
    /// cancelling is never charged, but a fee already charged isn't refunded by it, and one Stripe
    /// hasn't confirmed may have gone through. `nil` without a card on file.
    static func shopCancelNote(for appointment: IzzyAPI.Appointment) -> String? {
        guard appointment.card != nil else { return nil }
        guard let fee = appointment.noShowFee else { return noFeeWhenTheShopCancels }
        let what = "\(fee.amountLabel) \(fee.title.lowercased())"
        switch fee.status {
        case .charged:
            return "The \(what) stays charged: cancelling doesn't refund it. Refunds are made in the Stripe Dashboard."
        case .pending:
            return "Stripe hasn't confirmed the \(what) yet. If it went through, cancelling doesn't refund it. Refunds are made in the Stripe Dashboard."
        case .none, .declined, .needsAction:
            return noFeeWhenTheShopCancels
        }
    }

    static let noFeeWhenTheShopCancels = "There's no fee when the shop cancels."
}

extension IzzyAPI.Appointment {
    /// Whether "Mark no-show" is offered for a booked appointment, by the server's rule (the Kit's
    /// `canBeMarkedNoShow(at:)`): for a booking with a card on file only once it has ended (the
    /// server answers `not_started` before, so the client may still come) and never once it was
    /// completed or cancelled by the shop, even if it was reopened since (`completedAt`,
    /// `shopCancelledAt`; the server answers `already_completed` or `shop_cancelled`), for others
    /// whenever it's booked, as before.
    func canMarkNoShow(at now: Date) -> Bool {
        status == .booked && canBeMarkedNoShow(at: now)
    }

    /// Whether another client has this appointment's time now: another booked or completed
    /// appointment of the same barber that overlaps it, among `others` (the day's). Then a late
    /// cancellation isn't charged: the Cancellation & No-Show Policy promises it, and the server
    /// refuses it (`timeTakenSince` in server/src/noshowfee.ts), asked once the appointment has
    /// ended, when every booking for that time is in.
    func timeTaken(among others: [IzzyAPI.Appointment]) -> Bool {
        others.contains { other in
            other.id != id && other.barberId == barberId
                && (other.status == .booked || other.status == .completed)
                && other.start < end && other.end > start
        }
    }

    /// The client cancelled in the app less than the agreed window before the start, and more than
    /// 15 minutes after booking: a late cancellation, which can be charged (once) while it stays cancelled.
    var isCancelledLate: Bool {
        guard status == .cancelled, cancelledBy == .customer, card != nil, let fee = noShowFee else { return false }
        return IzzyAPI.NoShowRule.cancelledLate(
            start: start, customerCancelledAt: fee.customerCancelledAt, lateCancelWindowMinutes: fee.lateCancelWindowMinutes,
            createdAt: createdAt
        )
    }
}

extension FeePanel {
    /// "Visa ending in 4242": what VoiceOver says for "Visa •••• 4242" (it would read each dot).
    static func spokenCard(_ card: IzzyAPI.CardOnFile) -> String {
        "\(card.brandName) ending in \(card.last4)"
    }
}

/// The short labels on a schedule row and at the top of an appointment's details: the status
/// ("Cancelled late" for a late cancellation), Paid, and the card on file ("Card on file · Visa
/// •••• 4242") or what happened to its fee ("No-show fee $35 charged").
struct AppointmentBadges: Equatable {
    enum Tone: Equatable {
        case status(IzzyAPI.AppointmentStatus)
        case paid
        /// A card on file, nothing charged.
        case card
        /// Stripe charged the fee.
        case feeCharged
        /// The fee was declined.
        case feeDeclined
        /// The fee needs a look: not confirmed yet, or the client has to approve it.
        case feeWaiting
    }

    struct Item: Equatable {
        let text: String
        let tone: Tone
        /// What VoiceOver says, when it isn't `text` ("Card on file, Visa ending in 4242").
        var spokenText: String?

        var spoken: String { spokenText ?? text }
    }

    let items: [Item]

    init(appointment: IzzyAPI.Appointment) {
        var items = [Item(
            text: appointment.isCancelledLate ? "Cancelled late" : appointment.status.title,
            tone: .status(appointment.status)
        )]
        if let sale = appointment.sale {
            // Checked out: "Paid $60 · Cash".
            items.append(Item(text: sale.paidLabel, tone: .paid))
        } else if appointment.payment.status == .paid {
            items.append(Item(text: appointment.payment.amountCents.map { "Paid \(Money.amount($0))" } ?? "Paid", tone: .paid))
        }
        if let fee = appointment.noShowFee {
            switch fee.status {
            case .charged: items.append(Item(text: "\(fee.title) \(fee.amountLabel) charged", tone: .feeCharged))
            case .declined: items.append(Item(text: "Fee declined", tone: .feeDeclined))
            case .needsAction: items.append(Item(text: "Fee needs the client", tone: .feeWaiting))
            case .pending: items.append(Item(text: "Fee not confirmed", tone: .feeWaiting))
            case .none: items.append(Self.cardOnFile(appointment.card))
            }
        } else if appointment.card != nil {
            items.append(Self.cardOnFile(appointment.card))
        }
        self.items = items
    }

    /// "Card on file · Visa •••• 4242", or "Card on file" without the card's details.
    private static func cardOnFile(_ card: IzzyAPI.CardOnFile?) -> Item {
        guard let card else { return Item(text: "Card on file", tone: .card) }
        return Item(text: "Card on file · \(card.label)", tone: .card, spokenText: "Card on file, \(FeePanel.spokenCard(card))")
    }

    /// What VoiceOver reads for them, in order.
    var spoken: [String] { items.map(\.spoken) }
}

/// The Payment section of an appointment's details: its checkout ("Paid $60 · Cash"), or the
/// service's payment, and a fee charged to the
/// card on file said apart from it. "Not paid yet $35" right under "No-show fee charged: $35" could
/// be read as the fee not having gone through, or as the price still owed and taken at the counter.
struct PaymentSummary: Equatable {
    /// "Paid", "Not paid yet", or "Service not paid" once a fee was charged.
    let title: String
    /// What was paid ("$40.00"), or the service's price ("$35").
    let value: String
    /// "The $35 no-show fee was charged to the card on file." once Stripe charged it.
    let feeNote: String?

    init(appointment: IzzyAPI.Appointment) {
        let fee = appointment.noShowFee
        let feeCharged = fee?.status == .charged
        if let sale = appointment.sale {
            // Checked out: "$60 · Cash".
            title = "Paid"
            value = "\(Price.currencyString(cents: sale.totalCents)) · \(sale.method.title)"
        } else if appointment.payment.status == .paid {
            title = "Paid"
            value = appointment.payment.amountCents.map(Money.amount) ?? "Yes"
        } else {
            title = feeCharged ? "Service not paid" : "Not paid yet"
            value = appointment.priceLabel
        }
        if let fee, feeCharged {
            feeNote = "The \(fee.amountLabel) \(fee.title.lowercased()) was charged to the card on file."
        } else {
            feeNote = nil
        }
    }
}

extension IzzyAPI.Payment {
    /// "No-show fee" or "Late cancellation fee" for a fee charged to a card on file; `nil` for a
    /// payment taken in the shop.
    var feeLabel: String? { kind.isFee ? kind.title : nil }

    /// What Payments today says for it: the description, without the "No-show fee: " its label
    /// already says ("Haircut with Julian, Tue, Nov 3 at 11:00 AM").
    var listTitle: String {
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard kind.isFee else { return text.isEmpty ? "Card payment" : text }
        let prefix = kind.title + ": "
        if text.hasPrefix(prefix), text.count > prefix.count { return String(text.dropFirst(prefix.count)) }
        return text.isEmpty ? kind.title : text
    }
}
