import AuthenticationServices
import IzzyClipzKit
import UIKit

/// Stripe's window for Connect Stripe, in `ASWebAuthenticationSession`: Safari's engine in a sheet
/// of its own, so the app never sees what the owner types there. Stripe sends him to the shop's
/// server's https return page, which redirects to `izzyclipzbusiness://stripe-connected?status=…`,
/// and the sheet closes by itself on that address.
///
/// The session shares Safari's cookies (`prefersEphemeralWebBrowserSession` is off), so a Stripe
/// sign-in the owner already has, or makes here, is remembered for next time. iOS asks once whether
/// the app may use stripe.com to sign in.
@MainActor
final class WebStripeConnector: NSObject, StripeConnector, ASWebAuthenticationPresentationContextProviding {
    /// The window on screen, `nil` when none is open.
    private var current: StripeWindow?
    /// The window the sheet is shown over, found when it opens.
    private var anchor: UIWindow?

    func connect(using link: IzzyAPI.StripeConnectLink) async throws -> URL? {
        try Task.checkCancellation()
        // One window at a time.
        current?.close()
        current = nil
        guard let window = Self.currentWindow() else { throw StripeConnectorError.couldNotOpen }
        anchor = window

        let page = StripeWindow()
        current = page
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<StripeWindow.Outcome, Never>) in
                page.wait(continuation)
                let session = Self.makeSession(url: link.url) { callbackURL, error in
                    page.give(Self.outcome(callbackURL: callbackURL, error: error))
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                page.session = session
                if !session.start() {
                    page.give(.failed(.couldNotOpen))
                }
            }
        } onCancel: {
            page.give(.closed)
            Task { @MainActor in page.close() }
        }
        if Task.isCancelled {
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
        switch outcome {
        case .back(let url): return url
        case .closed: return nil
        case .failed(let error): throw error
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = anchor ?? Self.currentWindow() { return window }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
    }

    /// The window the owner is looking at: the key window of the scene in front.
    private static func currentWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let front = scenes.filter { $0.activationState == .foregroundActive } + scenes.filter { $0.activationState != .foregroundActive }
        for scene in front {
            if let window = scene.keyWindow ?? scene.windows.first { return window }
        }
        return nil
    }

    /// The session, waiting for the `izzyclipzbusiness` scheme.
    private static func makeSession(url: URL, completion: @escaping ASWebAuthenticationSession.CompletionHandler) -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(url: url, callback: .customScheme(IzzyAPI.StripeConnectLink.callbackScheme), completionHandler: completion)
    }

    /// What the session's answer means: closing the sheet changes nothing; the way back carries
    /// Stripe's status; anything else went wrong.
    nonisolated static func outcome(callbackURL: URL?, error: Error?) -> StripeWindow.Outcome {
        if let error {
            if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                return .closed
            }
            return .failed(.failed)
        }
        guard let callbackURL, IzzyAPI.StripeConnectReturn(callbackURL: callbackURL) != nil else { return .failed(.failed) }
        return .back(callbackURL)
    }
}

/// One open Stripe window: its session, and the answer it gives once, whichever comes first
/// (Stripe's way back to the app, the owner closing the sheet, the session failing to start, or
/// the task being cancelled).
final class StripeWindow: @unchecked Sendable {
    enum Outcome: Sendable {
        case back(URL)
        case closed
        case failed(StripeConnectorError)
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    /// An answer that came before anyone was waiting for it.
    private var early: Outcome?
    private var answered = false
    /// Only touched on the main actor.
    var session: ASWebAuthenticationSession?

    func wait(_ continuation: CheckedContinuation<Outcome, Never>) {
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

    func give(_ outcome: Outcome) {
        lock.lock()
        guard !answered else {
            lock.unlock()
            return
        }
        answered = true
        guard let waiting = continuation else {
            early = outcome
            lock.unlock()
            return
        }
        continuation = nil
        lock.unlock()
        waiting.resume(returning: outcome)
    }

    /// Closes the sheet, if it's still open.
    @MainActor
    func close() {
        session?.cancel()
        session = nil
    }
}
