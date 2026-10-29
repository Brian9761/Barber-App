import UIKit
import XCTest
@testable import IzzyClipz

/// Serves canned responses instead of going to the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            StubURLProtocol.requests.append(url)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: StubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class BravoStoreTests: XCTestCase {
    private let catalog = AppData.products

    override func setUp() {
        super.setUp()
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = Data()
        StubURLProtocol.requests = []
    }

    private func makeStore() -> BravoStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BravoStore(catalog: catalog, session: URLSession(configuration: configuration))
    }

    private func product(_ id: String) throws -> Product {
        try XCTUnwrap(catalog.product(withID: id))
    }

    private func feed(_ products: [(handle: String, price: String, available: Bool)]) -> Data {
        let items = products.map { product in
            """
            {"handle": "\(product.handle)", "title": "x", "variants": [{"price": "\(product.price)", "available": \(product.available)}]}
            """
        }
        return Data("{\"products\": [\(items.joined(separator: ","))]}".utf8)
    }

    func testBundledPricesUntilTheStoreAnswers() throws {
        let store = makeStore()
        let gel = try product("blue-bravo-hair-gel-16oz")
        XCTAssertEqual(store.price(for: gel), gel.price)
        XCTAssertFalse(store.isSoldOut(gel))
    }

    func testLivePricesReplaceBundledOnes() async throws {
        StubURLProtocol.body = feed([
            ("blue-bravo-hair-gel-16oz", "18.49", true),
            ("bravo-matte-clay", "17.99", false),
            ("something-else", "5.00", true),
        ])
        let store = makeStore()
        await store.refresh()

        XCTAssertEqual(StubURLProtocol.requests.first?.host, "bravohairgel.com")
        XCTAssertEqual(store.price(for: try product("blue-bravo-hair-gel-16oz")).cents, 1849)
        XCTAssertTrue(store.isSoldOut(try product("bravo-matte-clay")))
        XCTAssertNil(store.livePrices["something-else"], "Products the app doesn't show are ignored")
        // Products missing from the feed keep their bundled price.
        let onyx = try product("bravo-onyx-hair-gel")
        XCTAssertEqual(store.price(for: onyx), onyx.price)
    }

    func testAServerErrorKeepsBundledPrices() async throws {
        StubURLProtocol.statusCode = 500
        StubURLProtocol.body = feed([("blue-bravo-hair-gel-16oz", "99.00", true)])
        let store = makeStore()
        await store.refresh()
        XCTAssertTrue(store.livePrices.isEmpty)
        let gel = try product("blue-bravo-hair-gel-16oz")
        XCTAssertEqual(store.price(for: gel), gel.price)
    }

    func testGarbageKeepsBundledPrices() async {
        StubURLProtocol.body = Data("<html>Maintenance</html>".utf8)
        let store = makeStore()
        await store.refresh()
        XCTAssertTrue(store.livePrices.isEmpty)
    }

    func testChecksAtMostOnceAnHour() async {
        StubURLProtocol.body = feed([("blue-bravo-hair-gel-16oz", "17.99", true)])
        let store = makeStore()
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testEveryProductHasABundledPriceAndImage() {
        for product in catalog.products {
            XCTAssertGreaterThan(product.price.cents, 0, product.id)
            XCTAssertNotNil(UIImage(named: product.imageName), product.imageName)
        }
    }
}
