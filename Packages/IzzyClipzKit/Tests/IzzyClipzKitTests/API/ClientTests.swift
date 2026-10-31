import XCTest
@testable import IzzyClipzKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers every request from a canned reply and records what was sent.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers = ["Content-Type": "application/json"]
        var body = Data()
        var error: Error?

        static func json(_ status: Int, _ text: String) -> Reply {
            Reply(status: status, body: Data(text.utf8))
        }

        static func fixture(_ name: String, status: Int = 200) -> Reply {
            Reply(status: status, body: (try? kitFixture(name)) ?? Data())
        }

        static func failure(_ code: URLError.Code) -> Reply {
            Reply(error: URLError(code))
        }
    }

    struct Sent {
        let request: URLRequest
        let body: Data?

        var method: String? { request.httpMethod }
        var path: String? { request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath } }
        var query: String? { request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery } }
        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
        var json: JSONValue? { body.flatMap { try? JSONValue(data: $0) } }
    }

    private static let lock = NSLock()
    private static var makeReply: (URLRequest) -> Reply = { _ in Reply() }
    private static var sentRequests: [Sent] = []

    /// Replies to every request with `reply`, and forgets what was sent before.
    static func reply(_ reply: @escaping (URLRequest) -> Reply) {
        locked {
            makeReply = reply
            sentRequests = []
        }
    }

    static var sent: [Sent] { locked { sentRequests } }

    private static func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        let make = Self.locked { () -> (URLRequest) -> Reply in
            Self.sentRequests.append(Sent(request: request, body: body))
            return Self.makeReply
        }
        let reply = make(request)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class ClientTests: XCTestCase {
    let baseURL = URL(string: "https://api.test")!
    let ownerKey = "owner-key-0123456789abcdef0123456789abcdef"
    var client: IzzyAPIClient!

    override func setUp() {
        super.setUp()
        client = IzzyAPIClient(baseURL: baseURL, session: StubURLProtocol.session(), ownerKey: ownerKey)
        StubURLProtocol.reply { _ in Reply() }
    }

    typealias Reply = StubURLProtocol.Reply

    func only(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Sent {
        let sent = StubURLProtocol.sent
        XCTAssertEqual(sent.count, 1, "requests sent", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    /// Runs `work`, expecting it to throw `expected`.
    func assertThrows<T>(
        _ expected: APIError,
        _ work: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await work()
            XCTFail("Expected \(expected), got a result", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    // MARK: Success

    func testHealthIsAPlainGET() async throws {
        StubURLProtocol.reply { _ in .fixture("health.json") }
        let health = try await client.health()
        XCTAssertEqual(health, IzzyAPI.Health(ok: true, version: "1.0.0"))
        let sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.test/api/health")
        XCTAssertEqual(sent.header("Accept"), "application/json")
        // Public calls never carry the owner key, even from an owner's client.
        XCTAssertNil(sent.header("Authorization"))
        XCTAssertNil(sent.header("X-Manage-Token"))
        XCTAssertNil(sent.header("Content-Type"))
        XCTAssertNil(sent.body)
    }

    func testAvailabilityQueries() async throws {
        StubURLProtocol.reply { _ in .fixture("availability.json") }
        let availability = try await client.availability(IzzyAPI.AvailabilityQuery(
            target: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"), from: LocalDate("2026-11-02")!, days: 7
        ))
        XCTAssertEqual(availability.days.count, 2)
        var sent = try only()
        XCTAssertEqual(sent.path, "/api/availability")
        XCTAssertEqual(sent.query, "offeringId=flowxbori%2Fbbb0c294-87a6-465d-9f55-6f579dcb399a&from=2026-11-02&days=7")

        StubURLProtocol.reply { _ in .fixture("availability.json") }
        _ = try await client.availability(IzzyAPI.AvailabilityQuery(target: .anyBarber(serviceId: "haircut"), from: LocalDate("2026-12-31")!))
        sent = try only()
        XCTAssertEqual(sent.query, "serviceId=haircut&barberId=any&from=2026-12-31&days=1")
        XCTAssertNil(sent.header("Authorization"))

        // Anything that could change the URL is escaped.
        StubURLProtocol.reply { _ in .fixture("availability.json") }
        _ = try await client.availability(IzzyAPI.AvailabilityQuery(target: .anyBarber(serviceId: "a b+c&d=e/é#?"), from: LocalDate("2026-11-02")!))
        XCTAssertEqual(try only().query, "serviceId=a%20b%2Bc%26d%3De%2F%C3%A9%23%3F&barberId=any&from=2026-11-02&days=1")
    }

    func testBookingSendsTheContractBodyAndReadsA201() async throws {
        StubURLProtocol.reply { _ in .fixture("booking-confirmation.json", status: 201) }
        let token = IzzyAPI.ManageToken.generate()
        let confirmation = try await client.book(IzzyAPI.NewAppointment(
            target: .anyBarber(serviceId: "haircut"),
            start: utc(2026, 11, 2, 18),
            customer: IzzyAPI.NewCustomer(name: "Test Customer", phone: PhoneNumber(parsing: "(442) 555-0123")?.e164)
        ), token: token)
        XCTAssertEqual(confirmation.appointment.barberId, "flowxbori")
        XCTAssertEqual(confirmation.manageToken, "dGVzdC1tYW5hZ2UtdG9rZW4tZm9yLWZpeHR1cmVzLTAx")
        let sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/appointments")
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
        // The app's own manage token, which makes a retry safe.
        XCTAssertEqual(sent.header("X-Manage-Token"), token.rawValue)
        XCTAssertNil(sent.header("Authorization"))
        XCTAssertEqual(sent.json, .object([
            "serviceId": .string("haircut"), "barberId": .string("any"), "start": .string("2026-11-02T18:00:00Z"),
            "customer": .object(["name": .string("Test Customer"), "phone": .string("+14425550123")]),
        ]))
    }

    /// A retry of a booking that went through: the server answers 200 with the same appointment
    /// and token, which decodes like a new booking. Each try sends the token it was given.
    func testABookingRetryIsAnsweredWith200() async throws {
        let token = IzzyAPI.ManageToken.generate()
        let appointment = IzzyAPI.NewAppointment(
            target: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"),
            start: utc(2026, 11, 3, 18),
            customer: IzzyAPI.NewCustomer(name: "Test Customer", phone: "4425550123")
        )
        let body = String(decoding: try kitFixture("booking-confirmation.json"), as: UTF8.self)
            .replacingOccurrences(of: "dGVzdC1tYW5hZ2UtdG9rZW4tZm9yLWZpeHR1cmVzLTAx", with: token.rawValue)
        XCTAssertTrue(body.contains(token.rawValue))
        StubURLProtocol.reply { _ in .json(201, body) }
        let first = try await client.book(appointment, token: token)
        StubURLProtocol.reply { _ in .json(200, body) }
        let retry = try await client.book(appointment, token: token)
        XCTAssertEqual(retry, first)
        XCTAssertEqual(retry.manageToken, token.rawValue)
        let sent = try only()
        XCTAssertEqual(sent.header("X-Manage-Token"), token.rawValue)
        XCTAssertEqual(sent.json?["start"], .string("2026-11-03T18:00:00Z"))

        // The same token used for another booking is turned down in the server's words.
        StubURLProtocol.reply { _ in .json(400, #"{"error":{"code":"invalid_request","message":"That booking token was already used."}}"#) }
        await assertThrows(.server(code: "invalid_request", message: "That booking token was already used.", status: 400)) {
            try await self.client.book(appointment, token: token)
        }
    }

    func testManageTokenCalls() async throws {
        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        let appointment = try await client.appointment(id: "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b", manageToken: "token-abc_123")
        XCTAssertEqual(appointment.status, .cancelled)
        var sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/appointments/5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(sent.header("X-Manage-Token"), "token-abc_123")
        XCTAssertNil(sent.header("Authorization"))

        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        _ = try await client.cancelAppointment(id: "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b", manageToken: "token-abc_123")
        sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/appointments/5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b/cancel")
        XCTAssertEqual(sent.header("X-Manage-Token"), "token-abc_123")
        // A POST without a body of its own still sends JSON.
        XCTAssertEqual(sent.json, .object([:]))
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
    }

    func testIDsCantChangeThePath() async throws {
        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        _ = try await client.appointment(id: "../owner/me?x=1#y", manageToken: "t")
        XCTAssertEqual(try only().path, "/api/appointments/..%2Fowner%2Fme%3Fx%3D1%23y")

        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        _ = try await client.cancelAppointment(id: "..", manageToken: "t")
        XCTAssertEqual(try only().path, "/api/appointments/%2E%2E/cancel")

        StubURLProtocol.reply { _ in Reply(status: 204) }
        try await client.deleteTimeOff(id: "")
        XCTAssertEqual(try only().path, "/api/owner/time-off/%20")
    }

    func testReviewsAndProducts() async throws {
        StubURLProtocol.reply { _ in .fixture("reviews.json") }
        let reviews = try await client.reviews()
        XCTAssertEqual(reviews.google.reviews.count, 2)
        XCTAssertEqual(try only().path, "/api/reviews")

        StubURLProtocol.reply { _ in .fixture("products.json") }
        let products = try await client.products()
        XCTAssertEqual(products.count, 2)
        let sent = try only()
        XCTAssertEqual(sent.path, "/api/products")
        XCTAssertNil(sent.header("Authorization"))
    }

    // MARK: Owner calls

    struct OwnerCall {
        let name: String
        let reply: Reply
        let method: String
        let path: String
        var query: String?
        var body: JSONValue?
        let run: (IzzyAPIClient) async throws -> Void
    }

    func testEveryOwnerCallCarriesTheKeyAndHitsItsEndpoint() async throws {
        let day = LocalDate("2026-11-02")!
        let calls: [OwnerCall] = [
            OwnerCall(name: "me", reply: .fixture("owner-me.json"), method: "GET", path: "/api/owner/me") {
                let status = try await $0.ownerStatus()
                XCTAssertEqual(status.stripe.mode, .test)
                XCTAssertEqual(status.stripe.locationId, "tml_FixtureLocation")
            },
            OwnerCall(name: "walk-in times", reply: .fixture("availability.json"), method: "GET", path: "/api/owner/availability",
                      query: "offeringId=flowxbori%2Fbbb0c294-87a6-465d-9f55-6f579dcb399a&from=2026-11-02&days=1") {
                let open = try await $0.ownerAvailability(IzzyAPI.AvailabilityQuery(
                    target: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"), from: day
                ))
                XCTAssertEqual(open.days.count, 2)
            },
            OwnerCall(name: "day", reply: .fixture("owner-appointments.json"), method: "GET", path: "/api/owner/appointments", query: "date=2026-11-02") {
                let list = try await $0.appointments(on: day)
                XCTAssertEqual(list.count, 3)
            },
            OwnerCall(name: "range", reply: .fixture("owner-appointments.json"), method: "GET", path: "/api/owner/appointments",
                      query: "from=2026-11-02&to=2026-11-08") {
                _ = try await $0.appointments(from: day, to: day.adding(days: 6))
            },
            OwnerCall(name: "walk-in", reply: .fixture("appointment.json", status: 201), method: "POST", path: "/api/owner/appointments",
                      body: .object(["offeringId": .string("carlos-rafael/x"), "start": .string("2026-11-02T19:00:00Z"),
                                     "customer": .object(["name": .string("Walk-in")])])) {
                _ = try await $0.createAppointment(IzzyAPI.NewAppointment(
                    target: .offering(id: "carlos-rafael/x"), start: utc(2026, 11, 2, 19), customer: IzzyAPI.NewCustomer(name: "Walk-in")
                ))
            },
            OwnerCall(name: "status", reply: .fixture("appointment.json"), method: "PATCH", path: "/api/owner/appointments/a1",
                      body: .object(["status": .string("noShow")])) {
                _ = try await $0.setStatus(.noShow, ofAppointment: "a1")
            },
            OwnerCall(name: "time off", reply: .fixture("time-off-list.json"), method: "GET", path: "/api/owner/time-off",
                      query: "from=2026-11-02&to=2026-11-30") {
                let blocks = try await $0.timeOff(from: day, to: LocalDate("2026-11-30")!)
                XCTAssertEqual(blocks.count, 2)
            },
            OwnerCall(name: "block", reply: .fixture("time-off.json", status: 201), method: "POST", path: "/api/owner/time-off",
                      body: .object(["barberId": .null, "start": .string("2026-11-26T08:00:00Z"), "end": .string("2026-11-27T08:00:00Z"),
                                     "reason": .string("Thanksgiving")])) {
                let block = try await $0.createTimeOff(IzzyAPI.NewTimeOff(
                    barberId: nil, start: utc(2026, 11, 26, 8), end: utc(2026, 11, 27, 8), reason: "Thanksgiving"
                ))
                XCTAssertEqual(block.barberId, "carlos-rafael")
            },
            OwnerCall(name: "unblock", reply: Reply(status: 204, headers: [:]), method: "DELETE", path: "/api/owner/time-off/t1") {
                try await $0.deleteTimeOff(id: "t1")
            },
            OwnerCall(name: "products", reply: .fixture("owner-products.json"), method: "GET", path: "/api/owner/products") {
                let products = try await $0.allProducts()
                XCTAssertEqual(products.map(\.visible), [false])
            },
            OwnerCall(name: "add product", reply: .fixture("product.json", status: 201), method: "POST", path: "/api/owner/products",
                      body: .object(["name": .string("Sample pomade"), "priceCents": .number(1800)])) {
                _ = try await $0.createProduct(IzzyAPI.NewProduct(name: "Sample pomade", priceCents: 1800))
            },
            OwnerCall(name: "edit product", reply: .fixture("product.json"), method: "PATCH", path: "/api/owner/products/p1",
                      body: .object(["visible": .bool(false), "description": .null])) {
                _ = try await $0.updateProduct(id: "p1", IzzyAPI.ProductUpdate(description: .clear, visible: false))
            },
            OwnerCall(name: "delete product", reply: Reply(status: 204, headers: [:]), method: "DELETE", path: "/api/owner/products/p1") {
                try await $0.deleteProduct(id: "p1")
            },
            OwnerCall(name: "token", reply: .fixture("connection-token.json"), method: "POST", path: "/api/owner/terminal/connection-token",
                      body: .object([:])) {
                let secret = try await $0.connectionToken()
                XCTAssertEqual(secret, "pst_test_c2FtcGxlLWNvbm5lY3Rpb24tdG9rZW4")
            },
            OwnerCall(name: "charge", reply: .fixture("payment-intent.json", status: 201), method: "POST", path: "/api/owner/payments",
                      body: .object(["amountCents": .number(8000), "appointmentId": .string("a1")])) {
                let intent = try await $0.createPayment(IzzyAPI.NewPayment(amountCents: 8000, appointmentId: "a1"))
                XCTAssertEqual(intent.paymentIntentId, "pi_3SampleSampleSample01")
            },
            OwnerCall(name: "complete", reply: .fixture("payment.json"), method: "POST", path: "/api/owner/payments/pi_3SampleSampleSample01/complete",
                      body: .object([:])) {
                let payment = try await $0.completePayment(id: "pi_3SampleSampleSample01")
                XCTAssertTrue(payment.isSucceeded)
            },
            OwnerCall(name: "payments", reply: .fixture("payments.json"), method: "GET", path: "/api/owner/payments", query: "date=2026-11-02") {
                let payments = try await $0.payments(on: day)
                XCTAssertEqual(payments.count, 2)
            },
        ]
        for call in calls {
            StubURLProtocol.reply { _ in call.reply }
            do {
                try await call.run(client)
            } catch {
                XCTFail("\(call.name): \(error)")
                continue
            }
            let sent = try only()
            XCTAssertEqual(sent.method, call.method, call.name)
            XCTAssertEqual(sent.path, call.path, call.name)
            XCTAssertEqual(sent.query, call.query, call.name)
            XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey, call.name)
            XCTAssertNil(sent.header("X-Manage-Token"), call.name)
            XCTAssertEqual(sent.header("Accept"), "application/json", call.name)
            if let body = call.body {
                XCTAssertEqual(sent.json, body, call.name)
                XCTAssertEqual(sent.header("Content-Type"), "application/json", call.name)
            } else {
                XCTAssertNil(sent.body, call.name)
            }
        }
    }

    func testPhotoUploadSendsTheJPEGItself() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0xFF, 0xD9])
        StubURLProtocol.reply { _ in .fixture("product.json") }
        let product = try await client.uploadProductPhoto(id: "6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a", jpegData: jpeg)
        XCTAssertNotNil(product.imageUrl)
        let sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/owner/products/6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a/photo")
        XCTAssertEqual(sent.header("Content-Type"), "image/jpeg")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)
        XCTAssertEqual(sent.body, jpeg)
        XCTAssertEqual(sent.request.timeoutInterval, 60)
    }

    func testPhotosOverTheLimitArentUploaded() async throws {
        await assertThrows(.server(code: "invalid_request", message: "That photo is too big to upload. Pick a smaller one, or take it again.", status: 0)) {
            try await self.client.uploadProductPhoto(id: "p1", jpegData: Data(count: IzzyAPI.maxPhotoBytes + 1))
        }
        XCTAssertEqual(StubURLProtocol.sent.count, 0)
        StubURLProtocol.reply { _ in .fixture("product.json") }
        _ = try await client.uploadProductPhoto(id: "p1", jpegData: Data(count: IzzyAPI.maxPhotoBytes))
        XCTAssertEqual(try only().body?.count, IzzyAPI.maxPhotoBytes)
    }

    func testOwnerCallsNeedAUsableKeyAndNeverSendABadOne() async throws {
        for key in [nil, "", "   \n"] as [String?] {
            let signedOut = client.withOwnerKey(key)
            XCTAssertFalse(signedOut.hasOwnerKey)
            await assertThrows(.unauthorized) { try await signedOut.ownerStatus() }
        }
        // A line break inside the key would split the header.
        await assertThrows(.unauthorized) { try await self.client.withOwnerKey("abc\r\nX-Evil: 1").allProducts() }
        await assertThrows(.unauthorized) { try await self.client.withOwnerKey("ключ").allProducts() }
        await assertThrows(.unauthorized) { try await self.client.appointment(id: "a1", manageToken: "") }
        await assertThrows(.unauthorized) { try await self.client.appointment(id: "a1", manageToken: "t\nX: y") }
        XCTAssertEqual(StubURLProtocol.sent.count, 0, "nothing reaches the network")

        // Keys pasted with spaces or a trailing line break still work.
        StubURLProtocol.reply { _ in .fixture("owner-me.json") }
        _ = try await client.withOwnerKey("  \(ownerKey)\n").ownerStatus()
        XCTAssertEqual(try only().header("Authorization"), "Bearer " + ownerKey)

        // And the key never shows up in a log.
        XCTAssertFalse(String(describing: client!).contains(ownerKey))
        XCTAssertTrue(client.hasOwnerKey)
    }

    // MARK: Errors

    func testEveryErrorCodeMapsToItsCase() async {
        let cases: [(Int, String, APIError)] = [
            (400, "invalid_request", .server(code: "invalid_request", message: "Message for invalid_request", status: 400)),
            (401, "unauthorized", .unauthorized),
            (404, "not_found", .server(code: "not_found", message: "Message for not_found", status: 404)),
            (409, "slot_taken", .slotTaken),
            (409, "not_cancellable", .notCancellable),
            (422, "outside_hours", .outsideHours),
            (422, "too_soon", .tooSoon),
            (422, "too_far", .tooFar),
            (429, "rate_limited", .rateLimited(message: "Message for rate_limited")),
            (503, "stripe_not_configured", .notConfigured("stripe")),
            (503, "owner_not_configured", .notConfigured("owner")),
            (500, "server_error", .server(code: "server_error", message: "Message for server_error", status: 500)),
            (418, "something_new", .server(code: "something_new", message: "Message for something_new", status: 418)),
        ]
        for (status, code, expected) in cases {
            StubURLProtocol.reply { _ in .json(status, #"{"error":{"code":"\#(code)","message":"Message for \#(code)"}}"#) }
            await assertThrows(expected) { try await self.client.book(IzzyAPI.NewAppointment(
                target: .anyBarber(serviceId: "haircut"), start: utc(2026, 11, 2, 18), customer: IzzyAPI.NewCustomer(name: "T", phone: "+14425550123")
            ), token: .generate()) }
        }
        // The code wins over the status.
        StubURLProtocol.reply { _ in .json(400, #"{"error":{"code":"slot_taken","message":"x"}}"#) }
        await assertThrows(.slotTaken) { try await self.client.health() }
    }

    func testErrorsWithoutTheEnvelope() async {
        let cases: [(Reply, APIError)] = [
            (Reply(status: 401, headers: ["Content-Type": "text/html"], body: Data("<h1>Unauthorized</h1>".utf8)), .unauthorized),
            (Reply(status: 429, body: Data()), .rateLimited(message: "")),
            (Reply(status: 404, body: Data("Not found".utf8)), .server(code: "not_found", message: "", status: 404)),
            (Reply(status: 413, body: Data("Request Entity Too Large".utf8)),
             .server(code: "invalid_request", message: "That photo is too big to upload. Pick a smaller one, or take it again.", status: 413)),
            (Reply(status: 400, body: Data(#"{"message":"bad"}"#.utf8)), .server(code: "invalid_request", message: "", status: 400)),
            (Reply(status: 500, body: Data("A server error has occurred".utf8)), .server(code: "server_error", message: "", status: 500)),
            (Reply(status: 504, body: Data(#"{"error":"FUNCTION_INVOCATION_TIMEOUT"}"#.utf8)), .server(code: "server_error", message: "", status: 504)),
            (Reply(status: 308, headers: ["Location": "https://elsewhere.test/"]), .server(code: "server_error", message: "", status: 308)),
        ]
        for (reply, expected) in cases {
            StubURLProtocol.reply { _ in reply }
            await assertThrows(expected) { try await self.client.health() }
        }
    }

    /// The server's own rate_limited example (a number with 3 upcoming appointments) reaches the
    /// app with its message, which says what helps.
    func testTheServersRateLimitMessageIsKept() async throws {
        let url = TestPaths.serverFixtures.appendingPathComponent("errors/rate_limited.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No server contract fixtures at \(url.path) yet; the server's tests write them.")
        }
        let envelope = try IzzyAPI.makeDecoder().decode(IzzyAPI.ErrorEnvelope.self, from: data)
        XCTAssertTrue(envelope.error.message.contains("Cancel one"), envelope.error.message)
        StubURLProtocol.reply { _ in Reply(status: 429, headers: ["Content-Type": "application/json"], body: data) }
        await assertThrows(.rateLimited(message: envelope.error.message)) {
            try await self.client.book(IzzyAPI.NewAppointment(
                target: .anyBarber(serviceId: "haircut"), start: utc(2026, 11, 2, 18), customer: IzzyAPI.NewCustomer(name: "T", phone: "+14425550123")
            ), token: .generate())
        }
    }

    func testRunawayErrorMessagesAreCut() async throws {
        let long = String(repeating: "a", count: 2_000)
        StubURLProtocol.reply { _ in .json(500, #"{"error":{"code":"server_error","message":"\#(long)"}}"#) }
        await assertThrows(.server(code: "server_error", message: String(repeating: "a", count: 300), status: 500)) { try await self.client.health() }
    }

    func testConnectionProblemsMeanOffline() async {
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                                    .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed] {
            StubURLProtocol.reply { _ in .failure(code) }
            await assertThrows(.offline) { try await self.client.reviews() }
        }
        for code: URLError.Code in [.secureConnectionFailed, .serverCertificateUntrusted, .badServerResponse] {
            StubURLProtocol.reply { _ in .failure(code) }
            await assertThrows(.server(code: "network_error", message: "", status: 0)) { try await self.client.reviews() }
        }
    }

    func testCancellationIsNotAnAPIError() async {
        StubURLProtocol.reply { _ in .failure(.cancelled) }
        do {
            _ = try await client.products()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertTrue(APIError.fromTransport(CancellationError()) is CancellationError)
        XCTAssertEqual(APIError.fromTransport(NSError(domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue)) as? APIError, .offline)
        XCTAssertEqual(APIError.fromTransport(NSError(domain: "Other", code: 1)) as? APIError, .server(code: "network_error", message: "", status: 0))
        XCTAssertEqual(APIError.fromTransport(APIError.rateLimited(message: "x")) as? APIError, .rateLimited(message: "x"))
    }

    func testResponsesThatDontMatchTheContract() async throws {
        StubURLProtocol.reply { _ in .json(200, #"{"ok":true}"#) }
        await assertThrows(.decoding("response.version is missing")) { try await self.client.health() }

        StubURLProtocol.reply { _ in .json(200, "<html>Hello</html>") }
        do {
            _ = try await client.health()
            XCTFail("Expected a decoding error")
        } catch let APIError.decoding(text) {
            XCTAssertFalse(text.isEmpty)
        }

        StubURLProtocol.reply { _ in .json(200, "") }
        do {
            _ = try await client.reviews()
            XCTFail("Expected a decoding error")
        } catch APIError.decoding {
            // Expected.
        }

        StubURLProtocol.reply { _ in .fixture("appointment.json") }
        let wrongStatus = String(decoding: try kitFixture("appointment.json"), as: UTF8.self)
            .replacingOccurrences(of: #""status": "cancelled""#, with: #""status": "pending""#)
        StubURLProtocol.reply { _ in .json(200, wrongStatus) }
        do {
            _ = try await client.appointment(id: "a", manageToken: "t")
            XCTFail("Expected a decoding error")
        } catch let APIError.decoding(text) {
            XCTAssertTrue(text.hasPrefix("response.appointment.status"), text)
        }
    }

    func testDeleteAccepts204And200() async throws {
        StubURLProtocol.reply { _ in Reply(status: 204, headers: [:]) }
        try await client.deleteProduct(id: "p1")
        StubURLProtocol.reply { _ in .json(200, "{}") }
        try await client.deleteProduct(id: "p1")
        StubURLProtocol.reply { _ in .json(404, #"{"error":{"code":"not_found","message":"That product is gone."}}"#) }
        await assertThrows(.server(code: "not_found", message: "That product is gone.", status: 404)) { try await self.client.deleteProduct(id: "p1") }
    }

    // MARK: Base URL and request details

    func testBaseURLsWithAPathAndTrailingSlashes() async throws {
        StubURLProtocol.reply { _ in .fixture("health.json") }
        _ = try await IzzyAPIClient(baseURL: URL(string: "https://api.test/v4//")!, session: StubURLProtocol.session()).health()
        XCTAssertEqual(try only().request.url?.absoluteString, "https://api.test/v4/api/health")

        StubURLProtocol.reply { _ in .fixture("health.json") }
        _ = try await IzzyAPIClient(baseURL: URL(string: "http://localhost:3000/?x=1#top")!, session: StubURLProtocol.session()).health()
        XCTAssertEqual(try only().request.url?.absoluteString, "http://localhost:3000/api/health")
    }

    func testPlainHTTPOnlyForThisComputer() async throws {
        for text in ["http://localhost:3000", "http://127.0.0.1:3000", "http://[::1]:3000", "HTTP://LOCALHOST"] {
            StubURLProtocol.reply { _ in .fixture("owner-me.json") }
            _ = try await IzzyAPIClient(baseURL: URL(string: text)!, session: StubURLProtocol.session(), ownerKey: ownerKey).ownerStatus()
            XCTAssertEqual(try only().header("Authorization"), "Bearer " + ownerKey, text)
        }
        // Anywhere else, plain http could be overheard: nothing is sent, not even public calls.
        for text in ["http://izzy-clipz-api.vercel.app", "http://192.168.1.20:3000", "http://localhost.evil.test"] {
            StubURLProtocol.reply { _ in .fixture("health.json") }
            let insecure = IzzyAPIClient(baseURL: URL(string: text)!, session: StubURLProtocol.session(), ownerKey: ownerKey)
            await assertThrows(.notConfigured("server")) { try await insecure.ownerStatus() }
            await assertThrows(.notConfigured("server")) { try await insecure.health() }
            XCTAssertEqual(StubURLProtocol.sent.count, 0, text)
        }
    }

    func testTheDefaultSessionKeepsNothing() {
        let configuration = IzzyAPIClient.defaultSession.configuration
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(IzzyAPIClient(baseURL: baseURL).session === IzzyAPIClient.defaultSession)
    }

    func testUnusableBaseURLs() async {
        for text in ["ftp://api.test", "api.test", "file:///tmp/api", "https:///api"] {
            guard let url = URL(string: text) else { continue }
            let broken = IzzyAPIClient(baseURL: url, session: StubURLProtocol.session())
            await assertThrows(.notConfigured("server")) { try await broken.health() }
        }
        XCTAssertEqual(StubURLProtocol.sent.count, 0)
    }

    func testRequestsSkipCachesAndCookies() throws {
        let request = try IzzyAPI.Endpoints.availability(
            IzzyAPI.AvailabilityQuery(target: .anyBarber(serviceId: "haircut"), from: LocalDate("2026-11-02")!)
        ).urlRequest(baseURL: baseURL, ownerKey: nil)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testRedirectsAreRefused() {
        final class Box: @unchecked Sendable { var result: URLRequest?? }
        let box = Box()
        let delegate: URLSessionTaskDelegate = RedirectRefuser.shared
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://api.test/api/owner/me")!
        let task = session.dataTask(with: original)
        let response = HTTPURLResponse(url: original, statusCode: 308, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://elsewhere.test/"])!
        let next = URLRequest(url: URL(string: "https://elsewhere.test/")!)
        #if canImport(FoundationNetworking)
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: next) { box.result = .some($0) }
        #else
        delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: next) { box.result = .some($0) }
        #endif
        // Linux's default implementation would answer with `next`, so this
        // also proves the method above is the one the protocol calls.
        guard case .some(let answer) = box.result else { return XCTFail("the refuser didn't answer") }
        XCTAssertNil(answer, "the redirect is turned down")
    }
}
