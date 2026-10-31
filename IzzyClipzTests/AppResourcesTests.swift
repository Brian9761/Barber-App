import UIKit
import XCTest
@testable import IzzyClipz

/// Checks for problems the compiler can't catch: misspelled SF Symbols,
/// missing images and fonts, broken links and Info.plist settings.
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
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        let launch = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(launch["UIImageName"] as? String, Asset.launchLogo)
    }

    // MARK: Fonts

    /// The app uses the system font: no bundled fonts are registered.
    func testNoBundledFonts() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNil(info["UIAppFonts"], "The app uses the system font; UIAppFonts should be gone")
        XCTAssertTrue(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?.isEmpty ?? true)
    }

    /// Every text role is the system font in a Dynamic Type text style, so it scales with the
    /// person's text size.
    func testTextRolesFollowDynamicType() {
        for role in TextRole.allCases {
            XCTAssertGreaterThanOrEqual(role.largestDynamicTypeSize, .accessibility2, "\(role) stops growing too early")
        }
        XCTAssertEqual(TextRole.body.textStyle, .body)
        XCTAssertEqual(TextRole.displayXL.textStyle, .largeTitle)
    }

    func testPrivacyManifestIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testServerAddress() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let value = try XCTUnwrap(info[APIConfiguration.baseURLKey] as? String, "Info.plist has no IzzyAPIBaseURL")
        XCTAssertEqual(APIConfiguration.baseURL(from: value)?.scheme, "https")
        XCTAssertNotNil(APIConfiguration.baseURL)
    }

    /// Only https (and http to this machine, for a local server) is used.
    func testServerAddressMustBeSecure() {
        XCTAssertEqual(APIConfiguration.baseURL(from: "https://izzy-clipz-api.vercel.app")?.host, "izzy-clipz-api.vercel.app")
        XCTAssertEqual(APIConfiguration.baseURL(from: " https://example.com/api ")?.path, "/api")
        XCTAssertNotNil(APIConfiguration.baseURL(from: "http://localhost:3000"))
        XCTAssertNil(APIConfiguration.baseURL(from: "http://izzy-clipz-api.vercel.app"))
        XCTAssertNil(APIConfiguration.baseURL(from: "ftp://example.com"))
        XCTAssertNil(APIConfiguration.baseURL(from: ""))
        XCTAssertNil(APIConfiguration.baseURL(from: nil))
        XCTAssertNil(APIConfiguration.baseURL(from: 42))
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

    /// The shop's Instagram (Home and Visit), a direct message to it (Visit), and Izzy's own account.
    func testInstagramLinks() {
        XCTAssertEqual(AppData.shop.instagramURL.absoluteString, "https://www.instagram.com/izzy_clipz_barbershop_/")
        XCTAssertEqual(InstagramCard.messageURL.absoluteString, "https://ig.me/m/izzy_clipz_barbershop_")
        let izzy = AppData.catalog.barber(withID: "israel-flores")
        XCTAssertEqual(izzy?.instagramURL?.absoluteString, "https://www.instagram.com/izzy_clipz_/")
    }

    func testCalendarEventsSayWhatAndHowToChangeIt() {
        let event = SavedAppointment(snapshot: TestData.appointment(), origin: .app, remind: true).calendarEvent
        XCTAssertEqual(event.title, "Haircut at Izzy Clipz")
        XCTAssertEqual(event.start, TestData.friday)
        XCTAssertEqual(event.end, TestData.friday.addingTimeInterval(45 * 60))
        XCTAssertTrue(event.notes.contains("Haircut with Carlos"), event.notes)
        XCTAssertTrue(event.notes.contains("$45 · 45 min · Pay at the shop"), event.notes)
        XCTAssertTrue(event.notes.contains(AppData.shop.phone.display), event.notes)
    }

    func testCalendarEventsForASquireBookingWithoutABarberReadNaturally() {
        let old = Appointment(serviceID: "haircut", serviceName: "Haircut", barberID: nil, start: TestData.friday, durationMinutes: 45, priceLabel: "$35")
        let event = SavedAppointment(squire: old, remind: false).calendarEvent
        XCTAssertTrue(event.notes.contains("Haircut with the first available barber"), event.notes)
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
