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
        .rateLimited(message: ""),
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

    /// The server has two limits, and only its message says which one was hit and what helps:
    /// waiting an hour (too many tries from one network) or cancelling an appointment (a number
    /// with 3 upcoming ones, where waiting never helps).
    func testRateLimitedShowsTheServersMessage() {
        let phoneLimit = "This number already has 3 upcoming appointments. Cancel one, or call the shop to book more."
        let envelope = Data(#"{"error":{"code":"rate_limited","message":"\#(phoneLimit)"}}"#.utf8)
        let error = APIError.fromResponse(status: 429, body: envelope)
        XCTAssertEqual(error, .rateLimited(message: phoneLimit))
        XCTAssertEqual(error.userMessage, phoneLimit)
        XCTAssertEqual(error.code, IzzyAPI.ErrorCode.rateLimited)
        XCTAssertEqual(APIError.rateLimited(message: " Try again in an hour, or call the shop. \n").userMessage,
                       "Try again in an hour, or call the shop.")
        // Without a message (a bare 429 from the platform): the general advice.
        let generic = "That's a lot of tries in a short time. Wait a little and try again, or call the shop."
        XCTAssertEqual(APIError.fromResponse(status: 429, body: Data()), .rateLimited(message: ""))
        XCTAssertEqual(APIError.fromResponse(status: 429, body: Data()).userMessage, generic)
        XCTAssertEqual(APIError.rateLimited(message: " \n").userMessage, generic)
    }

    func testCodesRoundTrip() {
        for error in everyCase {
            guard let code = error.code else { continue }
            XCTAssertEqual(APIError(code: code, message: "", status: 0).code, code)
            if case .server = error { continue }
            if case .rateLimited = error {
                // Its message is kept: it says which limit it was and what helps.
                XCTAssertEqual(APIError(code: code, message: "Cancel one.", status: 429), .rateLimited(message: "Cancel one."), code)
                continue
            }
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
        XCTAssertTrue(APIError.rateLimited(message: "").isRetryable)
        XCTAssertTrue(APIError.server(code: "server_error", message: "", status: 503).isRetryable)
        XCTAssertTrue(APIError.server(code: "network_error", message: "", status: 0).isRetryable)
        XCTAssertFalse(APIError.server(code: "invalid_request", message: "", status: 400).isRetryable)
        XCTAssertFalse(APIError.server(code: "invalid_request", message: "Too big", status: 0).isRetryable)
        XCTAssertFalse(APIError.slotTaken.isRetryable)
        XCTAssertFalse(APIError.unauthorized.isRetryable)
        XCTAssertFalse(APIError.decoding("x").isRetryable)
    }
}
