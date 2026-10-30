import XCTest
@testable import IzzyClipz

@MainActor
final class BagStoreTests: XCTestCase {
    private let catalog = AppData.products

    override func setUp() {
        super.setUp()
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = Data()
        StubURLProtocol.requests = []
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "BagStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Bravo before its feed has answered: bundled prices and variants.
    private func bundledBravo() -> BravoStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BravoStore(catalog: catalog, session: URLSession(configuration: configuration))
    }

    /// Bravo after its feed answered with these variants, one per product.
    private func liveBravo(_ variants: [(handle: String, id: Int64?, price: String, available: Bool)]) async -> BravoStore {
        let items = variants.map { variant in
            let id = variant.id.map { "\"id\": \($0), " } ?? ""
            return """
            {"handle": "\(variant.handle)", "variants": [{\(id)"price": "\(variant.price)", "available": \(variant.available)}]}
            """
        }
        StubURLProtocol.body = Data("{\"products\": [\(items.joined(separator: ","))]}".utf8)
        let bravo = bundledBravo()
        await bravo.refresh()
        return bravo
    }

    private func product(_ id: String) throws -> Product {
        try XCTUnwrap(catalog.product(withID: id))
    }

    private func savedBag(in defaults: UserDefaults) throws -> Bag {
        let data = try XCTUnwrap(defaults.data(forKey: BagStore.storageKey))
        return try JSONDecoder().decode(Bag.self, from: data)
    }

    // MARK: Contents

    func testStartsEmpty() {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        XCTAssertTrue(bag.isEmpty)
        XCTAssertEqual(bag.count, 0)
        XCTAssertEqual(bag.lines, [])
        XCTAssertEqual(bag.subtotal, Price(cents: 0))
        XCTAssertNil(bag.checkoutURL)
        XCTAssertEqual(bag.freeShippingThreshold, Price(cents: 6400))
        XCTAssertEqual(bag.amountToFreeShipping.label, "$64")
        XCTAssertEqual(bag.freeShippingProgress, 0)
        XCTAssertFalse(bag.reachesFreeShipping)
    }

    func testAddingShowsLinesInOrderAtBundledPrices() throws {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        let gel = try product("blue-bravo-hair-gel-16oz")
        let clay = try product("bravo-matte-clay")

        XCTAssertTrue(bag.add(gel, quantity: 2))
        XCTAssertTrue(bag.add(clay))
        XCTAssertTrue(bag.add(gel))

        XCTAssertEqual(bag.count, 4)
        XCTAssertEqual(bag.quantity(of: gel), 3)
        XCTAssertEqual(bag.lines.map(\.product.id), ["blue-bravo-hair-gel-16oz", "bravo-matte-clay"])
        XCTAssertEqual(bag.lines.map(\.quantity), [3, 1])
        XCTAssertEqual(bag.lines.first?.unitPrice, gel.price)
        XCTAssertEqual(bag.lines.first?.total.label, "$53.97")
        XCTAssertEqual(bag.lines.map(\.isSoldOut), [false, false])
        XCTAssertEqual(bag.subtotal.label, "$71.96")
    }

    func testChangingAndRemovingLines() throws {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        let gel = try product("blue-bravo-hair-gel-16oz")
        let clay = try product("bravo-matte-clay")
        bag.add(gel)
        bag.add(clay)

        bag.setQuantity(4, of: gel)
        XCTAssertEqual(bag.quantity(of: gel), 4)
        bag.setQuantity(25, of: gel)
        XCTAssertEqual(bag.quantity(of: gel), 10)
        bag.setQuantity(0, of: gel)
        XCTAssertEqual(bag.lines.map(\.product.id), ["bravo-matte-clay"])

        bag.remove(clay)
        XCTAssertTrue(bag.isEmpty)
    }

    func testAddingStopsAtTheLimits() throws {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        let clay = try product("bravo-matte-clay")
        XCTAssertTrue(bag.canAdd(clay))
        XCTAssertTrue(bag.add(clay, quantity: 10))
        XCTAssertFalse(bag.canAdd(clay))
        XCTAssertFalse(bag.add(clay))
        XCTAssertEqual(bag.quantity(of: clay), 10)
        XCTAssertFalse(bag.add(try product("bravo-blue-pomade"), quantity: 0))
    }

    func testProductsBravoDoesNotSellHereCannotBeAdded() {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        let cape = Product(
            id: "bravo-cutting-cape", variantID: 45165054099633, name: "Cutting Cape", category: .grooming,
            price: Price(cents: 2099), summary: "S", highlights: ["1", "2", "3"]
        )
        XCTAssertFalse(bag.canAdd(cape))
        XCTAssertFalse(bag.add(cape))
        XCTAssertTrue(bag.isEmpty)
    }

    // MARK: Saving

    func testTheBagIsRememberedBetweenLaunches() throws {
        let defaults = makeDefaults()
        let gel = try product("white-bravo-hair-gel-4oz")
        let balm = try product("bravo-chapstick-3-pack")
        let first = BagStore(bravo: bundledBravo(), defaults: defaults)
        first.add(gel, quantity: 2)
        first.add(balm)
        first.setQuantity(3, of: balm)

        let second = BagStore(bravo: bundledBravo(), defaults: defaults)
        XCTAssertEqual(second.bag, first.bag)
        XCTAssertEqual(second.lines.map(\.product.id), ["white-bravo-hair-gel-4oz", "bravo-chapstick-3-pack"])
        XCTAssertEqual(second.count, 5)
        XCTAssertEqual(try savedBag(in: defaults), first.bag)

        second.remove(gel)
        XCTAssertEqual(BagStore(bravo: bundledBravo(), defaults: defaults).lines.map(\.product.id), ["bravo-chapstick-3-pack"])

        second.removeAll()
        XCTAssertTrue(BagStore(bravo: bundledBravo(), defaults: defaults).isEmpty)
    }

    func testProductsThatAreGoneAreDroppedOnLoad() throws {
        let defaults = makeDefaults()
        let saved = Bag(lines: [
            Bag.Line(productID: "bravo-discontinued-wax", quantity: 2),
            Bag.Line(productID: "bravo-matte-clay", quantity: 1),
        ])
        defaults.set(try JSONEncoder().encode(saved), forKey: BagStore.storageKey)

        let bag = BagStore(bravo: bundledBravo(), defaults: defaults)
        XCTAssertEqual(bag.lines.map(\.product.id), ["bravo-matte-clay"])
        XCTAssertEqual(bag.count, 1)
        XCTAssertEqual(try savedBag(in: defaults).lines.map(\.productID), ["bravo-matte-clay"], "The cleaned-up bag is saved")
    }

    func testAnUnreadableSaveStartsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: BagStore.storageKey)
        XCTAssertTrue(BagStore(bravo: bundledBravo(), defaults: defaults).isEmpty)
    }

    // MARK: Sold out

    func testSoldOutProductsCannotBeAdded() async throws {
        let bravo = await liveBravo([("bravo-matte-clay", 43628496945329, "17.99", false)])
        let defaults = makeDefaults()
        let bag = BagStore(bravo: bravo, defaults: defaults)
        let clay = try product("bravo-matte-clay")

        XCTAssertFalse(bag.canAdd(clay))
        XCTAssertFalse(bag.add(clay))
        XCTAssertEqual(bag.quantity(of: clay), 0)
        XCTAssertNil(defaults.data(forKey: BagStore.storageKey), "Nothing changed, so nothing was saved")
        // Others are fine.
        XCTAssertTrue(bag.add(try product("bravo-blue-pomade")))
    }

    func testItemsThatSellOutStayButAreNotCheckedOut() async throws {
        let defaults = makeDefaults()
        let saved = Bag(lines: [
            Bag.Line(productID: "bravo-matte-clay", quantity: 2),
            Bag.Line(productID: "blue-bravo-hair-gel-16oz", quantity: 1),
        ])
        defaults.set(try JSONEncoder().encode(saved), forKey: BagStore.storageKey)
        let bravo = await liveBravo([
            ("bravo-matte-clay", 43628496945329, "17.99", false),
            ("blue-bravo-hair-gel-16oz", 44210083561649, "17.99", true),
        ])
        let bag = BagStore(bravo: bravo, defaults: defaults)
        let clay = try product("bravo-matte-clay")

        XCTAssertEqual(bag.lines.map(\.isSoldOut), [true, false])
        XCTAssertEqual(bag.count, 3, "The client's pick stays in the bag")
        XCTAssertEqual(bag.subtotal.label, "$17.99")
        XCTAssertEqual(bag.checkoutURL?.absoluteString, "https://bravohairgel.com/cart/44210083561649:1")

        // It can go down or out, but not up.
        bag.setQuantity(5, of: clay)
        XCTAssertEqual(bag.quantity(of: clay), 2)
        bag.setQuantity(1, of: clay)
        XCTAssertEqual(bag.quantity(of: clay), 1)
        bag.setQuantity(0, of: clay)
        XCTAssertEqual(bag.quantity(of: clay), 0)
    }

    func testNoCheckoutWhenEverythingSoldOut() async throws {
        let defaults = makeDefaults()
        defaults.set(try JSONEncoder().encode(Bag(lines: [Bag.Line(productID: "bravo-matte-clay", quantity: 1)])), forKey: BagStore.storageKey)
        let bravo = await liveBravo([("bravo-matte-clay", nil, "17.99", false)])
        let bag = BagStore(bravo: bravo, defaults: defaults)
        XCTAssertFalse(bag.isEmpty)
        XCTAssertNil(bag.checkoutURL)
        XCTAssertEqual(bag.subtotal, Price(cents: 0))
    }

    // MARK: Checkout

    func testCheckoutUsesBundledVariantsUntilBravoAnswers() throws {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        bag.add(try product("blue-bravo-hair-gel-16oz"), quantity: 2)
        bag.add(try product("bravo-texture-powder"))
        XCTAssertEqual(
            bag.checkoutURL?.absoluteString,
            "https://bravohairgel.com/cart/44210083561649:2,46751008653489:1"
        )
    }

    func testCheckoutUsesLiveVariantsWhenKnown() async throws {
        let bravo = await liveBravo([
            // Bravo re-created this variant since the app was built.
            ("blue-bravo-hair-gel-16oz", 49999999999999, "17.99", true),
            // The feed didn't say which variant: the bundled one is used.
            ("bravo-matte-clay", nil, "17.99", true),
        ])
        let bag = BagStore(bravo: bravo, defaults: makeDefaults())
        bag.add(try product("blue-bravo-hair-gel-16oz"), quantity: 2)
        bag.add(try product("bravo-matte-clay"))
        bag.add(try product("bravo-after-shave"))
        XCTAssertEqual(
            bag.checkoutURL?.absoluteString,
            "https://bravohairgel.com/cart/49999999999999:2,43628496945329:1,45716306395313:1"
        )
    }

    // MARK: Free shipping

    func testFreeShippingAtBundledPrices() throws {
        let bag = BagStore(bravo: bundledBravo(), defaults: makeDefaults())
        bag.add(try product("blue-bravo-hair-gel-16oz"), quantity: 2) // $35.98
        bag.add(try product("bravo-onyx-hair-gel")) // $19.99
        XCTAssertEqual(bag.subtotal.label, "$55.97")
        XCTAssertEqual(bag.amountToFreeShipping.label, "$8.03")
        XCTAssertEqual(bag.freeShippingProgress, 5597.0 / 6400.0, accuracy: 0.000_001)
        XCTAssertFalse(bag.reachesFreeShipping)

        bag.add(try product("bravo-after-shave")) // $12.99, so $68.96
        XCTAssertEqual(bag.amountToFreeShipping, Price(cents: 0))
        XCTAssertEqual(bag.freeShippingProgress, 1)
        XCTAssertTrue(bag.reachesFreeShipping)
    }

    func testFreeShippingFollowsLivePrices() async throws {
        let bravo = await liveBravo([("blue-bravo-hair-gel-16oz", 44210083561649, "20.00", true)])
        let bag = BagStore(bravo: bravo, defaults: makeDefaults())
        bag.add(try product("blue-bravo-hair-gel-16oz"), quantity: 2) // live: $40.00
        bag.add(try product("bravo-onyx-hair-gel")) // bundled: $19.99
        XCTAssertEqual(bag.lines.first?.unitPrice, Price(cents: 2000))
        XCTAssertEqual(bag.subtotal.label, "$59.99")
        XCTAssertEqual(bag.amountToFreeShipping.label, "$4.01")

        // A few cents short.
        bag.setQuantity(1, of: try product("blue-bravo-hair-gel-16oz")) // $20.00 + $19.99
        bag.add(try product("blue-bravo-hair-gel-4oz"), quantity: 2) // + $23.98 = $63.97
        XCTAssertEqual(bag.amountToFreeShipping.label, "$0.03")
        XCTAssertFalse(bag.reachesFreeShipping)
    }

    func testFreeShippingExactlyAtTheThreshold() async throws {
        // 4 × $16.00 = $64.00
        let bravo = await liveBravo([("bravo-matte-clay", 43628496945329, "16.00", true)])
        let bag = BagStore(bravo: bravo, defaults: makeDefaults())
        bag.add(try product("bravo-matte-clay"), quantity: 4)
        XCTAssertEqual(bag.subtotal.label, "$64")
        XCTAssertEqual(bag.amountToFreeShipping, Price(cents: 0))
        XCTAssertEqual(bag.freeShippingProgress, 1)
        XCTAssertTrue(bag.reachesFreeShipping)
    }
}
