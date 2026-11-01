import Foundation

// No-show protection: a card saved before booking (Stripe Checkout in setup
// mode), charged only if the client doesn't come. Models field for field as the
// server writes them (server/README.md, "No-show protection").

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

    /// An appointment's no-show fee: `{ amountCents, status, chargedAt, message }`.
    public struct NoShowFee: Codable, Hashable, Sendable {
        /// The fee agreed at booking, in cents. Changing the settings later doesn't change it.
        public var amountCents: Int
        public var status: NoShowFeeStatus
        /// When Stripe reported it charged; `nil` otherwise.
        public var chargedAt: Date?
        /// Why it was declined or needs the client, in plain words for the owner.
        public var message: String?

        public init(amountCents: Int, status: NoShowFeeStatus = .none, chargedAt: Date? = nil, message: String? = nil) {
            self.amountCents = amountCents
            self.status = status
            self.chargedAt = chargedAt
            self.message = message
        }

        /// "$20", "$17.50".
        public var amountLabel: String { Price.currencyString(cents: amountCents) }

        public var isCharged: Bool { status == .charged }

        private enum CodingKeys: String, CodingKey {
            case amountCents, status, chargedAt, message
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(amountCents, forKey: .amountCents)
            try container.encode(status, forKey: .status)
            try container.encode(chargedAt, forKey: .chargedAt)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - The policy before booking

extension IzzyAPI {
    /// `GET /api/no-show-policy` → `{ required, minFeeCents, maxFeeCents, policyText }`.
    ///
    /// When `required`, booking needs a saved card, and the booking sends `policyText` back
    /// exactly as shown (`NoShowAgreement`). Otherwise the other fields are `nil` and booking
    /// works without a card.
    public struct NoShowPolicy: Codable, Hashable, Sendable {
        public var required: Bool
        public var minFeeCents: Int?
        public var maxFeeCents: Int?
        /// What to show above "Book appointment", in the server's words.
        public var policyText: String?

        public init(required: Bool, minFeeCents: Int? = nil, maxFeeCents: Int? = nil, policyText: String? = nil) {
            self.required = required
            self.minFeeCents = minFeeCents
            self.maxFeeCents = maxFeeCents
            self.policyText = policyText
        }

        /// No card needed.
        public static let notRequired = NoShowPolicy(required: false)

        /// "$20", or "$17.50–$22.50" for any barber when their fees differ; `nil` without a fee.
        public var feeLabel: String? {
            guard required, let minFeeCents, let maxFeeCents else { return nil }
            return NoShowRule.feeLabel(minCents: minFeeCents, maxCents: maxFeeCents)
        }

        private enum CodingKeys: String, CodingKey {
            case required, minFeeCents, maxFeeCents, policyText
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(required, forKey: .required)
            try container.encode(minFeeCents, forKey: .minFeeCents)
            try container.encode(maxFeeCents, forKey: .maxFeeCents)
            try container.encode(policyText, forKey: .policyText)
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
}

// MARK: - The owner's settings

extension IzzyAPI {
    public enum NoShowFeeMode: String, Codable, CaseIterable, Hashable, Sendable {
        /// A share of the booked service's price.
        case percent
        /// The same amount for every booking.
        case flat
    }

    /// `{ enabled, feeMode, percent, flatCents }`.
    public struct NoShowSettings: Codable, Hashable, Sendable {
        /// Whether online bookings need a card (and Stripe has to be set up too).
        public var enabled: Bool
        public var feeMode: NoShowFeeMode
        /// 1–100 (`NoShowRule.percentRange`), used in percent mode.
        public var percent: Int
        /// 50–50,000 cents (`NoShowRule.flatCentsRange`), used in flat mode.
        public var flatCents: Int

        public init(enabled: Bool = true, feeMode: NoShowFeeMode = .percent, percent: Int = 50, flatCents: Int = 2_000) {
            self.enabled = enabled
            self.feeMode = feeMode
            self.percent = percent
            self.flatCents = flatCents
        }

        /// What the server starts with: on, 50% of the service, $20 ready for flat mode.
        public static let `default` = NoShowSettings()

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

        public init(enabled: Bool? = nil, feeMode: NoShowFeeMode? = nil, percent: Int? = nil, flatCents: Int? = nil) {
            self.enabled = enabled
            self.feeMode = feeMode
            self.percent = percent
            self.flatCents = flatCents
        }

        /// Everything the settings screen shows.
        public static func replacing(with settings: NoShowSettings) -> NoShowSettingsUpdate {
            NoShowSettingsUpdate(enabled: settings.enabled, feeMode: settings.feeMode, percent: settings.percent, flatCents: settings.flatCents)
        }

        public var isEmpty: Bool { enabled == nil && feeMode == nil && percent == nil && flatCents == nil }

        /// Whether the server will take every field that's set.
        public var isValid: Bool {
            (percent.map(NoShowRule.percentRange.contains) ?? true) && (flatCents.map(NoShowRule.flatCentsRange.contains) ?? true)
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, feeMode, percent, flatCents
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(enabled, forKey: .enabled)
            try container.encodeIfPresent(feeMode, forKey: .feeMode)
            try container.encodeIfPresent(percent, forKey: .percent)
            try container.encodeIfPresent(flatCents, forKey: .flatCents)
        }
    }
}

// MARK: - The fee rule (a mirror of the server's, for previews)

extension IzzyAPI {
    /// The server's no-show fee rule and policy wording (`server/src/noshow.ts`), for the owner
    /// app's settings preview. The server decides the real fee at booking; the Kit's tests check
    /// this mirror against `server/test/fixtures/no-show-rule.json`, which the server writes.
    public enum NoShowRule {
        /// Stripe's smallest US card charge: a smaller fee means no fee.
        public static let minimumFeeCents = 50
        public static let percentRange: ClosedRange<Int> = 1...100
        public static let flatCentsRange: ClosedRange<Int> = 50...50_000

        /// The fee in cents for an item priced `priceCents` (`nil`: no fee): none for items
        /// included with a cut, free items or a fee under 50¢; percent mode rounds half up to
        /// the cent ("starting at" prices use the starting price); flat mode is the flat amount.
        public static func feeCents(priceCents: Int, includedWithCut: Bool, settings: NoShowSettings) -> Int? {
            guard !includedWithCut, priceCents > 0 else { return nil }
            let fee: Int
            switch settings.feeMode {
            case .flat:
                fee = settings.flatCents
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

        /// The policy clients see, as the server words it.
        public static func policyText(minFeeCents: Int, maxFeeCents: Int, settings: NoShowSettings) -> String {
            let share = settings.feeMode == .percent ? " (\(settings.percent)% of the service)" : ""
            return "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge "
                + feeLabel(minCents: minFeeCents, maxCents: maxFeeCents) + share + " to this card. "
                + "Cancelling in the app before your appointment is free."
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

        /// "Card payment", "No-show fee".
        public var title: String {
            switch self {
            case .inPerson: return "Card payment"
            case .noShowFee: return "No-show fee"
            }
        }

        /// A kind this version doesn't know reads as an in-person payment.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = PaymentKind(rawValue: raw) ?? .inPerson
        }
    }
}
