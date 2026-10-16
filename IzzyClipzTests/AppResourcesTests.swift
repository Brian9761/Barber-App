import UIKit
import XCTest
@testable import IzzyClipz

/// Checks for problems the compiler can't catch: misspelled SF Symbols,
/// missing images, and Info.plist settings.
final class AppResourcesTests: XCTestCase {
    func testEverySymbolExists() {
        for name in Symbol.all {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol '\(name)' doesn't exist")
        }
    }

    func testBundledImagesExist() {
        for photo in GalleryPhoto.allCases {
            XCTAssertNotNil(UIImage(named: photo.assetName), photo.assetName)
        }
        XCTAssertNotNil(UIImage(named: Asset.storefront))
        XCTAssertNotNil(UIImage(named: Asset.hero))
        XCTAssertNotNil(UIImage(named: Asset.launchLogo))
    }

    func testBrandColorsExist() {
        XCTAssertNotNil(UIColor(named: "AccentColor"))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
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

    func testPrivacyManifestIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testBookingLinksAreWebLinks() {
        // The in-app browser only accepts http(s) URLs and crashes on anything else.
        XCTAssertEqual(AppData.bookingURL(for: .anything).scheme, "https")
        for offering in AppData.catalog.offerings {
            XCTAssertEqual(AppData.bookingURL(for: .offering(offering)).scheme, "https", offering.id)
        }
        for barber in AppData.catalog.barbers {
            XCTAssertEqual(AppData.bookingURL(for: .barber(barber.id)).scheme, "https", barber.id)
        }
    }

    func testContactLinks() {
        XCTAssertEqual(AppData.shop.phone.callURL.scheme, "tel")
        XCTAssertEqual(AppData.shop.instagramURL.scheme, "https")
        XCTAssertEqual(AppData.shop.websiteURL.scheme, "https")
        XCTAssertEqual(AppData.shop.appleMapsDirectionsURL.scheme, "https")
        XCTAssertEqual(AppData.shop.googleMapsDirectionsURL.scheme, "https")
        XCTAssertNotNil(URL(string: UIApplication.openNotificationSettingsURLString))
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
