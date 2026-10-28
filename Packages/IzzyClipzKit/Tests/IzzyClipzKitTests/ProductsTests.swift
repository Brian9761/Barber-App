import XCTest
@testable import IzzyClipzKit

final class ProductCatalogTests: XCTestCase {
    let catalog = ProductCatalog.bravo
    let tracking = "utm_source=izzyclipz-app&utm_medium=ios&utm_campaign=izzy-clipz-partner"

    // MARK: Integrity

    func testCatalogIsValid() {
        XCTAssertEqual(catalog.validationProblems(), [])
    }

    func testProductsInOrder() {
        XCTAssertEqual(catalog.products.map(\.id), [
            "blue-bravo-hair-gel-16oz",
            "white-bravo-hair-gel-16oz",
            "bravo-onyx-hair-gel",
            "blue-bravo-hair-gel-4oz",
            "white-bravo-hair-gel-4oz",
            "bravo-matte-clay",
            "bravo-texture-powder",
            "bravo-blue-pomade",
            "bravo-after-shave",
            "bravo-chapstick-3-pack",
        ])
        XCTAssertEqual(Set(catalog.products.map(\.id)).count, catalog.products.count)
    }

    func testNamesSizesAndPrices() {
        let expected: [(id: String, name: String, size: String?, price: String)] = [
            ("blue-bravo-hair-gel-16oz", "Blue Hair Gel", "16 oz", "$17.99"),
            ("white-bravo-hair-gel-16oz", "White Hair Gel", "16 oz", "$17.99"),
            ("bravo-onyx-hair-gel", "Onyx Hair Gel", "16 oz", "$19.99"),
            ("blue-bravo-hair-gel-4oz", "Blue Hair Gel", "4 oz", "$11.99"),
            ("white-bravo-hair-gel-4oz", "White Hair Gel", "4 oz", "$11.99"),
            ("bravo-matte-clay", "Matte Clay", nil, "$17.99"),
            ("bravo-texture-powder", "Texture Powder", nil, "$18.99"),
            ("bravo-blue-pomade", "Blue Pomade", nil, "$17.99"),
            ("bravo-after-shave", "After-Shave Spray", nil, "$12.99"),
            ("bravo-chapstick-3-pack", "Mint Lip Balm", "3 pack", "$2.99"),
        ]
        XCTAssertEqual(expected.count, catalog.products.count)
        for item in expected {
            guard let product = catalog.product(withID: item.id) else {
                XCTFail("Missing \(item.id)")
                continue
            }
            XCTAssertEqual(product.name, item.name, item.id)
            XCTAssertEqual(product.size, item.size, item.id)
            XCTAssertEqual(product.price.label, item.price, item.id)
            XCTAssertEqual(product.price.kind, .fixed, item.id)
        }
    }

    func testEveryProductIsComplete() {
        for product in catalog.products {
            XCTAssertEqual(product.imageName, "Bravo-" + product.id)
            XCTAssertGreaterThan(product.price.cents, 0, product.id)
            XCTAssertFalse(product.summary.isEmpty, product.id)
            XCTAssertTrue((3...5).contains(product.highlights.count), product.id)
            XCTAssertTrue(product.highlights.allSatisfy { !$0.isEmpty && !$0.hasSuffix(".") }, product.id)
            XCTAssertTrue(Catalog.isURLSlug(product.id), product.id)
        }
    }

    // MARK: Grouping

    func testCategories() {
        XCTAssertEqual(catalog.categories, [.gels, .styling, .grooming])
        XCTAssertEqual(ProductCategory.allCases.map(\.title), ["Hair Gels", "Styling", "Grooming"])
        XCTAssertEqual(ProductCategory.allCases.map(\.id), ["gels", "styling", "grooming"])
        for category in ProductCategory.allCases {
            XCTAssertFalse(catalog.products(in: category).isEmpty, category.title)
        }
        XCTAssertEqual(catalog.products(in: .gels).count, 5)
        XCTAssertEqual(catalog.products(in: .styling).map(\.id), ["bravo-matte-clay", "bravo-texture-powder", "bravo-blue-pomade"])
        XCTAssertEqual(catalog.products(in: .grooming).map(\.id), ["bravo-after-shave", "bravo-chapstick-3-pack"])
    }

    func testFeatured() {
        XCTAssertEqual(catalog.featured.map(\.id), [
            "blue-bravo-hair-gel-16oz", "white-bravo-hair-gel-16oz", "bravo-onyx-hair-gel", "bravo-matte-clay",
        ])
    }

    func testLookup() {
        XCTAssertEqual(catalog.product(withID: "bravo-matte-clay")?.name, "Matte Clay")
        XCTAssertNil(catalog.product(withID: "bravo-cutting-cape"))
        XCTAssertNil(catalog.product(withID: ""))
    }

    // MARK: Links

    func testProductLinks() throws {
        let gel = try XCTUnwrap(catalog.product(withID: "blue-bravo-hair-gel-16oz"))
        XCTAssertEqual(
            catalog.url(for: gel).absoluteString,
            "https://bravohairgel.com/products/blue-bravo-hair-gel-16oz?\(tracking)"
        )
        for product in catalog.products {
            let components = try XCTUnwrap(URLComponents(url: catalog.url(for: product), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "bravohairgel.com")
            XCTAssertEqual(components.path, "/products/\(product.id)")
            XCTAssertEqual(components.queryItems, [
                URLQueryItem(name: "utm_source", value: "izzyclipz-app"),
                URLQueryItem(name: "utm_medium", value: "ios"),
                URLQueryItem(name: "utm_campaign", value: "izzy-clipz-partner"),
            ])
        }
    }

    func testStoreLink() {
        XCTAssertEqual(catalog.sponsor.storeURL.absoluteString, "https://bravohairgel.com/")
        XCTAssertEqual(catalog.storeURL.absoluteString, "https://bravohairgel.com/?\(tracking)")
    }

    func testTrackingReusesTheAppsBookingTags() {
        XCTAssertEqual(Array(catalog.tracking.prefix(2)), BookingLinks.appTracking)
        XCTAssertEqual(catalog.tracking, ProductCatalog.appTracking)
    }

    func testLinksWithoutTracking() throws {
        let plain = ProductCatalog(sponsor: catalog.sponsor, products: catalog.products, tracking: [])
        let clay = try XCTUnwrap(plain.product(withID: "bravo-matte-clay"))
        XCTAssertEqual(plain.url(for: clay).absoluteString, "https://bravohairgel.com/products/bravo-matte-clay")
        XCTAssertEqual(plain.storeURL.absoluteString, "https://bravohairgel.com/")
    }

    // MARK: Sponsor

    func testSponsor() {
        let bravo = catalog.sponsor
        XCTAssertEqual(bravo.name, "Bravo")
        XCTAssertEqual(bravo.fullName, "Bravo Hair Gel")
        XCTAssertEqual(bravo.tagline, "Designed by professionals, for professionals.")
        XCTAssertEqual(bravo.shippingNote, "Free shipping on U.S. orders $64+")
        XCTAssertNil(bravo.phone)
        XCTAssertEqual(bravo.about.count, 2)
        XCTAssertTrue(bravo.about[0].contains("Joana Davila"))
        XCTAssertTrue(bravo.about[1].contains("barbers and stylists"))
    }

    // MARK: Validation

    func testValidationCatchesBrokenData() {
        let fine = Product(id: "ok", name: "OK", category: .gels, price: Price(cents: 100), summary: "Fine.", highlights: ["a", "b", "c"], isFeatured: true)
        let broken = ProductCatalog(
            sponsor: Sponsor(
                name: "X", fullName: "X", tagline: "", about: [],
                storeURL: URL(string: "http://example.com/")!, shippingNote: ""
            ),
            products: [
                fine,
                fine,
                Product(id: "Bad Slug", name: " ", category: .gels, price: .includedWithCut, summary: "", highlights: ["a"]),
                Product(id: "too-many", name: "Many", size: " ", category: .styling, price: Price(cents: 0), summary: "S", highlights: ["1", "2", "3", "4", "5", "6"]),
                Product(id: "empty", name: "E", category: .styling, price: Price(cents: 100), summary: "S", highlights: ["1", "", "3"], imageName: ""),
            ]
        )
        let problems = broken.validationProblems()
        XCTAssertTrue(problems.contains("Duplicate product ID 'ok'"), "\(problems)")
        XCTAssertTrue(problems.contains("The store URL isn't an https link"), "\(problems)")
        XCTAssertTrue(problems.contains("Product ID 'Bad Slug' isn't a URL slug"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'Bad Slug' has no name"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'Bad Slug' has no summary"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'Bad Slug' needs 3 to 5 highlights"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'Bad Slug' needs a price"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'too-many' needs 3 to 5 highlights"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'too-many' needs a price"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'too-many' has an empty size"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'empty' has an empty highlight"), "\(problems)")
        XCTAssertTrue(problems.contains("Product 'empty' has no image"), "\(problems)")
        XCTAssertFalse(problems.contains { $0.contains("'ok'") && !$0.hasPrefix("Duplicate") }, "\(problems)")
    }

    func testValidationNeedsProductsAndAFeaturedOne() {
        let sponsor = catalog.sponsor
        XCTAssertEqual(ProductCatalog(sponsor: sponsor, products: []).validationProblems(), ["There are no products"])
        let plain = Product(id: "a", name: "A", category: .gels, price: Price(cents: 100), summary: "S", highlights: ["1", "2", "3"])
        XCTAssertEqual(ProductCatalog(sponsor: sponsor, products: [plain]).validationProblems(), ["No product is featured"])
    }

    func testImageNameDefaultsToTheHandle() {
        let product = Product(id: "bravo-x", name: "X", category: .grooming, price: Price(cents: 100), summary: "S", highlights: ["1", "2", "3"])
        XCTAssertEqual(product.imageName, "Bravo-bravo-x")
        XCTAssertNil(product.size)
        XCTAssertFalse(product.isFeatured)
    }
}

final class ShopifyPricesTests: XCTestCase {
    func testParsesPricesByHand() {
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "17.99"), 1799)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "18"), 1800)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "18.9"), 1890)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "18.90"), 1890)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "0.05"), 5)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "2.99"), 299)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "227.88"), 22788)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "0"), 0)
        XCTAssertEqual(ShopifyPrices.cents(fromPrice: "999999999.99"), 99_999_999_999)
    }

    func testRejectsAnythingElse() {
        for text in ["", ".", ".99", "17.", "17.999", "-1.00", "+1", "1,299.00", " 17.99", "17.99 ", "1e3", "abc", "1.2.3", "$17.99", "1234567890", "١٧"] {
            XCTAssertNil(ShopifyPrices.cents(fromPrice: text), text)
        }
    }

    func testParsesAFeed() throws {
        let json = #"""
        {"products": [
            {"handle": "single", "title": "Single", "variants": [{"price": "17.99", "available": true}]},
            {"handle": "multi", "variants": [
                {"title": "Box", "price": "227.88", "available": true},
                {"title": "Single", "price": "18.99", "available": false}
            ]},
            {"handle": "sold-out", "variants": [{"price": "12.99", "available": false}, {"price": "13.99", "available": false}]},
            {"handle": "no-flag", "variants": [{"price": "18"}]},
            {"handle": "odd-flag", "variants": [{"price": "18.50", "available": "yes"}]},
            {"handle": "one-bad-variant", "variants": [{"price": "18.9", "available": false}, {"price": "oops", "available": true}]},
            {"handle": "bad-price", "variants": [{"price": "abc", "available": true}]},
            {"handle": "numeric-price", "variants": [{"price": 17.99, "available": true}]},
            {"handle": "free", "variants": [{"price": "0.00", "available": true}]},
            {"handle": "no-variants", "variants": []},
            {"handle": "missing-variants"},
            {"handle": 42, "variants": [{"price": "1.00"}]},
            {"variants": [{"price": "9.99"}]},
            "not a product",
            null,
            {"handle": "after-junk", "variants": [{"price": "5.00", "available": true}]},
            {"handle": "single", "variants": [{"price": "1.00", "available": false}]}
        ]}
        """#
        let prices = try ShopifyPrices.parse(Data(json.utf8))
        XCTAssertEqual(prices, [
            "single": LivePrice(cents: 1799, isAvailable: true),
            "multi": LivePrice(cents: 1899, isAvailable: true),
            "sold-out": LivePrice(cents: 1299, isAvailable: false),
            "no-flag": LivePrice(cents: 1800, isAvailable: true),
            "odd-flag": LivePrice(cents: 1850, isAvailable: true),
            "one-bad-variant": LivePrice(cents: 1890, isAvailable: false),
            "after-junk": LivePrice(cents: 500, isAvailable: true),
        ])
    }

    func testEmptyFeed() throws {
        XCTAssertEqual(try ShopifyPrices.parse(Data(#"{"products": []}"#.utf8)), [:])
    }

    func testThrowsWhenItIsNotAProductList() {
        for json in ["", "nope", "[]", "{}", #"{"products": {}}"#, #"{"products": "none"}"#, #"{"items": []}"#, "null"] {
            XCTAssertThrowsError(try ShopifyPrices.parse(Data(json.utf8)), json) { error in
                XCTAssertEqual(error as? ShopifyPrices.ParseError, .notAProductList, json)
            }
        }
    }

    func testRealBravoFeedMatchesTheBundledPrices() throws {
        let prices = try ShopifyPrices.parse(Data(bravoFeedFixture.utf8))
        XCTAssertEqual(prices.count, 15)
        for product in ProductCatalog.bravo.products {
            XCTAssertEqual(prices[product.id], LivePrice(cents: product.price.cents, isAvailable: true), product.id)
        }
        // The single, not the 12-count display box.
        XCTAssertEqual(prices["bravo-texture-powder"]?.cents, 1899)
        XCTAssertEqual(prices["black-bravo-cutting-shears"]?.cents, 19999)
        XCTAssertEqual(prices["bravo-cutting-cape"]?.cents, 2099)
    }
}
