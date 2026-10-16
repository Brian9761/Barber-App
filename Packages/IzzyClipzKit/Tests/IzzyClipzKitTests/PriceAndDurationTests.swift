import XCTest
@testable import IzzyClipzKit

final class PriceTests: XCTestCase {
    func testCurrencyStrings() {
        XCTAssertEqual(Price.currencyString(cents: 0), "$0")
        XCTAssertEqual(Price.currencyString(cents: 1), "$0.01")
        XCTAssertEqual(Price.currencyString(cents: 500), "$5")
        XCTAssertEqual(Price.currencyString(cents: 750), "$7.50")
        XCTAssertEqual(Price.currencyString(cents: 1605), "$16.05")
        XCTAssertEqual(Price.currencyString(cents: 15000), "$150")
    }

    func testLabels() {
        XCTAssertEqual(Price.dollars(35).label, "$35")
        XCTAssertEqual(Price.startingAt(dollars: 80).label, "From $80")
        XCTAssertEqual(Price.includedWithCut.label, "Included with cut")
    }

    func testIncludedPricesAreAlwaysFree() {
        XCTAssertEqual(Price(cents: 500, kind: .includedWithCut).cents, 0)
    }

    func testSummaryOfOnePrice() {
        XCTAssertEqual(Price.summary(of: [.dollars(30)]), "$30")
        XCTAssertEqual(Price.summary(of: [.dollars(30), .dollars(30)]), "$30")
    }

    func testSummaryOfARange() {
        XCTAssertEqual(Price.summary(of: [.dollars(45), .dollars(35), .dollars(40)]), "$35–$45")
    }

    func testSummaryWithAStartingPrice() {
        XCTAssertEqual(Price.summary(of: [.startingAt(dollars: 80)]), "From $80")
        XCTAssertEqual(Price.summary(of: [.dollars(90), .startingAt(dollars: 80)]), "From $80")
    }

    func testSummaryIgnoresIncludedPricesWhenSomethingIsCharged() {
        XCTAssertEqual(Price.summary(of: [.includedWithCut, .dollars(5)]), "$5")
        XCTAssertEqual(Price.summary(of: [.includedWithCut]), "Included with cut")
    }

    func testSummaryOfNothing() {
        XCTAssertEqual(Price.summary(of: []), "")
    }

    func testOrdering() {
        XCTAssertLessThan(Price.dollars(16), Price.dollars(35))
        XCTAssertEqual([Price.dollars(40), .includedWithCut, .dollars(5)].min(), .includedWithCut)
    }
}

final class DurationTextTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(DurationText.short(minutes: 15), "15 min")
        XCTAssertEqual(DurationText.short(minutes: 45), "45 min")
        XCTAssertEqual(DurationText.short(minutes: 60), "1 hr")
        XCTAssertEqual(DurationText.short(minutes: 75), "1 hr 15 min")
        XCTAssertEqual(DurationText.short(minutes: 120), "2 hr")
        XCTAssertEqual(DurationText.short(minutes: 240), "4 hr")
    }

    func testSpoken() {
        XCTAssertEqual(DurationText.spoken(minutes: 1), "1 minute")
        XCTAssertEqual(DurationText.spoken(minutes: 45), "45 minutes")
        XCTAssertEqual(DurationText.spoken(minutes: 60), "1 hour")
        XCTAssertEqual(DurationText.spoken(minutes: 75), "1 hour 15 minutes")
        XCTAssertEqual(DurationText.spoken(minutes: 240), "4 hours")
    }

    func testRange() {
        XCTAssertEqual(DurationText.range(minutes: []), "")
        XCTAssertEqual(DurationText.range(minutes: [60, 60]), "1 hr")
        XCTAssertEqual(DurationText.range(minutes: [30, 15]), "15–30 min")
        XCTAssertEqual(DurationText.range(minutes: [45, 60]), "45 min – 1 hr")
        XCTAssertEqual(DurationText.range(minutes: [60, 120]), "1 hr – 2 hr")
    }
}

final class RatingTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(Rating(average: 5, count: 92).averageLabel, "5.0")
        XCTAssertEqual(Rating(average: 4.86, count: 3).averageLabel, "4.9")
        XCTAssertEqual(Rating(average: 4.04, count: 3).averageLabel, "4.0")
        XCTAssertEqual(Rating(average: 5, count: 1).countLabel, "1 review")
        XCTAssertEqual(Rating(average: 5, count: 115).countLabel, "115 reviews")
    }
}
