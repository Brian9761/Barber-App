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

    /// The shop's logo is white art on a transparent background, so it reads as is on the ink
    /// canvas, the black sticker and the badge.
    func testTheLogoIsWhiteOnTransparentSoItSitsOnTheDarkCanvas() throws {
        let logo = try XCTUnwrap(UIImage(named: Asset.logo)?.cgImage)
        let alpha = logo.alphaInfo
        XCTAssertTrue([.first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha), "Logo has no alpha channel")

        // Its pixels, drawn into a known layout: RGBA, 8 bits each, in sRGB.
        let width = logo.width, height = logo.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(logo, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn, "Couldn't read the logo's pixels")
        var clear = 0, solid = 0, solidNotWhite = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            switch pixels[pixel + 3] {
            case 0:
                clear += 1
            case 255:
                solid += 1
                if min(pixels[pixel], pixels[pixel + 1], pixels[pixel + 2]) < 235 { solidNotWhite += 1 }
            default:
                break
            }
        }
        let total = width * height
        XCTAssertGreaterThan(clear, total / 3, "The logo should be on a transparent background")
        XCTAssertGreaterThan(solid, total / 5, "The logo's art is missing")
        XCTAssertEqual(solidNotWhite, 0, "The logo's art should be white")
    }

    func testBrandColorsExist() {
        for name in ["AccentColor", "LaunchBackground", "BrandBlue", "BrandRed"] {
            XCTAssertNotNil(UIColor(named: name), name)
        }
    }

    /// No photo of a person is bundled: one goes in only with that person's written permission. The
    /// six photos of clients' cuts are gone, and Home shows the storefront.
    func testNoPhotosOfPeopleAreBundled() {
        for number in 1...6 {
            XCTAssertNil(UIImage(named: "Gallery\(number)"), "Gallery\(number) is back")
        }
        XCTAssertEqual(Asset.all, ["Storefront", "LaunchLogo", "Logo"])
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

    /// The name, number and note sent with a booking, and the card saved for no-show protection
    /// (its brand, last 4 digits and expiry; the number is typed on Stripe's page), are declared: used
    /// for the app's own functionality, linked to the client, never for tracking.
    func testPrivacyManifestDeclaresWhatGoesToTheShop() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        XCTAssertEqual(Set(types), [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypePhoneNumber",
            "NSPrivacyCollectedDataTypePaymentInfo",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        ])
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
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

    /// Only the demo version (built with IZZY_DEMO_MODE=YES) talks to the in-memory server; every
    /// other build talks to the shop's.
    func testOnlyTheDemoVersionUsesTheInMemoryServer() {
        let flag = Bundle.main.object(forInfoDictionaryKey: DemoMode.infoKey) as? String
        XCTAssertEqual(flag, "NO", "Info.plist's IzzyDemoMode is $(IZZY_DEMO_MODE), NO outside the test builds")
        XCTAssertFalse(DemoMode.isOn)
        XCTAssertTrue(APIConfiguration.makeAPI(demo: false, uiTesting: false) is IzzyAPIClient)
        XCTAssertTrue(APIConfiguration.makeAPI(demo: true, uiTesting: false) is FakeShopAPI, "The demo never uses the network")
    }

    /// The website the app links to (Visit's Website row and Share link, calendar events and the
    /// legal pages) comes from the build setting IZZY_WEBSITE_URL: the current public site until
    /// the shop's own domain replaces it there, never the older website.
    func testTheWebsiteIsTheNewOne() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNotNil(info[Website.infoKey], "Info.plist has no IzzyWebsiteURL")
        XCTAssertEqual(Website.baseURL.absoluteString, "https://izzy-clipz.vercel.app")
        XCTAssertEqual(Website.LegalPage.privacy.url().absoluteString, "https://izzy-clipz.vercel.app/privacy")
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
        XCTAssertEqual(ReviewLinks.yelpPage.absoluteString, "https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside")
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
}
