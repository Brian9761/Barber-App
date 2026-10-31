import XCTest
@testable import IzzyClipzKit

final class APIErrorTests: XCTestCase {
    let everyCase: [APIError] = [
        .offline,
        .server(code: "invalid_request", message: "", status: 400),
        .server(code: "not_found", message: "", status: 404),
        .server(code: "server_error", message: "", status: 500),
        .server(code: "network_error", message: "", status: 0),
        .server(code: "brand_new", message: "", status: 418),
        .slotTaken,
        .notCancellable,
        .rateLimited,
        .unauthorized,
        .notConfigured("stripe"),
        .notConfigured("owner"),
        .notConfigured("server"),
        .outsideHours,
        .tooSoon,
        .tooFar,
        .decoding("response.version is missing"),
    ]

    func testEveryCaseHasAPlainFriendlyMessage() {
        var seen: Set<String> = []
        for error in everyCase {
            let message = error.userMessage
            XCTAssertFalse(message.isEmpty, "\(error)")
            XCTAssertTrue(message.first?.isUppercase == true, message)
            XCTAssertTrue(message.hasSuffix("."), message)
            XCTAssertLessThanOrEqual(message.count, 120, message)
            XCTAssertFalse(message.contains("!"), message)
            // Sentence case: no shouted words ("ERROR", "OK"); "I" alone is fine.
            let shouted = message.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 1 && $0.allSatisfy(\.isUppercase) }
            XCTAssertEqual(shouted, [], message)
            // No technical leftovers.
            for word in ["null", "nil", "HTTP", "JSON", "decod", "_"] {
                XCTAssertFalse(message.contains(word), "\(message) contains \(word)")
            }
            XCTAssertEqual(error.errorDescription, message)
            XCTAssertEqual((error as Error).localizedDescription, message)
            seen.insert(message)
        }
        // The specific cases each say something specific.
        XCTAssertEqual(seen.count, everyCase.count - 1, "only the two generic server errors share a message")
    }

    func testTheServersMessageIsShownWhenItSendsOne() {
        let error = APIError.server(code: "invalid_request", message: "  Enter a US mobile number. ", status: 400)
        XCTAssertEqual(error.userMessage, "Enter a US mobile number.")
        XCTAssertEqual(APIError.server(code: "invalid_request", message: " \n", status: 400).userMessage,
                       APIError.server(code: "invalid_request", message: "", status: 400).userMessage)
    }

    func testCodesRoundTrip() {
        for error in everyCase {
            guard let code = error.code else { continue }
            XCTAssertEqual(APIError(code: code, message: "", status: 0).code, code)
            if case .server = error { continue }
            XCTAssertEqual(APIError(code: code, message: "ignored", status: 409), error, code)
        }
        XCTAssertNil(APIError.offline.code)
        XCTAssertNil(APIError.decoding("x").code)
        XCTAssertNil(APIError.notConfigured("server").code)
        XCTAssertEqual(APIError.slotTaken.code, IzzyAPI.ErrorCode.slotTaken)
        XCTAssertEqual(APIError.notConfigured(APIError.Feature.stripe).code, "stripe_not_configured")
    }

    func testRetryable() {
        XCTAssertTrue(APIError.offline.isRetryable)
        XCTAssertTrue(APIError.rateLimited.isRetryable)
        XCTAssertTrue(APIError.server(code: "server_error", message: "", status: 503).isRetryable)
        XCTAssertTrue(APIError.server(code: "network_error", message: "", status: 0).isRetryable)
        XCTAssertFalse(APIError.server(code: "invalid_request", message: "", status: 400).isRetryable)
        XCTAssertFalse(APIError.slotTaken.isRetryable)
        XCTAssertFalse(APIError.unauthorized.isRetryable)
        XCTAssertFalse(APIError.decoding("x").isRetryable)
    }
}
