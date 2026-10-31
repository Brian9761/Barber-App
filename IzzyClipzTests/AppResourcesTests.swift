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
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        let launch = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(launch["UIImageName"] as? String, Asset.launchLogo)
    }

    // MARK: Fonts

    /// Info.plist registers exactly the fonts `BrandFont` knows, and each file is in the app bundle
    /// (XcodeGen copies `Resources/Fonts` to the bundle's root).
    func testEveryListedFontFileIsBundled() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let files = try XCTUnwrap(info["UIAppFonts"] as? [String], "Info.plist has no UIAppFonts")
        XCTAssertEqual(files, BrandFont.fileNames, "UIAppFonts and BrandFont list different fonts")
        XCTAssertEqual(Set(files).count, files.count, "A font is listed twice")
        for file in files {
            XCTAssertNotNil(Bundle.main.url(forResource: file, withExtension: nil), "\(file) is in UIAppFonts but not in the app bundle")
        }
    }

    /// Every face the app asks for by PostScript name is registered, so no text falls back to the
    /// system font.
    func testEveryBrandFontLoads() {
        XCTAssertEqual(BrandFont.allCases.count, 11)
        for face in BrandFont.allCases {
            let font = UIFont(name: face.postScriptName, size: 17)
            XCTAssertNotNil(font, "\(face.postScriptName) doesn't load: check UIAppFonts and the file's PostScript name")
            XCTAssertEqual(font?.fontName, face.postScriptName)
        }
    }

    /// Each file holds the face it's named after (a file named for one face but holding another
    /// would still register, under the wrong name).
    func testEachFontFileHoldsTheFaceItIsNamedFor() throws {
        for face in BrandFont.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: face.fileName, withExtension: nil), face.fileName)
            let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL), face.fileName)
            let font = try XCTUnwrap(CGFont(provider), "\(face.fileName) isn't a font")
            XCTAssertEqual(font.postScriptName as String?, face.postScriptName, face.fileName)
        }
    }

    /// Every text role's face is one of the bundled fonts and loads at the role's size, and the UIKit
    /// version (the navigation bars) is the real face, not the system fallback.
    func testEveryTextRoleUsesARegisteredFace() {
        for role in TextRole.allCases {
            XCTAssertTrue(BrandFont.postScriptNames.contains(role.face.postScriptName), "\(role)")
            XCTAssertNotNil(UIFont(name: role.face.postScriptName, size: role.size), "\(role) uses \(role.face.postScriptName), which doesn't load")
            XCTAssertEqual(role.face.uiFont(size: role.size, relativeTo: .body).fontName, role.face.postScriptName, "\(role)")
        }
    }

    /// The fonts are SIL Open Font License: their licenses ship with them.
    func testFontLicensesAreBundled() {
        for license in ["OFL-Archivo", "OFL-SpaceMono", "OFL-RubikWetPaint"] {
            XCTAssertNotNil(Bundle.main.url(forResource: license, withExtension: "txt"), "\(license).txt isn't in the app bundle")
        }
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

    /// The shop's Instagram (Home and Visit), a direct message to it (Visit), and Izzy's own account.
    func testInstagramLinks() {
        XCTAssertEqual(AppData.shop.instagramURL.absoluteString, "https://www.instagram.com/izzy_clipz_barbershop_/")
        XCTAssertEqual(InstagramCard.messageURL.absoluteString, "https://ig.me/m/izzy_clipz_barbershop_")
        let izzy = AppData.catalog.barber(withID: "israel-flores")
        XCTAssertEqual(izzy?.instagramURL?.absoluteString, "https://www.instagram.com/izzy_clipz_/")
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

    func testCalendarNotesForFirstAvailableReadNaturally() {
        let appointment = Appointment(
            serviceID: "haircut",
            serviceName: "Haircut",
            barberID: nil,
            barberName: "First available",
            start: Date(timeIntervalSince1970: 1_793_395_800),
            durationMinutes: 45,
            priceLabel: "$45"
        )
        let notes = CalendarEventEditor.notes(for: appointment)
        XCTAssertTrue(notes.contains("Haircut with the first available barber"), notes)
        XCTAssertFalse(notes.contains("with First available"), notes)
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
