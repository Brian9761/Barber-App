import Foundation
import IzzyClipzKit
import Observation

/// Everything the signed-in owner works with. Made fresh at every sign in and
/// dropped at sign out, so nothing from one key is left for the next.
@MainActor
@Observable
final class Workspace {
    enum Tab: Hashable {
        case schedule, newBooking, payment, products, settings
    }

    let environment: AppEnvironment
    let api: any OwnerAPI
    let ownerKey: String
    var selectedTab: Tab = .schedule

    private(set) var ownerStatus: IzzyAPI.OwnerStatus?
    private(set) var statusError: String?
    private(set) var isCheckingStatus = false
    /// The server turned the saved key down (it was changed there).
    private(set) var keyWasRejected = false
    private(set) var health: IzzyAPI.Health?
    private(set) var healthError: String?
    /// Set when the keychain wouldn't keep the owner key.
    var keySaveError: String?

    /// Shows the app's own "How to Tap" steps (when Apple's can't be shown).
    var showsHowToTap = false
    /// Tap to Pay was connected on this iPhone before, so it's warmed up at
    /// launch and in the foreground without surprising the owner with Apple's
    /// terms.
    private(set) var hasSetUpTapToPay: Bool
    private(set) var tapToPaySetupError: String?
    private(set) var isSettingUpTapToPay = false

    let schedule: ScheduleStore
    let booking: NewBookingStore
    let checkout: CheckoutModel
    let products: ProductsStore

    private static let setUpKey = "hasSetUpTapToPay"
    fileprivate static let educationKey = "hasSeenHowToTap"

    init(environment: AppEnvironment, ownerKey: String, status: IzzyAPI.OwnerStatus?) {
        self.environment = environment
        self.ownerKey = ownerKey
        let api = environment.api(ownerKey: ownerKey)
        self.api = api
        self.ownerStatus = status
        self.hasSetUpTapToPay = environment.defaults.bool(forKey: Self.setUpKey)
        let schedule = ScheduleStore(api: api, shopTime: environment.shopTime, catalog: environment.catalog, clock: environment.clock)
        self.schedule = schedule
        self.booking = NewBookingStore(api: api, shopTime: environment.shopTime, catalog: environment.catalog, clock: environment.clock)
        self.checkout = CheckoutModel(
            api: api,
            shopTime: environment.shopTime,
            clock: environment.clock,
            terminal: environment.terminal,
            practiceTerminal: environment.practiceTerminal,
            pending: PendingPayments(defaults: environment.defaults),
            usesSampleServer: environment.usesSampleServer,
            deviceSupportsTapToPay: environment.deviceSupportsTapToPay
        )
        self.products = ProductsStore(api: api)
        checkout.update(stripe: status?.stripe)
        checkout.onPaid = { [weak schedule] _ in
            Task { await schedule?.refresh() }
        }
        booking.onBooked = { [weak schedule] appointment in
            schedule?.didBook(appointment)
        }
        checkout.onReaderConnected = { [weak self] in
            self?.noteTapToPayConnected()
        }
        #if canImport(StripeTerminal)
        if case .live = environment.backend {
            TerminalTokenProvider.shared.use { try await api.connectionToken() }
        }
        if let stripe = environment.terminal as? StripeTapToPayTerminal {
            // Freshly accepted terms (a new iPhone or Stripe account): show "How to Tap" again.
            let defaults = environment.defaults
            stripe.onTermsAccepted = { defaults.set(false, forKey: Workspace.educationKey) }
        }
        #endif
    }

    /// Right after signing in with a new key.
    func didSignIn() async {
        await warmUpTapToPay()
    }

    /// Before signing out or switching keys.
    func tearDown() async {
        checkout.onReaderConnected = nil
        #if canImport(StripeTerminal)
        TerminalTokenProvider.shared.use(nil)
        (environment.terminal as? StripeTapToPayTerminal)?.onTermsAccepted = nil
        #endif
        await environment.terminal.disconnect()
        await environment.practiceTerminal.disconnect()
    }

    // MARK: Server status

    /// `GET /api/owner/me`: checks the key and Stripe's status.
    func refreshStatus() async {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        do {
            let status = try await api.ownerStatus()
            ownerStatus = status
            statusError = nil
            checkout.update(stripe: status.stripe)
        } catch is CancellationError {
            return
        } catch {
            if case .unauthorized? = error as? APIError { keyWasRejected = true }
            statusError = AppModel.signInMessage(for: error)
        }
    }

    /// `GET /api/health`, for Settings.
    func refreshHealth() async {
        do {
            health = try await api.health()
            healthError = nil
        } catch is CancellationError {
            return
        } catch {
            health = nil
            healthError = ErrorText.message(for: error)
        }
    }

    // MARK: Tap to Pay

    /// Connects Tap to Pay ahead of time when it was set up on this iPhone
    /// before (Apple asks apps to warm up at launch and in the foreground).
    func warmUpTapToPay() async {
        guard hasSetUpTapToPay || environment.usesSampleServer else { return }
        await checkout.warmUp()
    }

    /// "Set up Tap to Pay on iPhone": connects (Apple shows its terms the
    /// first time), then shows "How to Tap" once.
    func setUpTapToPay() async {
        guard !isSettingUpTapToPay else { return }
        guard let locationId = checkout.locationId else {
            switch checkout.mode {
            case .unavailable(let issue): tapToPaySetupError = issue.message
            case .practice(.deviceUnsupported): tapToPaySetupError = TerminalIssue.notSupportedOnThisPhone.message
            default: tapToPaySetupError = "Card payments aren't ready yet. Check the server status above."
            }
            return
        }
        isSettingUpTapToPay = true
        defer { isSettingUpTapToPay = false }
        do {
            try await checkout.currentTerminal.prepare(locationId: locationId)
            tapToPaySetupError = nil
            hasSetUpTapToPay = true
            environment.defaults.set(true, forKey: Self.setUpKey)
            if !environment.defaults.bool(forKey: Self.educationKey) {
                await showHowToTap()
            }
        } catch {
            tapToPaySetupError = ErrorText.message(for: error)
        }
    }

    /// Apple's "How to Tap" screens, or the app's own when those can't show.
    func showHowToTap() async {
        environment.defaults.set(true, forKey: Self.educationKey)
        if environment.canShowAppleEducation, await TapToPayEducation.presentAppleContent() {
            return
        }
        showsHowToTap = true
    }

    /// Called when a payment connected Tap to Pay for the first time.
    func noteTapToPayConnected() {
        guard !hasSetUpTapToPay, case .live = checkout.mode else { return }
        hasSetUpTapToPay = true
        environment.defaults.set(true, forKey: Self.setUpKey)
    }

    /// Whether "How to Tap" still has to be shown once.
    var owesHowToTap: Bool {
        hasSetUpTapToPay && !environment.defaults.bool(forKey: Self.educationKey)
    }

    // MARK: Navigation

    /// Take payment for an appointment: switches to the Take payment tab
    /// with its price filled in. `false` while another payment is running.
    @discardableResult
    func takePayment(for appointment: IzzyAPI.Appointment) -> Bool {
        let context = CheckoutModel.AppointmentContext(appointment: appointment, catalog: environment.catalog)
        guard checkout.prefill(context) else { return false }
        selectedTab = .payment
        return true
    }
}
