import Foundation
import IzzyClipzKit

/// An appointment's card on file and its fee (for a no-show or a late cancellation), as its
/// details show them: what the client agreed to when booking, what happened to the fee, and what
/// the owner can do now. Worked out from the appointment as the server sent it, so the details
/// read the same when they're opened again later.
///
/// Which fee can be charged is the server's rule, through the Kit (`Appointment.chargeableFee(at:)`):
/// a no-show whose start has passed, or a cancellation by the client less than the agreed window
/// before the start. Only a fee Stripe reported as succeeded shows as charged.
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
        /// "Charge no-show fee ($35)", "Charge late cancellation fee ($35)", "Charge again ($35)" or "Check again".
        let title: String
        /// Asked before every new charge. `nil` for Check again: it only finishes the try the owner
        /// already confirmed (the server never charges a fee twice).
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

    static let pendingMessage = "Stripe hasn't confirmed this charge yet. Check again to see if it went through. The fee is never charged twice."

    /// `nil` when the appointment has no card on file (booked at the shop, by phone, or before
    /// no-show protection was on).
    init?(appointment: IzzyAPI.Appointment, now: Date, shopTime: ShopTime) {
        guard let fee = appointment.noShowFee else { return nil }
        let card = appointment.card?.label ?? "the card on file"
        cardLabel = appointment.card?.label ?? "Card on file"
        feeLabel = fee.fullPrice ? "\(fee.amountLabel) (the full service price)" : fee.amountLabel
        if let window = fee.lateCancelWindowMinutes {
            agreement = "For not showing up, or cancelling less than \(IzzyAPI.NoShowRule.windowLabel(minutes: window)) before."
        } else {
            agreement = "For not showing up. Cancelling in the app before the start is free."
        }

        switch fee.status {
        case .charged:
            let when = fee.chargedAt.map { ", \(shopTime.dayAndTime($0))" } ?? ""
            status = .charged(title: "\(fee.title) charged", detail: "\(fee.amountLabel) to \(card)\(when).")
            footer = "Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee."
        case .declined:
            status = .declined(Self.text(fee.message, or: "The bank declined the card."))
            footer = "You can try the card again later, or ask the client to pay at the shop."
        case .needsAction:
            status = .needsClient(Self.text(fee.message, or: "The client's bank wants them to approve this charge. Ask them to pay at the shop."))
            footer = nil
        case .pending:
            status = .pending(Self.pendingMessage)
            footer = nil
        case .none:
            status = .notCharged(note: Self.note(for: appointment, now: now))
            footer = appointment.chargeableFee(at: now) == nil
                ? nil
                : "Nothing is charged until you confirm, and a fee is only ever charged once."
        }

        if appointment.isFeePending {
            action = Action(title: "Check again", confirmation: nil)
        } else if let reason = appointment.chargeableFee(at: now) {
            let amount = fee.amountLabel
            let title = fee.status == .declined || fee.status == .needsAction
                ? "Charge again (\(amount))"
                : "Charge \(reason.title.lowercased()) (\(amount))"
            action = Action(title: title, confirmation: Confirmation(
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
            return appointment.start > now
                ? "If the client doesn't come, you can mark a no-show once the appointment has started. Then you can charge the fee."
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
                message += ": the client cancelled at \(shopTime.time(cancelled))"
                if let window = fee.lateCancelWindowMinutes {
                    message += ", less than \(IzzyAPI.NoShowRule.windowLabel(minutes: window)) before"
                }
            }
            return message + ". They agreed to it when booking."
        }
    }

    private static func text(_ message: String?, or fallback: String) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: Status changes

    /// What Reopen says first, when reopening changes something about the fee: a charged fee isn't
    /// refunded (refunds are made in the Stripe Dashboard), and a late cancellation that's
    /// reopened can't be charged any more. `nil` when there's nothing to say.
    static func reopenWarning(for appointment: IzzyAPI.Appointment, now: Date) -> String? {
        guard let fee = appointment.noShowFee else { return nil }
        if fee.status == .charged {
            return "The \(fee.amountLabel) \(fee.title.lowercased()) stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard."
        }
        if fee.status != .pending, appointment.chargeableFee(at: now) == .lateCancel {
            return "Once it's reopened, the \(fee.amountLabel) late cancellation fee can't be charged any more."
        }
        return nil
    }

    /// Under the status buttons of a booking with a card on file that hasn't started: "Mark no-show"
    /// isn't offered yet, because the client can still cancel in the app until then.
    static func noShowHint(for appointment: IzzyAPI.Appointment, now: Date, shopTime: ShopTime) -> String? {
        guard appointment.status == .booked, !appointment.canMarkNoShow(at: now) else { return nil }
        return "You can mark a no-show once the appointment starts at \(shopTime.time(appointment.start)). Until then, the client can still cancel in the app."
    }

    /// Added to "Cancel appointment"'s question for a booking with a card on file.
    static let shopCancelNote = "There's no fee when the shop cancels."
}

extension IzzyAPI.Appointment {
    /// Whether "Mark no-show" is offered: for a booking with a card on file only once it has
    /// started (the server answers `not_started` before, so the client can still cancel), for
    /// others whenever it's booked, as before.
    func canMarkNoShow(at now: Date) -> Bool {
        status == .booked && (card == nil || start <= now)
    }

    /// The client cancelled in the app less than the agreed window before the start: a late
    /// cancellation, which can be charged (once) while it stays cancelled.
    var isCancelledLate: Bool {
        guard status == .cancelled, cancelledBy == .customer, card != nil, let fee = noShowFee else { return false }
        return IzzyAPI.NoShowRule.cancelledLate(
            start: start, customerCancelledAt: fee.customerCancelledAt, lateCancelWindowMinutes: fee.lateCancelWindowMinutes
        )
    }
}

/// The short labels on a schedule row and at the top of an appointment's details: the status
/// ("Cancelled late" for a late cancellation), Paid, and the card on file or what happened to its
/// fee ("No-show fee $35 charged").
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
    }

    let items: [Item]

    init(appointment: IzzyAPI.Appointment) {
        var items = [Item(
            text: appointment.isCancelledLate ? "Cancelled late" : appointment.status.title,
            tone: .status(appointment.status)
        )]
        if appointment.payment.status == .paid {
            items.append(Item(text: appointment.payment.amountCents.map { "Paid \(Money.amount($0))" } ?? "Paid", tone: .paid))
        }
        if let fee = appointment.noShowFee {
            switch fee.status {
            case .charged: items.append(Item(text: "\(fee.title) \(fee.amountLabel) charged", tone: .feeCharged))
            case .declined: items.append(Item(text: "Fee declined", tone: .feeDeclined))
            case .needsAction: items.append(Item(text: "Fee needs the client", tone: .feeWaiting))
            case .pending: items.append(Item(text: "Fee not confirmed", tone: .feeWaiting))
            case .none: items.append(Item(text: "Card on file", tone: .card))
            }
        } else if appointment.card != nil {
            items.append(Item(text: "Card on file", tone: .card))
        }
        self.items = items
    }

    /// What VoiceOver reads for them, in order.
    var spoken: [String] { items.map(\.text) }
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
