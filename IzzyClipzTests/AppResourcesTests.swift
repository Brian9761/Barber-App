import UIKit
import XCTest
@testable import IzzyClipz

/// Checks for problems the compiler can't catch: misspelled SF Symbols,
/// missing images, broken links and Info.plist settings.
@MainActor
final class AppResourcesTests: XCTestCase {
    func testEverySymbolExists() {
        for name in Symbol.all {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol '\(name)' doesn't exist")
        }
        for part in DayPart.allCases {
            XCTAssertNotNil(UIImage(systemName: Symbol.symbol(for: part)), part.rawValue)
        }
    }

    func testBundledImagesExist() {
        for name in Asset.all {
            XCTAssertNotNil(UIImage(named: name), "Missing image '\(name)'")
        }
        XCTAssertNotNil(UIImage(named: "BravoLogo"))
    }

    func testTheLogoIsTransparentSoItSitsOnAnyLightSurface() throws {
        let logo = try XCTUnwrap(UIImage(named: Asset.logo)?.cgImage)
        let alpha = logo.alphaInfo
        XCTAssertTrue([.first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha), "Logo has no alpha channel")
    }

    func testBrandColorsExist() {
        for name in ["AccentColor", "LaunchBackground", "BrandBlue", "BrandRed"] {
            XCTAssertNotNil(UIColor(named: name), name)
        }
    }

    func testGalleryCaptionsAreUnique() {
        let captions = GalleryPhoto.allCases.map(\.caption)
        XCTAssertEqual(Set(captions).count, captions.count)
    }

    func testInfoPlist() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Izzy Clipz")
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Light")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        let launch = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(launch["UIImageName"] as? String, Asset.launchLogo)
    }

    func testPrivacyManifestIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testBookingLinksAreWebLinks() {
        // The in-app browser only accepts http(s) URLs.
        XCTAssertEqual(AppData.bookingURL(for: .anything).scheme, "https")
        for offering in AppData.catalog.offerings {
            XCTAssertEqual(AppData.bookingURL(for: .offering(offering)).scheme, "https", offering.id)
        }
        for barber in AppData.catalog.barbers {
            XCTAssertEqual(AppData.bookingURL(for: .barber(barber.id)).scheme, "https", barber.id)
        }
    }

    func testBravoLinksGoToBravoAndSayWhereTheyCameFrom() throws {
        let products = AppData.products
        var urls = products.products.map { products.url(for: $0) }
        urls.append(products.storeURL)
        for url in urls {
            XCTAssertEqual(url.scheme, "https", url.absoluteString)
            XCTAssertEqual(url.host, "bravohairgel.com", url.absoluteString)
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertTrue(query.contains(URLQueryItem(name: "utm_source", value: "izzyclipz-app")), url.absoluteString)
        }
        for product in products.products {
            XCTAssertTrue(products.url(for: product).path.hasSuffix("/products/\(product.id)"), product.id)
        }
    }

    func testContactLinks() {
        let shop = AppData.shop
        XCTAssertEqual(shop.phone.callURL.scheme, "tel")
        XCTAssertEqual(shop.instagramURL.scheme, "https")
        XCTAssertEqual(shop.websiteURL.scheme, "https")
        XCTAssertEqual(shop.appleMapsDirectionsURL.scheme, "https")
        XCTAssertEqual(shop.googleMapsDirectionsURL.scheme, "https")
        XCTAssertEqual(shop.googleMapsURL.scheme, "https")
        XCTAssertEqual(shop.googleReviewURL.scheme, "https")
        for sourced in shop.ratings {
            if let url = sourced.url {
                XCTAssertEqual(url.scheme, "https", sourced.source)
            }
        }
        for barber in AppData.catalog.barbers {
            if let url = barber.instagramURL {
                XCTAssertEqual(url.scheme, "https", barber.id)
            }
        }
        XCTAssertNotNil(URL(string: UIApplication.openNotificationSettingsURLString))
    }

    func testCalendarNotesMentionTheBooking() {
        let appointment = Appointment(
            serviceID: "haircut",
            serviceName: "Haircut",
            barberID: "carlos-rafael",
            barberName: "Carlos",
            start: Date(timeIntervalSince1970: 1_793_395_800),
            durationMinutes: 45,
            priceLabel: "$45"
        )
        let notes = CalendarEventEditor.notes(for: appointment)
        XCTAssertTrue(notes.contains("Haircut with Carlos"), notes)
        XCTAssertTrue(notes.contains("$45 · 45 min"), notes)
        XCTAssertTrue(notes.contains(AppData.shop.phone.display), notes)
    }

    func testZoomFitsPhotosInsideTheScreen() {
        let portrait = ZoomingImageScrollView.aspectFitSize(for: CGSize(width: 750, height: 1000), in: CGSize(width: 393, height: 852))
        XCTAssertEqual(portrait.width, 393, accuracy: 0.001)
        XCTAssertEqual(portrait.height, 524, accuracy: 0.001)
        let landscape = ZoomingImageScrollView.aspectFitSize(for: CGSize(width: 1000, height: 750), in: CGSize(width: 393, height: 852))
        XCTAssertEqual(landscape.width, 393, accuracy: 0.001)
        XCTAssertEqual(landscape.height, 294.75, accuracy: 0.001)
        XCTAssertEqual(ZoomingImageScrollView.aspectFitSize(for: .zero, in: CGSize(width: 10, height: 20)), CGSize(width: 10, height: 20))
    }
}
