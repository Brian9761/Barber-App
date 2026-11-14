import Foundation

/// Shows Stripe's card page for a Checkout Session the shop's server made (setup mode: a card is
/// saved, nothing is charged) and waits for it to send the client back to the app.
///
/// The real one, `WebCardSaver`, opens the page in `ASWebAuthenticationSession`, which waits for
/// the `izzyclipz://` address the server's return page redirects to. UI tests (`-ui-testing`) use
/// `FakeCardSaver`, which never opens a page.
///
/// What comes after (asking the shop's server to keep the card) is `CardSetup`'s job, the same
/// for both.
@MainActor
protocol CardSaver: AnyObject {
    /// How the card page ended: `.saved` when Stripe saved the card, `.cancelled` when the client
    /// closed it, `.failed` when the way back went wrong.
    ///
    /// - Throws: `CancellationError` when the task is cancelled (the page is closed then).
    func collectCard(on checkout: IzzyAPI.CardCheckout) async throws -> IzzyAPI.CardCheckoutResult
}

/// Stands in for Stripe's card page in UI tests: "Add a card" saves "Visa •••• 4242" straight away,
/// as if the client had typed Stripe's test card, on the in-memory server's Checkout Session. Launch
/// arguments make the first try go another way:
/// - `-fakeCardCancel`: the client closes the card page;
/// - `-fakeCardFail`: the way back from the card page goes wrong.
@MainActor
final class FakeCardSaver: CardSaver {
    struct Options: Equatable {
        var cancelsOnce = false
        var failsOnce = false

        init() {}

        init(arguments: [String]) {
            cancelsOnce = arguments.contains("-fakeCardCancel")
            failsOnce = arguments.contains("-fakeCardFail")
        }
    }

    private var options: Options
    private let api: FakeShopAPI
    /// How many times the card page was "opened". For tests.
    private(set) var pagesShown = 0

    init(api: FakeShopAPI, options: Options = Options()) {
        self.api = api
        self.options = options
    }

    func collectCard(on checkout: IzzyAPI.CardCheckout) async throws -> IzzyAPI.CardCheckoutResult {
        try Task.checkCancellation()
        pagesShown += 1
        if options.cancelsOnce {
            options.cancelsOnce = false
            return .cancelled
        }
        if options.failsOnce {
            options.failsOnce = false
            return .failed
        }
        // The client types Stripe's test card and taps Save; Stripe sends them back to the app.
        api.completeCardCheckout(sessionId: checkout.sessionId, card: api.sampleCard)
        var back = URLComponents()
        back.scheme = IzzyAPI.CardCheckout.callbackScheme
        back.host = "card-saved"
        back.queryItems = [URLQueryItem(name: "session_id", value: checkout.sessionId)]
        return back.url.flatMap(IzzyAPI.CardCheckoutResult.init(callbackURL:)) ?? .failed
    }
}
