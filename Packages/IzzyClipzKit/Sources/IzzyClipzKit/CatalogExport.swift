import Foundation

/// The catalog the server books against, as JSON: `server/data/catalog.json`.
///
/// The Kit is the source of truth for the menu, the team, the hours and the
/// booking rules; the server reads this file so both sides offer the same
/// services, prices and slots. A Kit test fails when the committed file
/// differs; regenerate it with `UPDATE_CATALOG_JSON=1 swift test`.
///
/// The server also serves it to the shop's website as `GET /api/catalog`, so it
/// carries what the website shows that the server doesn't need to book: the
/// shop's own details (`shop`), each service's description, category and
/// whether it's a favorite, and each barber's title, bio and monogram. The
/// server's booking code ignores those fields.
///
/// Shape:
/// ```
/// { timeZone, slotIntervalMinutes, leadTimeMinutes, windowDays,
///   hours: { "1": { opens: "10:00", closes: "18:00" }, … },
///   services: [{ id, name, description?, category, popular }],
///   barbers: [{ id, name, title, bio, specialties, monogram, instagram? }],
///   offerings: [{ id, serviceId, barberId, durationMinutes, priceCents, priceKind, priceLabel, name? }],
///   firstAvailable: [{ serviceId, offeringIds }],
///   shop: { name, fullName, tagline, phone: { e164, display },
///           address: { street, unit?, city, state, postalCode, lines },
///           coordinate: { latitude, longitude }, instagram: { handle, url },
///           appleMapsUrl, appleMapsDirectionsUrl, googleMapsUrl, googleMapsDirectionsUrl,
///           googleReviewUrl, websiteUrl, about, highlights, paymentMethods, accessibility } }
/// ```
/// - `hours` keys are the Kit's `Weekday` numbers, like Foundation's
///   `.weekday`: "1" = Sunday, "2" = Monday … "7" = Saturday. Days the shop is
///   closed have no key. Times are 24-hour shop wall-clock times, "HH:MM".
/// - Offering IDs are the Kit's `Offering.id`: "<barber id>/<Squire item id>",
///   e.g. "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a".
/// - `priceKind` is "fixed", "startingAt" or "includedWithCut";
///   `priceCents` is 0 for "includedWithCut"; `priceLabel` is `Price.label`.
/// - `name` is left out: the Kit's offerings use their service's name.
/// - `firstAvailable` lists, for each service that more than one barber shares
///   an item for, the offerings "Any barber" picks from, in team order
///   (`Catalog.firstAvailableOption(forService:)`). Services without "Any
///   barber" have no entry.
/// - A service's `description` is its `summary` (left out if it has none),
///   `category` the menu category's title ("Haircuts"), and `popular` whether
///   it's among Home's favorites. A barber's `monogram` is the two letters on
///   their tile (`Barber.monogram`), and `instagram` is left out without one.
/// - `shop.phone.e164` is "+14423413053" and `display` "(442) 341-3053";
///   `shop.address.lines` are the street line and the city line. The map and
///   review links are `ShopInfo`'s own.
public enum CatalogExport {
    public struct Document: Codable, Hashable, Sendable {
        public struct Hours: Codable, Hashable, Sendable {
            public var opens: String
            public var closes: String
        }

        public struct Service: Codable, Hashable, Sendable {
            public var id: String
            public var name: String
            /// What it is, in the menu's words; `nil` (left out) when the Kit has none.
            public var description: String?
            /// The menu category's title, e.g. "Haircuts". Services come in menu order, so
            /// each category's services are together.
            public var category: String
            /// One of the menu's favorites, as on Home.
            public var popular: Bool
        }

        /// An Instagram account: its handle without the "@", and its page.
        public struct Instagram: Codable, Hashable, Sendable {
            public var handle: String
            public var url: String
        }

        public struct Barber: Codable, Hashable, Sendable {
            public var id: String
            public var name: String
            /// "Owner · Barber".
            public var title: String
            public var bio: String
            public var specialties: [String]
            /// The two letters on their tile, "IZ" (`Barber.monogram`).
            public var monogram: String
            /// Their own account; `nil` (left out) when they have none.
            public var instagram: Instagram?
        }

        /// The shop itself, for the website's pages.
        public struct Shop: Codable, Hashable, Sendable {
            public struct Phone: Codable, Hashable, Sendable {
                /// "+14423413053".
                public var e164: String
                /// "(442) 341-3053".
                public var display: String
            }

            public struct Address: Codable, Hashable, Sendable {
                public var street: String
                public var unit: String?
                public var city: String
                public var state: String
                public var postalCode: String
                /// "1919 Mission Ave, Ste 105" and "Oceanside, CA 92058".
                public var lines: [String]
            }

            public struct Coordinate: Codable, Hashable, Sendable {
                public var latitude: Double
                public var longitude: Double
            }

            public var name: String
            public var fullName: String
            public var tagline: String
            public var phone: Phone
            public var address: Address
            public var coordinate: Coordinate
            public var instagram: Instagram
            public var appleMapsUrl: String
            public var appleMapsDirectionsUrl: String
            public var googleMapsUrl: String
            public var googleMapsDirectionsUrl: String
            public var googleReviewUrl: String
            public var websiteUrl: String
            public var about: [String]
            public var highlights: [String]
            public var paymentMethods: [String]
            public var accessibility: [String]
        }

        public struct Offering: Codable, Hashable, Sendable {
            public var id: String
            public var serviceId: String
            public var barberId: String
            public var durationMinutes: Int
            public var priceCents: Int
            public var priceKind: String
            public var priceLabel: String
            public var name: String?
        }

        public struct FirstAvailable: Codable, Hashable, Sendable {
            public var serviceId: String
            public var offeringIds: [String]
        }

        public var timeZone: String
        public var slotIntervalMinutes: Int
        public var leadTimeMinutes: Int
        public var windowDays: Int
        public var hours: [String: Hours]
        public var services: [Service]
        public var barbers: [Barber]
        public var offerings: [Offering]
        public var firstAvailable: [FirstAvailable]
        public var shop: Shop
    }

    /// The document for a catalog, the shop's hours and time zone, and the
    /// booking calendar's rules (the shop's default calendar unless given).
    public static func document(
        catalog: Catalog = .izzyClipz,
        shop: ShopInfo = .izzyClipz,
        calendar: BookingCalendar? = nil
    ) -> Document {
        let rules = calendar ?? shop.bookingCalendar
        var hours: [String: Document.Hours] = [:]
        for weekday in Weekday.allCases {
            guard let open = shop.schedule.hours(on: weekday) else { continue }
            hours[String(weekday.rawValue)] = Document.Hours(opens: clockTime(open.opens), closes: clockTime(open.closes))
        }
        return Document(
            timeZone: shop.timeZoneIdentifier,
            slotIntervalMinutes: rules.slotIntervalMinutes,
            leadTimeMinutes: rules.leadTimeMinutes,
            windowDays: rules.windowDays,
            hours: hours,
            services: catalog.services.map { service in
                let summary = service.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return Document.Service(
                    id: service.id,
                    name: service.name,
                    description: summary.isEmpty ? nil : summary,
                    category: service.category.title,
                    popular: service.isPopular
                )
            },
            barbers: catalog.barbers.map { barber in
                Document.Barber(
                    id: barber.id,
                    name: barber.name,
                    title: barber.title,
                    bio: barber.bio,
                    specialties: barber.specialties,
                    monogram: barber.monogram,
                    instagram: barber.instagramURL.flatMap { url in
                        barber.instagramHandle.map { Document.Instagram(handle: $0, url: url.absoluteString) }
                    }
                )
            },
            offerings: catalog.offerings.map { offering in
                Document.Offering(
                    id: offering.id,
                    serviceId: offering.serviceID,
                    barberId: offering.barberID,
                    durationMinutes: offering.durationMinutes,
                    priceCents: offering.price.cents,
                    priceKind: priceKind(offering.price.kind),
                    priceLabel: offering.price.label,
                    name: nil
                )
            },
            firstAvailable: catalog.services.compactMap { service in
                guard let option = catalog.firstAvailableOption(forService: service.id) else { return nil }
                let ids = option.barberIDs.compactMap { barberID in
                    catalog.offerings.first {
                        $0.barberID == barberID && $0.serviceID == service.id && $0.squireServiceID == option.squireServiceID
                    }?.id
                }
                return Document.FirstAvailable(serviceId: service.id, offeringIds: ids)
            },
            shop: shopDocument(shop)
        )
    }

    /// The shop's details as the website shows them.
    static func shopDocument(_ shop: ShopInfo) -> Document.Shop {
        Document.Shop(
            name: shop.name,
            fullName: shop.fullName,
            tagline: shop.tagline,
            phone: Document.Shop.Phone(e164: shop.phone.e164, display: shop.phone.display),
            address: Document.Shop.Address(
                street: shop.address.street,
                unit: shop.address.unit,
                city: shop.address.city,
                state: shop.address.state,
                postalCode: shop.address.postalCode,
                lines: [shop.address.streetLine, shop.address.cityLine]
            ),
            coordinate: Document.Shop.Coordinate(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude),
            instagram: Document.Instagram(handle: shop.instagramHandle, url: shop.instagramURL.absoluteString),
            appleMapsUrl: shop.appleMapsURL.absoluteString,
            appleMapsDirectionsUrl: shop.appleMapsDirectionsURL.absoluteString,
            googleMapsUrl: shop.googleMapsURL.absoluteString,
            googleMapsDirectionsUrl: shop.googleMapsDirectionsURL.absoluteString,
            googleReviewUrl: shop.googleReviewURL.absoluteString,
            websiteUrl: shop.websiteURL.absoluteString,
            about: shop.about,
            highlights: shop.highlights,
            paymentMethods: shop.paymentMethods,
            accessibility: shop.accessibility
        )
    }

    /// The document as the file is written: pretty-printed, sorted keys,
    /// slashes unescaped, ending in a newline.
    public static func jsonData(
        catalog: Catalog = .izzyClipz,
        shop: ShopInfo = .izzyClipz,
        calendar: BookingCalendar? = nil
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document(catalog: catalog, shop: shop, calendar: calendar))
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// "fixed", "startingAt", "includedWithCut".
    static func priceKind(_ kind: Price.Kind) -> String {
        switch kind {
        case .fixed: return "fixed"
        case .startingAt: return "startingAt"
        case .includedWithCut: return "includedWithCut"
        }
    }

    /// "10:00", "19:00", "09:30".
    static func clockTime(_ time: TimeOfDay) -> String {
        CalendarDay.twoDigits(time.hour) + ":" + CalendarDay.twoDigits(time.minute)
    }
}
