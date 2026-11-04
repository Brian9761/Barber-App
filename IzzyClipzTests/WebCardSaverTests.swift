import AuthenticationServices
import XCTest
@testable import IzzyClipz

/// What Stripe's card page in `ASWebAuthenticationSession` means when it closes: the address the
/// shop's server sent the client back to, or why the sheet closed.
final class WebCardSaverTests: XCTestCase {
    private func result(_ address: String?, error: Error? = nil) -> IzzyAPI.CardCheckoutResult {
        WebCardSaver.result(callbackURL: address.flatMap(URL.init(string:)), error: error)
    }

    func testTheWayBackToTheApp() {
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=cs_test_a1B2c3"), .saved(sessionId: "cs_test_a1B2c3"))
        XCTAssertEqual(result("izzyclipz://card-cancelled"), .cancelled)
        XCTAssertEqual(result("izzyclipz://card-failed"), .failed)
    }

    /// Anything else didn't save a card: an address that isn't the app's, one without a session,
    /// or none at all.
    func testAnythingElseIsAFailure() {
        XCTAssertEqual(result("izzyclipz://card-saved"), .failed)
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=pi_123"), .failed)
        XCTAssertEqual(result("https://checkout.stripe.com/c/pay/cs_test_a1"), .failed)
        XCTAssertEqual(result("izzyclipz://somewhere-else"), .failed)
        XCTAssertEqual(result(nil), .failed)
    }

    /// The client closed the sheet: a cancel, not an error. Any other error is a failure.
    func testClosingTheSheetIsACancel() {
        XCTAssertEqual(result(nil, error: ASWebAuthenticationSessionError(.canceledLogin)), .cancelled)
        XCTAssertEqual(result(nil, error: ASWebAuthenticationSessionError(.presentationContextInvalid)), .failed)
        XCTAssertEqual(result(nil, error: URLError(.notConnectedToInternet)), .failed)
        // An error wins over an address.
        XCTAssertEqual(result("izzyclipz://card-saved?session_id=cs_test_a1", error: URLError(.cancelled)), .failed)
    }

    /// On the in-memory server (the UI tests and the demo version) a stand-in saves Stripe's test card
    /// without opening a page: Stripe's real page couldn't know the in-memory server's card checkout.
    /// Every build that talks to the shop's server opens Stripe's page.
    @MainActor
    func testOnlyTheInMemoryServerSkipsStripesPage() throws {
        let fake = FakeShopAPI()
        XCTAssertTrue(APIConfiguration.makeCardSaver(api: fake, demo: true, uiTesting: false) is FakeCardSaver, "The demo never opens Stripe's page")
        XCTAssertTrue(APIConfiguration.makeCardSaver(api: fake, demo: false, uiTesting: true) is FakeCardSaver)
        let server = IzzyAPIClient(baseURL: try XCTUnwrap(URL(string: "https://example.com")))
        XCTAssertTrue(APIConfiguration.makeCardSaver(api: server, demo: false, uiTesting: false) is WebCardSaver)
        XCTAssertTrue(APIConfiguration.makeCardSaver(api: server, demo: true, uiTesting: false) is WebCardSaver, "Only the in-memory server has a stand-in")
    }
}
