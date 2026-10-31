import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Money in cents, the keypad, the simulated reader, and Stripe's errors in
/// plain words.
@MainActor
final class MoneyAndTerminalTests: XCTestCase {
    // MARK: Money

    func testAmountsAlwaysShowCents() {
        XCTAssertEqual(Money.amount(0), "$0.00")
        XCTAssertEqual(Money.amount(5), "$0.05")
        XCTAssertEqual(Money.amount(3500), "$35.00")
        XCTAssertEqual(Money.amount(3510), "$35.10")
        XCTAssertEqual(Money.amount(100_000), "$1,000.00")
        XCTAssertEqual(Money.amount(123_456_789), "$1,234,567.89")
        XCTAssertEqual(Money.amount(-250), "-$2.50")
    }

    func testSpokenAmounts() {
        XCTAssertEqual(Money.spoken(3500), "35 dollars")
        XCTAssertEqual(Money.spoken(101), "1 dollar and 1 cent")
        XCTAssertEqual(Money.spoken(50), "50 cents")
    }

    func testTypedPrices() {
        XCTAssertEqual(Money.cents(from: "25"), 2500)
        XCTAssertEqual(Money.cents(from: "25.5"), 2550)
        XCTAssertEqual(Money.cents(from: "$25.05"), 2505)
        XCTAssertEqual(Money.cents(from: " 1,250 "), 125_000)
        XCTAssertEqual(Money.cents(from: ".5"), 50)
        XCTAssertEqual(Money.cents(from: "0"), 0)
        XCTAssertNil(Money.cents(from: ""))
        XCTAssertNil(Money.cents(from: "."))
        XCTAssertNil(Money.cents(from: "1.234"))
        XCTAssertNil(Money.cents(from: "-5"))
        XCTAssertNil(Money.cents(from: "1.2.3"))
        XCTAssertNil(Money.cents(from: "ten"))
        XCTAssertNil(Money.cents(from: "99999999999"))
        XCTAssertEqual(Money.editable(2550), "25.50")
        XCTAssertEqual(Money.editable(2505), "25.05")
        XCTAssertEqual(Money.editable(2500), "25")
    }

    func testTheKeypadPushesDigitsInFromTheRight() {
        var entry = AmountEntry()
        for digit in [3, 5, 0, 0] { entry.append(digit: digit) }
        XCTAssertEqual(entry.cents, 3500)
        XCTAssertTrue(entry.isChargeable)
        entry.deleteLast()
        XCTAssertEqual(entry.cents, 350)
        entry.appendDoubleZero()
        XCTAssertEqual(entry.cents, 35_000)
        entry.clear()
        XCTAssertEqual(entry.cents, 0)
        XCTAssertFalse(entry.isChargeable)
        for _ in 0..<12 { entry.append(digit: 9) }
        XCTAssertEqual(entry.cents, AmountEntry.maximumCents, "It stops at the keypad's limit")
        XCTAssertFalse(entry.isChargeable, "Over the server's $1,000 limit")
        entry.append(digit: 42)
        XCTAssertEqual(entry.cents, AmountEntry.maximumCents)
        XCTAssertEqual(AmountEntry(cents: -5).cents, 0)
    }

    // MARK: Simulated reader

    func testTheSimulatedReaderPreparesWithProgressAndNeverChargesAnything() async throws {
        let terminal = SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .milliseconds(5))
        XCTAssertTrue(terminal.isSimulated)
        XCTAssertEqual(terminal.state, .idle)
        try await terminal.prepare(locationId: "tml_x")
        XCTAssertEqual(terminal.state, .ready)
        var approved: [String] = []
        terminal.onApproved = { approved.append($0) }
        let result = try await terminal.collect(amountCents: 100, clientSecret: "secret_1")
        XCTAssertEqual(result, TerminalPaymentResult(paymentIntentId: nil, status: .succeeded))
        XCTAssertEqual(approved, ["secret_1"])

        terminal.automaticOutcome = .decline
        do {
            _ = try await terminal.collect(amountCents: 100, clientSecret: "secret_2")
            XCTFail("Declined cards don't succeed")
        } catch let error as TerminalError {
            guard case .declined = error else { return XCTFail("Expected declined, got \(error)") }
        }
        terminal.automaticOutcome = .customerCancels
        do {
            _ = try await terminal.collect(amountCents: 100, clientSecret: "secret_3")
            XCTFail("Cancelled")
        } catch let error as TerminalError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertEqual(approved, ["secret_1"])
        await terminal.disconnect()
        XCTAssertEqual(terminal.state, .idle)
    }

    func testTheSimulatedReaderWaitsForTheTestCardChoice() async throws {
        let terminal = SimulatedPaymentTerminal(stepDelay: .zero)
        let collect = Task { try await terminal.collect(amountCents: 4200, clientSecret: "s") }
        let shown = await eventually { terminal.pendingTap != nil }
        XCTAssertTrue(shown)
        XCTAssertEqual(terminal.pendingTap?.amountCents, 4200)
        XCTAssertEqual(terminal.state, .collecting)
        terminal.choose(.approve)
        let result = try await collect.value
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertNil(terminal.pendingTap)
        terminal.choose(.decline)
        XCTAssertEqual(terminal.state, .ready, "A stray choice with nothing pending does nothing")
    }

    func testCancellingTheTaskCancelsTheSimulatedTap() async {
        let terminal = SimulatedPaymentTerminal(stepDelay: .zero)
        let collect = Task { try await terminal.collect(amountCents: 4200, clientSecret: "s") }
        _ = await eventually { terminal.pendingTap != nil }
        collect.cancel()
        do {
            _ = try await collect.value
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertEqual(error as? TerminalError, .cancelled)
        }
    }

    func testTerminalStatesSayWhenTheyreBusy() {
        XCTAssertTrue(TerminalState.preparing(progress: 0.5).isBusy)
        XCTAssertTrue(TerminalState.collecting.isBusy)
        XCTAssertTrue(TerminalState.reconnecting.isBusy)
        XCTAssertFalse(TerminalState.ready.isBusy)
        XCTAssertFalse(TerminalState.unavailable(.notSupportedOnThisPhone).isBusy)
        XCTAssertEqual(TerminalError.cancelled.message, "The payment was cancelled. No card was charged.")
    }

    // MARK: Stripe's errors

    #if canImport(StripeTerminal)
    private func stripeError(_ code: Int) -> NSError {
        NSError(domain: StripeTapToPayTerminal.stripeErrorDomain, code: code)
    }

    /// Codes from Stripe Terminal 6.0.0's SCPErrors.h.
    func testStripeErrorsBecomePlainMessages() {
        XCTAssertEqual(StripeTapToPayTerminal.map(stripeError(2020)), .cancelled, "canceled")
        XCTAssertEqual(StripeTapToPayTerminal.map(stripeError(2021)), .cancelled, "canceledByReader: the customer backed out")
        guard case .declined = StripeTapToPayTerminal.map(stripeError(6000)) else { return XCTFail("declinedByStripeAPI") }
        guard case .declined = StripeTapToPayTerminal.map(stripeError(6500)) else { return XCTFail("declinedByReader") }
        guard case .unavailable(let entitlement) = StripeTapToPayTerminal.map(stripeError(2900)) else { return XCTFail("commandNotAllowed") }
        XCTAssertTrue(entitlement.message.contains("Apple"))
        XCTAssertFalse(entitlement.canRetry)
        guard case .unavailable(let passcode) = StripeTapToPayTerminal.map(stripeError(2920)) else { return XCTFail("passcodeNotEnabled") }
        XCTAssertTrue(passcode.message.contains("passcode"))
        guard case .unavailable(let location) = StripeTapToPayTerminal.map(stripeError(2200)) else { return XCTFail("locationServicesDisabled") }
        XCTAssertTrue(location.message.contains("Location"))
        guard case .unavailable(let terms) = StripeTapToPayTerminal.map(stripeError(2960)) else { return XCTFail("needs iCloud") }
        XCTAssertTrue(terms.message.contains("Apple Account"))
        guard case .failed(let background) = StripeTapToPayTerminal.map(stripeError(3900)) else { return XCTFail("background") }
        XCTAssertTrue(background.contains("No card was charged"))
        guard case .failed(let offline) = StripeTapToPayTerminal.map(stripeError(9000)) else { return XCTFail("offline") }
        XCTAssertTrue(offline.contains("internet"))
        guard case .failed(let token) = StripeTapToPayTerminal.map(stripeError(9050)) else { return XCTFail("token") }
        XCTAssertTrue(token.contains("server"))
        guard case .failed = StripeTapToPayTerminal.map(NSError(domain: "Other", code: 1)) else { return XCTFail("other domains") }
        XCTAssertEqual(StripeTapToPayTerminal.map(TerminalError.outcomeUnknown), .outcomeUnknown)
    }

    func testTheTokenProviderNeedsASignedInOwner() async {
        let provider = TerminalTokenProvider()
        let signedOut = await fetch(from: provider)
        XCTAssertNil(signedOut.0)
        XCTAssertNotNil(signedOut.1)

        provider.use { "pst_test_123" }
        let signedIn = await fetch(from: provider)
        XCTAssertEqual(signedIn.0, "pst_test_123")
        XCTAssertNil(signedIn.1)

        provider.use { throw APIError.notConfigured(APIError.Feature.stripe) }
        let failing = await fetch(from: provider)
        XCTAssertNil(failing.0)
        XCTAssertEqual(failing.1 as? APIError, .notConfigured(APIError.Feature.stripe))
        provider.use(nil)
    }

    private func fetch(from provider: TerminalTokenProvider) async -> (String?, Error?) {
        await withCheckedContinuation { continuation in
            provider.fetchConnectionToken { token, error in
                continuation.resume(returning: (token, error))
            }
        }
    }

    func testTheRealTerminalStartsIdleAndSaysItsReal() {
        let terminal = StripeTapToPayTerminal()
        XCTAssertFalse(terminal.isSimulated)
        XCTAssertEqual(terminal.state, .idle)
        XCTAssertEqual(StripeTapToPayTerminal.merchantDisplayName, "Izzy Clipz")
    }
    #endif
}
