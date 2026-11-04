import AuthenticationServices
import SwiftUI
import UIKit

/// Stripe's card page in `ASWebAuthenticationSession`: Safari's engine in a sheet of its own, so
/// the app never sees what's typed there. Stripe sends the client to the shop's server's https
/// return page, which redirects to `izzyclipz://card-saved?session_id=…` (or `card-cancelled`), and
/// the sheet closes by itself on that address.
///
/// The session is private (`prefersEphemeralWebBrowserSession`): it shares no cookies with Safari,
/// and iOS doesn't first ask whether the app may "sign in" with stripe.com, which would make no
/// sense to someone adding a card.
@MainActor
final class WebCardSaver: NSObject, CardSaver, ASWebAuthenticationPresentationContextProviding {
    /// The page on screen and its answer, `nil` when none is open.
    private var current: CardPage?
    /// The window the page is shown over, found when it opens.
    private var anchor: UIWindow?

    func collectCard(on checkout: IzzyAPI.CardCheckout) async throws -> IzzyAPI.CardCheckoutResult {
        try Task.checkCancellation()
        // One card page at a time.
        current?.close()
        current = nil
        guard let window = Self.currentWindow() else { return .failed }
        anchor = window

        let page = CardPage()
        current = page
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<IzzyAPI.CardCheckoutResult, Never>) in
                page.wait(continuation)
                let session = Self.makeSession(url: checkout.url) { callbackURL, error in
                    page.give(Self.result(callbackURL: callbackURL, error: error))
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                page.session = session
                if !session.start() {
                    page.give(.failed)
                }
            }
        } onCancel: {
            // The task's answer is "cancelled" now, whether or not the session reports back.
            page.give(.cancelled)
            Task { @MainActor in page.close() }
        }
        if Task.isCancelled {
            // Closes the sheet now, if the session hasn't closed it.
            page.close()
        } else {
            // It has answered: let go of it (its completion handler holds the page).
            page.session = nil
        }
        if current === page {
            current = nil
            anchor = nil
        }
        try Task.checkCancellation()
        return result
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = anchor ?? Self.currentWindow() { return window }
        // Not reached: the page only opens over a window (`collectCard` checks). A window is needed.
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
    }

    /// The window the client is looking at: the key window of the scene in front.
    private static func currentWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let front = scenes.filter { $0.activationState == .foregroundActive } + scenes.filter { $0.activationState != .foregroundActive }
        for scene in front {
            if let window = scene.keyWindow ?? scene.windows.first { return window }
        }
        return nil
    }

    /// The session, waiting for the `izzyclipz` scheme (the matching callback API from iOS 17.4).
    private static func makeSession(
        url: URL,
        completion: @escaping ASWebAuthenticationSession.CompletionHandler
    ) -> ASWebAuthenticationSession {
        if #available(iOS 17.4, *) {
            return ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(IzzyAPI.CardCheckout.callbackScheme),
                completionHandler: completion
            )
        }
        return ASWebAuthenticationSession(url: url, callbackURLScheme: IzzyAPI.CardCheckout.callbackScheme, completionHandler: completion)
    }

    /// What the session's answer means: closing the sheet is a cancel; any other error, or an
    /// address that isn't one of the app's, didn't save a card.
    nonisolated static func result(callbackURL: URL?, error: Error?) -> IzzyAPI.CardCheckoutResult {
        if let error {
            if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                return .cancelled
            }
            return .failed
        }
        return callbackURL.flatMap(IzzyAPI.CardCheckoutResult.init(callbackURL:)) ?? .failed
    }
}

/// One open card page: its session, and the answer it gives once, whichever comes first (Stripe's
/// way back to the app, the client closing the sheet, the session failing to start, or the task
/// being cancelled).
private final class CardPage: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<IzzyAPI.CardCheckoutResult, Never>?
    /// An answer that came before anyone was waiting for it.
    private var early: IzzyAPI.CardCheckoutResult?
    private var answered = false
    /// Only touched on the main actor.
    var session: ASWebAuthenticationSession?

    func wait(_ continuation: CheckedContinuation<IzzyAPI.CardCheckoutResult, Never>) {
        lock.lock()
        if let early {
            self.early = nil
            lock.unlock()
            continuation.resume(returning: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func give(_ result: IzzyAPI.CardCheckoutResult) {
        lock.lock()
        guard !answered else {
            lock.unlock()
            return
        }
        answered = true
        guard let waiting = continuation else {
            early = result
            lock.unlock()
            return
        }
        continuation = nil
        lock.unlock()
        waiting.resume(returning: result)
    }

    /// Closes the sheet, if it's still open.
    @MainActor
    func close() {
        session?.cancel()
        session = nil
    }
}

extension APIConfiguration {
    /// Stripe's card page: the real one, or while UI testing a stand-in that saves Stripe's test
    /// card on the in-memory server without opening a page (`FakeCardSaver`).
    @MainActor
    static func makeCardSaver(api: any ShopAPI) -> any CardSaver {
        if LaunchOptions.isUITesting, let fake = api as? FakeShopAPI {
            return FakeCardSaver(api: fake, options: FakeCardSaver.Options(arguments: ProcessInfo.processInfo.arguments))
        }
        return WebCardSaver()
    }
}

private struct CardSaverKey: EnvironmentKey {
    static let defaultValue: (any CardSaver)? = nil
}

extension EnvironmentValues {
    /// Stripe's card page for adding a card on Review. `nil` (previews) shows the real page.
    var cardSaver: (any CardSaver)? {
        get { self[CardSaverKey.self] }
        set { self[CardSaverKey.self] = newValue }
    }
}
