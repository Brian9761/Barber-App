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
}
