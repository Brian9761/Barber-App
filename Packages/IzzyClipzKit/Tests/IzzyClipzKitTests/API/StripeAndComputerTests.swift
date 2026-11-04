import XCTest
@testable import IzzyClipzKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The server's own contract fixture `name` (`server/test/fixtures/contract`), or a skip when the
/// server isn't next to the Kit.
func serverFixture(_ name: String) throws -> Data {
    let url = TestPaths.serverFixtures.appendingPathComponent(name)
    guard let data = FileManager.default.contents(atPath: url.path) else {
        throw XCTSkip("No server contract fixture at \(url.path) yet; the server's tests write it.")
    }
    return data
}

/// The shop's own Stripe account (Stripe Connect) and signing in on a computer: the models, the
/// Kit's copy of the server's words, Stripe's way back to the app, and the client's requests.
final class StripeConnectionTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testTheConnectionSettingsShows() throws {
        let connection = try decoder.decode(IzzyAPI.StripeConnection.self, from: try kitFixture("stripe-connection.json"))
        XCTAssertEqual(connection, IzzyAPI.StripeConnection(
            mode: .connect, status: .needsInfo, accountId: "acct_1SampleShopAccount", businessName: "Izzy Clipz Barbershop",
            livemode: false, requirementsDue: 3, checkedAt: utc(2026, 11, 2, 17, 10)
        ))
        XCTAssertEqual(connection.message, "Finish setting up Stripe to take card payments.")
        XCTAssertEqual(connection.dashboardUrl.absoluteString, "https://dashboard.stripe.com/")
        XCTAssertEqual(connection.status.title, "Finish setting up")
        XCTAssertEqual(connection.status.connectButtonTitle, "Finish setting up")
        XCTAssertFalse(connection.status.takesCardPayments)
        XCTAssertEqual(connection.summary, IzzyAPI.StripeConnectionSummary(mode: .connect, status: .needsInfo, businessName: "Izzy Clipz Barbershop"))
        // Written back with every field, null when empty.
        XCTAssertEqual(try encodeAPI(IzzyAPI.StripeConnection(mode: .off, status: .off)), .object([
            "mode": .string("off"), "status": .string("off"), "accountId": .null, "businessName": .null, "livemode": .null,
            "chargesEnabled": .bool(false), "payoutsEnabled": .bool(false), "detailsSubmitted": .bool(false), "requirementsDue": .number(0),
            "message": .string("Stripe isn't set up on the server."), "dashboardUrl": .string("https://dashboard.stripe.com/"), "checkedAt": .null,
        ]))
    }

    func testEveryStatusInSettingsWords() {
        XCTAssertEqual(IzzyAPI.StripeConnection.Status.allCases.map(\.title), [
            "Not connected", "Finish setting up", "Stripe is checking your details", "Connected", "Paused by Stripe",
            "Uses the server's Stripe key", "Not set up on the server", "Check Stripe",
        ])
        XCTAssertEqual(IzzyAPI.StripeConnection.Status.allCases.map(\.connectButtonTitle), [
            "Connect Stripe", "Finish setting up", nil, nil, "Finish setting up", nil, nil, nil,
        ])
        XCTAssertEqual(IzzyAPI.StripeConnection.Status.allCases.filter(\.takesCardPayments), [.active, .direct])
        XCTAssertEqual(IzzyAPI.StripeConnection.message(for: .active, payoutsEnabled: false), "Connected. Card payments are on. Add your bank in Stripe to get paid out.")
        XCTAssertEqual(IzzyAPI.StripeConnection.message(for: .active, payoutsEnabled: true), "Connected. Card payments are on. Payouts to your bank are on.")
        for status in IzzyAPI.StripeConnection.Status.allCases {
            let message = IzzyAPI.StripeConnection.message(for: status)
            XCTAssertTrue(message.hasSuffix("."), message)
            XCTAssertFalse(message.contains("_"), message)
        }
    }

    /// A mode or status a newer server adds reads as unknown: never as connected, nothing to tap.
    func testAnUnknownModeOrStatusIsNeverConnected() throws {
        let text = String(decoding: try kitFixture("stripe-connection.json"), as: UTF8.self)
            .replacingOccurrences(of: #""status": "needsInfo""#, with: #""status": "underReview""#)
            .replacingOccurrences(of: #""mode": "connect""#, with: #""mode": "platform""#)
            .replacingOccurrences(of: #""dashboardUrl": "https://dashboard.stripe.com/""#, with: #""dashboardUrl": "javascript:alert(1)""#)
        let future = try decodeAPI(IzzyAPI.StripeConnection.self, text)
        XCTAssertEqual(future.status, .unknown)
        XCTAssertEqual(future.mode, .unknown)
        XCTAssertNil(future.status.connectButtonTitle)
        XCTAssertFalse(future.status.takesCardPayments)
        XCTAssertEqual(future.message, "Finish setting up Stripe to take card payments.", "the server's words are still shown")
        XCTAssertEqual(future.dashboardUrl, IzzyAPI.StripeConnection.dashboard, "only Stripe's own page opens")
        let summary = try decodeAPI(IzzyAPI.StripeConnectionSummary.self, #"{ "mode": "connect", "status": "frozen", "businessName": null }"#)
        XCTAssertEqual(summary.status, .unknown)
    }

    /// The Kit's words for each status are the server's, for every connection the server's tests wrote down.
    func testTheKitSpeaksLikeTheServer() throws {
        let names = ["off", "direct", "not-connected", "needs-info", "pending", "active", "restricted", "disconnected"]
        var seen: Set<IzzyAPI.StripeConnection.Status> = []
        for name in names {
            let connection = try decoder.decode(IzzyAPI.StripeConnection.self, from: try serverFixture("stripe-connection-\(name).json"))
            seen.insert(connection.status)
            if name == "disconnected" {
                XCTAssertEqual(connection.status, .notConnected)
                XCTAssertEqual(connection.message, IzzyAPI.StripeConnection.disconnectedMessage)
                continue
            }
            XCTAssertEqual(connection.message, IzzyAPI.StripeConnection.message(for: connection.status, payoutsEnabled: connection.payoutsEnabled), name)
            // A fake that fills in the same fields answers exactly like the server.
            let fake = IzzyAPI.StripeConnection(
                mode: connection.mode, status: connection.status, accountId: connection.accountId, businessName: connection.businessName,
                livemode: connection.livemode, chargesEnabled: connection.chargesEnabled, payoutsEnabled: connection.payoutsEnabled,
                detailsSubmitted: connection.detailsSubmitted, requirementsDue: connection.requirementsDue, checkedAt: connection.checkedAt
            )
            XCTAssertEqual(fake, connection, name)
        }
        XCTAssertEqual(seen, Set(IzzyAPI.StripeConnection.Status.allCases).subtracting([.unknown]))

        let me = try decoder.decode(IzzyAPI.OwnerStatus.self, from: try serverFixture("owner-me-connected.json"))
        XCTAssertEqual(me.connection, IzzyAPI.StripeConnectionSummary(mode: .connect, status: .active, businessName: "Izzy Clipz Barbershop"))
        XCTAssertEqual(me.stripe, IzzyAPI.StripeStatus(configured: true, mode: .test, locationId: "tml_TestFixture000003"))
        let direct = try decoder.decode(IzzyAPI.OwnerStatus.self, from: try serverFixture("owner-me.json"))
        XCTAssertEqual(direct.connection, IzzyAPI.StripeConnectionSummary(mode: .direct, status: .direct))
    }

    /// `GET /api/owner/me` from a server before Stripe Connect: no connection, written back as null.
    func testOwnerStatusFromAnOlderServer() throws {
        let old = try decodeAPI(IzzyAPI.OwnerStatus.self, #"{ "ok": true, "stripe": { "configured": false, "mode": null, "locationId": null } }"#)
        XCTAssertNil(old.connection)
        XCTAssertEqual(try encodeAPI(old)["connection"], .null)
    }

    func testTheConnectLink() throws {
        let link = try decoder.decode(IzzyAPI.StripeConnectLink.self, from: try kitFixture("stripe-connect-link.json"))
        XCTAssertEqual(link.url.absoluteString, "https://connect.stripe.com/setup/s/acct_1SampleShopAccount/SampleLink01")
        XCTAssertEqual(link.expiresAt, utc(2026, 11, 2, 17, 15))
        XCTAssertEqual(IzzyAPI.StripeConnectLink.callbackScheme, "izzyclipzbusiness")
        // Only a web page opens.
        XCTAssertThrowsError(try decodeAPI(IzzyAPI.StripeConnectLink.self, #"{ "url": "izzyclipzbusiness://x", "expiresAt": "2026-11-02T17:15:00Z" }"#))
        let server = try decoder.decode(IzzyAPI.StripeConnectLink.self, from: try serverFixture("stripe-connect-link.json"))
        XCTAssertEqual(server.url.host, "connect.stripe.com")
    }

    func testStripesWayBackToTheApp() throws {
        func back(_ text: String) -> IzzyAPI.StripeConnectReturn? {
            IzzyAPI.StripeConnectReturn(callbackURL: URL(string: text)!)
        }
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=active")?.status, .active)
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=active")?.resultMessage, "You're connected. You can take card payments now.")
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=needsInfo")?.resultMessage, "Stripe still needs a few details: tap Finish setting up.")
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=restricted")?.resultMessage, "Stripe still needs a few details: tap Finish setting up.")
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=pending")?.resultMessage, "Stripe is checking your details. This usually takes a few minutes.")
        XCTAssertEqual(back("IZZYCLIPZBUSINESS://Stripe-Connected?status=pending")?.status, .pending)
        // Something the link doesn't say, or a status this version doesn't know.
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected")?.status, .unknown)
        XCTAssertEqual(back("izzyclipzbusiness://stripe-connected?status=rejected")?.status, .unknown)
        // Not the way back from Stripe.
        XCTAssertNil(back("izzyclipz://stripe-connected?status=active"))
        XCTAssertNil(back("https://izzy-clipz-api.test/stripe-connected?status=active"))
        XCTAssertNil(back("izzyclipzbusiness://card-saved?session_id=cs_test_x"))
    }
}

final class ComputerSignInTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testTheCode() throws {
        let code = try decoder.decode(IzzyAPI.ComputerCode.self, from: try kitFixture("computer-code.json"))
        XCTAssertEqual(code, IzzyAPI.ComputerCode(code: "483920", expiresAt: utc(2026, 11, 2, 18, 10), expiresInSeconds: 600))
        XCTAssertEqual(code.grouped, "483 920")
        XCTAssertEqual(IzzyAPI.ComputerCode(code: "12345", expiresAt: utc(2026, 1, 1)).grouped, "12345")
        // Never in a log.
        XCTAssertFalse(String(describing: code).contains("483920"))
    }

    /// Counted from when the answer arrived, so a phone whose clock is off still shows the right time.
    func testTheCountdown() {
        let code = IzzyAPI.ComputerCode(code: "483920", expiresAt: utc(2026, 11, 2, 18, 10), expiresInSeconds: 600)
        let received = utc(2030, 1, 1, 9)
        XCTAssertEqual(code.secondsLeft(receivedAt: received, now: received), 600)
        XCTAssertEqual(code.secondsLeft(receivedAt: received, now: received.addingTimeInterval(0.5)), 600)
        XCTAssertEqual(code.secondsLeft(receivedAt: received, now: received.addingTimeInterval(18)), 582)
        XCTAssertEqual(code.secondsLeft(receivedAt: received, now: received.addingTimeInterval(600)), 0)
        XCTAssertEqual(code.secondsLeft(receivedAt: received, now: received.addingTimeInterval(900)), 0)
        XCTAssertEqual(IzzyAPI.ComputerCode.countdownLabel(seconds: 582), "9:42")
        XCTAssertEqual(IzzyAPI.ComputerCode.countdownLabel(seconds: 600), "10:00")
        XCTAssertEqual(IzzyAPI.ComputerCode.countdownLabel(seconds: 5), "0:05")
        XCTAssertEqual(IzzyAPI.ComputerCode.countdownLabel(seconds: -3), "0:00")
    }

    func testTheComputersSignedIn() throws {
        let sessions = try decoder.decode(IzzyAPI.ComputerSessionsResponse.self, from: try kitFixture("computer-sessions.json")).sessions
        XCTAssertEqual(sessions.map(\.name), ["Chrome on Mac", "Edge on Windows"])
        XCTAssertEqual(sessions[0], IzzyAPI.ComputerSession(
            id: "8a9b0c1d-2e3f-4a4b-9c5d-6e7f8a9b0c1d", name: "Chrome on Mac", createdAt: utc(2026, 11, 2, 18, 1, 30),
            lastUsedAt: utc(2026, 11, 2, 18, 45), expiresAt: utc(2026, 12, 2, 18, 1, 30)
        ))
        XCTAssertEqual(sessions.map(\.current), [false, false], "the Business app isn't one of them")

        let created = try decoder.decode(IzzyAPI.ComputerSessionCreated.self, from: try kitFixture("computer-session-created.json"))
        XCTAssertEqual(created.token.count, 43)
        XCTAssertTrue(created.session.current)
        XCTAssertFalse(String(describing: created).contains(created.token), "the token never shows up in a log")

        let server = try decoder.decode(IzzyAPI.ComputerSessionsResponse.self, from: try serverFixture("computer-sessions.json")).sessions
        XCTAssertEqual(server.map(\.current), [true, false])
    }

    /// The website's sign-in, described for completeness: public, and the code as typed.
    func testSigningInOnTheWebsite() throws {
        let endpoint = try IzzyAPI.Endpoints.signInComputer(code: " 483 920 ", name: "  Chrome on Mac ")
        let request = try endpoint.urlRequest(baseURL: URL(string: "https://api.test")!, ownerKey: "owner-key-0123456789abcdef0123456789abcdef")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/api/computer-sessions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "public: the owner key never goes with it")
        XCTAssertEqual(try JSONValue(data: XCTUnwrap(request.httpBody)), .object(["code": .string("483 920"), "name": .string("Chrome on Mac")]))
        let unnamed = try IzzyAPI.Endpoints.signInComputer(code: "483920", name: " ").urlRequest(baseURL: URL(string: "https://api.test")!, ownerKey: nil)
        XCTAssertEqual(try JSONValue(data: XCTUnwrap(unnamed.httpBody)), .object(["code": .string("483920")]))
    }
}

/// The client's requests for the shop's Stripe account and computers.
final class StripeAndComputerClientTests: XCTestCase {
    let ownerKey = "owner-key-0123456789abcdef0123456789abcdef"
    var client: IzzyAPIClient!

    typealias Reply = StubURLProtocol.Reply

    override func setUp() {
        super.setUp()
        client = IzzyAPIClient(baseURL: URL(string: "https://api.test")!, session: StubURLProtocol.session(), ownerKey: ownerKey)
        StubURLProtocol.reply { _ in Reply() }
    }

    func only(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Sent {
        let sent = StubURLProtocol.sent
        XCTAssertEqual(sent.count, 1, "requests sent", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    func testConnectingStripeSendsTheAppsWayBack() async throws {
        StubURLProtocol.reply { _ in .fixture("stripe-connect-link.json", status: 201) }
        let link = try await client.connectStripe()
        XCTAssertEqual(link.url.host, "connect.stripe.com")
        let sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/owner/stripe/connect")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
        XCTAssertEqual(sent.json, .object(["returnTo": .string("app")]))
        XCTAssertNil(sent.header("Idempotency-Key"))
    }

    func testDisconnectingAnswersWithTheConnection() async throws {
        let body = try serverFixtureOrKit("stripe-connection-disconnected.json", fallback: "stripe-connection.json")
        StubURLProtocol.reply { _ in Reply(status: 200, body: body) }
        let connection = try await client.disconnectStripe()
        XCTAssertFalse(connection.message.isEmpty)
        let sent = try only()
        XCTAssertEqual(sent.method, "DELETE")
        XCTAssertEqual(sent.path, "/api/owner/stripe/connect")
        XCTAssertNil(sent.body)
    }

    /// A server that uses its own Stripe key has nothing to connect: its 409 comes back in its own words.
    func testTheServersStripeErrorsKeepTheirWords() async throws {
        let message = "This server uses its own Stripe key, so there's nothing to connect."
        StubURLProtocol.reply { _ in .json(409, #"{"error":{"code":"stripe_connect_off","message":"\#(message)"}}"#) }
        do {
            _ = try await client.connectStripe()
            XCTFail("expected stripe_connect_off")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: IzzyAPI.ErrorCode.stripeConnectOff, message: message, status: 409))
            XCTAssertEqual(error.userMessage, message)
            XCTAssertFalse(error.isRetryable)
        }
        let forbidden = APIError(code: "forbidden", message: "This can only be done in the Izzy Clipz Business app on your iPhone.", status: 403)
        XCTAssertEqual(forbidden, .server(code: IzzyAPI.ErrorCode.forbidden, message: "This can only be done in the Izzy Clipz Business app on your iPhone.", status: 403))
        let wrongCode = APIError(code: "wrong_code", message: "That code isn't right or has run out.", status: 400)
        XCTAssertEqual(wrongCode.code, IzzyAPI.ErrorCode.wrongCode)
        XCTAssertEqual(wrongCode.userMessage, "That code isn't right or has run out.")
        // The server's own envelopes for these codes.
        for code in ["stripe_connect_off", "forbidden", "wrong_code"] {
            let envelope = try IzzyAPI.makeDecoder().decode(IzzyAPI.ErrorEnvelope.self, from: try serverFixture("errors/\(code).json"))
            XCTAssertEqual(envelope.error.code, code)
            let error = APIError.fromResponse(status: 400, body: try serverFixture("errors/\(code).json"))
            XCTAssertEqual(error.code, code)
            XCTAssertEqual(error.userMessage, envelope.error.message)
        }
    }

    func testSigningComputersOut() async throws {
        StubURLProtocol.reply { _ in Reply(status: 204, headers: [:]) }
        try await client.signOutComputer(id: "../computer-codes")
        XCTAssertEqual(try only().path, "/api/owner/computer-sessions/..%2Fcomputer-codes", "an id can't change the path")
        StubURLProtocol.reply { _ in Reply(status: 204, headers: [:]) }
        try await client.signOutAllComputers()
        let sent = try only()
        XCTAssertEqual(sent.method, "DELETE")
        XCTAssertEqual(sent.path, "/api/owner/computer-sessions")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)
        StubURLProtocol.reply { _ in .json(404, #"{"error":{"code":"not_found","message":"We couldn't find that computer."}}"#) }
        do {
            try await client.signOutComputer(id: "c1")
            XCTFail("expected not_found")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: "not_found", message: "We couldn't find that computer.", status: 404))
        }
    }

    func testOwnerCallsWithoutAKeyNeverLeaveThePhone() async throws {
        let signedOut = client.withOwnerKey(nil)
        for call in [
            { _ = try await signedOut.stripeConnection() },
            { _ = try await signedOut.connectStripe() },
            { _ = try await signedOut.disconnectStripe() },
            { _ = try await signedOut.createComputerCode() },
            { _ = try await signedOut.computerSessions() },
            { try await signedOut.signOutComputer(id: "c1") },
            { try await signedOut.signOutAllComputers() },
        ] as [() async throws -> Void] {
            do {
                try await call()
                XCTFail("expected unauthorized")
            } catch let error as APIError {
                XCTAssertEqual(error, .unauthorized)
            }
        }
        XCTAssertEqual(StubURLProtocol.sent.count, 0)
    }

    private func serverFixtureOrKit(_ name: String, fallback: String) throws -> Data {
        let url = TestPaths.serverFixtures.appendingPathComponent(name)
        return try FileManager.default.contents(atPath: url.path) ?? kitFixture(fallback)
    }
}
