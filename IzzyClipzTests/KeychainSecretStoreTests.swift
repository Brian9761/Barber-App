import Security
import XCTest
@testable import IzzyClipz

/// The real Keychain, under a service name of its own so it can't touch the app's tokens.
final class KeychainSecretStoreTests: XCTestCase {
    private var store: KeychainSecretStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainSecretStore(service: "com.izzyclipz.app.tests-\(UUID().uuidString)")
        // An unsigned simulator build (CI builds with CODE_SIGNING_ALLOWED=NO) may have no Keychain
        // at all: reading fails too, not just saving. The app then keeps tokens for the launch and
        // says so; there's nothing here to test.
        do {
            _ = try store.secret(for: "probe")
            try store.setSecret("probe", for: "probe")
            try store.removeSecret(for: "probe")
        } catch let failure as KeychainSecretStore.Failure where failure.status == errSecMissingEntitlement {
            throw XCTSkip("This build has no Keychain access (\(failure.status))")
        }
    }

    override func tearDown() {
        try? store.removeSecret(for: "a")
        try? store.removeSecret(for: "b")
        super.tearDown()
    }

    func testSavesReadsReplacesAndRemoves() throws {
        XCTAssertNil(try store.secret(for: "a"))
        try store.setSecret("first", for: "a")
        XCTAssertEqual(try store.secret(for: "a"), "first")
        try store.setSecret("second", for: "a")
        XCTAssertEqual(try store.secret(for: "a"), "second", "Saving again replaces it")
        try store.setSecret("other", for: "b")
        XCTAssertEqual(try store.secret(for: "a"), "second")
        try store.removeSecret(for: "a")
        XCTAssertNil(try store.secret(for: "a"))
        XCTAssertEqual(try store.secret(for: "b"), "other")
        // Removing one that isn't there is fine.
        XCTAssertNoThrow(try store.removeSecret(for: "a"))
    }

    func testServicesAreSeparate() throws {
        try store.setSecret("mine", for: "a")
        let other = KeychainSecretStore(service: "com.izzyclipz.app.tests-other-\(UUID().uuidString)")
        XCTAssertNil(try other.secret(for: "a"))
    }
}
