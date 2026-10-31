import Foundation

/// The catalog the server books against, as JSON: `server/data/catalog.json`.
///
/// The Kit is the source of truth for the menu, the team, the hours and the
/// booking rules; the server reads this file so both sides offer the same
/// services, prices and slots. A Kit test fails when the committed file
/// differs; regenerate it with `UPDATE_CATALOG_JSON=1 swift test`.
///
/// Shape:
/// ```
/// { timeZone, slotIntervalMinutes, leadTimeMinutes, windowDays,
///   hours: { "1": { opens: "10:00", closes: "18:00" }, … },
///   services: [{ id, name }], barbers: [{ id, name }],
///   offerings: [{ id, serviceId, barberId, durationMinutes, priceCents, priceKind, priceLabel, name? }],
///   firstAvailable: [{ serviceId, offeringIds }] }
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
public enum CatalogExport {
    public struct Document: Codable, Hashable, Sendable {
        public struct Hours: Codable, Hashable, Sendable {
            public var opens: String
            public var closes: String
        }

        public struct Service: Codable, Hashable, Sendable {
            public var id: String
            public var name: String
        }

        public struct Barber: Codable, Hashable, Sendable {
            public var id: String
            public var name: String
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
            services: catalog.services.map { Document.Service(id: $0.id, name: $0.name) },
            barbers: catalog.barbers.map { Document.Barber(id: $0.id, name: $0.name) },
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
            }
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
