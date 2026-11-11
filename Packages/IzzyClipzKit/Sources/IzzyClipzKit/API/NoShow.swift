import Foundation

// No-show protection: a card saved before booking (Stripe Checkout in setup
// mode), charged only if the client doesn't come or cancels late (less than the
// agreed window before the start), and only when the owner decides to. Models
// field for field as the server writes them (server/README.md, "No-show
// protection").

// MARK: - The card on an appointment

extension IzzyAPI {
    /// The card on file for an appointment's no-shows: `{ brand, last4 }`.
    public struct CardOnFile: Codable, Hashable, Sendable {
        /// Stripe's brand: "visa", "mastercard", "amex", "discover", …
        public var brand: String
        /// The card's last 4 digits.
        public var last4: String

        public init(brand: String, last4: String) {
            self.brand = brand
            self.last4 = last4
        }

        /// "Visa", "Mastercard", "American Express"; "Card" for a brand the Kit doesn't know.
        public var brandName: String { IzzyAPI.cardBrandName(brand) }

        /// "Visa •••• 4242".
        public var label: String { "\(brandName) •••• \(last4)" }
    }

    /// A brand as people say it, from Stripe's brand value.
    public static func cardBrandName(_ brand: String) -> String {
        switch brand.lowercased() {
        case "visa": return "Visa"
        case "mastercard": return "Mastercard"
        case "amex", "american_express": return "American Express"
        case "discover": return "Discover"
        case "diners", "diners_club": return "Diners Club"
        case "jcb": return "JCB"
        case "unionpay", "union_pay": return "UnionPay"
        case "cartes_bancaires": return "Cartes Bancaires"
        case "eftpos_au", "eftpos_australia": return "eftpos"
        case "link": return "Link"
        default: return "Card"
        }
    }

    /// What happened to an appointment's no-show fee.
    public enum NoShowFeeStatus: String, Codable, CaseIterable, Hashable, Sendable {
        /// Not charged; the owner may charge it once the client didn't come.
        case none
        /// Asked Stripe and no final answer yet (still processing, or the answer was lost).
        /// Charging again asks Stripe how it went; it never charges twice.
        case pending
        /// Stripe reported the payment as succeeded. The only status that means money moved.
        case charged
        /// Stripe said no (`message` says why). Charging again makes a new try.
        case declined
        /// The client's bank wants them to approve it, which they can't from here.
        case needsAction

        /// A status this version doesn't know reads as `pending`: never as charged, and
        /// charging again only asks Stripe how it went.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = NoShowFeeStatus(rawValue: raw) ?? .pending
        }
    }

    /// What a fee charged to the card on file is for.
    public enum NoShowFeeReason: String, Codable, CaseIterable, Hashable, Sendable {
        /// The client didn't come.
        case noShow
        /// The client cancelled in the app less than the agreed window before the start.
        case lateCancel

        /// "No-show fee", "Late cancellation fee".
        public var title: String {
            switch self {
            case .noShow: return "No-show fee"
            case .lateCancel: return "Late cancellation fee"
            }
        }
    }

    /// An appointment's fee (for a no-show or a late cancellation): `{ amountCents, fullPrice,
    /// status, chargedAt, message, customerCancelledAt, lateCancelWindowMinutes, reason }`.
    public struct NoShowFee: Codable, Hashable, Sendable {
        /// The fee agreed at booking, in cents. Changing the settings later doesn't change it.
        public var amountCents: Int
        /// Whether the fee is the booked service's whole price (it is at 100%), so the warnings
        /// say "the full service price". `false` from a server before it said so.
        public var fullPrice: Bool
        public var status: NoShowFeeStatus
        /// When Stripe reported it charged; `nil` otherwise.
        public var chargedAt: Date?
        /// Why it was declined or needs the client, in plain words for the owner.
        public var message: String?
        /// When the client cancelled in the app (or asked to) before the start. Then there's no
        /// no-show fee; inside `lateCancelWindowMinutes` of the start it's a late cancellation.
        public var customerCancelledAt: Date?
        /// The late-cancellation window in the policy the client agreed to, in minutes; `nil` when
        /// it had none (cancelling in the app before the start is free then).
        public var lateCancelWindowMinutes: Int?
        /// What the fee is (or would be) for, in the server's words: once the shop tried to charge
        /// it, what that charge was for; before, the case that applies now; `nil` when neither does.
        public var reason: NoShowFeeReason?

        public init(
            amountCents: Int,
            fullPrice: Bool = false,
            status: NoShowFeeStatus = .none,
            chargedAt: Date? = nil,
            message: String? = nil,
            customerCancelledAt: Date? = nil,
            lateCancelWindowMinutes: Int? = nil,
            reason: NoShowFeeReason? = nil
        ) {
            self.amountCents = amountCents
            self.fullPrice = fullPrice
            self.status = status
            self.chargedAt = chargedAt
            self.message = message
            self.customerCancelledAt = customerCancelledAt
            self.lateCancelWindowMinutes = lateCancelWindowMinutes
            self.reason = reason
        }

        /// "$20", "$17.50".
        public var amountLabel: String { Price.currencyString(cents: amountCents) }

        public var isCharged: Bool { status == .charged }

        /// "Late cancellation fee", or "No-show fee" (also when the case isn't known yet).
        public var title: String { (reason ?? .noShow).title }

        /// From when cancelling an appointment starting at `start` may be charged; `nil` when
        /// cancelling in the app is free until the start.
        public func lateCancelStarts(before start: Date) -> Date? {
            lateCancelWindowMinutes.map { start.addingTimeInterval(-Double($0) * 60) }
        }

        private enum CodingKeys: String, CodingKey {
            case amountCents, fullPrice, status, chargedAt, message, customerCancelledAt, lateCancelWindowMinutes, reason
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amountCents = try container.decode(Int.self, forKey: .amountCents)
            // Missing on a server from before it said so: then the warnings just give the amount.
            fullPrice = try container.decodeIfPresent(Bool.self, forKey: .fullPrice) ?? false
            status = try container.decode(NoShowFeeStatus.self, forKey: .status)
            chargedAt = try container.decodeIfPresent(Date.self, forKey: .chargedAt)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            // Missing on a server from before late cancellations; a reason this version doesn't
            // know reads as none, so the app never offers to charge something it can't name.
            customerCancelledAt = try container.decodeIfPresent(Date.self, forKey: .customerCancelledAt)
            lateCancelWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .lateCancelWindowMinutes)
            reason = try container.decodeIfPresent(String.self, forKey: .reason).flatMap(NoShowFeeReason.init(rawValue:))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(amountCents, forKey: .amountCents)
            try container.encode(fullPrice, forKey: .fullPrice)
            try container.encode(status, forKey: .status)
            try container.encode(chargedAt, forKey: .chargedAt)
            try container.encode(message, forKey: .message)
            try container.encode(customerCancelledAt, forKey: .customerCancelledAt)
            try container.encode(lateCancelWindowMinutes, forKey: .lateCancelWindowMinutes)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Which fee an appointment can be charged

extension IzzyAPI.Appointment {
    /// Which fee the server lets the owner charge now, or why not, mirroring the server
    /// (`feeCaseAt` in `server/src/feecase.ts`, checked against `server/test/fixtures/fee-cases.json`):
    /// a no-show only once the appointment has ended, a late cancellation (more than 15 minutes after
    /// booking) right away, and nothing more than 7 days after the start. It doesn't look at whether
    /// the fee is charged already: the server answers that as it is.
    public func feeCase(at now: Date) -> IzzyAPI.NoShowRule.FeeCase {
        guard card != nil, let noShowFee else { return .refused(IzzyAPI.NoShowRule.noCardMessage) }
        return IzzyAPI.NoShowRule.feeCase(
            status: status, cancelledBy: cancelledBy, start: start, end: end, createdAt: createdAt,
            customerCancelledAt: noShowFee.customerCancelledAt, lateCancelWindowMinutes: noShowFee.lateCancelWindowMinutes,
            at: now
        )
    }

    /// The last moment the fee can be charged: 7 days after the start (`nil` without a card on
    /// file). After it, "Charge" isn't offered, and `feeCase(at:)` says why
    /// (`NoShowRule.feeDeadlineMessage`); a try already pending can still be checked.
    public var feeDeadline: Date? {
        guard card != nil, noShowFee != nil else { return nil }
        return IzzyAPI.NoShowRule.feeDeadline(start: start)
    }

    /// Why the shop can't mark this appointment a no-show now, as the server answers
    /// (`PATCH /api/owner/appointments/:id`), or `nil` when it can: a booking with a card on file
    /// only once it has ended (409 `not_started`), and never once it's completed (409
    /// `already_completed`; the server also remembers a completed booking that was reopened since,
    /// which the Kit can't see). One without a card can always be marked. Ignores the checkout rule
    /// (a checked-out appointment needs its sale voided first).
    public func noShowMarkRefusal(at now: Date) -> String? {
        IzzyAPI.NoShowRule.noShowMarkRefusal(status: status, hasCard: card != nil, end: end, now: now)
    }

    /// Whether the shop can mark this appointment a no-show now (`noShowMarkRefusal(at:)` is `nil`).
    public func canBeMarkedNoShow(at now: Date) -> Bool {
        status != .noShow && noShowMarkRefusal(at: now) == nil
    }

    /// The fee the owner can act on now, or `nil`:
    /// - "Charge no-show fee" or "Charge late cancellation fee": a no-show whose end has passed,
    ///   or a late cancellation by the client, with a card on file and a fee that isn't charged yet
    ///   (a declined one, or one that needs the client, can be tried again), up to 7 days after the
    ///   start;
    /// - a `pending` fee (an earlier try's answer never came), always, whatever happened since, as
    ///   "Check again" (`isFeePending`): the server only asks Stripe how that try went, never
    ///   charges twice, and settles it as not charged ("Nothing was charged. …", a 409) when Stripe
    ///   never got it and the booking can't be charged any more. Its reason is that try's.
    public func chargeableFee(at now: Date) -> IzzyAPI.NoShowFeeReason? {
        guard card != nil, let noShowFee, noShowFee.status != .charged else { return nil }
        if noShowFee.status == .pending {
            if case .chargeable(let reason) = feeCase(at: now) { return noShowFee.reason ?? reason }
            return noShowFee.reason ?? .noShow
        }
        guard case .chargeable(let reason) = feeCase(at: now) else { return nil }
        return reason
    }

    /// Whether the owner can charge the fee now, or check again on a pending one (`chargeableFee(at:)`).
    public func canChargeNoShowFee(at now: Date) -> Bool {
        chargeableFee(at: now) != nil
    }

    /// Whether an earlier try at the fee has no final answer yet: the owner's button reads "Check
    /// again" rather than "Charge" (calling `chargeNoShowFee` then only asks Stripe how it went).
    public var isFeePending: Bool {
        card != nil && noShowFee?.status == .pending
    }

    /// For the client's "Cancel appointment" confirmation: "Cancelling now, less than 1 hour
    /// before your appointment, may be charged $40, the full service price." when cancelling now
    /// would be a late cancellation under the policy they agreed to; `nil` when it's free.
    ///
    /// Like the server, the time that counts is the first time the client cancelled (or asked to),
    /// if there was one: a booking they cancelled early, which the shop then reopened, stays free.
    /// Cancelling within 15 minutes of booking is free too (the grace period), so there's no warning then.
    /// Work it out again when the client taps the button, not only when the dialog opens. The
    /// server decides by its own clock, though: when the phone's is off (or the minute turned while
    /// the dialog was open), cancelling throws `APIError.lateCancelFee` with this same warning.
    public func lateCancelWarning(at now: Date) -> String? {
        guard isCancellable(at: now), card != nil, let noShowFee, let window = noShowFee.lateCancelWindowMinutes,
              IzzyAPI.NoShowRule.cancelledLate(
                  start: start, customerCancelledAt: noShowFee.customerCancelledAt ?? now, lateCancelWindowMinutes: window,
                  createdAt: createdAt
              )
        else { return nil }
        return IzzyAPI.NoShowRule.lateCancelWarning(windowMinutes: window, feeCents: noShowFee.amountCents, fullPrice: noShowFee.fullPrice)
    }

    /// What cancelling late may cost, for the appointment's reminders (`AppointmentPlanner`): a
    /// card on file under a policy that charges late cancellations, and the client hasn't cancelled
    /// or asked to before (after that, the first time decides, whenever they cancel again, so the
    /// reminders leave it out). `nil` otherwise. It carries when it was booked, so the 15 minutes
    /// after booking count as free too.
    public var lateCancelTerms: LateCancelTerms? {
        guard card != nil, let noShowFee, let window = noShowFee.lateCancelWindowMinutes,
              noShowFee.customerCancelledAt == nil
        else { return nil }
        return LateCancelTerms(windowMinutes: window, feeLabel: noShowFee.amountLabel, bookedAt: createdAt)
    }
}

// MARK: - The policy before booking

extension IzzyAPI {
    /// The notice clients see while booking (on Pick a day and time, and on Review): `{ title, message }`,
    /// e.g. "Full Service Cancellation & No-Show Fee" and "Cancelling less than 1 hour before your
    /// appointment, or not showing up, may be charged the full service price ($40). Cancelling in the
    /// app more than 1 hour before is free."
    public struct NoShowWarning: Codable, Hashable, Sendable {
        public var title: String
        public var message: String

        public init(title: String, message: String) {
            self.title = title
            self.message = message
        }
    }

    /// `GET /api/no-show-policy` → `{ required, minFeeCents, maxFeeCents, policyText,
    /// lateCancelWindowMinutes, warning }`.
    ///
    /// When `required`, booking needs a saved card, the app shows `warning`, and the booking sends
    /// `policyText` back exactly as shown (`NoShowAgreement`). Otherwise the other fields are
    /// `nil` and booking works without a card.
    public struct NoShowPolicy: Codable, Hashable, Sendable {
        public var required: Bool
        public var minFeeCents: Int?
        public var maxFeeCents: Int?
        /// What the client agrees to, above "Book appointment", in the server's words.
        public var policyText: String?
        /// Cancelling less than this many minutes before the start may be charged; `nil`:
        /// cancelling in the app before the start is free.
        public var lateCancelWindowMinutes: Int?
        /// The notice to show on Pick a day and time and on Review.
        public var warning: NoShowWarning?

        public init(
            required: Bool,
            minFeeCents: Int? = nil,
            maxFeeCents: Int? = nil,
            policyText: String? = nil,
            lateCancelWindowMinutes: Int? = nil,
            warning: NoShowWarning? = nil
        ) {
            self.required = required
            self.minFeeCents = minFeeCents
            self.maxFeeCents = maxFeeCents
            self.policyText = policyText
            self.lateCancelWindowMinutes = lateCancelWindowMinutes
            self.warning = warning
        }

        /// No card needed.
        public static let notRequired = NoShowPolicy(required: false)

        /// "$20", or "$17.50–$22.50" for any barber when their fees differ; `nil` without a fee.
        public var feeLabel: String? {
            guard required, let minFeeCents, let maxFeeCents else { return nil }
            return NoShowRule.feeLabel(minCents: minFeeCents, maxCents: maxFeeCents)
        }

        /// For the time the client picked, under `warning` on Pick a day and time and on Review:
        /// "This time is less than 1 hour away, so cancelling it more than 15 minutes after booking
        /// may be charged $35." when it starts less than the late-cancellation window after `now`.
        /// The booking lead time is shorter than the window, so the policy's "Cancelling in the app
        /// more than 1 hour before is free" can't apply to such a time: once it's booked, cancelling
        /// is free only for 15 minutes (the grace period). `nil` for a later time, with late
        /// cancellations off, or when no card is needed.
        public func lateCancelNotice(start: Date, now: Date) -> String? {
            guard let window = lateCancelWindowMinutes, let fee = feeLabel,
                  NoShowRule.cancellingMayBeCharged(start: start, now: now, windowMinutes: window)
            else { return nil }
            return NoShowRule.lateCancelNotice(windowMinutes: window, feeLabel: fee)
        }

        private enum CodingKeys: String, CodingKey {
            case required, minFeeCents, maxFeeCents, policyText, lateCancelWindowMinutes, warning
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            required = try container.decode(Bool.self, forKey: .required)
            minFeeCents = try container.decodeIfPresent(Int.self, forKey: .minFeeCents)
            maxFeeCents = try container.decodeIfPresent(Int.self, forKey: .maxFeeCents)
            policyText = try container.decodeIfPresent(String.self, forKey: .policyText)
            // Missing on a server from before late cancellations and the warning.
            lateCancelWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .lateCancelWindowMinutes)
            warning = try container.decodeIfPresent(NoShowWarning.self, forKey: .warning)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(required, forKey: .required)
            try container.encode(minFeeCents, forKey: .minFeeCents)
            try container.encode(maxFeeCents, forKey: .maxFeeCents)
            try container.encode(policyText, forKey: .policyText)
            try container.encode(lateCancelWindowMinutes, forKey: .lateCancelWindowMinutes)
            try container.encode(warning, forKey: .warning)
        }
    }

    /// What a protected booking sends: the saved card's token (`X-Card-Token`) and the policy
    /// text the client was shown, exactly as `NoShowPolicy.policyText` gave it.
    public struct NoShowAgreement: Hashable, Sendable, CustomStringConvertible {
        public var cardToken: CardToken
        public var policyText: String

        public init(cardToken: CardToken, policyText: String) {
            self.cardToken = cardToken
            self.policyText = policyText
        }

        /// Leaves the token out, so it never ends up in a log.
        public var description: String { "NoShowAgreement(cardToken: <redacted>, policyText: \(policyText))" }
    }
}

// MARK: - Saving a card

extension IzzyAPI {
    /// The secret that stands for one saved card: 32 random bytes in base64url (43
    /// characters), the same form as a manage token, made on the phone.
    ///
    /// Make a new one for each "Add a card" (`generate()`), send it with
    /// `startCardCheckout` and `saveCard`, then with every booking that uses the card. The
    /// server keeps only its SHA-256, and only the phone holding it can save or use the card.
    /// Keep it in the Keychain, never in a log.
    public struct CardToken: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
        public let rawValue: String

        /// `nil` unless `rawValue` is what `generate()` makes (see `ManageToken.init(rawValue:)`).
        public init?(rawValue: String) {
            guard let token = ManageToken(rawValue: rawValue) else { return nil }
            self.init(token)
        }

        private init(_ token: ManageToken) {
            rawValue = token.rawValue
        }

        /// A new token from the system's cryptographically secure random number generator.
        public static func generate() -> CardToken {
            CardToken(ManageToken.generate())
        }

        /// A new token from `generator`. Use `generate()` in the apps; this is for tests.
        public static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> CardToken {
            CardToken(ManageToken.generate(using: &generator))
        }

        /// Leaves the token out, so it never ends up in a log.
        public var description: String { "CardToken(<redacted>)" }
    }

    /// `POST /api/cards/checkout` → 201 `{ url, sessionId }`: Stripe's card page.
    public struct CardCheckout: Codable, Hashable, Sendable {
        /// Open it in `ASWebAuthenticationSession` with `callbackScheme`.
        public var url: URL
        /// The Checkout Session, `cs_…`. The callback carries it too.
        public var sessionId: String

        public init(url: URL, sessionId: String) {
            self.url = url
            self.sessionId = sessionId
        }

        private enum CodingKeys: String, CodingKey {
            case url, sessionId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeWebURL(forKey: .url)
            sessionId = try container.decode(String.self, forKey: .sessionId)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(sessionId, forKey: .sessionId)
        }

        /// The app's URL scheme Stripe's page comes back to (through the server's https page).
        public static let callbackScheme = "izzyclipz"
    }

    /// How Stripe's card page ended, from the URL `ASWebAuthenticationSession` hands back:
    /// `izzyclipz://card-saved?session_id=cs_…`, `izzyclipz://card-cancelled` or
    /// `izzyclipz://card-failed`.
    public enum CardCheckoutResult: Hashable, Sendable {
        /// Saved on Stripe's side: now call `saveCard(sessionId:token:)`.
        case saved(sessionId: String)
        /// The client tapped back on Stripe's page.
        case cancelled
        /// Something went wrong on the way back; try again.
        case failed

        /// `nil` for a URL that isn't one of these.
        public init?(callbackURL url: URL) {
            guard url.scheme?.lowercased() == CardCheckout.callbackScheme,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            switch components.host?.lowercased() {
            case "card-saved":
                let id = components.queryItems?.first { $0.name == "session_id" }?.value ?? ""
                guard id.hasPrefix("cs_"), id.count > 3,
                      id.unicodeScalars.allSatisfy({ ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_" })
                else {
                    self = .failed
                    return
                }
                self = .saved(sessionId: id)
            case "card-cancelled":
                self = .cancelled
            case "card-failed":
                self = .failed
            default:
                return nil
            }
        }
    }

    /// A saved card: `{ brand, last4, expMonth, expYear }`. Keep it with the token to show
    /// "Visa •••• 4242" next time.
    public struct SavedCard: Codable, Hashable, Sendable {
        public var brand: String
        public var last4: String
        public var expMonth: Int
        public var expYear: Int

        public init(brand: String, last4: String, expMonth: Int, expYear: Int) {
            self.brand = brand
            self.last4 = last4
            self.expMonth = expMonth
            self.expYear = expYear
        }

        public var cardOnFile: CardOnFile { CardOnFile(brand: brand, last4: last4) }

        /// "Visa •••• 4242".
        public var label: String { cardOnFile.label }

        /// "Expires 12/30".
        public var expiryLabel: String {
            "Expires \(expMonth)/" + Timestamp.pad(expYear % 100, 2)
        }

        /// Good through the last day of its expiry month, like the server's rule: a card that
        /// expires before an appointment's month can't hold that appointment.
        public func isValid(on day: LocalDate) -> Bool {
            expYear > day.year || (expYear == day.year && expMonth >= day.month)
        }

        /// `isValid(on:)` for the shop day containing `date`.
        public func isValid(at date: Date, in timeZone: TimeZone) -> Bool {
            isValid(on: LocalDate(containing: date, in: timeZone))
        }
    }

    /// `POST /api/cards` → `{ card }`.
    public struct SavedCardResponse: Codable, Hashable, Sendable {
        public var card: SavedCard

        public init(card: SavedCard) {
            self.card = card
        }
    }

    /// What happened to a card the client removed (`DELETE /api/cards`): `{ status, message }`.
    public struct CardDeletion: Codable, Hashable, Sendable {
        public enum Status: String, Codable, CaseIterable, Hashable, Sendable {
            /// Deleted at Stripe: it can't be charged any more.
            case deleted
            /// An appointment booked with it still needs it (it's upcoming, or could still be charged a
            /// fee within 7 days); it's deleted as soon as none does.
            case scheduled

            /// A status this version doesn't know reads as `scheduled`: never as deleted.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Status(rawValue: raw) ?? .scheduled
            }
        }

        public var status: Status
        /// In plain words for the client: "Your saved card is deleted. It can't be charged any more."
        public var message: String

        public init(status: Status, message: String) {
            self.status = status
            self.message = message
        }
    }

    /// `DELETE /api/cards` → `{ cardDeletion }`.
    public struct CardDeletionResponse: Codable, Hashable, Sendable {
        public var cardDeletion: CardDeletion

        public init(cardDeletion: CardDeletion) {
            self.cardDeletion = cardDeletion
        }
    }
}

// MARK: - The owner's settings

extension IzzyAPI {
    public enum NoShowFeeMode: String, Codable, CaseIterable, Hashable, Sendable {
        /// A share of the booked service's price.
        case percent
        /// The same amount for every booking.
        case flat
    }

    /// `{ enabled, feeMode, percent, flatCents, lateCancelEnabled, lateCancelWindowMinutes }`.
    public struct NoShowSettings: Codable, Hashable, Sendable {
        /// Whether online bookings need a card (and Stripe has to be set up too). Off until the
        /// owner turns it on.
        public var enabled: Bool
        public var feeMode: NoShowFeeMode
        /// 1–100 (`NoShowRule.percentRange`), used in percent mode.
        public var percent: Int
        /// 50–50,000 cents (`NoShowRule.flatCentsRange`), used in flat mode.
        public var flatCents: Int
        /// Whether a cancellation less than `lateCancelWindowMinutes` before the start may be
        /// charged the fee too. Off: cancelling in the app before the start is free.
        public var lateCancelEnabled: Bool
        /// 30 minutes to 48 hours (`NoShowRule.lateCancelWindowRange`).
        public var lateCancelWindowMinutes: Int

        public init(
            enabled: Bool = false,
            feeMode: NoShowFeeMode = .percent,
            percent: Int = 100,
            flatCents: Int = 2_000,
            lateCancelEnabled: Bool = true,
            lateCancelWindowMinutes: Int = 60
        ) {
            self.enabled = enabled
            self.feeMode = feeMode
            self.percent = percent
            self.flatCents = flatCents
            self.lateCancelEnabled = lateCancelEnabled
            self.lateCancelWindowMinutes = lateCancelWindowMinutes
        }

        /// What the server starts with: off; once on, the full service price (100%) for a
        /// no-show or a cancellation less than 1 hour before; $20 ready for flat mode.
        public static let `default` = NoShowSettings()

        private enum CodingKeys: String, CodingKey {
            case enabled, feeMode, percent, flatCents, lateCancelEnabled, lateCancelWindowMinutes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decode(Bool.self, forKey: .enabled)
            feeMode = try container.decode(NoShowFeeMode.self, forKey: .feeMode)
            percent = try container.decode(Int.self, forKey: .percent)
            flatCents = try container.decode(Int.self, forKey: .flatCents)
            // A server from before late cancellations never charges them.
            lateCancelEnabled = try container.decodeIfPresent(Bool.self, forKey: .lateCancelEnabled) ?? false
            lateCancelWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .lateCancelWindowMinutes) ?? 60
        }

        /// The fee for an item at `price` under these settings (`nil`: none), as the server
        /// works it out: for the preview, "A $40 haircut: $20".
        public func feeCents(for price: Price) -> Int? {
            NoShowRule.feeCents(for: price, settings: self)
        }
    }

    /// `GET`/`PATCH /api/owner/no-show-settings` → `{ noShowSettings }`.
    public struct NoShowSettingsResponse: Codable, Hashable, Sendable {
        public var noShowSettings: NoShowSettings

        public init(noShowSettings: NoShowSettings) {
            self.noShowSettings = noShowSettings
        }
    }

    /// `PATCH /api/owner/no-show-settings`: only the fields that are set are sent.
    public struct NoShowSettingsUpdate: Encodable, Hashable, Sendable {
        public var enabled: Bool?
        public var feeMode: NoShowFeeMode?
        public var percent: Int?
        public var flatCents: Int?
        public var lateCancelEnabled: Bool?
        public var lateCancelWindowMinutes: Int?

        public init(
            enabled: Bool? = nil,
            feeMode: NoShowFeeMode? = nil,
            percent: Int? = nil,
            flatCents: Int? = nil,
            lateCancelEnabled: Bool? = nil,
            lateCancelWindowMinutes: Int? = nil
        ) {
            self.enabled = enabled
            self.feeMode = feeMode
            self.percent = percent
            self.flatCents = flatCents
            self.lateCancelEnabled = lateCancelEnabled
            self.lateCancelWindowMinutes = lateCancelWindowMinutes
        }

        /// Everything the settings screen shows.
        public static func replacing(with settings: NoShowSettings) -> NoShowSettingsUpdate {
            NoShowSettingsUpdate(
                enabled: settings.enabled, feeMode: settings.feeMode, percent: settings.percent, flatCents: settings.flatCents,
                lateCancelEnabled: settings.lateCancelEnabled, lateCancelWindowMinutes: settings.lateCancelWindowMinutes
            )
        }

        public var isEmpty: Bool {
            enabled == nil && feeMode == nil && percent == nil && flatCents == nil && lateCancelEnabled == nil && lateCancelWindowMinutes == nil
        }

        /// Whether the server will take every field that's set.
        public var isValid: Bool {
            (percent.map(NoShowRule.percentRange.contains) ?? true)
                && (flatCents.map(NoShowRule.flatCentsRange.contains) ?? true)
                && (lateCancelWindowMinutes.map(NoShowRule.lateCancelWindowRange.contains) ?? true)
        }

        /// `settings` with the fields that are set changed, as the server merges them.
        public func applied(to settings: NoShowSettings) -> NoShowSettings {
            var changed = settings
            if let enabled { changed.enabled = enabled }
            if let feeMode { changed.feeMode = feeMode }
            if let percent { changed.percent = percent }
            if let flatCents { changed.flatCents = flatCents }
            if let lateCancelEnabled { changed.lateCancelEnabled = lateCancelEnabled }
            if let lateCancelWindowMinutes { changed.lateCancelWindowMinutes = lateCancelWindowMinutes }
            return changed
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, feeMode, percent, flatCents, lateCancelEnabled, lateCancelWindowMinutes
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(enabled, forKey: .enabled)
            try container.encodeIfPresent(feeMode, forKey: .feeMode)
            try container.encodeIfPresent(percent, forKey: .percent)
            try container.encodeIfPresent(flatCents, forKey: .flatCents)
            try container.encodeIfPresent(lateCancelEnabled, forKey: .lateCancelEnabled)
            try container.encodeIfPresent(lateCancelWindowMinutes, forKey: .lateCancelWindowMinutes)
        }
    }
}

// MARK: - The fee rule (a mirror of the server's, for previews)

extension IzzyAPI {
    /// The server's fee rule, policy wording and clients' warning (`server/src/noshow.ts`), for
    /// the owner app's settings preview, and which fee a booking can be charged
    /// (`server/src/feecase.ts`). The server decides the real fee at booking; the Kit's tests check
    /// this mirror against `server/test/fixtures/no-show-rule.json` and `fee-cases.json`, which the
    /// server writes.
    public enum NoShowRule {
        /// Stripe's smallest US card charge: a smaller fee means no fee.
        public static let minimumFeeCents = 50
        public static let percentRange: ClosedRange<Int> = 1...100
        public static let flatCentsRange: ClosedRange<Int> = 50...50_000
        /// How long before the start cancelling stops being free, in minutes: 30 minutes to 48 hours.
        public static let lateCancelWindowRange: ClosedRange<Int> = 30...2_880
        /// Cancelling within this many minutes of booking is always free: the grace period, which
        /// matters for a time booked when its free-cancellation cutoff had already passed.
        public static let lateCancelGraceMinutes = 15
        /// A fee can be charged until this many days (of 24 hours) after the appointment's start, never later.
        public static let feeDeadlineDays = 7

        /// "30 minutes", "1 hour", "90 minutes", "2 hours", "48 hours".
        public static func windowLabel(minutes: Int) -> String {
            guard minutes % 60 == 0 else { return "\(minutes) minutes" }
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        /// The fee in cents for an item priced `priceCents` (`nil`: no fee): none for items
        /// included with a cut, free items or a fee under 50¢; percent mode rounds half up to
        /// the cent ("starting at" prices use the starting price); flat mode is the flat amount.
        /// Never more than the item's price: a $20 flat fee on a $5 service is $5.
        public static func feeCents(priceCents: Int, includedWithCut: Bool, settings: NoShowSettings) -> Int? {
            guard !includedWithCut, priceCents > 0 else { return nil }
            let fee: Int
            switch settings.feeMode {
            case .flat:
                fee = min(settings.flatCents, priceCents)
            case .percent:
                fee = (priceCents * settings.percent + 50) / 100
            }
            return fee >= minimumFeeCents ? fee : nil
        }

        public static func feeCents(for price: Price, settings: NoShowSettings) -> Int? {
            feeCents(priceCents: price.cents, includedWithCut: price.kind == .includedWithCut, settings: settings)
        }

        /// "$20", or "$17.50–$22.50".
        public static func feeLabel(minCents: Int, maxCents: Int) -> String {
            minCents == maxCents
                ? Price.currencyString(cents: minCents)
                : Price.currencyString(cents: minCents) + "–" + Price.currencyString(cents: maxCents)
        }

        /// The policy clients agree to, as the server words it.
        public static func policyText(minFeeCents: Int, maxFeeCents: Int, settings: NoShowSettings) -> String {
            let share = settings.feeMode == .percent ? " (\(settings.percent)% of the service)" : ""
            let fee = feeLabel(minCents: minFeeCents, maxCents: maxFeeCents) + share
            if settings.lateCancelEnabled {
                let window = windowLabel(minutes: settings.lateCancelWindowMinutes)
                return "No payment now. If you cancel less than \(window) before your appointment, or don't come, Izzy Clipz may charge "
                    + fee + " to this card. Cancelling in the app more than \(window) before is free."
            }
            return "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge "
                + fee + " to this card. Cancelling in the app before your appointment is free."
        }

        /// The warning clients see while booking, as the server words it: "Full Service
        /// Cancellation & No-Show Fee" only when the fee is 100% of the service. It "may be
        /// charged", like the agreed policy's "may charge": the shop decides each time.
        public static func warning(minFeeCents: Int, maxFeeCents: Int, settings: NoShowSettings) -> NoShowWarning {
            let fee = feeLabel(minCents: minFeeCents, maxCents: maxFeeCents)
            let fullPrice = settings.feeMode == .percent && settings.percent == 100
            let amount = fullPrice
                ? "the full service price (\(fee))"
                : settings.feeMode == .percent ? "\(fee) (\(settings.percent)% of the service)" : fee
            if settings.lateCancelEnabled {
                let window = windowLabel(minutes: settings.lateCancelWindowMinutes)
                return NoShowWarning(
                    title: fullPrice ? "Full Service Cancellation & No-Show Fee" : "Late Cancellation & No-Show Fee",
                    message: "Cancelling less than \(window) before your appointment, or not showing up, may be charged \(amount). "
                        + "Cancelling in the app more than \(window) before is free."
                )
            }
            return NoShowWarning(
                title: "No-Show Fee",
                message: "Not showing up may be charged \(amount). Cancelling in the app before your appointment is free."
            )
        }

        /// Which fee a booking with a card on file can be charged, or why not (the owner's words).
        public enum FeeCase: Hashable, Sendable {
            case chargeable(NoShowFeeReason)
            case refused(String)
        }

        public static let noCardMessage = "This booking has no card on file, so there's no fee to charge."
        /// A no-show fee before the appointment's end: a client who comes before the end isn't a no-show.
        public static let notEndedMessage = "The appointment hasn't ended yet, so it can't be a no-show."
        /// Kept for older callers: a no-show now needs the end to have passed (`notEndedMessage`).
        public static let notStartedMessage = notEndedMessage
        /// Once the 7 days after the start are over.
        public static let feeDeadlineMessage = "It's more than 7 days after the appointment, so the fee can't be charged."
        /// The server's 409 `not_started` when a booking with a card on file is marked a no-show before it ends.
        public static let noShowBeforeEndMessage = "You can mark a no-show once the appointment has ended."
        /// The server's 409 `already_completed` when a booking with a card on file that was completed is marked a no-show.
        public static let completedNoShowMessage = "This appointment was marked completed, so it can't become a no-show."
        /// Why a completed booking can't be charged: the client came.
        public static let completedMessage = "The appointment is marked completed, so there's no fee to charge."
        /// A client who cancelled within 15 minutes of booking a time inside the window.
        public static let withinGraceMessage = "The client cancelled within 15 minutes of booking, so there's no fee."

        /// The server's 409 when a pending try turns out never to have reached Stripe and the booking
        /// can't be charged any more (it's settled as not charged): "Nothing was charged. Mark the
        /// appointment as a no-show first."
        public static func nothingChargedMessage(_ refusal: String) -> String {
            "Nothing was charged. " + refusal
        }
        static let cancelledInAppMessage = "The client cancelled this booking in the app, so there's no fee."
        static let shopCancelledMessage = "The shop cancelled this booking, so there's no fee."
        static let markNoShowMessage = "Mark the appointment as a no-show first."

        /// Whether the client cancelled less than the agreed window before the start (exactly that
        /// long before is still free) and, given `createdAt` (when it was booked), more than 15
        /// minutes after booking (exactly 15 minutes after is still free), whatever happened since.
        /// Pass `createdAt`: without it, the grace period isn't counted.
        public static func cancelledLate(start: Date, customerCancelledAt: Date?, lateCancelWindowMinutes: Int?, createdAt: Date? = nil) -> Bool {
            guard let customerCancelledAt, let lateCancelWindowMinutes else { return false }
            if let createdAt, customerCancelledAt.timeIntervalSince(createdAt) <= Double(lateCancelGraceMinutes) * 60 { return false }
            return start.timeIntervalSince(customerCancelledAt) < Double(lateCancelWindowMinutes) * 60
        }

        /// Whether an appointment that starts at `start` is already less than the agreed window away
        /// at `now`: booked now, cancelling it more than 15 minutes after booking may be charged
        /// (the grace period aside, the server's `cancelledLate` with `now` as the cancel time).
        public static func cancellingMayBeCharged(start: Date, now: Date, windowMinutes: Int?) -> Bool {
            cancelledLate(start: start, customerCancelledAt: now, lateCancelWindowMinutes: windowMinutes)
        }

        /// "This time is less than 1 hour away, so cancelling it more than 15 minutes after booking
        /// may be charged $35." (or a range for any barber, "$55–$60"): see
        /// `NoShowPolicy.lateCancelNotice(start:now:)`. The server words it the same
        /// (`server/test/fixtures/no-show-rule.json`).
        public static func lateCancelNotice(windowMinutes: Int, feeLabel: String) -> String {
            "This time is less than \(windowLabel(minutes: windowMinutes)) away, so cancelling it more than "
                + "\(lateCancelGraceMinutes) minutes after booking may be charged \(feeLabel)."
        }

        /// The last moment a fee can be charged for an appointment starting at `start`: 7 days (of 24 hours) later.
        public static func feeDeadline(start: Date) -> Date {
            start.addingTimeInterval(Double(feeDeadlineDays) * 24 * 60 * 60)
        }

        /// Whether it's too late at `now` to charge a fee for an appointment starting at `start`
        /// (exactly 7 days later still isn't).
        public static func isPastFeeDeadline(start: Date, now: Date) -> Bool {
            now > feeDeadline(start: start)
        }

        /// Why the server refuses to mark a booking a no-show now (`PATCH …/:id` with `noShow`), or
        /// `nil`: a booking with a card on file only once it has ended, and never once it's completed.
        public static func noShowMarkRefusal(status: AppointmentStatus, hasCard: Bool, end: Date, now: Date) -> String? {
            guard hasCard, status != .noShow else { return nil }
            if status == .completed { return completedNoShowMessage }
            return end > now ? noShowBeforeEndMessage : nil
        }

        /// What the client is told before cancelling inside the agreed window, as the server words
        /// it (also its 409 `late_cancel_fee`): "Cancelling now, less than 1 hour before your
        /// appointment, may be charged $35, the full service price."
        public static func lateCancelWarning(windowMinutes: Int, feeCents: Int, fullPrice: Bool) -> String {
            let amount = Price.currencyString(cents: feeCents) + (fullPrice ? ", the full service price" : "")
            return "Cancelling now, less than \(windowLabel(minutes: windowMinutes)) before your appointment, may be charged \(amount)."
        }

        /// The server's rule, ignoring the clock: a late cancellation (cancelled by the client
        /// inside the agreed window, and, given `createdAt`, more than 15 minutes after booking;
        /// still cancelled), or a no-show (marked, and the client never cancelled nor asked to).
        /// A completed booking has no fee. The clock decides the rest (the overload with `at:`).
        public static func feeCase(
            status: AppointmentStatus,
            cancelledBy: CancelledBy?,
            start: Date,
            customerCancelledAt: Date?,
            lateCancelWindowMinutes: Int?,
            createdAt: Date? = nil
        ) -> FeeCase {
            if status == .cancelled {
                guard cancelledBy == .customer else { return .refused(shopCancelledMessage) }
                if cancelledLate(start: start, customerCancelledAt: customerCancelledAt, lateCancelWindowMinutes: lateCancelWindowMinutes, createdAt: createdAt) {
                    return .chargeable(.lateCancel)
                }
                if let lateCancelWindowMinutes, customerCancelledAt != nil {
                    if cancelledLate(start: start, customerCancelledAt: customerCancelledAt, lateCancelWindowMinutes: lateCancelWindowMinutes) {
                        return .refused(withinGraceMessage)
                    }
                    return .refused("The client cancelled at least \(windowLabel(minutes: lateCancelWindowMinutes)) before, so there's no fee.")
                }
                return .refused(cancelledInAppMessage)
            }
            if customerCancelledAt != nil { return .refused(cancelledInAppMessage) }
            if status == .completed { return .refused(completedMessage) }
            guard status == .noShow else { return .refused(markNoShowMessage) }
            return .chargeable(.noShow)
        }

        /// The server's rule at `now` (its `feeCaseAt`): `feeCase`, then the clock. Nothing more than
        /// 7 days after the start (a booking still marked booked then hears that too, rather than to
        /// mark a no-show first), and a no-show only once the appointment has ended.
        public static func feeCase(
            status: AppointmentStatus,
            cancelledBy: CancelledBy?,
            start: Date,
            end: Date,
            createdAt: Date,
            customerCancelledAt: Date?,
            lateCancelWindowMinutes: Int?,
            at now: Date
        ) -> FeeCase {
            let found = feeCase(
                status: status, cancelledBy: cancelledBy, start: start,
                customerCancelledAt: customerCancelledAt, lateCancelWindowMinutes: lateCancelWindowMinutes, createdAt: createdAt
            )
            let tooLate = isPastFeeDeadline(start: start, now: now)
            switch found {
            case .refused(let refusal):
                return refusal == markNoShowMessage && tooLate ? .refused(feeDeadlineMessage) : found
            case .chargeable(let reason):
                if tooLate { return .refused(feeDeadlineMessage) }
                if reason == .noShow, end > now { return .refused(notEndedMessage) }
                return found
            }
        }
    }
}

// MARK: - Payments

extension IzzyAPI {
    /// What a payment was for.
    public enum PaymentKind: String, Codable, CaseIterable, Hashable, Sendable {
        /// Taken in the shop with Tap to Pay.
        case inPerson
        /// A no-show fee charged to the card on file.
        case noShowFee
        /// A late-cancellation fee charged to the card on file.
        case lateCancelFee

        /// "Card payment", "No-show fee", "Late cancellation fee".
        public var title: String {
            switch self {
            case .inPerson: return "Card payment"
            case .noShowFee: return "No-show fee"
            case .lateCancelFee: return "Late cancellation fee"
            }
        }

        /// A fee charged to the card on file, not a payment for the service.
        public var isFee: Bool { self != .inPerson }

        /// The payment kind of a fee for `reason`.
        public init(feeReason reason: NoShowFeeReason) {
            self = reason == .lateCancel ? .lateCancelFee : .noShowFee
        }

        /// A kind this version doesn't know reads as an in-person payment.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = PaymentKind(rawValue: raw) ?? .inPerson
        }
    }
}
