import XCTest
@testable import IzzyClipzKit

/// Every response example, the Kit's and the server's, must decode into the
/// Kit's models and encode back to exactly the same JSON. That catches a
/// renamed or extra field, a missing `null`, a time with fractional seconds
/// or an unknown status on either side.
///
/// The server's examples live in `server/test/fixtures/contract/*.json` (one
/// per response type). The test recognizes each file by its shape, so the
/// file names don't matter.
final class ContractFixtureTests: XCTestCase {
    /// A response type the contract defines.
    struct Kind {
        let name: String
        /// The top-level key only this response has.
        let matches: (JSONValue) -> Bool
        /// Decodes the example and encodes it again.
        let roundTrip: (Data) throws -> Data
    }

    static func kind<T: Codable>(_ type: T.Type, _ name: String, _ matches: @escaping (JSONValue) -> Bool) -> Kind {
        Kind(name: name, matches: matches) { data in
            try IzzyAPI.makeEncoder().encode(try IzzyAPI.makeDecoder().decode(T.self, from: data))
        }
    }

    static func has(_ key: String) -> (JSONValue) -> Bool {
        { $0[key] != nil }
    }

    /// In order: the first match wins.
    static let kinds: [Kind] = [
        kind(IzzyAPI.ErrorEnvelope.self, "error envelope", has("error")),
        kind(IzzyAPI.BookingConfirmation.self, "POST /api/appointments", has("manageToken")),
        kind(IzzyAPI.AppointmentResponse.self, "{ appointment }", has("appointment")),
        kind(IzzyAPI.AppointmentsResponse.self, "{ appointments }", has("appointments")),
        kind(IzzyAPI.AvailabilityResponse.self, "GET /api/availability", has("days")),
        kind(IzzyAPI.ReviewsResponse.self, "GET /api/reviews", has("google")),
        kind(IzzyAPI.ProductsResponse.self, "{ products }", has("products")),
        kind(IzzyAPI.ProductResponse.self, "{ product }", has("product")),
        kind(IzzyAPI.OwnerStatus.self, "GET /api/owner/me", has("stripe")),
        kind(IzzyAPI.Health.self, "GET /api/health", has("version")),
        kind(IzzyAPI.TimeOffListResponse.self, "GET /api/owner/time-off", { if case .array = $0["timeOff"] { return true }; return false }),
        kind(IzzyAPI.TimeOffResponse.self, "POST /api/owner/time-off", has("timeOff")),
        kind(IzzyAPI.ConnectionToken.self, "POST /api/owner/terminal/connection-token", has("secret")),
        kind(IzzyAPI.PaymentIntentCreated.self, "POST /api/owner/payments", has("clientSecret")),
        kind(IzzyAPI.PaymentResponse.self, "{ payment }", has("payment")),
        kind(IzzyAPI.PaymentsResponse.self, "{ payments }", has("payments")),
    ]

    /// Checks every file in `folder`; returns the kinds it covered.
    @discardableResult
    func checkFixtures(in folder: URL, file: StaticString = #filePath, line: UInt = #line) throws -> Set<String> {
        var covered: Set<String> = []
        let files = TestPaths.jsonFiles(in: folder)
        XCTAssertFalse(files.isEmpty, "No fixtures in \(folder.path)", file: file, line: line)
        for url in files {
            let name = url.lastPathComponent
            guard let data = FileManager.default.contents(atPath: url.path) else {
                XCTFail("\(name): can't read it", file: file, line: line)
                continue
            }
            let original: JSONValue
            do {
                original = try JSONValue(data: data)
            } catch {
                XCTFail("\(name): not JSON: \(error)", file: file, line: line)
                continue
            }
            guard let kind = Self.kinds.first(where: { $0.matches(original) }) else {
                XCTFail("\(name): no response type in the contract looks like this (top-level keys \(original.keys.sorted()))", file: file, line: line)
                continue
            }
            covered.insert(kind.name)
            do {
                let reencoded = try JSONValue(data: try kind.roundTrip(data))
                let differences = original.differences(from: reencoded)
                XCTAssertTrue(
                    differences.isEmpty,
                    "\(name) (\(kind.name)) doesn't survive a round trip through the Kit's models. First = the file, second = the Kit:\n"
                        + differences.prefix(20).joined(separator: "\n"),
                    file: file, line: line
                )
            } catch {
                XCTFail("\(name) (\(kind.name)) doesn't decode: \(APIError.describe(error))", file: file, line: line)
            }
        }
        return covered
    }

    func testTheKitsFixturesCoverEveryResponseType() throws {
        let covered = try checkFixtures(in: TestPaths.kitFixtures)
        let missing = Self.kinds.map(\.name).filter { !covered.contains($0) }
        XCTAssertEqual(missing, [], "The Kit has no fixture for these response types")
    }

    func testTheServersFixturesMatchTheKit() throws {
        let folder = TestPaths.serverFixtures
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw XCTSkip("No server contract fixtures at \(folder.path) yet; the server's tests write them.")
        }
        let covered = try checkFixtures(in: folder)
        let missing = Self.kinds.map(\.name).filter { !covered.contains($0) }
        XCTAssertEqual(missing, [], "The server has no contract fixture for these response types")
    }

    /// The checker itself: it must notice drift, not just pass.
    func testTheCheckCatchesDrift() throws {
        let original = try JSONValue(data: try kitFixture("booking-confirmation.json"))
        let kind = try XCTUnwrap(Self.kinds.first { $0.matches(original) })
        XCTAssertEqual(kind.name, "POST /api/appointments")

        func drift(_ from: String, _ to: String) throws -> [String] {
            let text = String(decoding: try kitFixture("booking-confirmation.json"), as: UTF8.self)
            let changed = Data(text.replacingOccurrences(of: from, with: to).utf8)
            XCTAssertNotEqual(changed, try kitFixture("booking-confirmation.json"), "Nothing replaced: \(from)")
            return try JSONValue(data: changed).differences(from: try JSONValue(data: try kind.roundTrip(changed)))
        }
        // Fractional seconds aren't the contract's form.
        XCTAssertEqual(try drift(#""start": "2026-11-02T18:00:00Z""#, #""start": "2026-11-02T18:00:00.000Z""#),
                       [#"$.appointment.start: "2026-11-02T18:00:00.000Z" vs "2026-11-02T18:00:00Z""#])
        // A field the Kit doesn't know.
        XCTAssertEqual(try drift(#""note": null,"#, #""note": null, "tip": 0,"#), ["$.appointment.tip: only in the first (0)"])
        // A missing null.
        XCTAssertEqual(try drift(#""cancelledBy": null,"#, ""), ["$.appointment.cancelledBy: only in the second (null)"])
        // A renamed field fails to decode outright.
        XCTAssertThrowsError(try drift(#""barberName""#, #""barber_name""#))
    }
}
