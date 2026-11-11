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
    /// Also clients who booked online with a card on file: Kim Sample (10 AM, a no-show), Lee
    /// Sample (11:30 AM, cancelled in the app at 10:50 AM: a late cancellation) and Nia Sample
    /// (2:30 PM, booked). All with Flowxbori, $35 haircuts, the full price as the fee. No-show
    /// protection starts on, as they booked with it on.
    static let cardsOnFile = "-fake-cards-on-file"
    /// The next fee charged to a card on file is declined (not enough money on the card).
    static let noShowDeclined = "-fake-no-show-declined"
    /// The next fee charged to a card on file needs the client to approve it with their bank.
    static let noShowNeedsAction = "-fake-no-show-needs-action"
    /// The next fee charged to a card on file never reaches Stripe: it waits, and Check again charges it.
    static let noShowUnreachable = "-fake-no-show-unreachable"
    /// The next fee charged to a card on file goes through (or is declined, with `noShowDeclined`), but
    /// the answer is lost on the way back: the app loads the day again and shows what happened.
    static let noShowAnswerLost = "-fake-no-show-answer-lost"
    /// The shop's own Stripe account isn't connected yet (Stripe Connect): Settings offers Connect
    /// Stripe, which connects the sample account straight away (a stand-in for Stripe's window).
    static let stripeNotConnected = "-fake-stripe-not-connected"
    /// Not connected yet, and the first Connect Stripe comes back with details still missing:
    /// Settings then offers Finish setting up.
    static let stripeNeedsInfo = "-fake-stripe-needs-info"
    /// Not connected yet, and the owner closes Stripe's window the first time.
    static let stripeCancel = "-fake-stripe-cancel"
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
    /// The shop's website (Info.plist `IzzyWebsiteURL`), where Settings → Legal opens the legal pages.
    let websiteURL: URL
    /// With the sample server: what the stand-in for Stripe's window does the first time (launch
    /// arguments), and how long it takes (a moment in the demo, so it reads as a step).
    var stripeFirstTry: FakeStripeConnector.FirstTry = .finishes
    var stripeWindowDelay: Duration = .zero
    /// Ask iOS for the person's age range at launch (`AgeCheck`): the real app and the demo, never UI
    /// tests, unit tests or previews (iOS's sheet would get in their way).
    var asksForAgeRange = false

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
        canShowAppleEducation: Bool,
        websiteURL: URL = Website.baseURL()
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
        self.websiteURL = websiteURL
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

    /// What opens Stripe's window for Settings → Connect Stripe: Stripe's real pages in
    /// `ASWebAuthenticationSession`, or the sample server's stand-in.
    func makeStripeConnector() -> any StripeConnector {
        switch backend {
        case .sample(let server):
            return FakeStripeConnector(server: server, firstTry: stripeFirstTry, delay: stripeWindowDelay)
        case .live:
            #if canImport(AuthenticationServices)
            return WebStripeConnector()
            #else
            return UnavailableStripeConnector()
            #endif
        }
    }

    /// Where the website's Business area is, for Settings → Use on a computer: the server's own site
    /// (the same address as the API, where the codes work), or with the sample server the demo
    /// website, whose Business area opens without a code.
    var businessSiteAddress: String {
        switch backend {
        case .live(let baseURL): return (baseURL.host() ?? baseURL.absoluteString) + "/business"
        case .sample: return (websiteURL.host() ?? "izzy-clipz.vercel.app") + "/business"
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
        if DemoMode.isEnabled(in: bundle) {
            return DemoMode.environment()
        }
        let shopTime = ShopTime()
        let terminal: any PaymentTerminal
        #if canImport(StripeTerminal)
        terminal = StripeTapToPayTerminal()
        #else
        terminal = SimulatedPaymentTerminal()
        #endif
        let environment = AppEnvironment(
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
        environment.asksForAgeRange = true
        return environment
    }

    /// The sample server with options from launch arguments: UI tests,
    /// previews, the unit tests' host app and the demo version (`DemoMode`).
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
        if arguments.contains(LaunchArgument.cardsOnFile) {
            options.noShowWithCard = true
            options.lateCancelWithCard = true
            options.upcomingWithCard = true
        }
        if arguments.contains(LaunchArgument.noShowDeclined) { options.nextFeeAnswer = .declined }
        if arguments.contains(LaunchArgument.noShowNeedsAction) { options.nextFeeAnswer = .needsAction }
        options.nextFeeChargeFails = arguments.contains(LaunchArgument.noShowUnreachable)
        options.loseNextFeeAnswer = arguments.contains(LaunchArgument.noShowAnswerLost)
        var stripeFirstTry = FakeStripeConnector.FirstTry.finishes
        if arguments.contains(LaunchArgument.stripeNeedsInfo) { stripeFirstTry = .leavesDetailsMissing }
        if arguments.contains(LaunchArgument.stripeCancel) { stripeFirstTry = .closesTheWindow }
        if [LaunchArgument.stripeNotConnected, LaunchArgument.stripeNeedsInfo, LaunchArgument.stripeCancel].contains(where: arguments.contains) {
            options.stripeAccount = .none
        }
        let server = FakeServer(options: options, shopTime: shopTime, now: clock)

        let terminal = SimulatedPaymentTerminal(stepDelay: stepDelay)
        terminal.onApproved = { [weak server] secret in server?.cardApproved(clientSecret: secret) }
        let suiteName = "com.izzyclipz.business.sample"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let signedIn = arguments.contains(LaunchArgument.signedIn)
        let environment = AppEnvironment(
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
        environment.stripeFirstTry = stripeFirstTry
        return environment
    }
}
