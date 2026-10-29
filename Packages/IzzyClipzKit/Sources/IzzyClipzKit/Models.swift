import Foundation

/// Groups on the service menu, in display order.
public enum ServiceCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case haircuts
    case packages
    case shaves
    case colorAndTexture
    case addOns

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .haircuts: return "Haircuts"
        case .packages: return "Packages"
        case .shaves: return "Shaves"
        case .colorAndTexture: return "Color & Texture"
        case .addOns: return "Add-ons"
        }
    }

    /// SF Symbol shown next to the category.
    public var symbol: String {
        switch self {
        case .haircuts: return "scissors"
        case .packages: return "crown"
        case .shaves: return "mustache"
        case .colorAndTexture: return "paintpalette"
        case .addOns: return "plus.circle"
        }
    }
}

/// Something a client can book, independent of who performs it.
///
/// Prices and durations live on `Offering`, because each barber sets their own.
public struct Service: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: ServiceCategory
    public let summary: String
    public let includes: [String]
    public let symbol: String
    public let isPopular: Bool

    public init(
        id: String,
        name: String,
        category: ServiceCategory,
        summary: String,
        includes: [String] = [],
        symbol: String,
        isPopular: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.includes = includes
        self.symbol = symbol
        self.isPopular = isPopular
    }
}

/// An average star rating and how many reviews it's based on.
public struct Rating: Hashable, Sendable {
    public let average: Double
    public let count: Int

    public init(average: Double, count: Int) {
        precondition((0...5).contains(average), "Ratings are out of 5")
        precondition(count >= 0, "Review counts can't be negative")
        self.average = average
        self.count = count
    }

    /// "5.0".
    public var averageLabel: String {
        let tenths = Int((average * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// "92 reviews", "1 review".
    public var countLabel: String {
        count == 1 ? "1 review" : "\(count) reviews"
    }
}

/// A rating as published by one review site, e.g. Squire or Google.
public struct SourcedRating: Hashable, Sendable {
    /// The site's name as shown to clients, e.g. "Google".
    public let source: String
    public let rating: Rating
    /// Where the reviews can be read, if there's a page for them.
    public let url: URL?

    public init(source: String, rating: Rating, url: URL? = nil) {
        self.source = source
        self.rating = rating
        self.url = url
    }
}

/// A member of the team, as listed on the shop's Squire page.
public struct Barber: Identifiable, Hashable, Sendable {
    /// The barber's Squire URL slug, e.g. "israel-flores". Used to build booking links.
    public let id: String
    /// The name clients know them by, e.g. "Izzy".
    public let name: String
    /// How Squire lists them, e.g. "Israel F.".
    public let listedName: String
    public let title: String
    public let bio: String
    public let specialties: [String]
    public let rating: Rating?
    /// Their own Instagram account, without the "@", e.g. "izzy_clipz_".
    public let instagramHandle: String?

    public init(
        id: String,
        name: String,
        listedName: String,
        title: String,
        bio: String,
        specialties: [String],
        rating: Rating?,
        instagramHandle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.listedName = listedName
        self.title = title
        self.bio = bio
        self.specialties = specialties
        self.rating = rating
        self.instagramHandle = instagramHandle
    }

    /// "https://www.instagram.com/izzy_clipz_/", or `nil` without a valid handle.
    public var instagramURL: URL? {
        guard let instagramHandle, Barber.isInstagramHandle(instagramHandle) else { return nil }
        return URL(string: "https://www.instagram.com/\(instagramHandle)/")
    }

    /// Instagram usernames are letters, digits, periods and underscores, up to 30 long.
    static func isInstagramHandle(_ string: String) -> Bool {
        (1...30).contains(string.count) && string.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                || scalar == "_" || scalar == "."
        }
    }

    /// Up to two letters for avatar monograms: "Israel F." -> "IF", "Flowxbori" -> "F".
    public var initials: String {
        let words = listedName
            .split(whereSeparator: { $0 == " " || $0 == "." })
            .filter { !$0.isEmpty }
        return words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

/// A specific barber's version of a service: the exact item on their Squire menu.
public struct Offering: Identifiable, Hashable, Sendable {
    /// The service's ID in Squire. Passed as `preselect` so the booking page
    /// opens with this exact item already in the cart.
    public let squireServiceID: String
    public let serviceID: String
    public let barberID: String
    public let price: Price
    public let durationMinutes: Int
    /// Barber-specific detail, e.g. what's included in their version.
    public let note: String?

    public init(
        squireServiceID: String,
        serviceID: String,
        barberID: String,
        price: Price,
        durationMinutes: Int,
        note: String? = nil
    ) {
        precondition(durationMinutes > 0, "An appointment needs a length")
        self.squireServiceID = squireServiceID.lowercased()
        self.serviceID = serviceID
        self.barberID = barberID
        self.price = price
        self.durationMinutes = durationMinutes
        self.note = note
    }

    public var id: String { "\(barberID)/\(squireServiceID)" }

    public var durationLabel: String { DurationText.short(minutes: durationMinutes) }
}

/// A client review quoted in the app.
public struct Review: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: String
    public let stars: Int
    public let text: String
    public let barberID: String?
    public let source: String
    /// When it was written, as display text, e.g. "Aug 2026". `nil` when unknown.
    public let date: String?

    public init(
        id: String,
        author: String,
        stars: Int,
        text: String,
        barberID: String?,
        source: String,
        date: String? = nil
    ) {
        precondition((1...5).contains(stars), "Reviews are 1 to 5 stars")
        self.id = id
        self.author = author
        self.stars = stars
        self.text = text
        self.barberID = barberID
        self.source = source
        self.date = date
    }
}
