import Foundation
import IzzyClipzKit
import Observation

/// Signing in and out, and the signed-in workspace.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        /// Reading the keychain.
        case launching
        case signedOut
        case signedIn(Workspace)
    }

    let environment: AppEnvironment
    private(set) var phase: Phase = .launching
    private(set) var isSigningIn = false
    /// Why the last sign-in didn't work, in plain words.
    private(set) var signInError: String?
    /// Shown on the sign-in screen after being signed out by the server.
    private(set) var notice: String?

    /// The owner key is at least this long on the server (shorter keys are
    /// turned down there with `owner_not_configured`).
    static let minimumKeyLength = 32

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var workspace: Workspace? {
        if case .signedIn(let workspace) = phase { return workspace }
        return nil
    }

    /// Opens the workspace straight away when a key is saved, then checks the
    /// key with the server in the background.
    func start() async {
        guard case .launching = phase else { return }
        let saved: String?
        do {
            saved = try environment.secrets.read()
        } catch {
            saved = nil
            notice = (error as? KeychainError)?.errorDescription
        }
        guard let key = saved, !key.isEmpty else {
            phase = .signedOut
            return
        }
        let workspace = makeWorkspace(ownerKey: key)
        phase = .signedIn(workspace)
        await refresh(workspace)
    }

    /// The app came back to the foreground.
    func becameActive() async {
        guard let workspace else { return }
        await refresh(workspace)
    }

    private func refresh(_ workspace: Workspace) async {
        await workspace.refreshStatus()
        if workspace.keyWasRejected, self.workspace === workspace {
            await signOut(notice: "The owner key changed on the server. Paste the new key to sign in again.")
            return
        }
        await workspace.warmUpTapToPay()
        // Payments a closed app never heard back about.
        await workspace.checkout.syncPendingPayments()
    }

    /// Checks a pasted owner key with the server and keeps it in the keychain.
    func signIn(key typed: String) async {
        guard !isSigningIn else { return }
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        notice = nil
        guard !key.isEmpty else {
            signInError = "Paste the owner key to sign in."
            return
        }
        guard key.count >= Self.minimumKeyLength else {
            signInError = "That key is too short. The owner key is at least \(Self.minimumKeyLength) characters long. Copy all of it."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let status = try await environment.api(ownerKey: key).ownerStatus()
            signInError = nil
            let workspace = makeWorkspace(ownerKey: key, status: status)
            workspace.keySaveError = saveKey(key)
            phase = .signedIn(workspace)
            await workspace.didSignIn()
        } catch is CancellationError {
            return
        } catch {
            signInError = Self.signInMessage(for: error)
        }
    }

    /// Replaces the saved owner key with a new one, after checking it.
    /// Returns a message when it didn't work.
    func replaceKey(with typed: String) async -> String? {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= Self.minimumKeyLength else {
            return "That key is too short. The owner key is at least \(Self.minimumKeyLength) characters long."
        }
        do {
            let status = try await environment.api(ownerKey: key).ownerStatus()
            if let old = workspace { await old.tearDown() }
            let workspace = makeWorkspace(ownerKey: key, status: status)
            workspace.keySaveError = saveKey(key)
            phase = .signedIn(workspace)
            await workspace.didSignIn()
            return nil
        } catch {
            return Self.signInMessage(for: error)
        }
    }

    func signOut(notice: String? = nil) async {
        if let workspace { await workspace.tearDown() }
        try? environment.secrets.delete()
        signInError = nil
        self.notice = notice
        phase = .signedOut
    }

    /// Keeps the key in the keychain. A keychain that refuses doesn't stop
    /// the owner working: they're told they'll need to paste it again.
    private func saveKey(_ key: String) -> String? {
        do {
            try environment.secrets.save(key)
            return nil
        } catch {
            return "This iPhone couldn't keep the owner key, so you'll need to paste it again next time. \(ErrorText.message(for: error))"
        }
    }

    private func makeWorkspace(ownerKey: String, status: IzzyAPI.OwnerStatus? = nil) -> Workspace {
        Workspace(environment: environment, ownerKey: ownerKey, status: status)
    }

    static func signInMessage(for error: Error) -> String {
        switch error as? APIError {
        case .unauthorized?:
            return "That owner key isn't right. Copy it again from the server's OWNER_KEY setting and paste all of it."
        case .offline?:
            return "We couldn't reach the server. Check your internet connection and try again."
        case .notConfigured(let feature)? where feature == APIError.Feature.owner:
            return "The server doesn't have an owner key yet. Set OWNER_KEY (at least 32 characters) in the server's settings, then try again."
        case .notConfigured?:
            return "The app's server address isn't set up correctly."
        case .decoding?:
            return "The server answered in a way this app doesn't understand. Make sure the server is up to date."
        case .server(_, _, let status)? where status == 0 || status >= 500:
            return "The server isn't answering right now. Try again in a moment."
        case let apiError?:
            return apiError.userMessage
        case nil:
            return (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
        }
    }
}
