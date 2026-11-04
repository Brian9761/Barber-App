import Foundation
import UserNotifications

/// The demo version: the app on its own sample data, so it can be tried before the shop's server
/// is up.
///
/// It's chosen when the app is built, never at run time: the build setting `IZZY_DEMO_MODE` (NO in
/// project.yml; the test builds set YES), which Info.plist passes on as `IzzyDemoMode`. In the demo
/// the app talks to the in-memory `FakeShopAPI` (the shop's real menu, team and hours, sample
/// reviews and products, open times from the real clock), never the network, and says so on Home
/// and when booking (`DemoNotice`).
///
/// Like that server, the demo forgets everything when the app closes: settings and appointments
/// start empty on every launch, booking tokens and a card added for no-show protection are kept in
/// memory (the card is "added" without opening Stripe's page), and reminders scheduled by an
/// earlier launch are dropped.
enum DemoMode {
    /// The Info.plist key: `$(IZZY_DEMO_MODE)`, so "YES" in the demo version and "NO" in every
    /// other build.
    static let infoKey = "IzzyDemoMode"

    /// Shown wherever a tester would otherwise take a booking for the real thing.
    static let notice = "Demo version: bookings aren't sent to the shop."

    /// Whether this is the demo version.
    static let isOn = isEnabled(in: .main)

    static func isEnabled(in bundle: Bundle) -> Bool {
        isEnabled(bundle.object(forInfoDictionaryKey: infoKey))
    }

    /// An Info.plist value as a Boolean: YES, 1 or true (any case) as text, a number or a Boolean.
    /// Anything else is off, including no value at all and an unexpanded `$(IZZY_DEMO_MODE)`.
    static func isEnabled(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as Int:
            return number == 1
        case let text as String:
            return ["yes", "1", "true"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        default:
            return false
        }
    }

    /// The demo's server: in memory, with the real clock and none of the UI tests' switches (no
    /// failures on purpose, no held bookings).
    @MainActor
    static func makeShopAPI() -> any ShopAPI {
        FakeShopAPI(options: FakeShopAPI.Options())
    }

    /// The settings store the demo uses instead of the standard one.
    static let defaultsSuite = "com.izzyclipz.app.demo"

    /// Starts the demo afresh and returns its settings store, emptied. Reminders scheduled by an
    /// earlier launch go too: they're for bookings the new in-memory server has never heard of.
    /// `LaunchOptions.defaults` calls it once, before anything reads a setting.
    static func startFresh() -> UserDefaults {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        defaults.removePersistentDomain(forName: defaultsSuite)
        return defaults
    }
}
