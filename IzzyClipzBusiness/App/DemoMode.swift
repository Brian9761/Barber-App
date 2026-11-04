import Foundation

/// The demo version: the owner app on the in-memory sample server, so it can be tried before the
/// shop's server and Stripe are set up.
///
/// It's chosen when the app is built, never at run time: the build setting `IZZY_DEMO_MODE` (NO in
/// project.yml; the test builds set YES), which Info.plist passes on as `IzzyDemoMode`. The demo
/// starts signed in with the sample owner key on `FakeServer`, with the real clock, and takes
/// payments with the simulated reader ("Test mode — no real charge": no card is read and no money
/// moves). Settings says it's the demo. Like the sample server, it forgets everything when the app
/// closes.
enum DemoMode {
    /// The Info.plist key: `$(IZZY_DEMO_MODE)`, so "YES" in the demo version and "NO" in every
    /// other build.
    static let infoKey = "IzzyDemoMode"

    /// Shown in Settings, and on the sign-in screen after signing out.
    static let notice = "Demo version: sample data, no real money."

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

    /// How long the sample server takes to answer, so loading states show for a moment, as they
    /// would over the network.
    static let serverLatency: Duration = .milliseconds(250)
    /// How long each step of the simulated reader takes (getting ready, reading the test card).
    static let readerStepDelay: Duration = .milliseconds(500)

    /// The demo's environment: the sample server and the simulated reader with the real clock,
    /// signed in with the sample owner key.
    @MainActor
    static func environment() -> AppEnvironment {
        let environment = AppEnvironment.sample(arguments: [LaunchArgument.signedIn], fixedClock: false, stepDelay: readerStepDelay)
        if case .sample(let server) = environment.backend {
            server.options.latency = serverLatency
        }
        return environment
    }
}
