import Foundation
import IzzyClipzKit

/// Launch arguments the app understands. UI tests and previews use them to
/// run against the in-memory sample server instead of the real one.
enum LaunchArgument {
    /// The in-memory sample server, an in-memory keychain, a fixed clock
    /// (Monday, November 2, 2026, 11:05 AM in the shop) and the simulated
    /// card reader. Nothing touches the network, the keychain or Stripe.
    static let uiTesting = "-ui-testing"
    /// Start signed in with the sample owner key.
    static let signedIn = "-signed-in"
    /// Sample server problems.
    static let offline = "-fake-offline"
    static let ownerNotConfigured = "-fake-owner-not-configured"
    static let stripeNotConfigured = "-fake-stripe-not-configured"
    static let noLocation = "-fake-no-location"
    static let slotTaken = "-fake-slot-taken"
    static let paymentProcessing = "-fake-payment-processing"
    static let paymentIncomplete = "-fake-payment-incomplete"
    static let empty = "-fake-empty"
    /// Every sample server call takes a moment, so loading states show.
    static let slow = "-fake-slow"
}

/// What the app talks to and how: the real server and Tap to Pay, or the
/// sample server and the simulated reader.
@MainActor
final class AppEnvironment {
    enum Backend {
        case live(baseURL: URL)
        case sample(FakeServer)
    }

    let backend: Backend
    let secrets: SecretStore
    let shopTime: ShopTime
    let catalog: Catalog
    let clock: () -> Date
    let defaults: UserDefaults
    /// The card reader for real payments: Stripe's Tap to Pay, or the
    /// simulated one with the sample server.
    let terminal: any PaymentTerminal
    /// The reader for test mode.
    let practiceTerminal: SimulatedPaymentTerminal
    let deviceSupportsTapToPay: Bool
    /// Starts signed in (UI tests of the signed-in screens).
    let startsSignedIn: Bool
    /// Apple's own "How to Tap" screens can be shown (never in tests).
    let canShowAppleEducation: Bool

    init(
        backend: Backend,
        secrets: SecretStore,
        shopTime: ShopTime = ShopTime(),
        catalog: Catalog = .izzyClipz,
        clock: @escaping () -> Date,
        defaults: UserDefaults,
        terminal: any PaymentTerminal,
        practiceTerminal: SimulatedPaymentTerminal,
        deviceSupportsTapToPay: Bool,
        startsSignedIn: Bool = false,
        canShowAppleEducation: Bool
    ) {
        self.backend = backend
        self.secrets = secrets
        self.shopTime = shopTime
        self.catalog = catalog
        self.clock = clock
        self.defaults = defaults
        self.terminal = terminal
        self.practiceTerminal = practiceTerminal
        self.deviceSupportsTapToPay = deviceSupportsTapToPay
        self.startsSignedIn = startsSignedIn
        self.canShowAppleEducation = canShowAppleEducation
    }

    var usesSampleServer: Bool {
        if case .sample = backend { return true }
        return false
    }

    /// The API with an owner key (`nil` before signing in).
    func api(ownerKey: String?) -> any OwnerAPI {
        switch backend {
        case .live(let baseURL):
            return IzzyAPIClient(baseURL: baseURL, ownerKey: ownerKey)
        case .sample(let server):
            return server.api(ownerKey: ownerKey)
        }
    }

    /// The server's address, for Settings.
    var serverDescription: String {
        switch backend {
        case .live(let baseURL): return baseURL.host() ?? baseURL.absoluteString
        case .sample: return "Sample server (test mode)"
        }
    }

    // MARK: Making one

    /// The server address from Info.plist (`IzzyAPIBaseURL`).
    static func baseURL(bundle: Bundle = .main) -> URL {
        if let text = bundle.object(forInfoDictionaryKey: "IzzyAPIBaseURL") as? String,
           let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "https" {
            return url
        }
        return URL(string: "https://izzy-clipz-api.vercel.app")!
    }

    /// Monday, November 2, 2026 at 11:05 AM in the shop: UI tests' "now".
    static func uiTestNow(shopTime: ShopTime) -> Date {
        let day = LocalDate(year: 2026, month: 11, day: 2) ?? shopTime.day(containing: Date())
        return shopTime.date(on: day, hour: 11, minute: 5) ?? shopTime.noon(on: day)
    }

    /// The environment for this launch.
    static func forLaunch(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> AppEnvironment {
        let arguments = Set(processInfo.arguments)
        let runningUnitTests = processInfo.environment["XCTestConfigurationFilePath"] != nil
        if arguments.contains(LaunchArgument.uiTesting) || runningUnitTests {
            return sample(arguments: arguments, fixedClock: true, stepDelay: runningUnitTests ? .zero : .milliseconds(300))
        }
        let shopTime = ShopTime()
        let terminal: any PaymentTerminal
        #if canImport(StripeTerminal)
        terminal = StripeTapToPayTerminal()
        #else
        terminal = SimulatedPaymentTerminal()
        #endif
        return AppEnvironment(
            backend: .live(baseURL: baseURL(bundle: bundle)),
            secrets: KeychainSecretStore(),
            shopTime: shopTime,
            clock: { Date() },
            defaults: .standard,
            terminal: terminal,
            practiceTerminal: SimulatedPaymentTerminal(),
            deviceSupportsTapToPay: TapToPayEducation.isSupportedOnThisDevice,
            canShowAppleEducation: true
        )
    }

    /// The sample server with options from launch arguments: UI tests,
    /// previews and the unit tests' host app.
    static func sample(arguments: Set<String> = [], fixedClock: Bool = true, stepDelay: Duration = .milliseconds(300)) -> AppEnvironment {
        let shopTime = ShopTime()
        let fixedNow = uiTestNow(shopTime: shopTime)
        let clock: () -> Date = fixedClock ? { fixedNow } : { Date() }
        var options = FakeServer.Options()
        options.offline = arguments.contains(LaunchArgument.offline)
        options.ownerNotConfigured = arguments.contains(LaunchArgument.ownerNotConfigured)
        options.stripeConfigured = !arguments.contains(LaunchArgument.stripeNotConfigured)
        if arguments.contains(LaunchArgument.noLocation) { options.locationId = nil }
        options.takeNextSlot = arguments.contains(LaunchArgument.slotTaken)
        if arguments.contains(LaunchArgument.paymentProcessing) { options.completeStatusOverride = "processing" }
        if arguments.contains(LaunchArgument.paymentIncomplete) { options.completeStatusOverride = "requires_payment_method" }
        options.empty = arguments.contains(LaunchArgument.empty)
        if arguments.contains(LaunchArgument.slow) { options.latency = .milliseconds(600) }
        let server = FakeServer(options: options, shopTime: shopTime, now: clock)

        let terminal = SimulatedPaymentTerminal(stepDelay: stepDelay)
        terminal.onApproved = { [weak server] secret in server?.cardApproved(clientSecret: secret) }
        let suiteName = "com.izzyclipz.business.sample"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let signedIn = arguments.contains(LaunchArgument.signedIn)
        return AppEnvironment(
            backend: .sample(server),
            secrets: InMemorySecretStore(secret: signedIn ? FakeServer.ownerKey : nil),
            shopTime: shopTime,
            clock: clock,
            defaults: defaults,
            terminal: terminal,
            practiceTerminal: SimulatedPaymentTerminal(stepDelay: stepDelay),
            deviceSupportsTapToPay: true,
            startsSignedIn: signedIn,
            canShowAppleEducation: false
        )
    }
}
