import Foundation

/// An in-memory stand-in for the shop's server, for UI tests (`-ui-testing`) and previews. It never
/// touches the network.
///
/// It answers like the real server (the same models, the same error codes), from the app's own
/// catalog and booking calendar:
/// - "Now" is frozen when it starts, so the times it offers don't move while a test runs.
/// - Every barber already has one booking each open day (an hour, at a different time per
///   barber), so the time lists have gaps like a real day.
/// - Bookings, look-ups and cancellations work on what it holds in memory.
/// - A booking keeps the manage token it was sent with. A retry with that token and the same
///   booking gets the same appointment back; the same token for another booking is turned down.
/// - No-show protection is off, as on the server until the owner turns it on. With
///   `-fakeNoShowProtection` it's on with the server's starting settings (the full service price
///   for a no-show or a cancellation less than 1 hour before): it gives the same policy and warning,
///   makes Checkout Sessions (`completeCardCheckout` stands for the client on Stripe's page), saves
///   cards under their tokens, and turns a booking down without a usable card (`card_required`) or
///   with another policy than today's (`policy_changed`), with the server's words.
///
/// Launch arguments make it misbehave on purpose, so the app's error states can be tested; see
/// `Options`. Everything it returns that isn't the shop's real menu (sample reviews, sample
/// products) is test data and says so.
@MainActor
final class FakeShopAPI: ShopAPI {
    struct Options: Equatable {
        /// `-fakeOffline`: every request fails as if the phone were offline.
        var offline = false
        /// `-fakeBookingOffline`: the first booking attempt fails as offline; a retry works.
        var bookingOfflineOnce = false
        /// `-fakeLoseBookingResponse`: the first booking goes through, but its answer is lost on
        /// the way back and the app sees it as offline. A retry with the same token gets it.
        var loseBookingResponseOnce = false
        /// `-fakeSlotTaken`: the first booking attempt finds the time just taken, and that time
        /// disappears from the list.
        var slotTakenOnce = false
        /// `-fakeSlowBooking`: the first booking doesn't answer until the app asks for open times
        /// again (the client has started another booking and reached its times), or until
        /// `slowBookingLimit` has passed. So the app can be used while it's on its way, however
        /// slow the simulator is.
        var slowBookingOnce = false
        /// `-fakeNoProducts`: the shop hasn't added any products yet.
        var noProducts = false
        /// `-fakeReviewsUnavailable`: Google's reviews can't be loaded (not set up, or over the
        /// daily limit) and Yelp isn't set up.
        var reviewsUnavailable = false
        /// `-fakeYelp`: the server also returns Yelp reviews.
        var yelp = false
        /// `-fakeShopCancels`: appointments the fake already holds come back cancelled by the shop.
        var shopCancels = false
        /// The owner's no-show settings. Off to start with, as on the server. `-fakeNoShowProtection`
        /// turns protection on (the full service price for a no-show or a cancellation less than 1
        /// hour before); `-fakeNoLateCancel` turns late cancellations off with it (no-shows only).
        var noShowSettings = IzzyAPI.NoShowSettings.default
        /// How long each answer takes, so loading states show briefly.
        var latency: Duration = .milliseconds(150)

        static let noShowProtectionArgument = "-fakeNoShowProtection"
        static let noLateCancelArgument = "-fakeNoLateCancel"

        init() {}

        init(arguments: [String]) {
            offline = arguments.contains("-fakeOffline")
            bookingOfflineOnce = arguments.contains("-fakeBookingOffline")
            loseBookingResponseOnce = arguments.contains("-fakeLoseBookingResponse")
            slotTakenOnce = arguments.contains("-fakeSlotTaken")
            slowBookingOnce = arguments.contains("-fakeSlowBooking")
            noProducts = arguments.contains("-fakeNoProducts")
            reviewsUnavailable = arguments.contains("-fakeReviewsUnavailable")
            yelp = arguments.contains("-fakeYelp")
            shopCancels = arguments.contains("-fakeShopCancels")
            noShowSettings.enabled = arguments.contains(Self.noShowProtectionArgument)
            if arguments.contains(Self.noLateCancelArgument) {
                noShowSettings.lateCancelEnabled = false
            }
        }
    }

    private struct Stored {
        var appointment: IzzyAPI.Appointment
        let token: String
        /// Made before the app started (a seeded booking), so `shopCancels` applies to it.
        let isSeeded: Bool
        /// What was asked for, to recognize a retry; `nil` for a seeded booking.
        var request: IzzyAPI.NewAppointment? = nil
    }

    /// A Checkout Session in setup mode, as Stripe keeps it for the server.
    private struct CheckoutSession {
        let id: String
        /// The card token the app started it with (the server keeps its hash in the metadata).
        let token: String
        /// Set once the client saved a card on Stripe's page.
        var card: IzzyAPI.SavedCard?
    }

    /// A card the server saved, under the card token it was saved with.
    private struct SavedCardRecord {
        let sessionId: String
        let card: IzzyAPI.SavedCard
    }

    /// Who pays what for a no-show or a late cancellation, as the server works it out for a booking.
    private struct Protection {
        let policy: IzzyAPI.NoShowPolicy
        /// The fee for each offering the booking may get, by offering ID; none when it has no fee.
        let fees: [String: Int]
    }

    private var options: Options
    private let now: Date
    private let calendar: BookingCalendar
    private let catalog: Catalog
    private let shop: ShopInfo
    private var stored: [String: Stored] = [:]
    /// Barber ID → times they can't take anyone (the sample bookings, plus everything booked here).
    private var busy: [String: [DateInterval]] = [:]
    private var bookingCount = 0
    private var checkoutSessions: [String: CheckoutSession] = [:]
    private var savedCards: [String: SavedCardRecord] = [:]

    /// The owner's no-show settings. Tests change them to stand for the owner changing them in the
    /// Business app (the policy changes, and a booking sent with the old one is turned down).
    var noShowSettings: IzzyAPI.NoShowSettings {
        get { options.noShowSettings }
        set { options.noShowSettings = newValue }
    }

    init(
        options: Options = Options(),
        now: Date = Date(),
        calendar: BookingCalendar = AppData.bookingCalendar,
        catalog: Catalog = AppData.catalog,
        shop: ShopInfo = AppData.shop
    ) {
        self.options = options
        self.now = now
        self.calendar = calendar
        self.catalog = catalog
        self.shop = shop
        addSampleBookings()
    }

    // MARK: ShopAPI

    func health() async throws -> IzzyAPI.Health {
        try await respond()
        return IzzyAPI.Health(version: "fake")
    }

    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        // Another booking has reached its times: let a held booking answer.
        holdsBooking = false
        try await respond()
        guard IzzyAPI.availabilityDaysRange.contains(query.days) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Ask for 1 to 31 days.", status: 400)
        }
        // Every day asked for is listed, empty when nothing is free, as on the server. An unknown
        // offering or service throws, also as on the server.
        var days: [IzzyAPI.DaySlots] = []
        for offset in 0..<query.days {
            let date = query.from.adding(days: offset)
            days.append(IzzyAPI.DaySlots(date: date, slots: try slots(on: date, for: query.target)))
        }
        return IzzyAPI.AvailabilityResponse(timeZone: shop.timeZoneIdentifier, days: days)
    }

    /// The longest the first booking waits with `slowBookingOnce`.
    static let slowBookingLimit: Duration = .seconds(120)

    /// A booking held back by `slowBookingOnce`, until the next request for open times.
    private var holdsBooking = false

    func book(_ request: IzzyAPI.NewAppointment, token manageToken: IzzyAPI.ManageToken) async throws -> IzzyAPI.BookingConfirmation {
        try await respond()
        if options.slowBookingOnce {
            options.slowBookingOnce = false
            holdsBooking = true
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.slowBookingLimit)
            while holdsBooking, clock.now < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            holdsBooking = false
        }
        if options.bookingOfflineOnce {
            options.bookingOfflineOnce = false
            throw APIError.offline
        }
        // A retry of a booking that went through: the same appointment, as it is now, before
        // any time rules (as on the server).
        if let earlier = stored.values.first(where: { $0.token == manageToken.rawValue }) {
            guard let asked = earlier.request, Self.isSameBooking(asked, request) else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That booking token was already used.", status: 400)
            }
            return IzzyAPI.BookingConfirmation(appointment: earlier.appointment, manageToken: earlier.token)
        }
        let name = request.customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Enter your name.", status: 400)
        }
        guard let phone = request.customer.phone.flatMap(PhoneNumber.init(parsing:)) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Enter a US mobile number, like (442) 341-3053.", status: 400)
        }
        let day = LocalDate(calendar.day(containing: request.start))
        let open = try slots(on: day, for: request.target)
        // The server's order: the time rules first, then what no-show protection needs (a usable
        // card and today's policy), then whether the time is still free.
        if let problem = try timeRuleProblem(for: request.start, day: day, target: request.target) {
            throw problem
        }
        let protection = try protection(for: request.target)
        let card = try cardOnFile(for: request, protection: protection)
        if options.slotTakenOnce {
            options.slotTakenOnce = false
            // Someone else got there first: the time is gone for everyone who could do it.
            for barberID in open.first(where: { $0.start == request.start })?.barberIds ?? [] {
                markBusy(barberID, from: request.start, minutes: 60)
            }
            throw APIError.slotTaken
        }
        guard let slot = open.first(where: { $0.start == request.start }),
              let offering = offering(for: request.target, freeBarbers: slot.barberIds)
        else { throw APIError.slotTaken }
        var appointment = makeAppointment(offering: offering, start: request.start, name: name, phone: phone.e164, note: request.note)
        // The fee agreed for the barber it lands with ("any barber" may land with any of them), the
        // window the policy states, and the card, as the server keeps them.
        if let card, let fee = protection.fees[offering.id] {
            appointment.card = card.cardOnFile
            appointment.noShowFee = IzzyAPI.NoShowFee(
                amountCents: fee,
                fullPrice: fee == offering.price.cents,
                lateCancelWindowMinutes: protection.policy.lateCancelWindowMinutes
            )
        }
        bookingCount += 1
        let token = manageToken.rawValue
        stored[appointment.id] = Stored(appointment: appointment, token: token, isSeeded: false, request: request)
        markBusy(offering.barberID, from: appointment.start, minutes: appointment.durationMinutes)
        if options.loseBookingResponseOnce {
            // Booked, but the answer never reaches the phone.
            options.loseBookingResponseOnce = false
            throw APIError.offline
        }
        return IzzyAPI.BookingConfirmation(appointment: appointment, manageToken: token)
    }

    /// How many appointments were booked through it (seeded ones not counted). For tests.
    var bookingsMade: Int { bookingCount }

    /// The server's rule for a retry: the same target asked for the same way, the same start and
    /// the same phone number. The name and note may differ.
    private static func isSameBooking(_ earlier: IzzyAPI.NewAppointment, _ retry: IzzyAPI.NewAppointment) -> Bool {
        func phone(_ request: IzzyAPI.NewAppointment) -> String? {
            request.customer.phone.flatMap(PhoneNumber.init(parsing:))?.e164
        }
        return earlier.target == retry.target && earlier.start == retry.start && phone(earlier) == phone(retry)
    }

    func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        try await respond()
        guard var entry = stored[id], entry.token == manageToken else {
            // The real server answers a wrong token with a plain 404, so IDs can't be probed.
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "", status: 404)
        }
        if options.shopCancels, entry.isSeeded, entry.appointment.status == .booked {
            entry.appointment.status = .cancelled
            entry.appointment.cancelledBy = .shop
            stored[id] = entry
        }
        return entry.appointment
    }

    func cancelAppointment(id: String, manageToken: String, acceptLateCancelFee: Bool) async throws -> IzzyAPI.Appointment {
        try await respond()
        guard var entry = stored[id], entry.token == manageToken else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "", status: 404)
        }
        guard entry.appointment.isCancellable(at: now) else {
            // Asked before the start, but the shop had marked it: as on the server, the request still
            // counts for a booking with a card on file (it's never charged as a no-show then).
            if entry.appointment.start > now, var fee = entry.appointment.noShowFee, fee.customerCancelledAt == nil {
                fee.customerCancelledAt = now
                entry.appointment.noShowFee = fee
                stored[id] = entry
            }
            throw APIError.notCancellable
        }
        // Inside the late-cancellation window the booking agreed to, the server asks first and changes
        // nothing (the warning counts from the client's first cancel time, as there).
        if !acceptLateCancelFee, let warning = entry.appointment.lateCancelWarning(at: now) {
            throw APIError.lateCancelFee(message: warning)
        }
        entry.appointment.status = .cancelled
        entry.appointment.cancelledBy = .customer
        if var fee = entry.appointment.noShowFee {
            // The first time counts, and the fee's reason is the case that applies now (a late cancellation, or none).
            fee.customerCancelledAt = fee.customerCancelledAt ?? now
            if fee.status == .none {
                let found = IzzyAPI.NoShowRule.feeCase(
                    status: .cancelled, cancelledBy: .customer, start: entry.appointment.start,
                    customerCancelledAt: fee.customerCancelledAt, lateCancelWindowMinutes: fee.lateCancelWindowMinutes,
                    createdAt: entry.appointment.createdAt
                )
                if case .chargeable(let reason) = found { fee.reason = reason } else { fee.reason = nil }
            }
            entry.appointment.noShowFee = fee
        }
        stored[id] = entry
        let appointment = entry.appointment
        busy[appointment.barberId]?.removeAll { $0.start == appointment.start }
        return appointment
    }

    /// Holds `appointment` as if this phone had booked it with `token`: say one with a card on file
    /// and a policy it couldn't book at this moment (a start inside the late-cancellation window).
    /// For tests.
    func hold(_ appointment: IzzyAPI.Appointment, token: String) {
        stored[appointment.id] = Stored(appointment: appointment, token: token, isSeeded: false)
    }

    func reviews() async throws -> IzzyAPI.ReviewsResponse {
        try await respond()
        let yelpPage = ReviewLinks.yelpPage
        guard !options.reviewsUnavailable else {
            return IzzyAPI.ReviewsResponse(
                google: IzzyAPI.ReviewSource(available: false, url: shop.googleMapsURL),
                yelp: IzzyAPI.ReviewSource(available: false, url: yelpPage)
            )
        }
        // TEST DATA: sample numbers and reviews for the app's automated tests and screenshots.
        // They are not the shop's rating and not anyone's real words; the real ones come from
        // Google (and Yelp) through the shop's server.
        let google = IzzyAPI.ReviewSource(
            available: true,
            rating: 4.5,
            count: 20,
            url: shop.googleMapsURL,
            reviews: [
                IzzyAPI.Review(
                    author: "Sample reviewer A",
                    authorUrl: URL(string: "https://www.google.com/maps/contrib/sample-a"),
                    rating: 5,
                    text: "Sample review text for the app's tests. Real reviews come from Google Maps.",
                    relativeTime: "a week ago",
                    url: URL(string: "https://www.google.com/maps/reviews/sample-a")
                ),
                IzzyAPI.Review(
                    author: "Sample reviewer B",
                    rating: 4,
                    text: "A second sample review, used only to test how reviews are laid out.",
                    relativeTime: "a month ago",
                    url: URL(string: "https://www.google.com/maps/reviews/sample-b")
                ),
            ],
            fetchedAt: now
        )
        let yelp: IzzyAPI.ReviewSource
        if options.yelp {
            // TEST DATA, like the Google sample above.
            yelp = IzzyAPI.ReviewSource(
                available: true,
                rating: 4.5,
                count: 10,
                url: yelpPage,
                reviews: [
                    IzzyAPI.Review(
                        author: "Sample Yelp reviewer",
                        rating: 5,
                        text: "Sample Yelp excerpt for the app's tests…",
                        url: URL(string: "https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside?hrid=sample")
                    ),
                ],
                fetchedAt: now
            )
        } else {
            yelp = IzzyAPI.ReviewSource(available: false, url: yelpPage)
        }
        return IzzyAPI.ReviewsResponse(google: google, yelp: yelp)
    }

    func products() async throws -> [IzzyAPI.Product] {
        try await respond()
        guard !options.noProducts else { return [] }
        // TEST DATA: placeholder products for the app's tests. No photos (the tests never load
        // images from the network), and one without a price, as the shop may list them.
        return [
            IzzyAPI.Product(
                id: "sample-pomade",
                name: "Sample pomade",
                description: "A sample product for testing the app. The shop's own products appear here once it adds them.",
                priceCents: 1800
            ),
            IzzyAPI.Product(
                id: "sample-beard-oil",
                name: "Sample beard oil",
                description: "Another sample product, listed without a price."
            ),
            IzzyAPI.Product(
                id: "sample-hair-spray",
                name: "Sample hair spray",
                description: nil,
                priceCents: 1250
            ),
        ]
    }

    // MARK: No-show protection

    // Like the server with Stripe set up: off until the owner turns it on (`noShowSettings`). Off,
    // no card is needed, there's no warning, a card sent with a booking is ignored, cancelling is
    // free and there's no card page. On, a booking whose item has a fee of at least 50¢ needs a
    // saved card and today's policy, and the server's fee rule, policy and warning apply (the
    // Kit's mirror of them, which its tests check against the server's own fixtures).

    func noShowPolicy(for target: IzzyAPI.BookingTarget) async throws -> IzzyAPI.NoShowPolicy {
        try await respond()
        // An unknown offering or service is a 400, as on the server.
        return try protection(for: target).policy
    }

    func startCardCheckout(for target: IzzyAPI.BookingTarget, token: IzzyAPI.CardToken) async throws -> IzzyAPI.CardCheckout {
        try await respond()
        guard try protection(for: target).policy.required else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "This booking doesn't need a card. Go ahead and book.", status: 400)
        }
        let id = "cs_test_fake\(checkoutSessions.count + 1)"
        checkoutSessions[id] = CheckoutSession(id: id, token: token.rawValue, card: nil)
        // TEST DATA: never opened; the UI tests' card saver doesn't load web pages.
        guard let url = URL(string: "https://checkout.stripe.com/c/pay/\(id)") else {
            throw APIError.server(code: IzzyAPI.ErrorCode.serverError, message: "", status: 500)
        }
        return IzzyAPI.CardCheckout(url: url, sessionId: id)
    }

    /// Stands for the client on Stripe's page: they typed `card` and tapped Save. For the UI tests'
    /// card saver and for tests.
    func completeCardCheckout(sessionId: String, card: IzzyAPI.SavedCard) {
        checkoutSessions[sessionId]?.card = card
    }

    /// The card the UI tests "type" on Stripe's page: Visa 4242, good for a few more years.
    var sampleCard: IzzyAPI.SavedCard {
        let year = LocalDate(containing: now, in: shop.timeZone).year
        return IzzyAPI.SavedCard(brand: "visa", last4: "4242", expMonth: 12, expYear: year + 3)
    }

    func saveCard(sessionId: String, token: IzzyAPI.CardToken) async throws -> IzzyAPI.SavedCard {
        try await respond()
        guard Self.isCheckoutSessionID(sessionId) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That isn't a Stripe Checkout session id.", status: 400)
        }
        // Saving again after a lost answer gets the same card; one token holds one card.
        if let saved = savedCards[token.rawValue] {
            guard saved.sessionId == sessionId else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That card token was already used for another card.", status: 400)
            }
            return saved.card
        }
        // Only the phone that started the session (it has the token) can save its card.
        guard let session = checkoutSessions[sessionId], session.token == token.rawValue else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that card. Add it again.", status: 404)
        }
        guard let card = session.card else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "The card wasn't added. Add it again.", status: 400)
        }
        guard card.isValid(at: now, in: shop.timeZone) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That card has expired. Add another card.", status: 400)
        }
        savedCards[token.rawValue] = SavedCardRecord(sessionId: sessionId, card: card)
        return card
    }

    /// `cs_test_…` or `cs_live_…` with 1 to 200 letters and digits after it, as the server checks.
    private static func isCheckoutSessionID(_ id: String) -> Bool {
        for prefix in ["cs_test_", "cs_live_"] where id.hasPrefix(prefix) {
            let rest = id.unicodeScalars.dropFirst(prefix.count)
            return (1...200).contains(rest.count) && rest.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
        }
        return false
    }

    /// Whether booking `target` needs a card, for how much and under which policy, as the server
    /// works it out (`protectionFor` in server/src/noshow.ts).
    private func protection(for target: IzzyAPI.BookingTarget) throws -> Protection {
        let offerings = try targetOfferings(target)
        let settings = noShowSettings
        var fees: [String: Int] = [:]
        if settings.enabled {
            for offering in offerings {
                fees[offering.id] = IzzyAPI.NoShowRule.feeCents(for: offering.price, settings: settings)
            }
        }
        guard let min = fees.values.min(), let max = fees.values.max() else {
            return Protection(policy: .notRequired, fees: [:])
        }
        let policy = IzzyAPI.NoShowPolicy(
            required: true,
            minFeeCents: min,
            maxFeeCents: max,
            policyText: IzzyAPI.NoShowRule.policyText(minFeeCents: min, maxFeeCents: max, settings: settings),
            lateCancelWindowMinutes: settings.lateCancelEnabled ? settings.lateCancelWindowMinutes : nil,
            warning: IzzyAPI.NoShowRule.warning(minFeeCents: min, maxFeeCents: max, settings: settings)
        )
        return Protection(policy: policy, fees: fees)
    }

    /// The saved card a booking that needs one goes with, checked like the server: there is one, it's
    /// known, it's good through the appointment's month, and the policy sent is today's. `nil` when
    /// the booking needs no card (any card sent is ignored then).
    private func cardOnFile(for request: IzzyAPI.NewAppointment, protection: Protection) throws -> IzzyAPI.SavedCard? {
        guard protection.policy.required else { return nil }
        guard let agreement = request.noShow else {
            throw APIError.cardRequired(message: "Add a card to book this time. You won't be charged now.")
        }
        guard let saved = savedCards[agreement.cardToken.rawValue] else {
            throw APIError.cardRequired(message: "We couldn't find your saved card. Add it again.")
        }
        guard saved.card.isValid(at: request.start, in: shop.timeZone) else {
            throw APIError.cardRequired(message: "That card expires before your appointment. Add another card.")
        }
        guard agreement.policyText == protection.policy.policyText else {
            throw APIError.policyChanged(message: "The no-show policy for this booking just changed. Check it and book again.")
        }
        return saved.card
    }

    // MARK: Seeding

    /// A booking that already exists when the app starts: a haircut with Carlos at his first open
    /// time two days from now. The app saves it as if it had been booked on this phone.
    func seedBooking(customerName: String = "Sample client") -> IzzyAPI.BookingConfirmation? {
        guard let offering = catalog.offerings(forService: "haircut").first(where: { $0.barberID == "carlos-rafael" }) else {
            return nil
        }
        let today = LocalDate(calendar.day(containing: now))
        for offset in 2...14 {
            let day = today.adding(days: offset)
            guard let slot = (try? slots(on: day, for: .offering(offering)))?.first else { continue }
            let appointment = makeAppointment(offering: offering, start: slot.start, name: customerName, phone: "+14425550123", note: nil)
            let token = "fake-seeded-token"
            stored[appointment.id] = Stored(appointment: appointment, token: token, isSeeded: true)
            markBusy(offering.barberID, from: appointment.start, minutes: appointment.durationMinutes)
            return IzzyAPI.BookingConfirmation(appointment: appointment, manageToken: token)
        }
        return nil
    }

    /// A booking with a card on file that already exists when the app starts: a haircut with Carlos
    /// in 45 minutes, booked yesterday under the server's starting policy (so the 15 minutes after
    /// booking when cancelling is always free are long over), so cancelling it now may be charged
    /// the full service price ($45). The app saves it as if it had been booked on this phone.
    func seedBookingStartingSoonWithCard(customerName: String = "Sample client") -> IzzyAPI.BookingConfirmation? {
        guard let offering = catalog.offerings(forService: "haircut").first(where: { $0.barberID == "carlos-rafael" }) else {
            return nil
        }
        var settings = IzzyAPI.NoShowSettings.default
        settings.enabled = true
        guard let fee = IzzyAPI.NoShowRule.feeCents(for: offering.price, settings: settings) else { return nil }
        // To the minute, like the times the app shows.
        let soon = now.addingTimeInterval(45 * 60)
        let start = Date(timeIntervalSince1970: (soon.timeIntervalSince1970 / 60).rounded(.down) * 60)
        var appointment = makeAppointment(offering: offering, start: start, name: customerName, phone: "+14425550123", note: nil)
        appointment.createdAt = now.addingTimeInterval(-24 * 60 * 60)
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = IzzyAPI.NoShowFee(
            amountCents: fee,
            fullPrice: fee == offering.price.cents,
            lateCancelWindowMinutes: settings.lateCancelEnabled ? settings.lateCancelWindowMinutes : nil
        )
        let token = "fake-seeded-token-soon"
        stored[appointment.id] = Stored(appointment: appointment, token: token, isSeeded: true)
        markBusy(offering.barberID, from: appointment.start, minutes: appointment.durationMinutes)
        return IzzyAPI.BookingConfirmation(appointment: appointment, manageToken: token)
    }

    // MARK: Availability

    /// The open start times on `day` for a barber's offering, or for any barber who shares the
    /// service's "first available" item, each for their own length.
    private func slots(on day: LocalDate, for target: IzzyAPI.BookingTarget) throws -> [IzzyAPI.Slot] {
        var free: [Date: [String]] = [:]
        for offering in try targetOfferings(target) {
            for start in openStarts(on: day, for: offering) {
                free[start, default: []].append(offering.barberID)
            }
        }
        return free.keys.sorted().map { IzzyAPI.Slot(start: $0, barberIds: free[$0] ?? []) }
    }

    /// The offerings a booking for `target` may get: the one asked for, or those of "any barber".
    /// One that isn't on the menu is a 400, as on the server.
    private func targetOfferings(_ target: IzzyAPI.BookingTarget) throws -> [Offering] {
        switch target {
        case .offering(let id):
            guard let offering = catalog.offering(withID: id) else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That service isn't on the menu.", status: 400)
            }
            return [offering]
        case .anyBarber(let serviceID):
            let offerings = firstAvailableOfferings(forService: serviceID)
            guard !offerings.isEmpty else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Pick a barber for this service.", status: 400)
            }
            return offerings
        }
    }

    private func openStarts(on day: LocalDate, for offering: Offering) -> [Date] {
        calendar.slots(on: day.calendarDay, durationMinutes: offering.durationMinutes, now: now)
            .map(\.start)
            .filter { isFree(offering.barberID, from: $0, minutes: offering.durationMinutes) }
    }

    /// The offerings "Any barber" books from, in team order: the same as the server's
    /// `firstAvailable` list in catalog.json.
    private func firstAvailableOfferings(forService serviceID: String) -> [Offering] {
        guard let option = catalog.firstAvailableOption(forService: serviceID) else { return [] }
        return option.barberIDs.compactMap { barberID in
            catalog.offerings.first {
                $0.barberID == barberID && $0.serviceID == serviceID && $0.squireServiceID == option.squireServiceID
            }
        }
    }

    /// The offering a booking goes to: the one asked for, or the first free barber's.
    private func offering(for target: IzzyAPI.BookingTarget, freeBarbers: [String]) -> Offering? {
        switch target {
        case .offering(let id):
            return catalog.offering(withID: id)
        case .anyBarber(let serviceID):
            return firstAvailableOfferings(forService: serviceID).first { freeBarbers.contains($0.barberID) }
        }
    }

    /// Why `start` can't be booked whoever is free, with the server's codes: too soon, too far,
    /// or not one of the booking times (outside the hours). `nil` when it's one of them.
    private func timeRuleProblem(for start: Date, day: LocalDate, target: IzzyAPI.BookingTarget) throws -> APIError? {
        if start < now.addingTimeInterval(TimeInterval(calendar.leadTimeMinutes) * 60) { return .tooSoon }
        if day.calendarDay > calendar.lastBookableDay(now: now) { return .tooFar }
        let onTheGrid = try targetOfferings(target).contains { offering in
            calendar.slots(on: day.calendarDay, durationMinutes: offering.durationMinutes, now: now).contains { $0.start == start }
        }
        return onTheGrid ? nil : .outsideHours
    }

    private func isFree(_ barberID: String, from start: Date, minutes: Int) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
        return !(busy[barberID] ?? []).contains { $0.start < end && start < $0.end }
    }

    private func markBusy(_ barberID: String, from start: Date, minutes: Int) {
        busy[barberID, default: []].append(DateInterval(start: start, duration: TimeInterval(minutes) * 60))
    }

    /// One hour booked per barber per open day: an hour after opening for the first barber,
    /// two hours after for the second, and so on.
    private func addSampleBookings() {
        let today = calendar.day(containing: now)
        for offset in 0...calendar.windowDays {
            let day = today.adding(days: offset)
            guard let hours = calendar.clock.schedule.hours(on: day.weekday) else { continue }
            for (index, barber) in catalog.barbers.enumerated() {
                let minutes = hours.opens.minutesSinceMidnight + (index + 1) * 60
                guard minutes + 60 <= hours.closes.minutesSinceMidnight,
                      let start = calendar.date(on: day, at: TimeOfDay(hour: minutes / 60, minute: minutes % 60))
                else { continue }
                markBusy(barber.id, from: start, minutes: 60)
            }
        }
    }

    private func makeAppointment(offering: Offering, start: Date, name: String, phone: String, note: String?) -> IzzyAPI.Appointment {
        IzzyAPI.Appointment(
            id: UUID().uuidString.lowercased(),
            offeringId: offering.id,
            serviceId: offering.serviceID,
            serviceName: catalog.service(withID: offering.serviceID)?.name ?? "Appointment",
            barberId: offering.barberID,
            barberName: catalog.barber(withID: offering.barberID)?.name ?? "Your barber",
            start: start,
            end: start.addingTimeInterval(TimeInterval(offering.durationMinutes) * 60),
            durationMinutes: offering.durationMinutes,
            priceLabel: offering.price.label,
            customer: IzzyAPI.Customer(name: name, phone: phone),
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: now
        )
    }

    /// Waits a moment like a real request, then fails if the phone is "offline".
    private func respond() async throws {
        if options.latency > .zero {
            try await Task.sleep(for: options.latency)
        }
        if options.offline { throw APIError.offline }
    }
}

extension String {
    /// `nil` for an empty string.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
