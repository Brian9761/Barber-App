import Foundation
import IzzyClipzKit

/// Opens Stripe's own window for Settings → Connect Stripe (or Finish setting up), where the owner
/// signs in to Stripe or signs up and finishes setting up, and waits for Stripe to send him back to
/// the app.
///
/// The real one, `WebStripeConnector`, opens the link in `ASWebAuthenticationSession` and waits
/// for the `izzyclipzbusiness://stripe-connected?status=…` address the server's return page
/// redirects to. On the sample server (UI tests and the demo version), `FakeStripeConnector`
/// stands in for Stripe's window.
@MainActor
protocol StripeConnector: AnyObject {
    /// The address Stripe's pages came back to, or `nil` when the owner closed the window (nothing
    /// changes then).
    ///
    /// - Throws: `StripeConnectorError` when the window couldn't open, and `CancellationError` when
    ///   the task is cancelled (the window closes then).
    func connect(using link: IzzyAPI.StripeConnectLink) async throws -> URL?
}

/// Why Stripe's window didn't bring the owner back.
enum StripeConnectorError: Error, Equatable, LocalizedError {
    /// The window couldn't open (no window to show it over, or iOS refused).
    case couldNotOpen
    /// The window closed with something other than the way back.
    case failed

    var errorDescription: String? {
        switch self {
        case .couldNotOpen: return "Stripe's window didn't open. Try again in a moment."
        case .failed: return "Stripe didn't send you back to the app. Tap the button again to finish."
        }
    }
}

/// Stands in for Stripe's window on the sample server: tapping Connect Stripe connects the sample
/// account straight away (`FakeServer.finishStripeSetup`), and comes back the way Stripe would. In
/// the demo it takes a moment, so it reads as a step. Launch arguments make the first try go
/// another way:
/// - `-fake-stripe-needs-info`: the owner leaves details missing (Settings then says Finish setting up);
/// - `-fake-stripe-cancel`: the owner closes the window (nothing changes).
@MainActor
final class FakeStripeConnector: StripeConnector {
    /// What the first try does.
    enum FirstTry: Equatable, Sendable {
        case finishes
        case leavesDetailsMissing
        case closesTheWindow
    }

    private let server: FakeServer
    private var firstTry: FirstTry?
    private let delay: Duration
    /// How many times the window was "opened". For tests.
    private(set) var windowsOpened = 0

    init(server: FakeServer, firstTry: FirstTry = .finishes, delay: Duration = .zero) {
        self.server = server
        self.firstTry = firstTry
        self.delay = delay
    }

    func connect(using link: IzzyAPI.StripeConnectLink) async throws -> URL? {
        try Task.checkCancellation()
        windowsOpened += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        let attempt = firstTry ?? .finishes
        firstTry = nil
        switch attempt {
        case .closesTheWindow:
            return nil
        case .leavesDetailsMissing:
            return Self.wayBack(status: server.finishStripeSetup(detailsSubmitted: false))
        case .finishes:
            return Self.wayBack(status: server.finishStripeSetup(detailsSubmitted: true))
        }
    }

    /// `izzyclipzbusiness://stripe-connected?status=active`, as the server's return page sends it.
    static func wayBack(status: IzzyAPI.StripeConnection.Status) -> URL? {
        var back = URLComponents()
        back.scheme = IzzyAPI.StripeConnectLink.callbackScheme
        back.host = "stripe-connected"
        back.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
        return back.url
    }
}

/// For a build without `ASWebAuthenticationSession` (the Linux checks): Stripe's window can't open.
@MainActor
final class UnavailableStripeConnector: StripeConnector {
    func connect(using link: IzzyAPI.StripeConnectLink) async throws -> URL? {
        throw StripeConnectorError.couldNotOpen
    }
}
