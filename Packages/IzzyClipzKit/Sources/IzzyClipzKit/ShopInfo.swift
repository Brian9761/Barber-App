import Foundation

public struct PostalAddress: Hashable, Sendable {
    public let street: String
    public let unit: String?
    public let city: String
    public let state: String
    public let postalCode: String

    public init(street: String, unit: String?, city: String, state: String, postalCode: String) {
        self.street = street
        self.unit = unit
        self.city = city
        self.state = state
        self.postalCode = postalCode
    }

    /// "1919 Mission Ave, Ste 105".
    public var streetLine: String {
        [street, unit].compactMap { $0 }.joined(separator: ", ")
    }

    /// "Oceanside, CA 92058".
    public var cityLine: String {
        "\(city), \(state) \(postalCode)"
    }

    /// "1919 Mission Ave, Ste 105, Oceanside, CA 92058".
    public var singleLine: String {
        "\(streetLine), \(cityLine)"
    }
}

public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        precondition((-90...90).contains(latitude) && (-180...180).contains(longitude), "Invalid coordinate")
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A North American phone number.
public struct PhoneNumber: Hashable, Sendable {
    /// Ten digits, e.g. "4423413053".
    public let digits: String

    public init(digits: String) {
        precondition(digits.count == 10 && digits.allSatisfy(\.isASCIIDigitCharacter), "Expected a 10-digit number")
        self.digits = digits
    }

    /// "(442) 341-3053".
    public var display: String {
        let chars = Array(digits)
        return "(\(String(chars[0..<3]))) \(String(chars[3..<6]))-\(String(chars[6..<10]))"
    }

    /// "tel:+14423413053".
    public var callURL: URL {
        URL(string: "tel:+1\(digits)")!
    }

    /// Read digit by digit, e.g. "4 4 2, 3 4 1, 3 0 5 3".
    public var spoken: String {
        let chars = Array(digits).map(String.init)
        return [chars[0..<3], chars[3..<6], chars[6..<10]]
            .map { $0.joined(separator: " ") }
            .joined(separator: ", ")
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { ("0"..."9").contains(self) }
}

/// Everything the app knows about the shop itself.
public struct ShopInfo: Sendable {
    public let name: String
    public let fullName: String
    public let tagline: String
    public let about: [String]
    public let address: PostalAddress
    public let coordinate: Coordinate
    public let phone: PhoneNumber
    public let timeZoneIdentifier: String
    public let schedule: WeeklySchedule
    public let instagramHandle: String
    public let websiteURL: URL
    public let paymentMethods: [String]
    public let highlights: [String]
    public let accessibility: [String]
    /// The shop's Google Maps place ID, used for its Maps page and "Write a review".
    public let googlePlaceID: String

    public init(
        name: String,
        fullName: String,
        tagline: String,
        about: [String],
        address: PostalAddress,
        coordinate: Coordinate,
        phone: PhoneNumber,
        timeZoneIdentifier: String,
        schedule: WeeklySchedule,
        instagramHandle: String,
        websiteURL: URL,
        paymentMethods: [String],
        highlights: [String],
        accessibility: [String],
        googlePlaceID: String
    ) {
        precondition(TimeZone(identifier: timeZoneIdentifier) != nil, "Unknown time zone \(timeZoneIdentifier)")
        precondition(ShopInfo.isPlaceID(googlePlaceID), "Invalid Google place ID")
        self.name = name
        self.fullName = fullName
        self.tagline = tagline
        self.about = about
        self.address = address
        self.coordinate = coordinate
        self.phone = phone
        self.timeZoneIdentifier = timeZoneIdentifier
        self.schedule = schedule
        self.instagramHandle = instagramHandle
        self.websiteURL = websiteURL
        self.paymentMethods = paymentMethods
        self.highlights = highlights
        self.accessibility = accessibility
        self.googlePlaceID = googlePlaceID
    }

    public var timeZone: TimeZone {
        // Validated in `init`.
        TimeZone(identifier: timeZoneIdentifier)!
    }

    public var clock: ShopClock {
        ShopClock(schedule: schedule, timeZone: timeZone)
    }

    /// The in-app booking calendar with its default slot length, lead time and window.
    public var bookingCalendar: BookingCalendar {
        BookingCalendar(clock: clock)
    }

    public var instagramURL: URL {
        URL(string: "https://www.instagram.com/\(instagramHandle)/")!
    }

    /// Opens the shop in Apple Maps.
    public var appleMapsURL: URL {
        ShopInfo.link(host: "maps.apple.com", path: "/", query: [
            ("q", fullName),
            ("address", address.singleLine),
            ("ll", "\(coordinate.latitude),\(coordinate.longitude)"),
        ])
    }

    /// Driving directions to the shop in Apple Maps.
    public var appleMapsDirectionsURL: URL {
        ShopInfo.link(host: "maps.apple.com", path: "/", query: [
            ("daddr", address.singleLine),
            ("dirflg", "d"),
        ])
    }

    /// Directions in Google Maps (the app if installed, otherwise the web).
    public var googleMapsDirectionsURL: URL {
        ShopInfo.link(host: "www.google.com", path: "/maps/dir/", query: [
            ("api", "1"),
            ("destination", "\(fullName), \(address.singleLine)"),
        ])
    }

    /// The shop's Google Maps page, with its Google reviews.
    public var googleMapsURL: URL {
        ShopInfo.googleMapsURL(name: fullName, placeID: googlePlaceID)
    }

    /// Google's "Write a review" page for the shop.
    public var googleReviewURL: URL {
        ShopInfo.googleReviewURL(placeID: googlePlaceID)
    }

    static func googleMapsURL(name: String, placeID: String) -> URL {
        link(host: "www.google.com", path: "/maps/search/", query: [
            ("api", "1"),
            ("query", name),
            ("query_place_id", placeID),
        ])
    }

    static func googleReviewURL(placeID: String) -> URL {
        link(host: "search.google.com", path: "/local/writereview", query: [("placeid", placeID)])
    }

    /// Google place IDs are URL-safe base64: letters, digits, "-" and "_".
    static func isPlaceID(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                || scalar == "-" || scalar == "_"
        }
    }

    private static func link(host: String, path: String, query: [(String, String)]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            preconditionFailure("Couldn't build a link to \(host)")
        }
        return url
    }
}
