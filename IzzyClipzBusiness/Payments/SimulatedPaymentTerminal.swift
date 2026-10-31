import Foundation
import Observation

/// A pretend card reader that never touches a card or Stripe.
///
/// Used by UI tests, previews, and whenever this iPhone or the shop's account
/// can't take real Tap to Pay payments, so the owner can still practice. The
/// app labels every screen that uses it "Test mode — no real charge".
///
/// It shows its own "tap a card" sheet (`SimulatedTapSheet`) with three test
/// cards: one that's approved, one that's declined, and the customer
/// cancelling. Unit tests and previews set `automaticOutcome` instead.
@MainActor
@Observable
final class SimulatedPaymentTerminal: PaymentTerminal {
    enum Outcome: String, CaseIterable, Sendable {
        case approve
        case decline
        case customerCancels
    }

    /// A "tap a card" request waiting for one of the test cards.
    struct PendingTap: Identifiable, Equatable {
        let id = UUID()
        let amountCents: Int
    }

    let isSimulated = true
    private(set) var state: TerminalState = .idle

    /// When set, every payment resolves this way on its own, without the sheet.
    var automaticOutcome: Outcome?
    /// How long pretend steps take, so progress is visible; zero in unit tests.
    var stepDelay: Duration
    /// Called when a test card is approved, with the PaymentIntent's client
    /// secret: the in-memory fake server uses it to mark its pretend
    /// PaymentIntent succeeded, as Stripe would.
    var onApproved: ((String) -> Void)?

    /// The sheet's request, while one is up.
    private(set) var pendingTap: PendingTap?
    private var continuation: CheckedContinuation<Outcome, Never>?

    /// How many times `collect` ran, and with which client secrets.
    private(set) var collectedSecrets: [String] = []

    init(automaticOutcome: Outcome? = nil, stepDelay: Duration = .milliseconds(350)) {
        self.automaticOutcome = automaticOutcome
        self.stepDelay = stepDelay
    }

    func prepare(locationId: String) async throws {
        if state == .ready { return }
        state = .preparing(progress: 0)
        for progress in [0.35, 0.7, 1.0] {
            try await pause()
            state = .preparing(progress: progress)
        }
        state = .ready
    }

    func collect(amountCents: Int, clientSecret: String) async throws -> TerminalPaymentResult {
        if state != .ready {
            try await prepare(locationId: "simulated")
        }
        collectedSecrets.append(clientSecret)
        state = .collecting
        let outcome: Outcome
        if let automaticOutcome {
            try? await pause()
            outcome = automaticOutcome
        } else {
            outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    self.pendingTap = PendingTap(amountCents: amountCents)
                }
            } onCancel: {
                Task { @MainActor in self.choose(.customerCancels) }
            }
        }
        pendingTap = nil
        switch outcome {
        case .approve:
            state = .processing
            try? await pause()
            onApproved?(clientSecret)
            state = .ready
            return TerminalPaymentResult(paymentIntentId: nil, status: .succeeded)
        case .decline:
            state = .ready
            throw TerminalError.declined(message: "The test card was declined. In test mode no card is ever charged.")
        case .customerCancels:
            state = .ready
            throw TerminalError.cancelled
        }
    }

    /// The test card the owner picked on the sheet.
    func choose(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }

    func cancel() {
        choose(.customerCancels)
    }

    func abandon(clientSecret: String) async {}

    func disconnect() async {
        cancel()
        state = .idle
    }

    private func pause() async throws {
        if stepDelay > .zero {
            try await Task.sleep(for: stepDelay)
        }
    }
}
