import Security
import XCTest
@testable import IzzyClipz

/// The real Keychain, under a service name of its own so it can't touch the app's tokens.
final class KeychainSecretStoreTests: XCTestCase {
    private var store: KeychainSecretStore!

    override func setUp() {
        super.setUp()
        store = KeychainSecretStore(service: "com.izzyclipz.app.tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.removeSecret(for: "a")
        try? store.removeSecret(for: "b")
        super.tearDown()
    }

    func testSavesReadsReplacesAndRemoves() throws {
        XCTAssertNil(try store.secret(for: "a"))
        do {
            try store.setSecret("first", for: "a")
        } catch let failure as KeychainSecretStore.Failure where failure.status == errSecMissingEntitlement {
            // An unsigned simulator build (CI builds with CODE_SIGNING_ALLOWED=NO) may have no
            // Keychain at all; the app then keeps tokens for the launch and says so.
            throw XCTSkip("This build has no Keychain access (\(failure.status))")
        }
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
        do {
            try store.setSecret("mine", for: "a")
        } catch let failure as KeychainSecretStore.Failure where failure.status == errSecMissingEntitlement {
            throw XCTSkip("This build has no Keychain access (\(failure.status))")
        }
        let other = KeychainSecretStore(service: "com.izzyclipz.app.tests-other-\(UUID().uuidString)")
        XCTAssertNil(try other.secret(for: "a"))
    }
}
