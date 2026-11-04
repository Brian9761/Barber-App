import Foundation

// The shop's own Stripe account, connected from the Business app's Settings (Stripe Connect),
// and signing in to the website's Business area on a computer with a 6-digit code from the app.
// Models field for field as the server writes them (server/README.md, "Stripe Connect and
// computers").

// MARK: - The shop's Stripe account

extension IzzyAPI {
    /// `GET /api/owner/stripe` (and `DELETE /api/owner/stripe/connect`): how the server takes card
    /// payments and, with Stripe Connect, how the shop's own Stripe account is doing. What Settings
    /// shows under "Card payments (Stripe)".
    public struct StripeConnection: Codable, Hashable, Sendable {
        /// How the server takes card payments.
        public enum Mode: String, Codable, CaseIterable, Hashable, Sendable {
            /// Through the shop's own Stripe account, connected from Settings.
            case connect
            /// With the server's own Stripe key: there's nothing to connect.
            case direct
            /// Stripe isn't set up on the server.
            case off
            /// A mode this version doesn't know: show the connection's `message`.
            case unknown

            /// A mode this version doesn't know reads as `unknown`.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Mode(rawValue: raw) ?? .unknown
            }
        }

        /// Where the connection stands, in the server's words (`message` says it in full).
        public enum Status: String, Codable, CaseIterable, Hashable, Sendable {
            /// No Stripe account connected yet.
            case notConnected
            /// Stripe needs more details before card payments can start.
            case needsInfo
            /// The details are in, and Stripe is checking them (usually a few minutes).
            case pending
            /// Card payments are on.
            case active
            /// Stripe paused card payments; the owner fixes it in Stripe.
            case restricted
            /// The server uses its own Stripe key (`Mode.direct`).
            case direct
            /// Stripe isn't set up on the server.
            case off
            /// A status this version doesn't know: show `message`, and offer nothing to tap.
            case unknown

            /// A status this version doesn't know reads as `unknown`, never as connected.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Status(rawValue: raw) ?? .unknown
            }

            /// The status row in Settings: "Connected", "Not connected", "Finish setting up", "Stripe is
            /// checking your details", "Paused by Stripe", "Uses the server's Stripe key" or "Not set up
            /// on the server".
            public var title: String {
                switch self {
                case .notConnected: return "Not connected"
                case .needsInfo: return "Finish setting up"
                case .pending: return "Stripe is checking your details"
                case .active: return "Connected"
                case .restricted: return "Paused by Stripe"
                case .direct: return "Uses the server's Stripe key"
                case .off: return "Not set up on the server"
                case .unknown: return "Check Stripe"
                }
            }

            /// The main button, which opens Stripe (`connectStripe()`): "Connect Stripe" before an
            /// account is connected, "Finish setting up" when Stripe needs something from the owner;
            /// `nil` when there's nothing to do in Stripe's pages.
            public var connectButtonTitle: String? {
                switch self {
                case .notConnected: return "Connect Stripe"
                case .needsInfo, .restricted: return "Finish setting up"
                case .pending, .active, .direct, .off, .unknown: return nil
                }
            }

            /// Whether card payments (Tap to Pay, saved cards, fees) can be taken now.
            public var takesCardPayments: Bool {
                self == .active || self == .direct
            }
        }

        public var mode: Mode
        public var status: Status
        /// The shop's connected account, "acct_…"; `nil` until one is connected, and in direct or off mode.
        public var accountId: String?
        /// The business name on the Stripe account, e.g. "Izzy Clipz Barbershop".
        public var businessName: String?
        /// A live (not test) account; `nil` when that isn't known yet.
        public var livemode: Bool?
        public var chargesEnabled: Bool
        public var payoutsEnabled: Bool
        public var detailsSubmitted: Bool
        /// How many things Stripe needs from the owner now.
        public var requirementsDue: Int
        /// What Settings says, in the server's plain words ("Connected. Card payments are on. …").
        public var message: String
        /// The Stripe Dashboard, for "Open Stripe Dashboard".
        public var dashboardUrl: URL
        /// When the server last asked Stripe; `nil` when it never has.
        public var checkedAt: Date?

        /// `message` defaults to what the server says for `status` (`message(for:payoutsEnabled:)`), so a
        /// fake answers in the server's words.
        public init(
            mode: Mode,
            status: Status,
            accountId: String? = nil,
            businessName: String? = nil,
            livemode: Bool? = nil,
            chargesEnabled: Bool = false,
            payoutsEnabled: Bool = false,
            detailsSubmitted: Bool = false,
            requirementsDue: Int = 0,
            message: String? = nil,
            dashboardUrl: URL = StripeConnection.dashboard,
            checkedAt: Date? = nil
        ) {
            self.mode = mode
            self.status = status
            self.accountId = accountId
            self.businessName = businessName
            self.livemode = livemode
            self.chargesEnabled = chargesEnabled
            self.payoutsEnabled = payoutsEnabled
            self.detailsSubmitted = detailsSubmitted
            self.requirementsDue = requirementsDue
            self.message = message ?? StripeConnection.message(for: status, payoutsEnabled: payoutsEnabled)
            self.dashboardUrl = dashboardUrl
            self.checkedAt = checkedAt
        }

        /// What `GET /api/owner/me` keeps of it: `{ mode, status, businessName }`.
        public var summary: StripeConnectionSummary {
            StripeConnectionSummary(mode: mode, status: status, businessName: businessName)
        }

        /// Where "Open Stripe Dashboard" goes.
        public static let dashboard = URL(string: "https://dashboard.stripe.com/")!

        /// What the server says after "Disconnect Stripe": the account stays open at Stripe.
        public static let disconnectedMessage =
            "Stripe is disconnected. Your Stripe account isn't closed: you can still sign in to Stripe to see its payments and payouts."

        /// What the server says about each status (`server/src/stripeaccount.ts`, `connectionMessage`).
        /// For a connected account, `payoutsEnabled` says whether its bank is set up for payouts.
        public static func message(for status: Status, payoutsEnabled: Bool = false) -> String {
            switch status {
            case .off: return "Stripe isn't set up on the server."
            case .direct: return "Card payments use this server's own Stripe key."
            case .notConnected: return "Connect your Stripe account to take card payments in the app."
            case .needsInfo: return "Finish setting up Stripe to take card payments."
            case .pending: return "Stripe is checking your details. This usually takes a few minutes."
            case .restricted: return "Stripe paused card payments: open Stripe to fix it."
            case .active:
                return "Connected. Card payments are on." + (payoutsEnabled ? " Payouts to your bank are on." : " Add your bank in Stripe to get paid out.")
            case .unknown: return "Open Stripe to see how your account is doing."
            }
        }

        private enum CodingKeys: String, CodingKey {
            case mode, status, accountId, businessName, livemode, chargesEnabled, payoutsEnabled, detailsSubmitted, requirementsDue
            case message, dashboardUrl, checkedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decode(Mode.self, forKey: .mode)
            status = try container.decode(Status.self, forKey: .status)
            accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
            businessName = try container.decodeIfPresent(String.self, forKey: .businessName)
            livemode = try container.decodeIfPresent(Bool.self, forKey: .livemode)
            chargesEnabled = try container.decode(Bool.self, forKey: .chargesEnabled)
            payoutsEnabled = try container.decode(Bool.self, forKey: .payoutsEnabled)
            detailsSubmitted = try container.decode(Bool.self, forKey: .detailsSubmitted)
            requirementsDue = try container.decode(Int.self, forKey: .requirementsDue)
            message = try container.decode(String.self, forKey: .message)
            // Only ever Stripe's own https page; anything else falls back to it.
            dashboardUrl = container.decodeWebURLIfPossible(forKey: .dashboardUrl) ?? StripeConnection.dashboard
            checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mode, forKey: .mode)
            try container.encode(status, forKey: .status)
            try container.encode(accountId, forKey: .accountId)
            try container.encode(businessName, forKey: .businessName)
            try container.encode(livemode, forKey: .livemode)
            try container.encode(chargesEnabled, forKey: .chargesEnabled)
            try container.encode(payoutsEnabled, forKey: .payoutsEnabled)
            try container.encode(detailsSubmitted, forKey: .detailsSubmitted)
            try container.encode(requirementsDue, forKey: .requirementsDue)
            try container.encode(message, forKey: .message)
            try container.encode(dashboardUrl.absoluteString, forKey: .dashboardUrl)
            try container.encode(checkedAt, forKey: .checkedAt)
        }
    }

    /// `GET /api/owner/me`'s `connection`: `{ mode, status, businessName }`, from the server's cache
    /// (it never asks Stripe). `stripeConnection()` has the rest.
    public struct StripeConnectionSummary: Codable, Hashable, Sendable {
        public var mode: StripeConnection.Mode
        public var status: StripeConnection.Status
        public var businessName: String?

        public init(mode: StripeConnection.Mode, status: StripeConnection.Status, businessName: String? = nil) {
            self.mode = mode
            self.status = status
            self.businessName = businessName
        }

        private enum CodingKeys: String, CodingKey {
            case mode, status, businessName
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mode, forKey: .mode)
            try container.encode(status, forKey: .status)
            try container.encode(businessName, forKey: .businessName)
        }
    }

    /// `POST /api/owner/stripe/connect` → 201 `{ url, expiresAt }`: Stripe's own page, where the owner
    /// signs in to Stripe (or signs up) and finishes setting up.
    public struct StripeConnectLink: Codable, Hashable, Sendable {
        /// Open it in `ASWebAuthenticationSession` with `callbackScheme`, keeping the owner's Stripe
        /// sign-in (`prefersEphemeralWebBrowserSession = false`).
        public var url: URL
        /// Stripe's link works once, until then; tap Connect Stripe again for a new one.
        public var expiresAt: Date

        public init(url: URL, expiresAt: Date) {
            self.url = url
            self.expiresAt = expiresAt
        }

        /// The Business app's URL scheme Stripe's pages come back to (through the server's https page).
        public static let callbackScheme = "izzyclipzbusiness"

        private enum CodingKeys: String, CodingKey {
            case url, expiresAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeWebURL(forKey: .url)
            expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(expiresAt, forKey: .expiresAt)
        }
    }

    /// How Stripe's pages ended, from the URL `ASWebAuthenticationSession` hands back:
    /// `izzyclipzbusiness://stripe-connected?status=active`. Ask `stripeConnection()` for the rest.
    public struct StripeConnectReturn: Hashable, Sendable {
        /// The account's status when the owner came back; `unknown` when the link didn't say.
        public var status: StripeConnection.Status

        public init(status: StripeConnection.Status) {
            self.status = status
        }

        /// `nil` for a URL that isn't the way back from Stripe.
        public init?(callbackURL url: URL) {
            guard url.scheme?.lowercased() == StripeConnectLink.callbackScheme,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.host?.lowercased() == "stripe-connected"
            else { return nil }
            let raw = components.queryItems?.first { $0.name == "status" }?.value ?? ""
            status = StripeConnection.Status(rawValue: raw) ?? .unknown
        }

        /// The line Settings shows on the way back: "You're connected. You can take card payments now.", or
        /// "Stripe still needs a few details: tap Finish setting up." (and the server's words otherwise).
        public var resultMessage: String {
            switch status {
            case .active: return "You're connected. You can take card payments now."
            case .needsInfo, .restricted: return "Stripe still needs a few details: tap Finish setting up."
            case .pending, .notConnected, .direct, .off, .unknown: return StripeConnection.message(for: status)
            }
        }
    }

    /// `POST /api/owner/stripe/connect` body `{ returnTo }`: where Stripe sends the owner back.
    struct StripeConnectBody: Encodable, Hashable, Sendable {
        /// The Business app (`StripeConnectLink.callbackScheme`); the website sends "web".
        var returnTo = "app"
    }
}

// MARK: - Signing in on a computer

extension IzzyAPI {
    /// `POST /api/owner/computer-codes` → 201 `{ code, expiresAt, expiresInSeconds }`: the 6-digit code
    /// the owner types on the website (Settings → Use on a computer). It works once, for 10 minutes,
    /// and a new code replaces it.
    public struct ComputerCode: Codable, Hashable, Sendable, CustomStringConvertible {
        /// Six digits, e.g. "483920" (`grouped` for showing it).
        public var code: String
        /// By the server's clock.
        public var expiresAt: Date
        /// How long it works from when it was made: 600.
        public var expiresInSeconds: Int

        public init(code: String, expiresAt: Date, expiresInSeconds: Int = 600) {
            self.code = code
            self.expiresAt = expiresAt
            self.expiresInSeconds = expiresInSeconds
        }

        /// "483 920": easier to read out and type.
        public var grouped: String {
            guard code.count == 6 else { return code }
            return String(code.prefix(3)) + " " + String(code.suffix(3))
        }

        /// The seconds it still works at `now`, counted from when its answer arrived (`receivedAt`)
        /// rather than from `expiresAt`, so a phone whose clock is off still counts down right.
        public func secondsLeft(receivedAt: Date, now: Date) -> Int {
            let left = Double(expiresInSeconds) - now.timeIntervalSince(receivedAt)
            return max(0, Int(left.rounded(.up)))
        }

        /// "9:42", "0:05": for "Expires in 9:42".
        public static func countdownLabel(seconds: Int) -> String {
            let seconds = max(0, seconds)
            return "\(seconds / 60):" + Timestamp.pad(seconds % 60, 2)
        }

        /// Leaves the code out, so it never ends up in a log.
        public var description: String { "ComputerCode(code: <redacted>, expiresAt: \(Timestamp.string(from: expiresAt)))" }
    }

    /// A computer signed in to the website's Business area: `{ id, name, createdAt, lastUsedAt, expiresAt, current }`.
    public struct ComputerSession: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        /// What the website calls it, e.g. "Chrome on Mac".
        public var name: String
        public var createdAt: Date
        /// Updated at most every 10 minutes.
        public var lastUsedAt: Date
        /// 30 days after it signed in.
        public var expiresAt: Date
        /// The computer asking (never one of them for the Business app, which uses the owner key).
        public var current: Bool

        public init(id: String, name: String, createdAt: Date, lastUsedAt: Date, expiresAt: Date, current: Bool = false) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
            self.expiresAt = expiresAt
            self.current = current
        }
    }

    /// `GET /api/owner/computer-sessions` → `{ sessions }`: the computers signed in now, most recently used first.
    public struct ComputerSessionsResponse: Codable, Hashable, Sendable {
        public var sessions: [ComputerSession]

        public init(sessions: [ComputerSession]) {
            self.sessions = sessions
        }
    }

    /// `POST /api/computer-sessions` → 201 `{ token, session }`: the website signed in with a code. The
    /// token works like the owner key on most owner routes; the Business app never needs one.
    public struct ComputerSessionCreated: Codable, Hashable, Sendable, CustomStringConvertible {
        /// The computer's secret (43 characters of base64url). Keep it out of logs.
        public var token: String
        public var session: ComputerSession

        public init(token: String, session: ComputerSession) {
            self.token = token
            self.session = session
        }

        /// Leaves the token out, so it never ends up in a log.
        public var description: String { "ComputerSessionCreated(session: \(session.id), token: <redacted>)" }
    }

    /// `POST /api/computer-sessions` body `{ code, name }`.
    struct ComputerSignInBody: Encodable, Hashable, Sendable {
        var code: String
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case code, name
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(code.trimmed, forKey: .code)
            try container.encodeIfPresent(name?.trimmed.nonEmpty, forKey: .name)
        }
    }
}
