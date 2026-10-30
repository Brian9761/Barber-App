import XCTest
@testable import IzzyClipzKit

final class BagTests: XCTestCase {
    private let catalog = ProductCatalog.bravo
    private let storeURL = URL(string: "https://bravohairgel.com/")!

    private func bundledPrice(_ id: String) -> Price? {
        catalog.product(withID: id)?.price
    }

    private func bundledVariant(_ id: String) -> Int64? {
        catalog.product(withID: id)?.variantID
    }

    // MARK: Adding

    func testStartsEmpty() {
        let bag = Bag()
        XCTAssertTrue(bag.isEmpty)
        XCTAssertEqual(bag.itemCount, 0)
        XCTAssertEqual(bag.lines, [])
        XCTAssertFalse(bag.isFull)
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 0)
        XCTAssertFalse(bag.contains("bravo-matte-clay"))
    }

    func testAddingKeepsTheOrderItemsWereFirstAdded() {
        var bag = Bag()
        XCTAssertTrue(bag.add("bravo-matte-clay"))
        XCTAssertTrue(bag.add("blue-bravo-hair-gel-16oz", quantity: 2))
        XCTAssertTrue(bag.add("bravo-after-shave"))
        XCTAssertTrue(bag.add("bravo-matte-clay"))
        XCTAssertEqual(bag.lines, [
            Bag.Line(productID: "bravo-matte-clay", quantity: 2),
            Bag.Line(productID: "blue-bravo-hair-gel-16oz", quantity: 2),
            Bag.Line(productID: "bravo-after-shave", quantity: 1),
        ])
        XCTAssertEqual(bag.itemCount, 5)
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 2)
        XCTAssertTrue(bag.contains("bravo-after-shave"))
        XCTAssertEqual(bag.lines.map(\.id), ["bravo-matte-clay", "blue-bravo-hair-gel-16oz", "bravo-after-shave"])
    }

    func testAddingClampsToTen() {
        var bag = Bag()
        XCTAssertTrue(bag.add("bravo-matte-clay", quantity: 8))
        XCTAssertTrue(bag.add("bravo-matte-clay", quantity: 5))
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 10)
        XCTAssertFalse(bag.add("bravo-matte-clay"), "Nothing more fits on the line")
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 10)

        XCTAssertTrue(bag.add("bravo-blue-pomade", quantity: 25))
        XCTAssertEqual(bag.quantity(of: "bravo-blue-pomade"), 10)
        XCTAssertFalse(bag.add("bravo-blue-pomade", quantity: .max), "Huge numbers don't overflow")
        XCTAssertEqual(bag.quantity(of: "bravo-blue-pomade"), 10)
    }

    func testAddingNothingAddsNothing() {
        var bag = Bag()
        XCTAssertFalse(bag.add("bravo-matte-clay", quantity: 0))
        XCTAssertFalse(bag.add("bravo-matte-clay", quantity: -3))
        XCTAssertFalse(bag.add("bravo-matte-clay", quantity: .min))
        XCTAssertFalse(bag.add(""))
        XCTAssertTrue(bag.isEmpty)
    }

    func testHoldsAtMostTenDifferentProducts() {
        var bag = Bag()
        for index in 1...10 {
            XCTAssertTrue(bag.add("product-\(index)"))
        }
        XCTAssertTrue(bag.isFull)
        XCTAssertFalse(bag.add("product-11"))
        XCTAssertFalse(bag.contains("product-11"))
        // Products already in a full bag can still go up.
        XCTAssertTrue(bag.add("product-3", quantity: 2))
        XCTAssertEqual(bag.quantity(of: "product-3"), 3)
        XCTAssertEqual(bag.lines.count, 10)

        bag.remove("product-1")
        XCTAssertFalse(bag.isFull)
        XCTAssertTrue(bag.add("product-11"))
        XCTAssertEqual(bag.lines.last?.productID, "product-11")
    }

    // MARK: Changing

    func testSettingAQuantity() {
        var bag = Bag()
        bag.add("bravo-matte-clay")
        bag.add("bravo-after-shave")

        bag.setQuantity(4, for: "bravo-matte-clay")
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 4)
        bag.setQuantity(11, for: "bravo-matte-clay")
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 10)
        bag.setQuantity(1, for: "bravo-matte-clay")
        XCTAssertEqual(bag.quantity(of: "bravo-matte-clay"), 1)
        XCTAssertEqual(bag.lines.map(\.productID), ["bravo-matte-clay", "bravo-after-shave"], "Changing a quantity keeps the line's place")

        bag.setQuantity(0, for: "bravo-matte-clay")
        XCTAssertFalse(bag.contains("bravo-matte-clay"))
        bag.setQuantity(-1, for: "bravo-after-shave")
        XCTAssertTrue(bag.isEmpty)
    }

    func testSettingAQuantityDoesNotAddAProduct() {
        var bag = Bag()
        bag.setQuantity(3, for: "bravo-matte-clay")
        XCTAssertTrue(bag.isEmpty)
    }

    func testRemoving() {
        var bag = Bag()
        bag.add("bravo-matte-clay", quantity: 3)
        bag.add("bravo-after-shave")
        bag.add("bravo-blue-pomade")

        bag.remove("bravo-matte-clay")
        XCTAssertEqual(bag.lines.map(\.productID), ["bravo-after-shave", "bravo-blue-pomade"])
        bag.remove("not-in-the-bag")
        XCTAssertEqual(bag.lines.count, 2)

        bag.removeAll { $0.productID == "bravo-blue-pomade" }
        XCTAssertEqual(bag.lines.map(\.productID), ["bravo-after-shave"])

        bag.removeAll()
        XCTAssertTrue(bag.isEmpty)
        XCTAssertEqual(bag.itemCount, 0)
    }

    func testMakingABagFromLinesMakesItValid() {
        let bag = Bag(lines: [
            Bag.Line(productID: "a", quantity: 2),
            Bag.Line(productID: "b", quantity: 0),
            Bag.Line(productID: "c", quantity: 40),
            Bag.Line(productID: "a", quantity: 3),
            Bag.Line(productID: "", quantity: 1),
            Bag.Line(productID: "d", quantity: -2),
            Bag.Line(productID: "a", quantity: 9),
            Bag.Line(productID: "e", quantity: .max),
            Bag.Line(productID: "e", quantity: .max),
        ])
        XCTAssertEqual(bag.lines, [
            Bag.Line(productID: "a", quantity: 10),
            Bag.Line(productID: "c", quantity: 10),
            Bag.Line(productID: "e", quantity: 10),
        ])

        let tooMany = Bag(lines: (1...12).map { Bag.Line(productID: "p\($0)", quantity: 1) } + [Bag.Line(productID: "p2", quantity: 1)])
        XCTAssertEqual(tooMany.lines.map(\.productID), (1...10).map { "p\($0)" }, "The first ten products are kept")
        XCTAssertEqual(tooMany.quantity(of: "p2"), 2)
    }

    // MARK: Totals

    func testSubtotal() {
        var bag = Bag()
        bag.add("blue-bravo-hair-gel-16oz", quantity: 2) // 2 × $17.99
        bag.add("bravo-chapstick-3-pack") // $2.99
        let subtotal = bag.subtotal(price: bundledPrice)
        XCTAssertEqual(subtotal.cents, 3897)
        XCTAssertEqual(subtotal.label, "$38.97")
        XCTAssertEqual(subtotal.kind, .fixed)
    }

    func testSubtotalSkipsUnknownProducts() {
        var bag = Bag()
        bag.add("bravo-matte-clay")
        bag.add("bravo-cutting-cape", quantity: 3)
        XCTAssertEqual(bag.subtotal(price: bundledPrice).cents, 1799)
        XCTAssertEqual(bag.subtotal(price: { _ in nil }).cents, 0)
        XCTAssertEqual(Bag().subtotal(price: bundledPrice).label, "$0")
    }

    func testFreeShippingProgress() {
        let threshold = catalog.sponsor.freeShippingThreshold
        var bag = Bag()
        XCTAssertEqual(bag.amountToFreeShipping(threshold: threshold, price: bundledPrice), threshold)
        XCTAssertEqual(bag.freeShippingProgress(threshold: threshold, price: bundledPrice), 0)
        XCTAssertFalse(bag.reachesFreeShipping(threshold: threshold, price: bundledPrice))

        bag.add("blue-bravo-hair-gel-16oz", quantity: 2) // $35.98
        bag.add("bravo-onyx-hair-gel") // $19.99, so $55.97
        XCTAssertEqual(bag.amountToFreeShipping(threshold: threshold, price: bundledPrice).label, "$8.03")
        XCTAssertEqual(bag.freeShippingProgress(threshold: threshold, price: bundledPrice), 5597.0 / 6400.0, accuracy: 0.000_001)
        XCTAssertFalse(bag.reachesFreeShipping(threshold: threshold, price: bundledPrice))

        bag.add("bravo-matte-clay") // $73.96
        XCTAssertEqual(bag.amountToFreeShipping(threshold: threshold, price: bundledPrice), Price(cents: 0))
        XCTAssertEqual(bag.freeShippingProgress(threshold: threshold, price: bundledPrice), 1, "Never past the end of the meter")
        XCTAssertTrue(bag.reachesFreeShipping(threshold: threshold, price: bundledPrice))
    }

    func testFreeShippingThresholdExactlyMet() {
        var bag = Bag()
        bag.add("a", quantity: 4)
        let price: (String) -> Price? = { _ in Price(cents: 1600) } // 4 × $16 = $64
        let threshold = Price(cents: 6400)
        XCTAssertEqual(bag.amountToFreeShipping(threshold: threshold, price: price).cents, 0)
        XCTAssertEqual(bag.freeShippingProgress(threshold: threshold, price: price), 1)
        XCTAssertTrue(bag.reachesFreeShipping(threshold: threshold, price: price))

        // A cent short.
        let short: (String) -> Price? = { _ in Price(cents: 1599) }
        bag.setQuantity(4, for: "a")
        XCTAssertEqual(bag.amountToFreeShipping(threshold: Price(cents: 6397), price: short).cents, 1)
        XCTAssertFalse(bag.reachesFreeShipping(threshold: Price(cents: 6397), price: short))
    }

    func testNoThresholdMeansTheMeterIsFull() {
        var bag = Bag()
        bag.add("bravo-matte-clay")
        XCTAssertEqual(bag.freeShippingProgress(threshold: Price(cents: 0), price: bundledPrice), 1)
        XCTAssertEqual(bag.amountToFreeShipping(threshold: Price(cents: 0), price: bundledPrice).cents, 0)
    }

    // MARK: Checkout

    func testCheckoutLinkListsVariantsAndQuantitiesInOrder() throws {
        var bag = Bag()
        bag.add("blue-bravo-hair-gel-16oz", quantity: 2)
        bag.add("bravo-matte-clay")
        bag.add("bravo-texture-powder", quantity: 3)
        let url = try XCTUnwrap(bag.checkoutURL(storeURL: storeURL, variantID: bundledVariant))
        XCTAssertEqual(
            url.absoluteString,
            "https://bravohairgel.com/cart/44210083561649:2,43628496945329:1,46751008653489:3"
        )
        XCTAssertEqual(url.host, "bravohairgel.com")
        XCTAssertNil(url.query)
    }

    func testCheckoutLinkForOneItem() {
        var bag = Bag()
        bag.add("bravo-chapstick-3-pack")
        XCTAssertEqual(
            bag.checkoutURL(storeURL: storeURL, variantID: bundledVariant)?.absoluteString,
            "https://bravohairgel.com/cart/46396389916849:1"
        )
    }

    func testCheckoutLinkSkipsProductsWithoutAVariant() {
        var bag = Bag()
        bag.add("gone-product", quantity: 2)
        bag.add("bravo-after-shave")
        bag.add("zero-variant")
        let variant: (String) -> Int64? = { id in id == "zero-variant" ? 0 : self.bundledVariant(id) }
        XCTAssertEqual(
            bag.checkoutURL(storeURL: storeURL, variantID: variant)?.absoluteString,
            "https://bravohairgel.com/cart/45716306395313:1"
        )
    }

    func testNoCheckoutLinkWithoutItems() {
        XCTAssertNil(Bag().checkoutURL(storeURL: storeURL, variantID: bundledVariant))

        var unknown = Bag()
        unknown.add("bravo-cutting-cape")
        XCTAssertNil(unknown.checkoutURL(storeURL: storeURL, variantID: bundledVariant), "No line resolves")
    }

    func testCheckoutLinkUsesOnlyTheStoresHost() {
        var bag = Bag()
        bag.add("bravo-matte-clay")
        let tracked = URL(string: "https://bravohairgel.com/collections/all?utm_source=x#top")!
        XCTAssertEqual(
            bag.checkoutURL(storeURL: tracked, variantID: bundledVariant)?.absoluteString,
            "https://bravohairgel.com/cart/43628496945329:1"
        )
        XCTAssertNil(bag.checkoutURL(storeURL: URL(string: "file:///tmp/")!, variantID: bundledVariant))
    }

    // MARK: Saving

    func testRoundTripsThroughJSON() throws {
        var bag = Bag()
        bag.add("bravo-matte-clay", quantity: 3)
        bag.add("blue-bravo-hair-gel-4oz")
        let data = try JSONEncoder().encode(bag)
        XCTAssertEqual(try JSONDecoder().decode(Bag.self, from: data), bag)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try XCTUnwrap(json["lines"] as? [[String: Any]])
        XCTAssertEqual(lines.first?["productID"] as? String, "bravo-matte-clay")
        XCTAssertEqual(lines.first?["quantity"] as? Int, 3)
    }

    func testDecodingASavedBagSkipsBadLinesAndMakesItValid() throws {
        let json = #"""
        {"lines": [
            {"productID": "bravo-matte-clay", "quantity": 2},
            {"productID": "bravo-matte-clay", "quantity": 2},
            {"productID": "bravo-after-shave", "quantity": 99},
            {"productID": "bravo-blue-pomade"},
            {"productID": 7, "quantity": 1},
            "junk",
            null,
            {"productID": "bravo-chapstick-3-pack", "quantity": 0},
            {"productID": "white-bravo-hair-gel-4oz", "quantity": 1, "note": "extra fields are fine"}
        ]}
        """#
        let bag = try JSONDecoder().decode(Bag.self, from: Data(json.utf8))
        XCTAssertEqual(bag.lines, [
            Bag.Line(productID: "bravo-matte-clay", quantity: 4),
            Bag.Line(productID: "bravo-after-shave", quantity: 10),
            Bag.Line(productID: "white-bravo-hair-gel-4oz", quantity: 1),
        ])
    }

    func testDecodingSomethingElseGivesAnEmptyBag() throws {
        for json in ["{}", #"{"lines": "none"}"#, #"{"lines": null}"#, #"{"items": []}"#] {
            XCTAssertEqual(try JSONDecoder().decode(Bag.self, from: Data(json.utf8)), Bag(), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(Bag.self, from: Data("[]".utf8)))
    }
}
