import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Settings → Card payments (Stripe): what each status shows, Connect Stripe through Stripe's
/// window (the sample server's stand-in), the line that says what happened, Disconnect, and
/// Take payment reading the same status.
@MainActor
final class StripeConnectionTests: XCTestCase {
    private func harness(_ account: FakeServer.StripeAccount) -> Harness {
        var options = FakeServer.Options()
        options.stripeAccount = account
        return Harness(options: options)
    }

    // MARK: What Settings shows

    func testEachStatusReadsAsSettingsSaysIt() {
        let expected: [(IzzyAPI.StripeConnection.Status, String, String?)] = [
            (.active, "Connected", nil),
            (.notConnected, "Not connected", "Connect Stripe"),
            (.needsInfo, "Finish setting up", "Finish setting up"),
            (.pending, "Stripe is checking your details", nil),
            (.restricted, "Paused by Stripe", "Finish setting up"),
            (.direct, "Uses the server's Stripe key", nil),
            (.off, "Not set up on the server", nil),
        ]
        for (status, title, button) in expected {
            let mode: IzzyAPI.StripeConnection.Mode = status == .direct ? .direct : status == .off ? .off : .connect
            let display = StripeStatusDisplay(connection: IzzyAPI.StripeConnection(mode: mode, status: status))
            XCTAssertEqual(display.title, title, "\(status)")
            XCTAssertEqual(display.buttonTitle, button, "\(status)")
        }
    }

    func testConnectedShowsTheGreenCheckTheNameAndWhatStripeSays() {
        let connection = IzzyAPI.StripeConnection(
            mode: .connect, status: .active, accountId: "acct_1", businessName: "  Izzy Clipz Barbershop ",
            chargesEnabled: true, payoutsEnabled: false, detailsSubmitted: true
        )
        let display = StripeStatusDisplay(connection: connection)
        XCTAssertEqual(display.symbol, "checkmark.circle.fill")
        XCTAssertEqual(display.tone, .good)
        XCTAssertEqual(display.businessName, "Izzy Clipz Barbershop")
        XCTAssertEqual(display.message, "Connected. Card payments are on. Add your bank in Stripe to get paid out.")
        XCTAssertTrue(display.showsDashboard)
        XCTAssertTrue(display.canDisconnect)
        XCTAssertEqual(display.spoken, "Card payments, Connected, Izzy Clipz Barbershop")
    }

    func testOnlyAConnectedAccountCanBeDisconnected() {
        let notConnected = StripeStatusDisplay(connection: IzzyAPI.StripeConnection(mode: .connect, status: .notConnected))
        XCTAssertFalse(notConnected.canDisconnect)
        XCTAssertFalse(notConnected.showsDashboard)
        let direct = StripeStatusDisplay(connection: IzzyAPI.StripeConnection(mode: .direct, status: .direct))
        XCTAssertFalse(direct.canDisconnect, "The server's own key has nothing to disconnect")
        XCTAssertTrue(direct.showsDashboard)
        let needsInfo = StripeStatusDisplay(connection: IzzyAPI.StripeConnection(mode: .connect, status: .needsInfo, accountId: "acct_1"))
        XCTAssertTrue(needsInfo.canDisconnect)
    }

    // MARK: Connecting

    func testConnectStripeComesBackConnected() async {
        let harness = harness(.none)
        let connector = FakeStripeConnector(server: harness.server)
        let store = StripeConnectionStore(api: harness.api, connector: connector)
        var changes = 0
        store.onChange = { changes += 1 }
        await store.refresh()
        XCTAssertEqual(store.connection?.status, .notConnected)
        XCTAssertEqual(store.display?.buttonTitle, "Connect Stripe")

        await store.connect()
        XCTAssertEqual(connector.windowsOpened, 1)
        XCTAssertEqual(store.connection?.status, .active)
        XCTAssertEqual(store.result, StripeConnectionStore.Result(message: "You're connected. You can take card payments now.", isGoodNews: true))
        XCTAssertNil(store.actionError)
        XCTAssertEqual(changes, 1, "Take payment reads the new status")
        XCTAssertEqual(harness.server.calls.filter { $0 != "stripeConnection" }, ["connectStripe"], "One link, then the status again")
        XCTAssertTrue(harness.server.ownerStatus().stripe.configured, "Card payments work now")
    }

    func testDetailsLeftMissingSayToFinishSettingUp() async {
        let harness = harness(.none)
        let store = StripeConnectionStore(api: harness.api, connector: FakeStripeConnector(server: harness.server, firstTry: .leavesDetailsMissing))
        await store.refresh()
        await store.connect()
        XCTAssertEqual(store.connection?.status, .needsInfo)
        XCTAssertEqual(store.result?.message, "Stripe still needs a few details: tap Finish setting up.")
        XCTAssertEqual(store.result?.isGoodNews, false)
        XCTAssertEqual(store.display?.buttonTitle, "Finish setting up")

        // Finish setting up: the next window finishes.
        await store.connect()
        XCTAssertEqual(store.connection?.status, .active)
        XCTAssertEqual(store.result?.isGoodNews, true)
    }

    func testClosingStripesWindowShowsNoResult() async {
        let harness = harness(.none)
        let store = StripeConnectionStore(api: harness.api, connector: FakeStripeConnector(server: harness.server, firstTry: .closesTheWindow))
        var changes = 0
        store.onChange = { changes += 1 }
        await store.refresh()
        await store.connect()
        XCTAssertNil(store.result, "Closing the window isn't a result")
        XCTAssertNil(store.actionError, "…or an error")
        XCTAssertFalse(store.isConnecting)
        // The server started the shop's account before the window opened: it says so from now on.
        XCTAssertEqual(store.connection?.status, .needsInfo)
        XCTAssertEqual(changes, 1)
    }

    func testTheServersAnswerWinsOverTheWayBack() async {
        // Stripe sent the owner back saying "active", but the server (asking Stripe again) still
        // says Stripe is checking: Settings says what the server says.
        let harness = harness(.none)
        let store = StripeConnectionStore(api: harness.api, connector: ScriptedStripeWindow(wayBack: "izzyclipzbusiness://stripe-connected?status=active"))
        await store.connect()
        XCTAssertEqual(store.connection?.status, .needsInfo)
        XCTAssertEqual(store.result?.message, "Stripe still needs a few details: tap Finish setting up.")
    }

    func testConnectingOfflineSaysToCheckTheConnection() async {
        let harness = harness(.none)
        let store = StripeConnectionStore(api: harness.api, connector: FakeStripeConnector(server: harness.server))
        await store.refresh()
        harness.server.options.offline = true
        await store.connect()
        XCTAssertEqual(store.actionError, "We couldn't reach the server. Check your internet connection and try again.")
        XCTAssertEqual(store.connection?.status, .notConnected, "What was on screen stays")
    }

    func testAWindowThatDoesntOpenSaysToTryAgain() async {
        let harness = harness(.none)
        let store = StripeConnectionStore(api: harness.api, connector: UnavailableStripeConnector())
        await store.connect()
        XCTAssertEqual(store.actionError, "Stripe's window didn't open. Try again in a moment.")
    }

    func testDisconnectForgetsTheAccountAndSaysItStaysOpenAtStripe() async {
        let harness = harness(.active)
        let store = StripeConnectionStore(api: harness.api, connector: FakeStripeConnector(server: harness.server))
        var changes = 0
        store.onChange = { changes += 1 }
        await store.refresh()
        XCTAssertEqual(store.connection?.status, .active)
        await store.disconnect()
        XCTAssertEqual(store.connection?.status, .notConnected)
        XCTAssertEqual(store.result?.message, IzzyAPI.StripeConnection.disconnectedMessage)
        XCTAssertTrue(store.result?.message.contains("Your Stripe account isn't closed") == true)
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(harness.server.ownerStatus().stripe.configured, "Card payments stop")
        XCTAssertTrue(StripeConnectionStore.disconnectExplanation.contains("Card payments stop until you connect Stripe again."))
        XCTAssertTrue(StripeConnectionStore.disconnectExplanation.contains("cards clients saved stay with it"))
    }

    func testAServerFromBeforeStripeConnectShowsWhatItHad() async {
        // ScriptedAPI doesn't pass `stripeConnection()` on: it answers 404, like an older server.
        let harness = Harness()
        let store = StripeConnectionStore(api: ScriptedAPI(base: harness.api), connector: FakeStripeConnector(server: harness.server))
        await store.refresh()
        XCTAssertEqual(store.loadState, .notOnThisServer)
        XCTAssertNil(store.display)
    }

    func testWithoutStripeOnTheServerThereIsNothingToConnect() async {
        var options = FakeServer.Options()
        options.stripeConfigured = false
        let harness = Harness(options: options)
        let store = StripeConnectionStore(api: harness.api, connector: FakeStripeConnector(server: harness.server))
        await store.refresh()
        XCTAssertEqual(store.connection?.mode, .off)
        XCTAssertEqual(store.display?.title, "Not set up on the server")
        XCTAssertNil(store.display?.buttonTitle)
    }

    // MARK: Take payment reads the same status

    func testTakePaymentSaysToConnectStripeAndOffersSettings() {
        let checkout = CheckoutModel(
            api: Harness().api, shopTime: TestClock.shopTime, clock: { TestClock.now },
            terminal: SimulatedPaymentTerminal(stepDelay: .zero), practiceTerminal: SimulatedPaymentTerminal(stepDelay: .zero),
            pending: PendingPayments(defaults: makeDefaults()), usesSampleServer: true, deviceSupportsTapToPay: true
        )
        checkout.update(stripe: IzzyAPI.StripeStatus(configured: false), connection: IzzyAPI.StripeConnectionSummary(mode: .connect, status: .notConnected))
        guard case .unavailable(let issue) = checkout.mode else { return XCTFail("Got \(checkout.mode)") }
        XCTAssertEqual(issue.title, "Connect Stripe to take cards")
        XCTAssertTrue(issue.fixInSettings)
        XCTAssertTrue(issue.message.contains("record cash and other payments"), issue.message)

        checkout.update(stripe: IzzyAPI.StripeStatus(configured: false), connection: IzzyAPI.StripeConnectionSummary(mode: .connect, status: .needsInfo))
        XCTAssertEqual(checkout.mode, .unavailable(.stripeNotConnected(.needsInfo)))
        XCTAssertEqual(TerminalIssue.stripeNotConnected(.needsInfo).title, "Finish setting up Stripe")
        XCTAssertEqual(TerminalIssue.stripeNotConnected(.pending).title, "Stripe is checking your details")
        XCTAssertEqual(TerminalIssue.stripeNotConnected(.restricted).title, "Stripe paused card payments")

        // The server's own key, not set up: the old message, about the server's settings.
        checkout.update(stripe: IzzyAPI.StripeStatus(configured: false), connection: IzzyAPI.StripeConnectionSummary(mode: .off, status: .off))
        XCTAssertEqual(checkout.mode, .unavailable(.stripeNotConfigured))
        checkout.update(stripe: IzzyAPI.StripeStatus(configured: false))
        XCTAssertEqual(checkout.mode, .unavailable(.stripeNotConfigured))
        XCTAssertFalse(TerminalIssue.stripeNotConfigured.fixInSettings)
    }

    func testConnectingInSettingsTurnsOnCardPaymentsOnTakePayment() async throws {
        let environment = AppEnvironment.sample(arguments: [LaunchArgument.signedIn, LaunchArgument.stripeNotConnected], stepDelay: .zero)
        let model = AppModel(environment: environment)
        await model.start()
        let workspace = try XCTUnwrap(model.workspace)
        XCTAssertEqual(workspace.checkout.mode, .unavailable(.stripeNotConnected(.notConnected)))

        await workspace.stripeConnection.connect()
        let on = await eventually { workspace.checkout.mode == .sampleServer(locationId: "tml_sample_location") }
        XCTAssertTrue(on, "Got \(workspace.checkout.mode)")
        XCTAssertEqual(workspace.ownerStatus?.connection?.status, .active)
    }

    func testTheLaunchArgumentsPickWhatStripesWindowDoes() {
        func firstTry(_ arguments: Set<String>) -> FakeStripeConnector.FirstTry {
            AppEnvironment.sample(arguments: arguments).stripeFirstTry
        }
        func account(_ arguments: Set<String>) -> FakeServer.StripeAccount? {
            guard case .sample(let server) = AppEnvironment.sample(arguments: arguments).backend else { return nil }
            return server.options.stripeAccount
        }
        XCTAssertEqual(firstTry([]), .finishes)
        XCTAssertEqual(account([]), .active, "Connected, as before: card payments work in every other UI test")
        XCTAssertEqual(account([LaunchArgument.stripeNotConnected]), FakeServer.StripeAccount.none)
        XCTAssertEqual(firstTry([LaunchArgument.stripeNeedsInfo]), .leavesDetailsMissing)
        XCTAssertEqual(account([LaunchArgument.stripeNeedsInfo]), FakeServer.StripeAccount.none)
        XCTAssertEqual(firstTry([LaunchArgument.stripeCancel]), .closesTheWindow)
        XCTAssertEqual(account([LaunchArgument.stripeCancel]), FakeServer.StripeAccount.none)
    }
}

/// Stripe's window, coming back with a given address.
@MainActor
private final class ScriptedStripeWindow: StripeConnector {
    let wayBack: String

    init(wayBack: String) {
        self.wayBack = wayBack
    }

    func connect(using link: IzzyAPI.StripeConnectLink) async throws -> URL? {
        URL(string: wayBack)
    }
}
