import XCTest
@testable import IzzyClipzKit

final class ShopInfoTests: XCTestCase {
    let shop = ShopInfo.izzyClipz

    func testPhone() {
        XCTAssertEqual(shop.phone.display, "(442) 341-3053")
        XCTAssertEqual(shop.phone.callURL.absoluteString, "tel:+14423413053")
        XCTAssertEqual(shop.phone.spoken, "4 4 2, 3 4 1, 3 0 5 3")
    }

    func testAddress() {
        XCTAssertEqual(shop.address.streetLine, "1919 Mission Ave, Ste 105")
        XCTAssertEqual(shop.address.cityLine, "Oceanside, CA 92058")
        XCTAssertEqual(shop.address.singleLine, "1919 Mission Ave, Ste 105, Oceanside, CA 92058")
        XCTAssertEqual(
            PostalAddress(street: "1 Main St", unit: nil, city: "Vista", state: "CA", postalCode: "92083").singleLine,
            "1 Main St, Vista, CA 92083"
        )
    }

    func testTimeZone() {
        XCTAssertEqual(shop.timeZone.identifier, "America/Los_Angeles")
    }

    func testCoordinateIsInOceanside() {
        XCTAssertEqual(shop.coordinate.latitude, 33.2, accuracy: 0.05)
        XCTAssertEqual(shop.coordinate.longitude, -117.36, accuracy: 0.05)
    }

    func testInstagram() {
        XCTAssertEqual(shop.instagramURL.absoluteString, "https://www.instagram.com/izzy_clipz_barbershop_/")
    }

    func testAppleMapsLinks() throws {
        let place = try XCTUnwrap(URLComponents(url: shop.appleMapsURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(place.host, "maps.apple.com")
        XCTAssertEqual(place.queryItems?.first { $0.name == "q" }?.value, "Izzy Clipz Barbershop")
        XCTAssertEqual(place.queryItems?.first { $0.name == "ll" }?.value, "33.2034409,-117.364815")

        let directions = try XCTUnwrap(URLComponents(url: shop.appleMapsDirectionsURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(directions.queryItems?.first { $0.name == "daddr" }?.value, shop.address.singleLine)
        XCTAssertFalse(shop.appleMapsDirectionsURL.absoluteString.contains(" "))
    }

    func testGoogleMapsLink() throws {
        let directions = try XCTUnwrap(URLComponents(url: shop.googleMapsDirectionsURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(directions.host, "www.google.com")
        XCTAssertEqual(directions.path, "/maps/dir/")
        XCTAssertEqual(directions.queryItems?.first { $0.name == "api" }?.value, "1")
        XCTAssertEqual(
            directions.queryItems?.first { $0.name == "destination" }?.value,
            "Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058"
        )
    }

    func testGooglePlaceLinks() {
        XCTAssertEqual(shop.googlePlaceID, "ChIJGz5HChRv3IARYJJy_6jyRm8")
        XCTAssertEqual(
            shop.googleMapsURL.absoluteString,
            "https://www.google.com/maps/search/?api=1&query=Izzy%20Clipz%20Barbershop&query_place_id=ChIJGz5HChRv3IARYJJy_6jyRm8"
        )
        XCTAssertEqual(
            shop.googleReviewURL.absoluteString,
            "https://search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8"
        )
    }

    func testPlaceIDValidation() {
        XCTAssertTrue(ShopInfo.isPlaceID("ChIJGz5HChRv3IARYJJy_6jyRm8"))
        XCTAssertTrue(ShopInfo.isPlaceID("Ab-_09"))
        XCTAssertFalse(ShopInfo.isPlaceID(""))
        XCTAssertFalse(ShopInfo.isPlaceID("has space"))
        XCTAssertFalse(ShopInfo.isPlaceID("a&b=c"))
    }

    func testBookingCalendarUsesTheShopsClock() {
        let calendar = shop.bookingCalendar
        XCTAssertEqual(calendar.clock.calendar.timeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(calendar.slotIntervalMinutes, 30)
        XCTAssertEqual(calendar.leadTimeMinutes, 30)
        XCTAssertEqual(calendar.windowDays, 60)
    }

    func testHoursAndContactAreUnchanged() {
        XCTAssertEqual(shop.phone.digits, "4423413053")
        XCTAssertEqual(shop.address.singleLine, "1919 Mission Ave, Ste 105, Oceanside, CA 92058")
        for day in [Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday] {
            XCTAssertEqual(shop.schedule.hours(on: day)?.label, "10 AM – 7 PM", day.name)
        }
        XCTAssertEqual(shop.schedule.hours(on: .sunday)?.label, "10 AM – 6 PM")
    }

    /// The shop's new website, never the older Squarespace one (whose booking button goes to Squire).
    func testWebsiteIsTheNewOne() {
        XCTAssertEqual(shop.websiteURL.absoluteString, "https://izzy-clipz.vercel.app")
        XCTAssertFalse(shop.websiteURL.absoluteString.contains("izzyclipzbarbershop.net"))
    }

    /// Only the accessibility lines the owner checked and confirmed, in that order: "ADA-compliant" is
    /// a legal claim no inspection backs up, and he didn't confirm a step-free entrance (the apps and
    /// the website ask clients to call about getting in, after these lines).
    func testOnlyTheAccessibilityLinesTheOwnerConfirmed() {
        XCTAssertEqual(shop.accessibility, [
            "Room for a wheelchair inside, at the chairs and the counter",
            "Disabled parking space near the entrance",
        ])
        for line in shop.accessibility {
            XCTAssertNil(line.range(of: "ADA", options: .caseInsensitive), line)
            XCTAssertNil(line.range(of: "step-free", options: .caseInsensitive), line)
            XCTAssertNotEqual(line, "Wheelchair accessible")
        }
    }

    /// Who runs the shop, where, and how to get that by email (Business and Professions Code
    /// §17538(d)): until the owner gives the LLC's registered name and the shop's email, the lines say
    /// only what's known, the shop and where it is, and nothing made up: no "is operated by" without
    /// the name, and no line about email without an address.
    func testWhoRunsTheShopSaysOnlyWhatIsGiven() {
        XCTAssertEqual(shop.legalName, "")
        XCTAssertEqual(shop.email, "")
        XCTAssertFalse(shop.hasLegalName)
        XCTAssertFalse(shop.hasEmail)
        XCTAssertFalse(shop.isOperatorKnown)
        XCTAssertEqual(shop.operatedByLine, "Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.")
        XCTAssertNil(shop.byEmailLine)
        for line in [shop.operatedByLine] {
            XCTAssertFalse(line.contains("["), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("to be added"), line)
        }

        let filledIn = Self.shop(legalName: "Izzy Clipz Barbershop LLC", email: "hello@izzyclipz.example")
        XCTAssertTrue(filledIn.isOperatorKnown)
        XCTAssertEqual(
            filledIn.operatedByLine,
            "Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States."
        )
        XCTAssertEqual(filledIn.byEmailLine, "To get this information by email, email us at hello@izzyclipz.example and we'll send it within 5 days.")

        // One without the other: each line says what's given.
        let nameOnly = Self.shop(legalName: "Izzy Clipz Barbershop LLC", email: "")
        XCTAssertFalse(nameOnly.isOperatorKnown)
        XCTAssertTrue(nameOnly.operatedByLine.hasPrefix("Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, "))
        XCTAssertNil(nameOnly.byEmailLine)
        let emailOnly = Self.shop(legalName: "", email: "hello@izzyclipz.example")
        XCTAssertFalse(emailOnly.isOperatorKnown)
        XCTAssertEqual(emailOnly.operatedByLine, shop.operatedByLine)
        XCTAssertEqual(emailOnly.byEmailLine, filledIn.byEmailLine)
        // Spaces alone are nothing given.
        let blank = Self.shop(legalName: "  ", email: " \n")
        XCTAssertEqual(blank.legalName, "")
        XCTAssertEqual(blank.email, "")
        XCTAssertEqual(blank.operatedByLine, shop.operatedByLine)
        XCTAssertNil(blank.byEmailLine)
    }

    /// The shop with the business that runs it and its email filled in (or not).
    static func shop(legalName: String, email: String) -> ShopInfo {
        let shop = ShopInfo.izzyClipz
        return ShopInfo(
            name: shop.name,
            fullName: shop.fullName,
            tagline: shop.tagline,
            about: shop.about,
            address: shop.address,
            coordinate: shop.coordinate,
            phone: shop.phone,
            timeZoneIdentifier: shop.timeZoneIdentifier,
            schedule: shop.schedule,
            instagramHandle: shop.instagramHandle,
            websiteURL: shop.websiteURL,
            paymentMethods: shop.paymentMethods,
            highlights: shop.highlights,
            accessibility: shop.accessibility,
            googlePlaceID: shop.googlePlaceID,
            legalName: legalName,
            email: email
        )
    }
}
