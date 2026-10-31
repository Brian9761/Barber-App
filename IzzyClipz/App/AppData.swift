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

/// What `-ui-testing` launches start with, set by launch arguments so each UI test gets the state
/// it needs without going through the app to make it.
@MainActor
enum UITestSetup {
    /// `-fakeSquireAppointment`: an appointment saved by the previous version of the app after
    /// booking on Squire, three days from now at 3 PM, with reminders on.
    static let squireAppointment = "-fakeSquireAppointment"
    /// `-fakeBookedAppointment`: an appointment already booked in the app (a haircut with Carlos).
    static let bookedAppointment = "-fakeBookedAppointment"
    /// `-fakeSavedDetails`: the client's name and number are already remembered.
    static let savedDetails = "-fakeSavedDetails"

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Runs before the appointments are read, so they find what the previous version left.
    static func prepareDefaults(_ defaults: UserDefaults) {
        guard arguments.contains(squireAppointment) else { return }
        let calendar = AppData.bookingCalendar
        let day = calendar.day(containing: Date()).adding(days: 3)
        guard let start = calendar.date(on: day, at: TimeOfDay(hour: 15)) else { return }
        let old = Appointment(
            serviceID: "haircut-and-beard",
            serviceName: "Haircut & Beard",
            barberID: "julian-ramos",
            barberName: "Julian",
            start: start,
            durationMinutes: 60,
            priceLabel: "$55"
        )
        if let data = try? AppointmentPlanner.encode([old]) {
            defaults.set(data, forKey: "appointments.v1")
            defaults.set([old.id.uuidString], forKey: "appointments.reminding.v1")
        }
    }

    static func seed(_ store: AppointmentStore, api: any ShopAPI, customerDetails: CustomerDetailsStore) {
        if arguments.contains(bookedAppointment), let fake = api as? FakeShopAPI, let confirmation = fake.seedBooking() {
            store.add(confirmation, remind: true)
        }
        if arguments.contains(savedDetails) {
            customerDetails.remember(CustomerDetails(name: "Sample Client", phone: "(442) 555-0123"))
        }
    }
}
