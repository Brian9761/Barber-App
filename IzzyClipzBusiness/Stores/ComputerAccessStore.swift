import Foundation
import IzzyClipzKit
import Observation

/// Settings → Use on a computer: the 6-digit code the owner types on the website's Business area
/// (`POST /api/owner/computer-codes`), counting down while it works, and the computers signed in
/// (`GET /api/owner/computer-sessions`), each of which (or all) can be signed out.
///
/// A code works once, for 10 minutes, and a new one replaces it. The countdown runs from when the
/// code arrived, by this app's clock, so a phone whose clock is off still counts right.
@MainActor
@Observable
final class ComputerAccessStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The code on screen, and when it arrived.
    private(set) var code: IzzyAPI.ComputerCode?
    private(set) var receivedAt: Date?
    private(set) var isMakingCode = false
    /// Why the last code didn't come, with what to do.
    private(set) var codeError: String?

    /// The computers signed in now, most recently used first.
    private(set) var sessions: [IzzyAPI.ComputerSession] = []
    private(set) var sessionsState: LoadState = .idle
    /// Computers being signed out right now.
    private(set) var signingOut: Set<String> = []
    private(set) var isSigningOutAll = false
    /// A sign out that didn't work, for an alert.
    var actionError: String?

    /// Where the Business area is: "izzy-clipz-api.vercel.app/business".
    let siteAddress: String
    let shopTime: ShopTime
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored private let api: any OwnerAPI
    /// Bumped by every load of the computers, so a slow answer never replaces a newer one.
    @ObservationIgnored private var generation = 0

    init(api: any OwnerAPI, siteAddress: String, shopTime: ShopTime, clock: @escaping () -> Date) {
        self.api = api
        self.siteAddress = siteAddress
        self.shopTime = shopTime
        self.clock = clock
    }

    // MARK: The code

    /// The seconds the code on screen still works at `now`; `nil` without a code.
    func secondsLeft(at now: Date) -> Int? {
        guard let code, let receivedAt else { return nil }
        return code.secondsLeft(receivedAt: receivedAt, now: now)
    }

    /// Whether the code on screen has run out (or there isn't one).
    func codeHasRunOut(at now: Date) -> Bool {
        (secondsLeft(at: now) ?? 0) == 0
    }

    /// "Expires in 9:42", or "This code has run out. Get a new code." once it has.
    func countdownText(at now: Date) -> String? {
        guard let left = secondsLeft(at: now) else { return nil }
        guard left > 0 else { return "This code has run out. Get a new code." }
        return "Expires in " + IzzyAPI.ComputerCode.countdownLabel(seconds: left)
    }

    /// The code, as VoiceOver reads it: digit by digit, "4 8 3, 9 2 0".
    var spokenCode: String? {
        guard let code else { return nil }
        let digits = code.code.map(String.init)
        guard digits.count == 6 else { return digits.joined(separator: " ") }
        return digits[0..<3].joined(separator: " ") + ", " + digits[3..<6].joined(separator: " ")
    }

    /// When the screen opens: a code, unless the one on screen still works.
    func showCodeIfNeeded() async {
        guard !isMakingCode else { return }
        if code != nil, !codeHasRunOut(at: clock()) { return }
        await makeCode()
    }

    /// Get a new code: it replaces the one before, which stops working.
    func makeCode() async {
        guard !isMakingCode else { return }
        isMakingCode = true
        defer { isMakingCode = false }
        codeError = nil
        do {
            let made = try await api.createComputerCode()
            code = made
            receivedAt = clock()
        } catch is CancellationError {
            return
        } catch {
            codeError = Self.message(for: error)
        }
    }

    // MARK: Computers signed in

    func refreshSessions() async {
        generation += 1
        let requested = generation
        if sessionsState != .loaded { sessionsState = .loading }
        do {
            let loaded = try await api.computerSessions()
            guard requested == generation else { return }
            sessions = loaded
            sessionsState = .loaded
        } catch is CancellationError {
            if requested == generation, sessionsState == .loading { sessionsState = .idle }
        } catch {
            guard requested == generation else { return }
            let message = Self.message(for: error)
            if sessionsState == .loaded {
                actionError = message
            } else {
                sessionsState = .failed(message)
            }
        }
    }

    /// Signs one computer out: it goes back to the website's sign-in page.
    func signOut(_ session: IzzyAPI.ComputerSession) async {
        guard !signingOut.contains(session.id), !isSigningOutAll else { return }
        signingOut.insert(session.id)
        defer { signingOut.remove(session.id) }
        do {
            try await api.signOutComputer(id: session.id)
            generation += 1
            sessions.removeAll { $0.id == session.id }
        } catch let error as APIError where error.code == IzzyAPI.ErrorCode.notFound {
            // Already signed out (on the website, or it ran out).
            generation += 1
            sessions.removeAll { $0.id == session.id }
        } catch is CancellationError {
            return
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// Signs every computer out (after the owner confirmed).
    func signOutAll() async {
        guard !isSigningOutAll else { return }
        isSigningOutAll = true
        defer { isSigningOutAll = false }
        do {
            try await api.signOutAllComputers()
            generation += 1
            sessions = []
            sessionsState = .loaded
        } catch is CancellationError {
            return
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// "Last used today at 10:45 AM", "Last used yesterday at 6:10 PM", "Last used Mon, Nov 2 at 9:05 AM".
    func lastUsedText(for session: IzzyAPI.ComputerSession) -> String {
        let today = shopTime.day(containing: clock())
        let day = shopTime.relativeDay(shopTime.day(containing: session.lastUsedAt), today: today)
        let when = ["Today", "Tomorrow", "Yesterday"].contains(day) ? day.lowercased() : day
        return "Last used \(when) at \(shopTime.time(session.lastUsedAt))"
    }

    /// Settings' row: "2 computers signed in", "1 computer signed in", "No computers signed in".
    var summary: String? {
        guard sessionsState == .loaded else { return nil }
        switch sessions.count {
        case 0: return "No computers signed in"
        case 1: return "1 computer signed in"
        default: return "\(sessions.count) computers signed in"
        }
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError, case .offline = apiError {
            return "We couldn't reach the server. Check your internet connection and try again."
        }
        return ErrorText.message(for: error)
    }

    /// What Sign out all computers asks first.
    static let signOutAllQuestion = "Sign out all computers?"
    static let signOutAllExplanation = "Every computer goes back to the website's sign-in page. To use one again, sign in with a new code from here."
}
