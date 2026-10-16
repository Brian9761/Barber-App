import XCTest
@testable import IzzyClipzKit

final class BookingLinksTests: XCTestCase {
    let links = ShopInfo.izzyClipz.booking
    let tracking = "utm_source=izzyclipz-app&utm_medium=ios"

    func testShopPage() {
        XCTAssertEqual(
            links.url(for: .anything).absoluteString,
            "https://getsquire.com/booking/book/izzy-clipz-oceanside?\(tracking)"
        )
    }

    func testBarberPage() {
        XCTAssertEqual(
            links.url(for: .barber("carlos-rafael")).absoluteString,
            "https://getsquire.com/booking/book/izzy-clipz-oceanside/barber/carlos-rafael/services?\(tracking)"
        )
    }

    func testSpecificOfferingPreselectsTheMenuItem() throws {
        let offering = try XCTUnwrap(Catalog.izzyClipz.offerings(forBarber: "carlos-rafael").first)
        XCTAssertEqual(
            links.url(for: .offering(offering)).absoluteString,
            "https://getsquire.com/booking/book/izzy-clipz-oceanside/barber/carlos-rafael/services?preselect=9343fc67-b196-4604-987e-a4a9b6b4cc41&\(tracking)"
        )
    }

    func testFirstAvailableUsesAnyBarber() throws {
        let option = try XCTUnwrap(Catalog.izzyClipz.firstAvailableOption(forService: "haircut-and-beard"))
        XCTAssertEqual(
            links.url(for: .firstAvailable(option)).absoluteString,
            "https://getsquire.com/booking/book/izzy-clipz-oceanside/barber/any/services?preselect=23936782-15f7-4ed5-9cde-ece8cc1d730c&\(tracking)"
        )
    }

    func testServiceIDsAreLowercased() {
        let request = BookingRequest(barberID: nil, squireServiceID: "23936782-15F7-4ED5-9CDE-ECE8CC1D730C")
        XCTAssertEqual(request.squireServiceID, "23936782-15f7-4ed5-9cde-ece8cc1d730c")
    }

    func testWithoutTracking() {
        let plain = BookingLinks(shopSlug: "izzy-clipz-oceanside", tracking: [])
        XCTAssertEqual(plain.url(for: .anything).absoluteString, "https://getsquire.com/booking/book/izzy-clipz-oceanside")
    }

    func testEveryOfferingLinksToItsOwnMenuItem() throws {
        for offering in Catalog.izzyClipz.offerings {
            let url = links.url(for: .offering(offering))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "getsquire.com")
            XCTAssertEqual(components.path, "/booking/book/izzy-clipz-oceanside/barber/\(offering.barberID)/services")
            XCTAssertEqual(components.queryItems?.first { $0.name == "preselect" }?.value, offering.squireServiceID)
        }
    }
}

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

    func testReviewsPointAtRealBarbers() {
        for review in shop.reviews {
            if let barberID = review.barberID {
                XCTAssertNotNil(Catalog.izzyClipz.barber(withID: barberID), review.id)
            }
            XCTAssertFalse(review.text.isEmpty)
        }
    }

    func testRating() {
        XCTAssertEqual(shop.rating.averageLabel, "5.0")
        XCTAssertEqual(shop.rating.countLabel, "115 reviews")
    }
}
