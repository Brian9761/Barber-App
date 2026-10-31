import XCTest
@testable import IzzyClipzKit

/// The manage tokens the app makes for its bookings: the server's own format, from a secure
/// random source, and never the same twice.
final class ManageTokenTests: XCTestCase {
    /// The 32 bytes a token stands for, decoded with Foundation's own base64.
    private func bytes(of token: IzzyAPI.ManageToken) -> [UInt8]? {
        let base64 = token.rawValue.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="
        return Data(base64Encoded: base64).map(Array.init)
    }

    func testGeneratedTokensHaveTheServersFormat() throws {
        for _ in 0..<500 {
            let token = IzzyAPI.ManageToken.generate()
            XCTAssertEqual(token.rawValue.count, 43)
            XCTAssertTrue(token.rawValue.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0)
            }, token.rawValue)
            XCTAssertFalse(token.rawValue.contains("="))
            XCTAssertEqual(try XCTUnwrap(bytes(of: token)).count, 32)
            // It reads back as a token, so the app can keep it and the server takes it.
            XCTAssertEqual(IzzyAPI.ManageToken(rawValue: token.rawValue), token)
        }
    }

    func testGeneratedTokensAreNeverTheSame() {
        let tokens = (0..<2_000).map { _ in IzzyAPI.ManageToken.generate() }
        XCTAssertEqual(Set(tokens).count, tokens.count)
        // And look random: across them, every one of the 64 characters turns up.
        XCTAssertEqual(Set(tokens.flatMap { $0.rawValue.dropLast() }).count, 64)
    }

    /// The bytes come from the generator, all 32 of them, in order.
    func testBytesComeFromTheGenerator() throws {
        var zeros = FixedGenerator(words: [0])
        XCTAssertEqual(IzzyAPI.ManageToken.generate(using: &zeros).rawValue, String(repeating: "A", count: 43))

        var ones = FixedGenerator(words: [.max])
        XCTAssertEqual(IzzyAPI.ManageToken.generate(using: &ones).rawValue, String(repeating: "_", count: 42) + "8")

        var counting = FixedGenerator(words: [0x0706_0504_0302_0100, 0x0F0E_0D0C_0B0A_0908, 0x1716_1514_1312_1110, 0x1F1E_1D1C_1B1A_1918])
        let token = IzzyAPI.ManageToken.generate(using: &counting)
        XCTAssertEqual(try XCTUnwrap(bytes(of: token)), Array(0..<32))
        XCTAssertEqual(token.rawValue, "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        XCTAssertEqual(counting.calls, 4, "Four 64-bit words make 32 bytes")
    }

    func testOnlyExactlyTheServersFormatIsAToken() {
        let good = IzzyAPI.ManageToken.generate().rawValue
        let head = String(good.dropLast())
        let as42 = String(repeating: "A", count: 42)
        var bad: [String] = ["", "short", head]
        bad.append(good + "A")
        bad.append(head + "+")
        bad.append(head + "/")
        bad.append(head + "=")
        bad.append(head + "é")
        bad.append(" " + String(good.dropFirst()))
        // 43 base64url characters that no 32 bytes encode to: the last one's unused bits are set.
        bad.append(as42 + "B")
        bad.append(as42 + "_")
        // The server's test fixtures' stand-in tokens aren't real ones either.
        bad.append("fixture-manage-token-0001xxxxxxxxxxxxxxxxx")
        for text in bad {
            XCTAssertNil(IzzyAPI.ManageToken(rawValue: text), text)
        }
        let ok: [String] = [as42 + "A", as42 + "w", String(repeating: "-", count: 42) + "0"]
        for text in ok {
            XCTAssertNotNil(IzzyAPI.ManageToken(rawValue: text), text)
        }
    }

    func testCodesAsAPlainStringAndRejectsBadOnes() throws {
        let token = IzzyAPI.ManageToken.generate()
        let data = try JSONEncoder().encode([token])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"[""# + token.rawValue + #""]"#)
        XCTAssertEqual(try JSONDecoder().decode([IzzyAPI.ManageToken].self, from: data), [token])
        XCTAssertThrowsError(try JSONDecoder().decode([IzzyAPI.ManageToken].self, from: Data(#"["short"]"#.utf8)))
    }

    func testItsNeverPrinted() {
        let token = IzzyAPI.ManageToken.generate()
        XCTAssertFalse("\(token)".contains(token.rawValue))
        XCTAssertFalse(String(describing: token).contains(token.rawValue))
    }

    func testTheBookingEndpointSendsIt() throws {
        let token = IzzyAPI.ManageToken.generate()
        let endpoint = try IzzyAPI.Endpoints.book(IzzyAPI.NewAppointment(
            target: .anyBarber(serviceId: "haircut"),
            start: Date(timeIntervalSince1970: 1_793_210_400),
            customer: IzzyAPI.NewCustomer(name: "Test", phone: "4425550123")
        ), token: token)
        XCTAssertEqual(endpoint.credential, .manageToken(token.rawValue))
        let request = try endpoint.urlRequest(baseURL: URL(string: "https://api.test")!, ownerKey: "owner-key-that-must-not-be-sent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Manage-Token"), token.rawValue)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.httpMethod, "POST")
    }
}

/// Hands out the same words in a loop, and counts how many it gave.
private struct FixedGenerator: RandomNumberGenerator {
    let words: [UInt64]
    private(set) var calls = 0

    init(words: [UInt64]) {
        self.words = words
    }

    mutating func next() -> UInt64 {
        defer { calls += 1 }
        return words[calls % words.count]
    }
}
