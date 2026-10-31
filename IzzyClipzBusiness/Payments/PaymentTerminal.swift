import Foundation

/// A card reader the app can take a payment with: Tap to Pay on iPhone
/// through Stripe Terminal (`StripeTapToPayTerminal`), or a stand-in that
/// never charges anything (`SimulatedPaymentTerminal`).
///
/// The server always creates the PaymentIntent, so the terminal only gets its
/// client secret and can't change the amount. A terminal does one thing at a
/// time, like Stripe's SDK.
@MainActor
protocol PaymentTerminal: AnyObject {
    /// True for the stand-in: the app then says "Test mode — no real charge".
    var isSimulated: Bool { get }

    /// Where the reader is. Terminals are `@Observable`, so views reading this
    /// update when it changes.
    var state: TerminalState { get }

    /// Connects the reader for `locationId` (the Stripe Terminal location the
    /// server reports). The first time on an iPhone, Apple configures it, which
    /// can take a minute or two: `state` reports `.preparing` with progress.
    /// Calling it again while it's already preparing waits for that attempt.
    func prepare(locationId: String) async throws

    /// Shows the Tap to Pay screen for the PaymentIntent behind
    /// `clientSecret` and waits for the card. `amountCents` is what the app
    /// showed the owner; the terminal refuses to go on if the PaymentIntent
    /// says otherwise.
    ///
    /// Calling it again with the same client secret after a decline,
    /// cancellation or an unknown outcome retries the same PaymentIntent, as
    /// Stripe asks, so a card can't be charged twice for one checkout.
    ///
    /// - Throws: `TerminalError`.
    func collect(amountCents: Int, clientSecret: String) async throws -> TerminalPaymentResult

    /// Stops whatever the reader is doing (connecting or waiting for a card).
    /// The running `prepare` or `collect` then throws `TerminalError.cancelled`.
    func cancel()

    /// Best effort: tells Stripe a PaymentIntent that was never charged won't
    /// be used again, when the owner changes the amount or gives up.
    func abandon(clientSecret: String) async

    /// Disconnects and forgets the account's credentials (on sign out).
    func disconnect() async
}

/// Where a reader is.
enum TerminalState: Equatable, Sendable {
    /// Not connected yet.
    case idle
    /// Connecting. `progress` (0...1) is set while Apple configures the iPhone
    /// for Tap to Pay, which happens the first time and after some updates.
    case preparing(progress: Double?)
    /// Connected: a payment can start straight away.
    case ready
    /// The Tap to Pay screen is up, waiting for the customer's card.
    case collecting
    /// The card was read; the payment is being authorized.
    case processing
    /// The reader lost its connection (the app went to the background, the
    /// network dropped) and is reconnecting on its own.
    case reconnecting
    /// This iPhone or account can't take payments yet; says why and what to do.
    case unavailable(TerminalIssue)

    var isBusy: Bool {
        switch self {
        case .preparing, .collecting, .processing, .reconnecting: return true
        case .idle, .ready, .unavailable: return false
        }
    }
}

/// Why payments can't be taken, in plain words, with what to do about it.
struct TerminalIssue: Equatable, Sendable {
    let title: String
    let message: String
    /// Whether trying again later might work without changing anything.
    var canRetry = true
}

/// What happened to a PaymentIntent the terminal processed. Only the server's
/// answer to `completePayment` decides whether it's paid.
struct TerminalPaymentResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Stripe says the money is in (automatic capture).
        case succeeded
        /// Authorized but not captured yet; the server uses automatic capture,
        /// so this shouldn't happen.
        case requiresCapture
        /// Stripe is still working on it.
        case processing
    }

    var paymentIntentId: String?
    var status: Status
}

/// Why a payment didn't go through at the reader.
enum TerminalError: Error, Equatable, Sendable {
    /// The owner or the customer cancelled. Nothing was charged; the same
    /// PaymentIntent can be tried again.
    case cancelled
    /// The card was declined. The same PaymentIntent can be tried again with
    /// another card.
    case declined(message: String)
    /// Payments can't be taken on this iPhone or account yet.
    case unavailable(TerminalIssue)
    /// The reader timed out and nobody knows whether the card was charged.
    /// Check with the server before anything else, then retry the same
    /// PaymentIntent if it wasn't.
    case outcomeUnknown
    /// The PaymentIntent doesn't match what the app showed, or was already
    /// cancelled: start a new payment.
    case mismatch(message: String)
    /// Anything else, with a plain message.
    case failed(message: String)

    var message: String {
        switch self {
        case .cancelled:
            return "The payment was cancelled. No card was charged."
        case .declined(let message), .mismatch(let message), .failed(let message):
            return message
        case .unavailable(let issue):
            return issue.message
        case .outcomeUnknown:
            return "We couldn't tell if the card was charged. Check the payment before trying again."
        }
    }
}

extension TerminalError: LocalizedError {
    var errorDescription: String? { message }
}

extension TerminalIssue {
    static let notSupportedOnThisPhone = TerminalIssue(
        title: "This iPhone can't take Tap to Pay",
        message: "Tap to Pay on iPhone needs an iPhone XS or later with the latest iOS. You can still practice in test mode.",
        canRetry: false
    )

    static let stripeNotConfigured = TerminalIssue(
        title: "Card payments aren't set up yet",
        message: "The shop's Stripe account isn't connected to the server yet, so cards can't be charged. Add STRIPE_SECRET_KEY on the server, then come back. You can practice in test mode meanwhile.",
        canRetry: true
    )

    static let locationMissing = TerminalIssue(
        title: "Tap to Pay needs the shop's Stripe location",
        message: "Stripe is connected, but the server has no Terminal location yet. Create one in the Stripe Dashboard (Terminal, Locations) and set STRIPE_TERMINAL_LOCATION_ID on the server. You can practice in test mode meanwhile.",
        canRetry: true
    )
}
