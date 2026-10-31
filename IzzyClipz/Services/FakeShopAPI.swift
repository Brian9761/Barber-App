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
        /// `-fakeSlotTaken`: the first booking attempt finds the time just taken, and that time
        /// disappears from the list.
        var slotTakenOnce = false
        /// `-fakeNoProducts`: the shop hasn't added any products yet.
        var noProducts = false
        /// `-fakeReviewsUnavailable`: Google's reviews can't be loaded (not set up, or over the
        /// daily limit) and Yelp isn't set up.
        var reviewsUnavailable = false
        /// `-fakeYelp`: the server also returns Yelp reviews.
        var yelp = false
        /// `-fakeShopCancels`: appointments the fake already holds come back cancelled by the shop.
        var shopCancels = false
        /// How long each answer takes, so loading states show briefly.
        var latency: Duration = .milliseconds(150)

        init() {}

        init(arguments: [String]) {
            offline = arguments.contains("-fakeOffline")
            bookingOfflineOnce = arguments.contains("-fakeBookingOffline")
            slotTakenOnce = arguments.contains("-fakeSlotTaken")
            noProducts = arguments.contains("-fakeNoProducts")
            reviewsUnavailable = arguments.contains("-fakeReviewsUnavailable")
            yelp = arguments.contains("-fakeYelp")
            shopCancels = arguments.contains("-fakeShopCancels")
        }
    }

    private struct Stored {
        var appointment: IzzyAPI.Appointment
        let token: String
        /// Made before the app started (a seeded booking), so `shopCancels` applies to it.
        let isSeeded: Bool
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

    func book(_ request: IzzyAPI.NewAppointment) async throws -> IzzyAPI.BookingConfirmation {
        try await respond()
        if options.bookingOfflineOnce {
            options.bookingOfflineOnce = false
            throw APIError.offline
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
        if options.slotTakenOnce {
            options.slotTakenOnce = false
            // Someone else got there first: the time is gone for everyone who could do it.
            for barberID in open.first(where: { $0.start == request.start })?.barberIds ?? [] {
                markBusy(barberID, from: request.start, minutes: 60)
            }
            throw APIError.slotTaken
        }
        guard let slot = open.first(where: { $0.start == request.start }) else {
            throw rejection(for: request.start, day: day)
        }
        guard let offering = offering(for: request.target, freeBarbers: slot.barberIds) else {
            throw APIError.slotTaken
        }
        let appointment = makeAppointment(offering: offering, start: request.start, name: name, phone: phone.e164, note: request.note)
        bookingCount += 1
        let token = "fake-manage-token-\(bookingCount)"
        stored[appointment.id] = Stored(appointment: appointment, token: token, isSeeded: false)
        markBusy(offering.barberID, from: appointment.start, minutes: appointment.durationMinutes)
        return IzzyAPI.BookingConfirmation(appointment: appointment, manageToken: token)
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

    func cancelAppointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        try await respond()
        guard var entry = stored[id], entry.token == manageToken else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "", status: 404)
        }
        guard entry.appointment.isCancellable(at: now) else {
            throw APIError.notCancellable
        }
        entry.appointment.status = .cancelled
        entry.appointment.cancelledBy = .customer
        stored[id] = entry
        let appointment = entry.appointment
        busy[appointment.barberId]?.removeAll { $0.start == appointment.start }
        return appointment
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

    // MARK: Availability

    /// The open start times on `day` for a barber's offering, or for any barber who shares the
    /// service's "first available" item, each for their own length.
    private func slots(on day: LocalDate, for target: IzzyAPI.BookingTarget) throws -> [IzzyAPI.Slot] {
        switch target {
        case .offering(let id):
            guard let offering = catalog.offering(withID: id) else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That service isn't on the menu.", status: 400)
            }
            return openStarts(on: day, for: offering).map { IzzyAPI.Slot(start: $0, barberIds: [offering.barberID]) }
        case .anyBarber(let serviceID):
            let offerings = firstAvailableOfferings(forService: serviceID)
            guard !offerings.isEmpty else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Pick a barber for this service.", status: 400)
            }
            var free: [Date: [String]] = [:]
            for offering in offerings {
                for start in openStarts(on: day, for: offering) {
                    free[start, default: []].append(offering.barberID)
                }
            }
            return free.keys.sorted().map { IzzyAPI.Slot(start: $0, barberIds: free[$0] ?? []) }
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

    /// Why a start that isn't offered was turned down, with the server's codes.
    private func rejection(for start: Date, day: LocalDate) -> APIError {
        if start < now.addingTimeInterval(TimeInterval(calendar.leadTimeMinutes) * 60) { return .tooSoon }
        if day.calendarDay > calendar.lastBookableDay(now: now) { return .tooFar }
        guard let hours = calendar.clock.schedule.hours(on: day.weekday),
              let opens = calendar.date(on: day.calendarDay, at: hours.opens),
              let closes = calendar.date(on: day.calendarDay, at: hours.closes),
              start >= opens, start < closes
        else { return .outsideHours }
        return .slotTaken
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
