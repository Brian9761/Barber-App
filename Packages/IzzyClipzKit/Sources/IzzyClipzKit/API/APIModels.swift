import Foundation

// Response models, field for field as in the v1 contract. Optional fields are
// always written, as `null` when empty, the way the server writes them, so a
// fake built on these types returns exactly what the real server would.

// MARK: - Appointments

extension IzzyAPI {
    public enum AppointmentStatus: String, Codable, CaseIterable, Hashable, Sendable {
        case booked
        case cancelled
        case completed
        case noShow

        /// "Booked", "Cancelled", "Completed", "No-show".
        public var title: String {
            switch self {
            case .booked: return "Booked"
            case .cancelled: return "Cancelled"
            case .completed: return "Completed"
            case .noShow: return "No-show"
            }
        }
    }

    public enum CancelledBy: String, Codable, Hashable, Sendable {
        case customer
        case shop
    }

    public enum PaymentStatus: String, Codable, Hashable, Sendable {
        case unpaid
        case paid
    }

    /// An appointment's payment: `{ status, amountCents, paidAt }`.
    public struct AppointmentPayment: Codable, Hashable, Sendable {
        public var status: PaymentStatus
        public var amountCents: Int?
        public var paidAt: Date?

        public init(status: PaymentStatus = .unpaid, amountCents: Int? = nil, paidAt: Date? = nil) {
            self.status = status
            self.amountCents = amountCents
            self.paidAt = paidAt
        }

        public static let unpaid = AppointmentPayment()

        private enum CodingKeys: String, CodingKey {
            case status, amountCents, paidAt
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(amountCents, forKey: .amountCents)
            try container.encode(paidAt, forKey: .paidAt)
        }
    }

    /// Who the appointment is for: `{ name, phone, email }`. Walk-ins the shop
    /// books may have no phone.
    public struct Customer: Codable, Hashable, Sendable {
        public var name: String
        /// E.164, e.g. "+14423413053".
        public var phone: String?
        public var email: String?

        public init(name: String, phone: String? = nil, email: String? = nil) {
            self.name = name
            self.phone = phone
            self.email = email
        }

        private enum CodingKeys: String, CodingKey {
            case name, phone, email
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(phone, forKey: .phone)
            try container.encode(email, forKey: .email)
        }
    }

    public struct Appointment: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        /// The Kit's `Offering.id`, e.g. "flowxbori/bbb0c294-…".
        public var offeringId: String
        public var serviceId: String
        public var serviceName: String
        public var barberId: String
        public var barberName: String
        public var start: Date
        public var end: Date
        public var durationMinutes: Int
        /// "$35", "From $80", "Included with cut".
        public var priceLabel: String
        public var status: AppointmentStatus
        public var cancelledBy: CancelledBy?
        public var payment: AppointmentPayment
        public var customer: Customer
        public var note: String?
        public var createdAt: Date

        public init(
            id: String,
            offeringId: String,
            serviceId: String,
            serviceName: String,
            barberId: String,
            barberName: String,
            start: Date,
            end: Date,
            durationMinutes: Int,
            priceLabel: String,
            status: AppointmentStatus = .booked,
            cancelledBy: CancelledBy? = nil,
            payment: AppointmentPayment = .unpaid,
            customer: Customer,
            note: String? = nil,
            createdAt: Date
        ) {
            self.id = id
            self.offeringId = offeringId
            self.serviceId = serviceId
            self.serviceName = serviceName
            self.barberId = barberId
            self.barberName = barberName
            self.start = start
            self.end = end
            self.durationMinutes = durationMinutes
            self.priceLabel = priceLabel
            self.status = status
            self.cancelledBy = cancelledBy
            self.payment = payment
            self.customer = customer
            self.note = note
            self.createdAt = createdAt
        }

        /// Hasn't finished yet: it's later, or happening right now.
        public func isUpcoming(at now: Date) -> Bool {
            end > now
        }

        /// What the server lets a customer cancel: booked and not started yet.
        public func isCancellable(at now: Date) -> Bool {
            status == .booked && start > now
        }

        /// "45 min", "1 hr 15 min".
        public var durationLabel: String {
            durationMinutes > 0 ? DurationText.short(minutes: durationMinutes) : ""
        }

        private enum CodingKeys: String, CodingKey {
            case id, offeringId, serviceId, serviceName, barberId, barberName, start, end, durationMinutes, priceLabel
            case status, cancelledBy, payment, customer, note, createdAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
            // The Kit's duration formatting requires a length, like its own Appointment.
            guard durationMinutes > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .durationMinutes, in: container, debugDescription: "An appointment needs a length")
            }
            self.init(
                id: try container.decode(String.self, forKey: .id),
                offeringId: try container.decode(String.self, forKey: .offeringId),
                serviceId: try container.decode(String.self, forKey: .serviceId),
                serviceName: try container.decode(String.self, forKey: .serviceName),
                barberId: try container.decode(String.self, forKey: .barberId),
                barberName: try container.decode(String.self, forKey: .barberName),
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decode(Date.self, forKey: .end),
                durationMinutes: durationMinutes,
                priceLabel: try container.decode(String.self, forKey: .priceLabel),
                status: try container.decode(AppointmentStatus.self, forKey: .status),
                cancelledBy: try container.decodeIfPresent(CancelledBy.self, forKey: .cancelledBy),
                payment: try container.decode(AppointmentPayment.self, forKey: .payment),
                customer: try container.decode(Customer.self, forKey: .customer),
                note: try container.decodeIfPresent(String.self, forKey: .note),
                createdAt: try container.decode(Date.self, forKey: .createdAt)
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(offeringId, forKey: .offeringId)
            try container.encode(serviceId, forKey: .serviceId)
            try container.encode(serviceName, forKey: .serviceName)
            try container.encode(barberId, forKey: .barberId)
            try container.encode(barberName, forKey: .barberName)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(durationMinutes, forKey: .durationMinutes)
            try container.encode(priceLabel, forKey: .priceLabel)
            try container.encode(status, forKey: .status)
            try container.encode(cancelledBy, forKey: .cancelledBy)
            try container.encode(payment, forKey: .payment)
            try container.encode(customer, forKey: .customer)
            try container.encode(note, forKey: .note)
            try container.encode(createdAt, forKey: .createdAt)
        }
    }

    /// `POST /api/appointments` → 201 `{ appointment, manageToken }` (200 for a retry of a
    /// booking that already went through).
    public struct BookingConfirmation: Codable, Hashable, Sendable, CustomStringConvertible {
        public var appointment: Appointment
        /// The secret that lets this phone look up and cancel the appointment.
        /// The server only keeps its hash, so store it safely; it can't be recovered.
        public var manageToken: String

        public init(appointment: Appointment, manageToken: String) {
            self.appointment = appointment
            self.manageToken = manageToken
        }

        /// Leaves the token out, so it never ends up in a log.
        public var description: String {
            "BookingConfirmation(appointment: \(appointment.id), manageToken: <redacted>)"
        }
    }

    /// `{ appointment }`.
    public struct AppointmentResponse: Codable, Hashable, Sendable {
        public var appointment: Appointment

        public init(appointment: Appointment) {
            self.appointment = appointment
        }
    }

    /// `{ appointments: [Appointment] }`.
    public struct AppointmentsResponse: Codable, Hashable, Sendable {
        public var appointments: [Appointment]

        public init(appointments: [Appointment]) {
            self.appointments = appointments
        }
    }
}

// MARK: - Availability

extension IzzyAPI {
    /// A start time and the barbers free for it: `{ start, barberIds }`.
    public struct Slot: Codable, Hashable, Identifiable, Sendable {
        public var start: Date
        public var barberIds: [String]

        public init(start: Date, barberIds: [String]) {
            self.start = start
            self.barberIds = barberIds
        }

        public var id: Date { start }
    }

    /// One shop day of slots: `{ date, slots }`.
    public struct DaySlots: Codable, Hashable, Identifiable, Sendable {
        public var date: LocalDate
        public var slots: [Slot]

        public init(date: LocalDate, slots: [Slot]) {
            self.date = date
            self.slots = slots
        }

        public var id: LocalDate { date }
    }

    /// `GET /api/availability` → `{ timeZone, days }`.
    public struct AvailabilityResponse: Codable, Hashable, Sendable {
        /// The shop's IANA time zone, e.g. "America/Los_Angeles".
        public var timeZone: String
        public var days: [DaySlots]

        public init(timeZone: String, days: [DaySlots]) {
            self.timeZone = timeZone
            self.days = days
        }

        /// `nil` if the server sent a name this device doesn't know.
        public var shopTimeZone: TimeZone? { TimeZone(identifier: timeZone) }

        /// The slots on `date`; empty when the response doesn't cover it.
        public func slots(on date: LocalDate) -> [Slot] {
            days.first { $0.date == date }?.slots ?? []
        }
    }
}

// MARK: - Products

extension IzzyAPI {
    /// One of the shop's own products.
    public struct Product: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var description: String?
        /// `nil` when the shop doesn't list a price.
        public var priceCents: Int?
        /// `nil` until the owner adds a photo. Only http and https links are kept.
        public var imageUrl: URL?
        public var visible: Bool

        public init(
            id: String,
            name: String,
            description: String? = nil,
            priceCents: Int? = nil,
            imageUrl: URL? = nil,
            visible: Bool = true
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.priceCents = priceCents
            self.imageUrl = imageUrl
            self.visible = visible
        }

        /// "$12", "$7.50", or `nil` without a price.
        public var priceLabel: String? {
            guard let priceCents, priceCents >= 0 else { return nil }
            return Price.currencyString(cents: priceCents)
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, description, priceCents, imageUrl, visible
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            priceCents = try container.decodeIfPresent(Int.self, forKey: .priceCents)
            imageUrl = container.decodeWebURLIfPossible(forKey: .imageUrl)
            visible = try container.decode(Bool.self, forKey: .visible)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
            try container.encode(priceCents, forKey: .priceCents)
            try container.encode(imageUrl?.absoluteString, forKey: .imageUrl)
            try container.encode(visible, forKey: .visible)
        }
    }

    /// `{ products: [Product] }`. A product that can't be read is skipped
    /// rather than hiding the whole list.
    public struct ProductsResponse: Codable, Hashable, Sendable {
        public var products: [Product]

        public init(products: [Product]) {
            self.products = products
        }

        private enum CodingKeys: String, CodingKey {
            case products
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            products = try container.decode([Lossy<Product>].self, forKey: .products).decodedValues()
        }
    }

    /// `{ product }`.
    public struct ProductResponse: Codable, Hashable, Sendable {
        public var product: Product

        public init(product: Product) {
            self.product = product
        }
    }
}

// MARK: - Reviews

extension IzzyAPI {
    /// A review as Google or Yelp published it. Show it with its author, a
    /// link to the review and the source's attribution.
    public struct Review: Codable, Hashable, Sendable {
        public var author: String
        public var authorPhotoUrl: URL?
        public var authorUrl: URL?
        /// 1 to 5 stars.
        public var rating: Int
        public var text: String
        /// The source's own wording, e.g. "2 weeks ago".
        public var relativeTime: String?
        public var publishedAt: Date?
        /// The review on Google Maps or Yelp.
        public var url: URL?

        public init(
            author: String,
            authorPhotoUrl: URL? = nil,
            authorUrl: URL? = nil,
            rating: Int,
            text: String,
            relativeTime: String? = nil,
            publishedAt: Date? = nil,
            url: URL? = nil
        ) {
            self.author = author
            self.authorPhotoUrl = authorPhotoUrl
            self.authorUrl = authorUrl
            self.rating = rating
            self.text = text
            self.relativeTime = relativeTime
            self.publishedAt = publishedAt
            self.url = url
        }

        private enum CodingKeys: String, CodingKey {
            case author, authorPhotoUrl, authorUrl, rating, text, relativeTime, publishedAt, url
        }

        /// Reviews are third-party content, so the optional extras are read
        /// leniently: a link that isn't http(s) or a time that can't be read
        /// becomes `nil` instead of losing the review.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            author = try container.decode(String.self, forKey: .author)
            authorPhotoUrl = container.decodeWebURLIfPossible(forKey: .authorPhotoUrl)
            authorUrl = container.decodeWebURLIfPossible(forKey: .authorUrl)
            // Stars are whole numbers in the contract; round a 4.0 or 4.5 rather
            // than fail, and keep them in 0...5 so a star row can't overflow.
            let stars: Double
            if let whole = try? container.decode(Int.self, forKey: .rating) {
                stars = Double(whole)
            } else {
                stars = try container.decode(Double.self, forKey: .rating)
            }
            rating = Int(min(max(stars, 0), 5).rounded())
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            relativeTime = try? container.decodeIfPresent(String.self, forKey: .relativeTime)
            publishedAt = (try? container.decodeIfPresent(String.self, forKey: .publishedAt)).flatMap(Timestamp.date(from:))
            url = container.decodeWebURLIfPossible(forKey: .url)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(author, forKey: .author)
            try container.encode(authorPhotoUrl?.absoluteString, forKey: .authorPhotoUrl)
            try container.encode(authorUrl?.absoluteString, forKey: .authorUrl)
            try container.encode(rating, forKey: .rating)
            try container.encode(text, forKey: .text)
            try container.encode(relativeTime, forKey: .relativeTime)
            try container.encode(publishedAt, forKey: .publishedAt)
            try container.encode(url?.absoluteString, forKey: .url)
        }
    }

    /// One review site's rating and reviews.
    ///
    /// When `available` is false the app links to `url` instead (the shop's
    /// Google Maps or Yelp page). Never combine Google and Yelp ratings.
    public struct ReviewSource: Codable, Hashable, Sendable {
        public var available: Bool
        public var rating: Double?
        public var count: Int?
        /// The shop's page on the site; always present.
        public var url: URL
        /// In the order the site returned them (Google: "most relevant").
        public var reviews: [Review]
        public var fetchedAt: Date?

        /// The rating and count as the Kit's `Rating` ("4.9", "61 reviews"),
        /// when the site gave both.
        public var summary: Rating? {
            guard available, let rating, let count, (0...5).contains(rating), count >= 0 else { return nil }
            return Rating(average: rating, count: count)
        }

        public init(
            available: Bool,
            rating: Double? = nil,
            count: Int? = nil,
            url: URL,
            reviews: [Review] = [],
            fetchedAt: Date? = nil
        ) {
            self.available = available
            self.rating = rating
            self.count = count
            self.url = url
            self.reviews = reviews
            self.fetchedAt = fetchedAt
        }

        private enum CodingKeys: String, CodingKey {
            case available, rating, count, url, reviews, fetchedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            available = try container.decode(Bool.self, forKey: .available)
            // Out-of-range numbers are treated as unknown rather than shown.
            rating = (try? container.decodeIfPresent(Double.self, forKey: .rating)).flatMap { (0...5).contains($0) ? $0 : nil }
            count = (try? container.decodeIfPresent(Int.self, forKey: .count)).flatMap { $0 >= 0 ? $0 : nil }
            url = try container.decodeWebURL(forKey: .url)
            reviews = try container.decodeIfPresent([Lossy<Review>].self, forKey: .reviews)?.decodedValues() ?? []
            fetchedAt = (try? container.decodeIfPresent(String.self, forKey: .fetchedAt)).flatMap(Timestamp.date(from:))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(available, forKey: .available)
            try container.encode(rating, forKey: .rating)
            try container.encode(count, forKey: .count)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(reviews, forKey: .reviews)
            try container.encode(fetchedAt, forKey: .fetchedAt)
        }
    }

    /// `GET /api/reviews` → `{ google, yelp }`.
    public struct ReviewsResponse: Codable, Hashable, Sendable {
        public var google: ReviewSource
        public var yelp: ReviewSource

        public init(google: ReviewSource, yelp: ReviewSource) {
            self.google = google
            self.yelp = yelp
        }
    }
}

// MARK: - Owner

extension IzzyAPI {
    public enum StripeMode: String, Codable, Hashable, Sendable {
        case test
        case live
    }

    /// `{ configured, mode, locationId }`; `mode` and `locationId` are `nil` when Stripe isn't
    /// configured. `locationId` is the Stripe Terminal location Tap to Pay connects to.
    public struct StripeStatus: Codable, Hashable, Sendable {
        public var configured: Bool
        public var mode: StripeMode?
        public var locationId: String?

        public init(configured: Bool, mode: StripeMode? = nil, locationId: String? = nil) {
            self.configured = configured
            self.mode = mode
            self.locationId = locationId
        }

        private enum CodingKeys: String, CodingKey {
            case configured, mode, locationId
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(configured, forKey: .configured)
            try container.encode(mode, forKey: .mode)
            try container.encode(locationId, forKey: .locationId)
        }
    }

    /// `GET /api/owner/me` → `{ ok: true, stripe }`.
    public struct OwnerStatus: Codable, Hashable, Sendable {
        public var ok: Bool
        public var stripe: StripeStatus

        public init(ok: Bool = true, stripe: StripeStatus) {
            self.ok = ok
            self.stripe = stripe
        }
    }

    /// `GET /api/health` → `{ ok: true, version }`.
    public struct Health: Codable, Hashable, Sendable {
        public var ok: Bool
        public var version: String

        public init(ok: Bool = true, version: String) {
            self.ok = ok
            self.version = version
        }
    }

    /// Time a barber, or the whole shop, can't be booked.
    public struct TimeOff: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        /// `nil` means the whole shop.
        public var barberId: String?
        public var start: Date
        public var end: Date
        public var reason: String?

        public init(id: String, barberId: String?, start: Date, end: Date, reason: String? = nil) {
            self.id = id
            self.barberId = barberId
            self.start = start
            self.end = end
            self.reason = reason
        }

        public var isWholeShop: Bool { barberId == nil }

        private enum CodingKeys: String, CodingKey {
            case id, barberId, start, end, reason
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(barberId, forKey: .barberId)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(reason, forKey: .reason)
        }
    }

    /// `GET /api/owner/time-off` → `{ timeOff: [TimeOff] }`.
    public struct TimeOffListResponse: Codable, Hashable, Sendable {
        public var timeOff: [TimeOff]

        public init(timeOff: [TimeOff]) {
            self.timeOff = timeOff
        }
    }

    /// `POST /api/owner/time-off` → 201 `{ timeOff }` (one entry, same key).
    public struct TimeOffResponse: Codable, Hashable, Sendable {
        public var timeOff: TimeOff

        public init(timeOff: TimeOff) {
            self.timeOff = timeOff
        }
    }

    /// A card payment taken in the shop.
    public struct Payment: Codable, Hashable, Identifiable, Sendable {
        /// The Stripe PaymentIntent ID, "pi_…".
        public var id: String
        public var amountCents: Int
        public var description: String?
        public var appointmentId: String?
        /// Stripe's PaymentIntent status, e.g. "succeeded".
        public var status: String
        public var createdAt: Date

        public init(
            id: String,
            amountCents: Int,
            description: String? = nil,
            appointmentId: String? = nil,
            status: String,
            createdAt: Date
        ) {
            self.id = id
            self.amountCents = amountCents
            self.description = description
            self.appointmentId = appointmentId
            self.status = status
            self.createdAt = createdAt
        }

        public var isSucceeded: Bool { status == "succeeded" }

        /// "$45", "$7.50".
        public var amountLabel: String { Price.currencyString(cents: amountCents) }

        private enum CodingKeys: String, CodingKey {
            case id, amountCents, description, appointmentId, status, createdAt
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(amountCents, forKey: .amountCents)
            try container.encode(description, forKey: .description)
            try container.encode(appointmentId, forKey: .appointmentId)
            try container.encode(status, forKey: .status)
            try container.encode(createdAt, forKey: .createdAt)
        }
    }

    /// `{ payment }`.
    public struct PaymentResponse: Codable, Hashable, Sendable {
        public var payment: Payment

        public init(payment: Payment) {
            self.payment = payment
        }
    }

    /// `{ payments: [Payment] }`.
    public struct PaymentsResponse: Codable, Hashable, Sendable {
        public var payments: [Payment]

        public init(payments: [Payment]) {
            self.payments = payments
        }
    }

    /// `POST /api/owner/terminal/connection-token` → `{ secret }`.
    public struct ConnectionToken: Codable, Hashable, Sendable, CustomStringConvertible {
        public var secret: String

        public init(secret: String) {
            self.secret = secret
        }

        public var description: String { "ConnectionToken(secret: <redacted>)" }
    }

    /// `POST /api/owner/payments` → 201 `{ paymentIntentId, clientSecret }`.
    public struct PaymentIntentCreated: Codable, Hashable, Sendable, CustomStringConvertible {
        public var paymentIntentId: String
        /// Hand this to Stripe Terminal's `retrievePaymentIntent(clientSecret:)`.
        public var clientSecret: String

        public init(paymentIntentId: String, clientSecret: String) {
            self.paymentIntentId = paymentIntentId
            self.clientSecret = clientSecret
        }

        public var description: String {
            "PaymentIntentCreated(paymentIntentId: \(paymentIntentId), clientSecret: <redacted>)"
        }
    }

    /// A 204 response: nothing to read.
    public struct NoContent: Decodable, Hashable, Sendable {
        public init() {}

        public init(from decoder: Decoder) throws {}
    }
}

// MARK: - Errors

extension IzzyAPI {
    /// The contract's error codes.
    public enum ErrorCode {
        public static let invalidRequest = "invalid_request"
        public static let unauthorized = "unauthorized"
        public static let notFound = "not_found"
        public static let slotTaken = "slot_taken"
        public static let notCancellable = "not_cancellable"
        public static let outsideHours = "outside_hours"
        public static let tooSoon = "too_soon"
        public static let tooFar = "too_far"
        public static let rateLimited = "rate_limited"
        public static let stripeNotConfigured = "stripe_not_configured"
        public static let ownerNotConfigured = "owner_not_configured"
        public static let serverError = "server_error"
    }

    /// `{ "error": { "code": "slot_taken", "message": "…" } }`.
    public struct ErrorEnvelope: Codable, Hashable, Sendable {
        public struct Body: Codable, Hashable, Sendable {
            public var code: String
            public var message: String

            public init(code: String, message: String) {
                self.code = code
                self.message = message
            }

            private enum CodingKeys: String, CodingKey {
                case code, message
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                code = try container.decode(String.self, forKey: .code)
                message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
            }
        }

        public var error: Body

        public init(code: String, message: String) {
            self.error = Body(code: code, message: message)
        }
    }
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// An http(s) link, or `nil` if it's missing, `null` or anything else.
    func decodeWebURLIfPossible(forKey key: Key) -> URL? {
        guard let string = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return webURL(string)
    }

    /// A required http(s) link.
    func decodeWebURL(forKey key: Key) throws -> URL {
        let string = try decode(String.self, forKey: key)
        guard let url = webURL(string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected an http(s) link, got \"\(string)\"")
        }
        return url
    }

    private func webURL(_ string: String) -> URL? {
        // A link with a raw space or accent isn't a valid URL everywhere; escape
        // just those characters and try again.
        let escaped = string.addingPercentEncoding(withAllowedCharacters: Self.linkCharacters)
        guard let url = URL(string: string) ?? escaped.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Everything a URL may contain as is, including "%" for what's already escaped.
    private static var linkCharacters: CharacterSet {
        CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#%[]"))
    }
}
