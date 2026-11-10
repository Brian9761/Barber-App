import Foundation
import IzzyClipzKit
import Observation

/// Settings → Card payments (Stripe): how the shop's card payments are set up, and the "login
/// window" that connects the shop's own Stripe account (`GET /api/owner/stripe`,
/// `POST /api/owner/stripe/connect`, `DELETE /api/owner/stripe/connect`).
///
/// Connect Stripe (or Finish setting up) asks the server for a link to Stripe's pages, opens them
/// in Stripe's window (`StripeConnector`), and on the way back loads the status again and says
/// what happened: "You're connected. You can take card payments now." or "Stripe still needs a few
/// details: tap Finish setting up." Closing the window changes nothing.
@MainActor
@Observable
final class StripeConnectionStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        /// The server is from before Stripe Connect: Settings shows what `GET /api/owner/me` says.
        case notOnThisServer
    }

    private(set) var connection: IzzyAPI.StripeConnection?
    private(set) var loadState: LoadState = .idle
    private(set) var isConnecting = false
    private(set) var isDisconnecting = false
    /// What happened after Stripe's window or Disconnect, in plain words, until the next action.
    private(set) var result: Result?
    /// Why the last Connect or Disconnect didn't work, with what to do.
    var actionError: String?

    struct Result: Equatable {
        let message: String
        /// Good news (connected), shown in green; otherwise something to know or do.
        let isGoodNews: Bool
    }

    @ObservationIgnored private let api: any OwnerAPI
    @ObservationIgnored let connector: any StripeConnector
    /// Bumped by every load, so a slow answer for an older load never replaces a newer one.
    @ObservationIgnored private var generation = 0
    /// Called when the connection changed (connected, finished, disconnected), so Take payment and
    /// Tap to Pay read the new status from the server too.
    @ObservationIgnored var onChange: (() -> Void)?

    init(api: any OwnerAPI, connector: any StripeConnector) {
        self.api = api
        self.connector = connector
    }

    /// The status row, the buttons and the lines, for what the server said last.
    var display: StripeStatusDisplay? {
        connection.map(StripeStatusDisplay.init(connection:))
    }

    // MARK: Loading

    /// `GET /api/owner/stripe`: the server asks Stripe how the account is doing. Keeps what's on
    /// screen if it fails.
    func refresh() async {
        generation += 1
        let requested = generation
        if connection == nil { loadState = .loading }
        do {
            let loaded = try await api.stripeConnection()
            guard requested == generation else { return }
            connection = loaded
            loadState = .loaded
        } catch is CancellationError {
            if requested == generation, loadState == .loading { loadState = .idle }
        } catch {
            guard requested == generation else { return }
            if let apiError = error as? APIError, apiError.code == IzzyAPI.ErrorCode.notFound {
                loadState = .notOnThisServer
            } else {
                loadState = .failed(ErrorText.message(for: error))
            }
        }
    }

    // MARK: Connecting

    /// Connect Stripe, or Finish setting up: Stripe's window, then the status again and a line
    /// that says what happened. Closing the window changes nothing.
    func connect() async {
        guard !isConnecting, !isDisconnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        actionError = nil
        result = nil
        do {
            let link = try await api.connectStripe()
            // The server made the shop's account if it had none: the status shows it from now on
            // (Finish setting up), here and on Take payment, even if the owner closes the window.
            guard let wayBack = try await connector.connect(using: link) else {
                await refresh()
                onChange?()
                return
            }
            let returned = IzzyAPI.StripeConnectReturn(callbackURL: wayBack) ?? IzzyAPI.StripeConnectReturn(status: .unknown)
            await refresh()
            // The server just asked Stripe again: its answer wins over the one on the way back.
            let status = loadState == .loaded ? (connection?.status ?? returned.status) : returned.status
            result = Result(message: IzzyAPI.StripeConnectReturn(status: status).resultMessage, isGoodNews: status == .active)
            onChange?()
        } catch is CancellationError {
            return
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// Disconnect Stripe (after the owner confirmed): the server forgets the account, which stays
    /// open at Stripe. Card payments stop until he connects again.
    func disconnect() async {
        guard !isDisconnecting, !isConnecting else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        actionError = nil
        result = nil
        do {
            let answer = try await api.disconnectStripe()
            generation += 1
            connection = answer
            loadState = .loaded
            result = Result(message: answer.message, isGoodNews: false)
            onChange?()
        } catch is CancellationError {
            return
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// The server's words when it has them; the owner key only for Disconnect, which the app has.
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError, case .offline = apiError {
            return "We couldn't reach the server. Check your internet connection and try again."
        }
        return ErrorText.message(for: error)
    }

    /// What Disconnect asks first.
    static let disconnectQuestion = "Disconnect Stripe?"
    static let disconnectExplanation =
        "Card payments stop until you connect Stripe again. Your Stripe account isn't closed, and cards clients saved stay with it: they can't be used here until they add them again."
}

/// What Settings shows for the shop's Stripe connection: the status row ("Connected" with a green
/// check, the business name and the server's message), the main button, and which other actions
/// make sense.
struct StripeStatusDisplay: Equatable {
    enum Tone: Equatable {
        /// Card payments are on.
        case good
        /// Something to finish, or Stripe is checking.
        case waiting
        /// Stripe paused card payments.
        case problem
        /// Nothing connected, or nothing to connect.
        case neutral
    }

    /// "Connected", "Not connected", "Finish setting up", "Stripe is checking your details", "Paused
    /// by Stripe", "Uses the server's Stripe key", "Not set up on the server".
    let title: String
    let symbol: String
    let tone: Tone
    /// The Stripe account's business name, once one is connected.
    let businessName: String?
    /// The server's plain words: "Connected. Card payments are on. Payouts to your bank are on."
    let message: String
    /// "Connect Stripe", "Finish setting up", or nothing to tap.
    let buttonTitle: String?
    /// Open Stripe Dashboard: with an account connected, or the server's own key.
    let showsDashboard: Bool
    /// Disconnect Stripe: only with an account connected (owner key only, which the app has).
    let canDisconnect: Bool
    let dashboardURL: URL

    init(connection: IzzyAPI.StripeConnection) {
        let status = connection.status
        title = status.title
        switch status {
        case .active:
            symbol = "checkmark.circle.fill"
            tone = .good
        case .direct:
            symbol = "checkmark.circle.fill"
            tone = .good
        case .notConnected:
            symbol = "link.circle"
            tone = .neutral
        case .needsInfo:
            symbol = "exclamationmark.circle.fill"
            tone = .waiting
        case .pending:
            symbol = "clock.fill"
            tone = .waiting
        case .restricted:
            symbol = "pause.circle.fill"
            tone = .problem
        case .off:
            symbol = "minus.circle"
            tone = .neutral
        case .unknown:
            symbol = "questionmark.circle"
            tone = .waiting
        }
        businessName = connection.businessName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        message = connection.message
        buttonTitle = status.connectButtonTitle
        let hasAccount = connection.mode == .connect && connection.accountId != nil
        showsDashboard = hasAccount || connection.mode == .direct
        canDisconnect = hasAccount
        dashboardURL = connection.dashboardUrl
    }

    /// What VoiceOver reads for the status row: "Card payments, Connected, Izzy Clipz Barbershop".
    var spoken: String {
        ["Card payments", title, businessName].compactMap { $0 }.joined(separator: ", ")
    }
}
