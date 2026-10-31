#if canImport(StripeTerminal)
import Foundation
import Observation
import StripeTerminal
import UIKit

/// Tap to Pay on iPhone through Stripe Terminal 6.
///
/// - Stripe's SDK is set up once, the first time a reader is prepared
///   (`Terminal.initWithTokenProvider`), with `TerminalTokenProvider` fetching
///   connection tokens from the shop's server.
/// - `prepare` connects the iPhone's built-in reader to the shop's Terminal
///   location. The first connect on a phone shows Apple's terms (once per
///   Stripe account) and configures the phone, reported as progress.
/// - `collect` retrieves the PaymentIntent the server created, collects the
///   card on Apple's Tap to Pay screen, then confirms it with Stripe (the app
///   says Processing in between). Retries reuse the same PaymentIntent, so
///   one checkout can never charge a card twice.
/// - Stripe calls the delegate on its own threads; `TapToPayReaderEvents`
///   moves every event to the main actor, in order, before touching state.
@MainActor
@Observable
final class StripeTapToPayTerminal: PaymentTerminal {
    let isSimulated = false
    private(set) var state: TerminalState = .idle
    /// What the reader asks the app to show, e.g. "Remove card".
    private(set) var readerMessage: String?
    /// Called when Apple's Tap to Pay terms were just accepted: the app
    /// shows "How to Tap" next, as Apple asks.
    @ObservationIgnored var onTermsAccepted: (() -> Void)?

    /// The name the customer sees on Apple's Tap to Pay screen.
    static let merchantDisplayName = "Izzy Clipz"

    @ObservationIgnored private let events = TapToPayReaderEvents()
    @ObservationIgnored private var connectTask: Task<Void, Error>?
    @ObservationIgnored private var connectCancelable: Cancelable?
    @ObservationIgnored private var paymentCancelable: Cancelable?
    @ObservationIgnored private var reconnectCancelable: Cancelable?
    @ObservationIgnored private var connectedLocationId: String?
    @ObservationIgnored private var requestedLocationId: String?
    /// The latest copy of each PaymentIntent this terminal worked on, by client
    /// secret, so a retry continues from where the last attempt stopped.
    @ObservationIgnored private var intents: [String: PaymentIntent] = [:]
    /// Set by `cancel()`. The running `prepare` or `collect` stops at its next
    /// step, also where Stripe has nothing to cancel (while it reconnects by
    /// itself, or while the PaymentIntent is looked up).
    @ObservationIgnored private var cancelRequested = false

    init() {
        events.terminal = self
    }

    /// Sets up Stripe's SDK once per launch. It fetches a connection token
    /// straight away, so it's only called once the owner is signed in.
    static func initializeSDKIfNeeded() {
        if !Terminal.isInitialized() {
            Terminal.initWithTokenProvider(TerminalTokenProvider.shared)
        }
    }

    // MARK: Connecting

    func prepare(locationId: String) async throws {
        cancelRequested = false
        try await connectIfNeeded(locationId: locationId)
        // Cancel tapped just as Tap to Pay connected: it stays ready, but this payment stops.
        if cancelRequested { throw TerminalError.cancelled }
    }

    private func connectIfNeeded(locationId: String) async throws {
        requestedLocationId = locationId
        if let connectTask {
            // Already connecting (at launch, or coming back to the foreground): wait for it.
            try await connectTask.value
            if connectedLocationId == locationId { return }
        }
        Self.initializeSDKIfNeeded()
        let terminal = Terminal.shared
        switch terminal.connectionStatus {
        case .connected:
            if connectedLocationId == locationId || terminal.connectedReader?.locationId == locationId {
                connectedLocationId = locationId
                state = .ready
                return
            }
            // The shop moved to another location or account (test to live):
            // start over with fresh credentials.
            try? await terminal.disconnectReader()
            _ = terminal.clearCachedCredentials()
            intents = [:]
        case .reconnecting, .connecting, .discovering:
            // Stripe is reconnecting on its own after the app came back; wait for it.
            state = .reconnecting
            await waitWhileConnecting()
            if terminal.connectionStatus == .connected {
                connectedLocationId = terminal.connectedReader?.locationId ?? locationId
                state = .ready
                return
            }
        case .notConnected:
            break
        @unknown default:
            break
        }
        if cancelRequested {
            // Cancel tapped while waiting for Stripe: don't start connecting. If
            // Stripe is still reconnecting by itself, its events say how that ends.
            state = terminal.connectionStatus == .reconnecting ? .reconnecting : .idle
            throw TerminalError.cancelled
        }
        let task = Task { try await self.connect(locationId: locationId) }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func connect(locationId: String) async throws {
        state = .preparing(progress: nil)
        readerMessage = nil
        if case .failure(let error) = Terminal.shared.supportsReaders(of: .tapToPay, discoveryMethod: .tapToPay, simulated: false) {
            let mapped = Self.map(error)
            settleAfterFailure(mapped)
            throw mapped
        }
        do {
            let discovery = try TapToPayDiscoveryConfigurationBuilder().setSimulated(false).build()
            let connection = try TapToPayConnectionConfigurationBuilder(delegate: events, locationId: locationId)
                .setMerchantDisplayName(Self.merchantDisplayName)
                .setTosAcceptancePermitted(true)
                .setAutoReconnectOnUnexpectedDisconnect(true)
                .build()
            let configuration = TapToPayEasyConnectConfiguration(discoveryConfiguration: discovery, connectionConfiguration: connection)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connectCancelable = Terminal.shared.easyConnect(configuration) { reader, error in
                    if reader != nil {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? TerminalError.failed(message: "Tap to Pay couldn't connect. Try again."))
                    }
                }
            }
            connectCancelable = nil
            connectedLocationId = locationId
            UIApplication.shared.isIdleTimerDisabled = false
            state = .ready
        } catch {
            connectCancelable = nil
            UIApplication.shared.isIdleTimerDisabled = false
            let mapped = Self.map(error)
            settleAfterFailure(mapped)
            throw mapped
        }
    }

    private func settleAfterFailure(_ error: TerminalError) {
        if case .unavailable(let issue) = error {
            state = .unavailable(issue)
        } else {
            state = Terminal.shared.connectionStatus == .connected ? .ready : .idle
        }
    }

    /// Waits (up to two minutes, Apple's longest configuration) while Stripe
    /// is connecting or reconnecting by itself, or until Cancel is tapped.
    private func waitWhileConnecting() async {
        await ReaderWait.whileConnecting({
            switch Terminal.shared.connectionStatus {
            case .connecting, .reconnecting, .discovering: return true
            default: return false
            }
        }, unlessCancelled: { cancelRequested })
    }

    // MARK: Payments

    func collect(amountCents: Int, clientSecret: String) async throws -> TerminalPaymentResult {
        cancelRequested = false
        if state != .ready || !Terminal.isInitialized() || Terminal.shared.connectionStatus != .connected {
            guard let location = connectedLocationId ?? requestedLocationId else {
                throw TerminalError.failed(message: "Tap to Pay isn't set up yet. Go to Settings and set up Tap to Pay on iPhone.")
            }
            try await connectIfNeeded(locationId: location)
        }

        var intent: PaymentIntent
        if let known = intents[clientSecret] {
            intent = known
        } else {
            do {
                intent = try await Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret)
            } catch {
                throw Self.map(error)
            }
            intents[clientSecret] = intent
        }
        guard intent.amount == UInt(amountCents), intent.currency.lowercased() == "usd" else {
            intents[clientSecret] = nil
            throw TerminalError.mismatch(message: "This payment's amount doesn't match what's on screen, so it wasn't charged. Start a new payment.")
        }

        switch intent.status {
        case .succeeded:
            return TerminalPaymentResult(paymentIntentId: intent.stripeId, status: .succeeded)
        case .processing:
            return TerminalPaymentResult(paymentIntentId: intent.stripeId, status: .processing)
        case .requiresCapture:
            return TerminalPaymentResult(paymentIntentId: intent.stripeId, status: .requiresCapture)
        case .canceled:
            intents[clientSecret] = nil
            throw TerminalError.mismatch(message: "This payment was cancelled in Stripe. Start a new payment.")
        default:
            break
        }
        // Cancel tapped while Tap to Pay reconnected or the PaymentIntent was
        // looked up: stop before Apple's Tap to Pay screen opens.
        if cancelRequested { throw TerminalError.cancelled }

        readerMessage = nil
        do {
            var collected = intent
            if intent.status != .requiresConfirmation {
                // Apple's Tap to Pay screen takes the card.
                state = .collecting
                collected = try await collectPaymentMethod(intent)
                // Kept, so if confirming fails the same card is confirmed again.
                intents[clientSecret] = collected
            }
            // The card was read (now, or before confirming failed on a network
            // blip): Stripe authorizes it while the app says Processing.
            state = .processing
            let updated = try await confirm(collected)
            intents[clientSecret] = updated
            paymentCancelable = nil
            state = .ready
            switch updated.status {
            case .succeeded:
                return TerminalPaymentResult(paymentIntentId: updated.stripeId, status: .succeeded)
            case .requiresCapture:
                return TerminalPaymentResult(paymentIntentId: updated.stripeId, status: .requiresCapture)
            case .processing:
                return TerminalPaymentResult(paymentIntentId: updated.stripeId, status: .processing)
            default:
                throw TerminalError.declined(message: "The card wasn't charged. Ask for another card and try again.")
            }
        } catch let error as TerminalError {
            // Nobody knows if the card was charged: look the PaymentIntent up again next time.
            if error == .outcomeUnknown { intents[clientSecret] = nil }
            paymentCancelable = nil
            state = Terminal.shared.connectionStatus == .connected ? .ready : .idle
            throw error
        } catch {
            if let failure = error as? ConfirmPaymentIntentError {
                if let updated = failure.paymentIntent {
                    intents[clientSecret] = updated
                } else {
                    // Timed out: nobody knows if the card was charged. Look the
                    // PaymentIntent up again next time instead of reusing a stale copy.
                    intents[clientSecret] = nil
                }
            }
            paymentCancelable = nil
            state = Terminal.shared.connectionStatus == .connected ? .ready : .idle
            throw Self.map(error)
        }
    }

    /// Apple's Tap to Pay screen reads the card. Nothing is charged yet:
    /// `confirm` does that.
    private func collectPaymentMethod(_ intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PaymentIntent, Error>) in
            paymentCancelable = Terminal.shared.collectPaymentMethod(intent) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? TerminalError.failed(message: "Tap to Pay couldn't read the card. No card was charged. Try again."))
                }
            }
        }
    }

    private func confirm(_ intent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PaymentIntent, Error>) in
            paymentCancelable = Terminal.shared.confirmPaymentIntent(intent) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? TerminalError.outcomeUnknown)
                }
            }
        }
    }

    func cancel() {
        // Once the card is read, Stripe is authorizing it: stopping that could
        // leave nobody knowing whether the card was charged.
        guard state != .processing else { return }
        cancelRequested = true
        paymentCancelable?.cancel { _ in }
        paymentCancelable = nil
        connectCancelable?.cancel { _ in }
        connectCancelable = nil
    }

    func abandon(clientSecret: String) async {
        guard let intent = intents.removeValue(forKey: clientSecret), Terminal.isInitialized(), !state.isBusy else { return }
        guard intent.status == .requiresPaymentMethod || intent.status == .requiresConfirmation else { return }
        _ = try? await Terminal.shared.cancelPaymentIntent(intent)
    }

    func disconnect() async {
        cancel()
        if let reconnecting = reconnectCancelable {
            reconnectCancelable = nil
            try? await reconnecting.cancel()
        }
        intents = [:]
        connectedLocationId = nil
        requestedLocationId = nil
        guard Terminal.isInitialized() else {
            state = .idle
            return
        }
        if Terminal.shared.connectionStatus != .notConnected {
            try? await Terminal.shared.disconnectReader()
        }
        // Forget the account, so the next owner key starts clean.
        _ = Terminal.shared.clearCachedCredentials()
        state = .idle
    }

    // MARK: Reader events (on the main actor, in the order Stripe sent them)

    fileprivate func readerStartedInstallingUpdate(cancelable: Cancelable?) {
        // Apple configures the iPhone for Tap to Pay: show progress and keep the screen on.
        UIApplication.shared.isIdleTimerDisabled = true
        state = .preparing(progress: 0)
    }

    fileprivate func readerReportedUpdateProgress(_ progress: Float) {
        state = .preparing(progress: min(max(Double(progress), 0), 1))
    }

    fileprivate func readerFinishedInstallingUpdate(failed: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        if case .preparing = state {
            state = .preparing(progress: failed ? nil : 1)
        }
    }

    fileprivate func readerRequested(message: String) {
        readerMessage = message
    }

    fileprivate func readerDisconnected() {
        connectedLocationId = nil
        if !state.isBusy || state == .reconnecting {
            state = .idle
        }
    }

    fileprivate func readerStartedReconnecting(cancelable: Cancelable) {
        reconnectCancelable = cancelable
        state = .reconnecting
    }

    fileprivate func readerReconnected() {
        reconnectCancelable = nil
        connectedLocationId = Terminal.shared.connectedReader?.locationId ?? connectedLocationId
        state = .ready
    }

    fileprivate func readerFailedToReconnect() {
        reconnectCancelable = nil
        connectedLocationId = nil
        state = .idle
    }

    fileprivate func readerAcceptedTerms() {
        onTermsAccepted?()
    }

    // MARK: Errors

    /// Stripe Terminal's error domain (`SCPErrorDomain`), for tests.
    static var stripeErrorDomain: String { ErrorDomain }

    /// Stripe's errors in plain words, with what to do next.
    static func map(_ error: Error) -> TerminalError {
        if let terminalError = error as? TerminalError { return terminalError }
        if let failure = error as? ConfirmPaymentIntentError {
            if let intent = failure.paymentIntent, intent.status == .requiresPaymentMethod {
                return .declined(message: declineMessage(failure.declineCode))
            }
            let code = (failure as NSError).code
            if code == ErrorCode.Code.canceled.rawValue || code == ErrorCode.Code.canceledByReader.rawValue {
                return .cancelled
            }
            if failure.paymentIntent == nil {
                return .outcomeUnknown
            }
        }
        let nsError = error as NSError
        guard nsError.domain == ErrorDomain, let code = ErrorCode.Code(rawValue: nsError.code) else {
            if nsError.domain == NSError.scp_tapToPayReaderErrorDomain {
                return .failed(message: "Tap to Pay had a problem (\(nsError.code)). Try again in a moment.")
            }
            return .failed(message: "Something went wrong with Tap to Pay. Try again in a moment.")
        }
        switch code {
        case .canceled, .canceledByReader:
            return .cancelled
        case .declinedByStripeAPI, .declinedByReader:
            return .declined(message: declineMessage(nsError.userInfo[ErrorKey.stripeAPIDeclineCode.rawValue] as? String))
        case .cardNotSupported:
            return .declined(message: "That card can't be used with Tap to Pay. Ask for another card.")
        case .locationServicesDisabled:
            return .unavailable(TerminalIssue(
                title: "Turn on Location Services",
                message: "Card payments need this iPhone's location. Open Settings, then Privacy & Security, Location Services, Izzy Clipz Business, and choose While Using the App."
            ))
        case .commandNotAllowed:
            return .unavailable(TerminalIssue(
                title: "Tap to Pay isn't enabled for this app yet",
                message: "Apple hasn't enabled Tap to Pay on iPhone for this copy of the app yet. Once Apple approves it, install the update. Until then you can practice in test mode.",
                canRetry: false
            ))
        case .unsupportedMobileDeviceConfiguration:
            return .unavailable(TerminalIssue(
                title: "Update this iPhone for Tap to Pay",
                message: "Tap to Pay on iPhone needs an iPhone XS or later with the latest iOS, and doesn't work on iOS betas. Update iOS in Settings, then try again.",
                canRetry: false
            ))
        case .passcodeNotEnabled:
            return .unavailable(TerminalIssue(
                title: "Set a passcode",
                message: "Tap to Pay needs a passcode on this iPhone. Set one in Settings, Face ID & Passcode, then try again."
            ))
        case .commandNotAllowedDuringCall:
            return .failed(message: "Tap to Pay can't run during a phone call. Hang up and try again.")
        case .tapToPayReaderTOSAcceptanceRequiresiCloudSignIn:
            return .unavailable(TerminalIssue(
                title: "Sign in with your Apple Account",
                message: "To accept Apple's Tap to Pay terms, sign in with your Apple Account in Settings, then try again."
            ))
        case .tapToPayReaderTOSAcceptanceCanceled, .tapToPayReaderTOSNotYetAccepted, .tapToPayReaderTOSAcceptanceFailed:
            return .unavailable(TerminalIssue(
                title: "Accept Apple's Tap to Pay terms",
                message: "The shop's owner needs to accept Apple's terms for Tap to Pay on iPhone once. Tap Set up Tap to Pay to see them again."
            ))
        case .readerNotAccessibleInBackground, .tapToPayReaderRequestInterrupted:
            return .failed(message: "The payment stopped because the app left the screen. No card was charged. Try again.")
        case .tapToPayReaderFailedToPrepare:
            return .failed(message: "Tap to Pay couldn't get ready. Try again in a moment.")
        case .tapToPayReaderDeviceBanned, .tapToPayReaderMerchantBlocked, .tapToPayReaderInvalidMerchant, .tapToPayReaderAccountDeactivated:
            return .unavailable(TerminalIssue(
                title: "Stripe needs to look at this account",
                message: "Tap to Pay is blocked for this iPhone or Stripe account. Contact Stripe support from the Stripe Dashboard.",
                canRetry: false
            ))
        case .notConnectedToInternet, .requestTimedOut, .tapToPayInternalNetworkError:
            return .failed(message: "No internet connection. Check Wi-Fi or cellular data and try again.")
        case .connectionTokenProviderCompletedWithError, .connectionTokenProviderTimedOut, .connectionTokenProviderCompletedWithNothing:
            return .failed(message: "We couldn't reach the shop's server to start Tap to Pay. Check your internet connection and try again.")
        case .sessionExpired, .notConnectedToReader:
            return .failed(message: "Tap to Pay disconnected. Try again to reconnect.")
        case .readerBusy:
            return .failed(message: "Tap to Pay is busy with another request. Try again in a moment.")
        default:
            let detail = nsError.localizedDescription
            return .failed(message: detail.isEmpty ? "Something went wrong with Tap to Pay. Try again in a moment." : detail)
        }
    }

    private static func declineMessage(_ code: String?) -> String {
        switch code {
        case "insufficient_funds":
            return "The card was declined for insufficient funds. Ask for another card."
        case "expired_card":
            return "The card has expired. Ask for another card."
        case "incorrect_pin", "invalid_pin":
            return "The PIN was wrong. Try again, or ask for another card."
        default:
            return "The card was declined. Ask for another card or another way to pay."
        }
    }
}

/// Hands Stripe Terminal a fresh connection token from the shop's server
/// (`POST /api/owner/terminal/connection-token`). Never cached: Stripe asks
/// for a new one when it needs it.
final class TerminalTokenProvider: NSObject, ConnectionTokenProvider {
    static let shared = TerminalTokenProvider()

    enum TokenError: LocalizedError {
        case signedOut

        var errorDescription: String? { "Sign in with the owner key to take payments." }
    }

    private let lock = NSLock()
    private var fetchToken: (@Sendable () async throws -> String)?

    /// Set when the owner signs in, cleared on sign out.
    func use(_ fetch: (@Sendable () async throws -> String)?) {
        lock.withLock { fetchToken = fetch }
    }

    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        let fetch = lock.withLock { fetchToken }
        guard let fetch else {
            completion(nil, TokenError.signedOut)
            return
        }
        Task {
            do {
                completion(try await fetch(), nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}

/// Receives the Tap to Pay reader's events on Stripe's threads and replays
/// them on the main actor, in order. An NSObject that isn't isolated to any
/// actor, as Stripe's Objective-C delegate protocols need.
final class TapToPayReaderEvents: NSObject, TapToPayReaderDelegate {
    /// Set once, before Stripe can call back. Weak: the terminal owns this object.
    weak var terminal: StripeTapToPayTerminal?

    private func onMain(_ body: @escaping @MainActor (StripeTapToPayTerminal) -> Void) {
        let terminal = self.terminal
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let terminal { body(terminal) }
            }
        }
    }

    func reader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        onMain { $0.readerStartedInstallingUpdate(cancelable: cancelable) }
    }

    func reader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        onMain { $0.readerReportedUpdateProgress(progress) }
    }

    func reader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        let failed = error != nil
        onMain { $0.readerFinishedInstallingUpdate(failed: failed) }
    }

    func reader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        let message = Terminal.stringFromReaderInputOptions(inputOptions)
        onMain { $0.readerRequested(message: message) }
    }

    func reader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
        let message = Terminal.stringFromReaderDisplayMessage(displayMessage)
        onMain { $0.readerRequested(message: message) }
    }

    func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {
        onMain { $0.readerDisconnected() }
    }

    func reader(_ reader: Reader, didStartReconnect cancelable: Cancelable, disconnectReason: DisconnectReason) {
        onMain { $0.readerStartedReconnecting(cancelable: cancelable) }
    }

    func readerDidSucceedReconnect(_ reader: Reader) {
        onMain { $0.readerReconnected() }
    }

    func readerDidFailReconnect(_ reader: Reader) {
        onMain { $0.readerFailedToReconnect() }
    }

    func tapToPayReaderDidAcceptTermsOfService(_ reader: Reader) {
        onMain { $0.readerAcceptedTerms() }
    }
}
#endif
