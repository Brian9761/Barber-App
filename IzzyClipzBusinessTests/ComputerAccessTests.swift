import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Settings → Use on a computer: the code and its countdown, a new code replacing the old one,
/// and the computers signed in, one or all of which can be signed out.
@MainActor
final class ComputerAccessTests: XCTestCase {
    private func makeStore(_ harness: Harness? = nil, clock: MovableClock? = nil) -> ComputerAccessStore {
        let harness = harness ?? Harness()
        let clock = clock ?? MovableClock(TestClock.now)
        return ComputerAccessStore(api: harness.api, siteAddress: "izzy-clipz-api.vercel.app/business", shopTime: TestClock.shopTime, clock: { clock.now })
    }

    // MARK: The code

    func testTheCodeShowsGroupedAndCountsDownFromWhenItArrived() async {
        let clock = MovableClock(TestClock.now)
        let store = makeStore(clock: clock)
        XCTAssertNil(store.countdownText(at: clock.now))
        await store.showCodeIfNeeded()
        XCTAssertEqual(store.code?.code, "483920")
        XCTAssertEqual(store.code?.grouped, "483 920")
        XCTAssertEqual(store.spokenCode, "4 8 3, 9 2 0")
        XCTAssertEqual(store.countdownText(at: clock.now), "Expires in 10:00")
        XCTAssertEqual(store.countdownText(at: clock.now.addingTimeInterval(18)), "Expires in 9:42")
        XCTAssertEqual(store.countdownText(at: clock.now.addingTimeInterval(594.5)), "Expires in 0:06")
        XCTAssertFalse(store.codeHasRunOut(at: clock.now.addingTimeInterval(599)))
        XCTAssertTrue(store.codeHasRunOut(at: clock.now.addingTimeInterval(600)))
        XCTAssertEqual(store.countdownText(at: clock.now.addingTimeInterval(601)), "This code has run out. Get a new code.")
    }

    func testOpeningAgainKeepsACodeThatStillWorksAndReplacesOneThatRanOut() async {
        let harness = Harness()
        let clock = MovableClock(TestClock.now)
        let store = makeStore(harness, clock: clock)
        await store.showCodeIfNeeded()
        clock.now = clock.now.addingTimeInterval(120)
        await store.showCodeIfNeeded()
        XCTAssertEqual(store.code?.code, "483920", "Still good: the same code")
        XCTAssertEqual(harness.server.calls.filter { $0 == "createComputerCode" }.count, 1)

        clock.now = clock.now.addingTimeInterval(600)
        await store.showCodeIfNeeded()
        XCTAssertEqual(store.code?.code, "271846", "It ran out: a new one")
        XCTAssertEqual(store.countdownText(at: clock.now), "Expires in 10:00")
    }

    func testGetANewCodeReplacesTheOneBefore() async {
        let harness = Harness()
        let store = makeStore(harness)
        await store.makeCode()
        await store.makeCode()
        XCTAssertEqual(store.code?.code, "271846")
        XCTAssertEqual(harness.server.computerCode?.code, "271846", "Only the newest code works")
    }

    func testACodeThatDoesntComeSaysWhy() async {
        var options = FakeServer.Options()
        options.offline = true
        let store = makeStore(Harness(options: options))
        await store.makeCode()
        XCTAssertNil(store.code)
        XCTAssertEqual(store.codeError, "We couldn't reach the server. Check your internet connection and try again.")
        XCTAssertFalse(store.isMakingCode)
    }

    // MARK: Computers signed in

    func testTheComputersSignedInMostRecentlyUsedFirst() async {
        let store = makeStore()
        await store.refreshSessions()
        XCTAssertEqual(store.sessions.map(\.name), ["Chrome on Mac", "Safari on iPad"])
        XCTAssertEqual(store.summary, "2 computers signed in")
        XCTAssertEqual(store.lastUsedText(for: store.sessions[0]), "Last used today at 10:45 AM")
        XCTAssertEqual(store.lastUsedText(for: store.sessions[1]), "Last used yesterday at 11:05 AM")
    }

    func testSignOutOneComputerThenAll() async throws {
        let harness = Harness()
        let store = makeStore(harness)
        await store.refreshSessions()
        let mac = try XCTUnwrap(store.sessions.first)
        await store.signOut(mac)
        XCTAssertEqual(store.sessions.map(\.name), ["Safari on iPad"])
        XCTAssertEqual(store.summary, "1 computer signed in")
        XCTAssertFalse(harness.server.signedInComputers().contains { $0.id == mac.id })

        await store.signOutAll()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.summary, "No computers signed in")
        XCTAssertTrue(harness.server.signedInComputers().isEmpty)
        XCTAssertNil(store.actionError)
    }

    func testAComputerAlreadySignedOutJustGoes() async throws {
        let harness = Harness()
        let store = makeStore(harness)
        await store.refreshSessions()
        let mac = try XCTUnwrap(store.sessions.first)
        harness.server.signOutAllComputers()
        await store.signOut(mac)
        XCTAssertFalse(store.sessions.contains { $0.id == mac.id })
        XCTAssertNil(store.actionError, "A 404 means it's signed out already")
    }

    func testComputersThatDontLoadOfferToTryAgain() async {
        var options = FakeServer.Options()
        options.offline = true
        let harness = Harness(options: options)
        let store = makeStore(harness)
        await store.refreshSessions()
        XCTAssertEqual(store.sessionsState, .failed("We couldn't reach the server. Check your internet connection and try again."))
        XCTAssertNil(store.summary)
        harness.server.options.offline = false
        await store.refreshSessions()
        XCTAssertEqual(store.sessionsState, .loaded)
    }

    // MARK: Where the Business area is

    func testTheBusinessAreaIsOnTheServersOwnSite() {
        let shopTime = TestClock.shopTime
        let live = AppEnvironment(
            backend: .live(baseURL: URL(string: "https://izzy-clipz-api.vercel.app")!),
            secrets: InMemorySecretStore(), shopTime: shopTime, clock: { TestClock.now }, defaults: makeDefaults(),
            terminal: SimulatedPaymentTerminal(stepDelay: .zero), practiceTerminal: SimulatedPaymentTerminal(stepDelay: .zero),
            deviceSupportsTapToPay: true, canShowAppleEducation: false
        )
        XCTAssertEqual(live.businessSiteAddress, "izzy-clipz-api.vercel.app/business", "The same address as the API, where the codes work")
        let sample = AppEnvironment.sample()
        XCTAssertEqual(sample.businessSiteAddress, "\(sample.websiteURL.host() ?? "")/business", "The demo website, without a code")
    }
}
