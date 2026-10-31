import Foundation

/// The shop's data, shared app-wide.
enum AppData {
    static let shop = ShopInfo.izzyClipz
    static let catalog = Catalog.izzyClipz
    static let clock = shop.clock
    /// Day and time picking for appointments, in the shop's time zone.
    static let bookingCalendar = BookingCalendar(clock: clock)
}

/// Where the shop's reviews live on Google and Yelp.
enum ReviewLinks {
    /// The shop's Yelp page, for "Read our reviews on Yelp" when the server has no Yelp data.
    static let yelpPage = URL(string: "https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside")!
}

/// Launch configuration, so UI tests run against a clean, predictable app.
enum LaunchOptions {
    static let uiTestingArgument = "-ui-testing"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    /// Settings storage. UI tests get a throwaway store that starts empty on every launch.
    static let defaults: UserDefaults = {
        guard isUITesting else { return .standard }
        let suite = "com.izzyclipz.app.ui-testing"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}

/// Photos of the shop's work, bundled from izzyclipzbarbershop.net.
enum GalleryPhoto: Int, CaseIterable, Identifiable, Hashable {
    case curls = 1
    case blueColor
    case fullBeard
    case fadeAndBeard
    case classicBeard
    case texturedCrop

    var id: Int { rawValue }

    var assetName: String { "Gallery\(rawValue)" }

    /// Describes the cut for VoiceOver.
    var caption: String {
        switch self {
        case .curls: return "Curly top with a taper fade"
        case .blueColor: return "Blue color with a fade"
        case .fullBeard: return "Fade with a full, shaped beard"
        case .fadeAndBeard: return "Short fade with a lined-up beard"
        case .classicBeard: return "Classic cut with a groomed beard"
        case .texturedCrop: return "Textured crop with a fade"
        }
    }
}

enum Asset {
    static let storefront = "Storefront"
    static let hero = GalleryPhoto.texturedCrop.assetName
    static let launchLogo = "LaunchLogo"
    /// The shop's official logo, transparent background.
    static let logo = "Logo"
    /// The barber-pole mascot from the logo, transparent background.
    static let mascot = "LogoMascot"

    /// Every bundled image the app refers to, for a test to check.
    static var all: [String] {
        [storefront, hero, launchLogo, logo, mascot]
            + GalleryPhoto.allCases.map(\.assetName)
    }
}
