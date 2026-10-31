import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Signing in with the owner key: checked with the server, kept in the
/// (here in-memory) keychain, and cleared errors for each way it can fail.
@MainActor
final class SessionTests: XCTestCase {
    private func makeModel(options: FakeServer.Options = .init(), savedKey: String? = nil) -> (AppModel, InMemorySecretStore, FakeServer) {
        let shopTime = TestClock.shopTime
        let server = FakeServer(options: options, shopTime: shopTime, now: { TestClock.now })
        let secrets = InMemorySecretStore(secret: savedKey)
        let terminal = SimulatedPaymentTerminal(stepDelay: .zero)
        let environment = AppEnvironment(
            backend: .sample(server), secrets: secrets, shopTime: shopTime, clock: { TestClock.now },
            defaults: makeDefaults(), terminal: terminal, practiceTerminal: SimulatedPaymentTerminal(stepDelay: .zero),
            deviceSupportsTapToPay: true, canShowAppleEducation: false
        )
        return (AppModel(environment: environment), secrets, server)
    }

    func testTheRightKeySignsInAndIsKept() async throws {
        let (model, secrets, server) = makeModel()
        await model.start()
        guard case .signedOut = model.phase else { return XCTFail("Expected the sign-in screen") }

        await model.signIn(key: "  \(FakeServer.ownerKey)\n")
        let workspace = try XCTUnwrap(model.workspace)
        XCTAssertEqual(workspace.ownerKey, FakeServer.ownerKey, "Pasted spaces and line breaks are dropped")
        XCTAssertEqual(try secrets.read(), FakeServer.ownerKey)
        XCTAssertNil(model.signInError)
        XCTAssertEqual(workspace.ownerStatus?.stripe.configured, true)
        XCTAssertEqual(workspace.checkout.mode, .sampleServer(locationId: "tml_sample_location"))
        XCTAssertEqual(server.calls.first, "ownerStatus", "The key is checked with GET /api/owner/me")
    }

    func testAWrongKeyIsTurnedDownAndNotKept() async throws {
        let (model, secrets, _) = makeModel()
        await model.start()
        await model.signIn(key: String(repeating: "x", count: 40))
        guard case .signedOut = model.phase else { return XCTFail("A wrong key signed in") }
        XCTAssertNil(try secrets.read())
        XCTAssertEqual(model.signInError, AppModel.signInMessage(for: APIError.unauthorized))
        XCTAssertTrue(model.signInError?.contains("isn't right") == true)
    }

    func testAnEmptyOrShortKeyIsExplainedWithoutAskingTheServer() async {
        let (model, _, server) = makeModel()
        await model.start()
        await model.signIn(key: "   ")
        XCTAssertEqual(model.signInError, "Paste the owner key to sign in.")
        await model.signIn(key: "short-key")
        XCTAssertTrue(model.signInError?.contains("too short") == true)
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testAnUnreachableServerSaysSo() async {
        let (model, _, _) = makeModel(options: { var o = FakeServer.Options(); o.offline = true; return o }())
        await model.start()
        await model.signIn(key: FakeServer.ownerKey)
        XCTAssertEqual(model.signInError, "We couldn't reach the server. Check your internet connection and try again.")
        XCTAssertNil(model.workspace)
    }

    func testAServerWithoutAnOwnerKeySaysWhatToSet() async {
        let (model, _, _) = makeModel(options: { var o = FakeServer.Options(); o.ownerNotConfigured = true; return o }())
        await model.start()
        await model.signIn(key: FakeServer.ownerKey)
        XCTAssertTrue(model.signInError?.contains("OWNER_KEY") == true)
        XCTAssertNil(model.workspace)
    }

    func testAKeychainThatRefusesDoesntStopTheOwner() async throws {
        let (model, _, _) = makeModel()
        await model.start()
        let failing = RefusingSecretStore()
        let environment = model.environment
        let refusing = AppModel(environment: AppEnvironment(
            backend: environment.backend, secrets: failing, shopTime: environment.shopTime, clock: environment.clock,
            defaults: environment.defaults, terminal: environment.terminal, practiceTerminal: environment.practiceTerminal,
            deviceSupportsTapToPay: true, canShowAppleEducation: false
        ))
        await refusing.start()
        await refusing.signIn(key: FakeServer.ownerKey)
        let workspace = try XCTUnwrap(refusing.workspace, "Signed in anyway")
        XCTAssertTrue(workspace.keySaveError?.contains("paste it again next time") == true)
    }

    func testOtherErrorsHavePlainMessages() {
        XCTAssertTrue(AppModel.signInMessage(for: APIError.server(code: "server_error", message: "", status: 500)).contains("isn't answering"))
        XCTAssertTrue(AppModel.signInMessage(for: APIError.decoding("x")).contains("up to date"))
        XCTAssertTrue(AppModel.signInMessage(for: APIError.notConfigured(APIError.Feature.server)).contains("server address"))
        XCTAssertEqual(AppModel.signInMessage(for: KeychainError(status: -34018)), KeychainError(status: -34018).errorDescription)
    }

    func testASavedKeyOpensStraightAwayAndIsCheckedInTheBackground() async {
        let (model, _, server) = makeModel(savedKey: FakeServer.ownerKey)
        await model.start()
        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(server.calls.first, "ownerStatus")
        XCTAssertEqual(model.workspace?.ownerStatus?.stripe.mode, .test)
    }

    func testASavedKeyTheServerNoLongerAcceptsSignsOut() async throws {
        let (model, secrets, _) = makeModel(savedKey: String(repeating: "old", count: 12))
        await model.start()
        guard case .signedOut = model.phase else { return XCTFail("Expected to be signed out") }
        XCTAssertNil(try secrets.read(), "The rejected key is removed")
        XCTAssertTrue(model.notice?.contains("changed on the server") == true)
    }

    func testASavedKeyStaysWhenOffline() async {
        let (model, _, server) = makeModel(savedKey: FakeServer.ownerKey)
        server.options.offline = true
        await model.start()
        let workspace = model.workspace
        XCTAssertNotNil(workspace, "Offline isn't a reason to sign out")
        XCTAssertEqual(workspace?.statusError, "We couldn't reach the server. Check your internet connection and try again.")
        XCTAssertEqual(workspace?.checkout.mode, .checking)
    }

    func testSignOutForgetsTheKeyAndTheWorkspace() async throws {
        let (model, secrets, _) = makeModel(savedKey: FakeServer.ownerKey)
        await model.start()
        await model.signOut()
        guard case .signedOut = model.phase else { return XCTFail("Still signed in") }
        XCTAssertNil(try secrets.read())
        XCTAssertNil(model.notice)
    }

    func testReplacingTheKeyChecksTheNewOneFirst() async throws {
        let (model, secrets, _) = makeModel(savedKey: FakeServer.ownerKey)
        await model.start()
        let before = try XCTUnwrap(model.workspace)
        let error = await model.replaceKey(with: String(repeating: "y", count: 40))
        XCTAssertNotNil(error)
        XCTAssertTrue(model.workspace === before, "A bad new key leaves things as they were")
        XCTAssertEqual(try secrets.read(), FakeServer.ownerKey)

        let ok = await model.replaceKey(with: FakeServer.ownerKey)
        XCTAssertNil(ok)
        XCTAssertFalse(model.workspace === before, "A new workspace for the new key")
    }

    func testBackInTheForegroundRechecksTheKey() async {
        let (model, _, server) = makeModel(savedKey: FakeServer.ownerKey)
        await model.start()
        server.options.ownerNotConfigured = false
        await model.becameActive()
        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(server.calls.filter { $0 == "ownerStatus" }.count, 2)
    }

    // MARK: Keychain

    /// A keychain that refuses everything (a locked or broken one).
    @MainActor
    final class RefusingSecretStore: SecretStore {
        func read() throws -> String? { nil }
        func save(_ secret: String) throws { throw KeychainError(status: -25308) }
        func delete() throws {}
    }

    func testKeychainStoreSavesReadsReplacesAndDeletes() throws {
        let store = KeychainSecretStore(service: "com.izzyclipz.business.tests", account: UUID().uuidString)
        do {
            try store.save("first-key")
        } catch let error as KeychainError where error.status == errSecMissingEntitlement {
            throw XCTSkip("This test host has no keychain access (unsigned simulator build).")
        }
        XCTAssertEqual(try store.read(), "first-key")
        try store.save("second-key")
        XCTAssertEqual(try store.read(), "second-key", "Saving again replaces, not duplicates")
        try store.delete()
        XCTAssertNil(try store.read())
        XCTAssertNoThrow(try store.delete(), "Deleting nothing is fine")
    }

    func testInMemoryStore() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.read())
        try store.save("k")
        XCTAssertEqual(try store.read(), "k")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    // MARK: Launch

    func testLaunchArgumentsConfigureTheSampleServer() {
        let environment = AppEnvironment.sample(arguments: [
            LaunchArgument.signedIn, LaunchArgument.stripeNotConfigured, LaunchArgument.paymentIncomplete,
        ])
        XCTAssertTrue(environment.usesSampleServer)
        XCTAssertTrue(environment.startsSignedIn)
        XCTAssertEqual(try environment.secrets.read(), FakeServer.ownerKey)
        guard case .sample(let server) = environment.backend else { return XCTFail("Not the sample server") }
        XCTAssertFalse(server.options.stripeConfigured)
        XCTAssertEqual(server.options.completeStatusOverride, "requires_payment_method")
        XCTAssertFalse(environment.canShowAppleEducation)
        XCTAssertEqual(environment.clock(), AppEnvironment.uiTestNow(shopTime: environment.shopTime))
    }

    func testTheBaseURLComesFromInfoPlist() {
        XCTAssertEqual(AppEnvironment.baseURL().scheme, "https")
        XCTAssertEqual(AppEnvironment.baseURL(bundle: Bundle(for: SessionTests.self)).absoluteString, "https://izzy-clipz-api.vercel.app")
    }
}
