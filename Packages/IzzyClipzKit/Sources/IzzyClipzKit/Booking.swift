import Foundation

/// What a client wants to book. Every field is optional: the less is known,
/// the earlier in Squire's flow the booking page starts.
public struct BookingRequest: Hashable, Sendable {
    /// A barber's Squire slug, or `nil` for whoever is available.
    public let barberID: String?
    /// The Squire menu item to put in the cart, or `nil` to choose on Squire.
    public let squireServiceID: String?

    public init(barberID: String? = nil, squireServiceID: String? = nil) {
        self.barberID = barberID
        self.squireServiceID = squireServiceID?.lowercased()
    }

    /// Start from the top: pick a barber, service and time on Squire.
    public static let anything = BookingRequest()

    public static func barber(_ barberID: String) -> BookingRequest {
        BookingRequest(barberID: barberID)
    }

    public static func offering(_ offering: Offering) -> BookingRequest {
        BookingRequest(barberID: offering.barberID, squireServiceID: offering.squireServiceID)
    }

    public static func firstAvailable(_ option: FirstAvailableOption) -> BookingRequest {
        BookingRequest(barberID: nil, squireServiceID: option.squireServiceID)
    }
}

/// Builds links into the shop's Squire booking flow.
///
/// Appointments are made on Squire because that's where the barbers manage
/// their calendars; the app never pretends to hold a slot itself.
public struct BookingLinks: Hashable, Sendable {
    public struct QueryParameter: Hashable, Sendable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public let shopSlug: String
    /// Added to every link so the shop can tell which bookings came from the app.
    public let tracking: [QueryParameter]

    public init(shopSlug: String, tracking: [QueryParameter] = BookingLinks.appTracking) {
        precondition(Catalog.isURLSlug(shopSlug), "The shop slug must be URL-safe")
        self.shopSlug = shopSlug
        self.tracking = tracking
    }

    public static let appTracking = [
        QueryParameter("utm_source", "izzyclipz-app"),
        QueryParameter("utm_medium", "ios"),
    ]

    /// e.g. https://getsquire.com/booking/book/izzy-clipz-oceanside/barber/carlos-rafael/services?preselect=…
    public func url(for request: BookingRequest) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "getsquire.com"

        var path = "/booking/book/\(shopSlug)"
        if request.barberID != nil || request.squireServiceID != nil {
            path += "/barber/\(request.barberID ?? "any")/services"
        }
        components.path = path

        var query: [URLQueryItem] = []
        if let squireServiceID = request.squireServiceID {
            query.append(URLQueryItem(name: "preselect", value: squireServiceID))
        }
        query += tracking.map { URLQueryItem(name: $0.name, value: $0.value) }
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            preconditionFailure("Couldn't build a booking URL for \(request)")
        }
        return url
    }
}
