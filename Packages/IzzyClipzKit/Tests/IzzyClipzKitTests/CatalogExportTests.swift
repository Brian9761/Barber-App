import XCTest
@testable import IzzyClipzKit

final class CatalogExportTests: XCTestCase {
    let document = CatalogExport.document()

    func testBookingRulesAndTimeZone() {
        XCTAssertEqual(document.timeZone, "America/Los_Angeles")
        XCTAssertEqual(document.slotIntervalMinutes, 30)
        XCTAssertEqual(document.leadTimeMinutes, 30)
        XCTAssertEqual(document.windowDays, 60)
        let calendar = ShopInfo.izzyClipz.bookingCalendar
        XCTAssertEqual(document.slotIntervalMinutes, calendar.slotIntervalMinutes)
        XCTAssertEqual(document.leadTimeMinutes, calendar.leadTimeMinutes)
        XCTAssertEqual(document.windowDays, calendar.windowDays)
    }

    func testHoursUseTheKitsWeekdayNumbers() {
        // 1 = Sunday … 7 = Saturday, like Foundation's `.weekday` and the Kit's `Weekday`.
        XCTAssertEqual(document.hours.keys.sorted(), ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(document.hours["1"], CatalogExport.Document.Hours(opens: "10:00", closes: "18:00"))
        for key in ["2", "3", "4", "5", "6", "7"] {
            XCTAssertEqual(document.hours[key], CatalogExport.Document.Hours(opens: "10:00", closes: "19:00"), key)
        }
        for weekday in Weekday.allCases {
            let hours = ShopInfo.izzyClipz.schedule.hours(on: weekday)!
            XCTAssertEqual(document.hours[String(weekday.rawValue)]?.opens, CatalogExport.clockTime(hours.opens), weekday.name)
            XCTAssertEqual(document.hours[String(weekday.rawValue)]?.closes, CatalogExport.clockTime(hours.closes), weekday.name)
        }
    }

    func testClosedDaysAreLeftOutAndTimesArePadded() {
        let shop = ShopInfo.izzyClipz
        let custom = ShopInfo(
            name: shop.name, fullName: shop.fullName, tagline: shop.tagline, about: shop.about, address: shop.address,
            coordinate: shop.coordinate, phone: shop.phone, timeZoneIdentifier: "America/New_York",
            schedule: WeeklySchedule([
                .tuesday: OpeningHours(opens: TimeOfDay(hour: 9, minute: 30), closes: TimeOfDay(hour: 17, minute: 5)),
            ]),
            instagramHandle: shop.instagramHandle, websiteURL: shop.websiteURL, booking: shop.booking,
            paymentMethods: shop.paymentMethods, highlights: shop.highlights, accessibility: shop.accessibility,
            ratings: shop.ratings, reviews: shop.reviews, googlePlaceID: shop.googlePlaceID
        )
        let rules = BookingCalendar(clock: custom.clock, slotIntervalMinutes: 15, leadTimeMinutes: 0, windowDays: 14)
        let exported = CatalogExport.document(shop: custom, calendar: rules)
        XCTAssertEqual(exported.timeZone, "America/New_York")
        XCTAssertEqual(exported.hours, ["3": CatalogExport.Document.Hours(opens: "09:30", closes: "17:05")])
        XCTAssertEqual(exported.slotIntervalMinutes, 15)
        XCTAssertEqual(exported.leadTimeMinutes, 0)
        XCTAssertEqual(exported.windowDays, 14)
    }

    func testServicesAndBarbersInMenuAndTeamOrder() {
        XCTAssertEqual(document.services.map(\.id), Catalog.izzyClipz.services.map(\.id))
        XCTAssertEqual(document.services.first, CatalogExport.Document.Service(id: "haircut", name: "Haircut"))
        XCTAssertEqual(document.barbers.map(\.id), ["israel-flores", "carlos-rafael", "flowxbori", "cristian-ceja", "julian-ramos"])
        XCTAssertEqual(document.barbers.map(\.name), ["Izzy", "Carlos", "Flowxbori", "Cristian", "Julian"])
    }

    func testOfferingsMatchTheKit() {
        XCTAssertEqual(document.offerings.count, Catalog.izzyClipz.offerings.count)
        XCTAssertEqual(Set(document.offerings.map(\.id)).count, document.offerings.count, "unique IDs")
        for (exported, offering) in zip(document.offerings, Catalog.izzyClipz.offerings) {
            XCTAssertEqual(exported.id, offering.id)
            XCTAssertEqual(exported.id, "\(offering.barberID)/\(offering.squireServiceID)")
            XCTAssertEqual(exported.serviceId, offering.serviceID)
            XCTAssertEqual(exported.barberId, offering.barberID)
            XCTAssertEqual(exported.durationMinutes, offering.durationMinutes)
            XCTAssertEqual(exported.priceCents, offering.price.cents)
            XCTAssertEqual(exported.priceLabel, offering.price.label)
            XCTAssertNil(exported.name)
        }
        let lightener = document.offerings.first { $0.serviceId == "lightener" }
        XCTAssertEqual(lightener?.priceKind, "startingAt")
        XCTAssertEqual(lightener?.priceLabel, "From $80")
        XCTAssertEqual(lightener?.priceCents, 8000)
        let eyebrows = document.offerings.first { $0.serviceId == "eyebrows" }
        XCTAssertEqual(eyebrows?.priceKind, "includedWithCut")
        XCTAssertEqual(eyebrows?.priceCents, 0)
        XCTAssertEqual(eyebrows?.priceLabel, "Included with cut")
        XCTAssertEqual(document.offerings.first?.priceKind, "fixed")
        XCTAssertEqual(Set(document.offerings.map(\.priceKind)), ["fixed", "startingAt", "includedWithCut"])
    }

    func testFirstAvailableIsTheKitsAnyBarberChoice() {
        let byService = Dictionary(uniqueKeysWithValues: document.firstAvailable.map { ($0.serviceId, $0.offeringIds) })
        XCTAssertEqual(byService["haircut"], [
            "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a",
            "cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a",
            "julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a",
        ])
        XCTAssertEqual(byService["military-haircut"]?.map { $0.split(separator: "/")[0] }, ["israel-flores", "flowxbori", "cristian-ceja", "julian-ramos"])
        XCTAssertEqual(byService["hot-towel-shave"]?.count, 3, "Cristian's 15-minute shave is a different item")
        // Only one barber offers these, so there's no "Any barber".
        for serviceId in ["lightener", "perm", "hot-lather-shave", "eyebrows", "mustache", "enhancements"] {
            XCTAssertNil(byService[serviceId], serviceId)
        }
        let offerings = Dictionary(uniqueKeysWithValues: document.offerings.map { ($0.id, $0) })
        for entry in document.firstAvailable {
            XCTAssertGreaterThanOrEqual(entry.offeringIds.count, 2, entry.serviceId)
            XCTAssertEqual(Set(entry.offeringIds.compactMap { offerings[$0]?.barberId }).count, entry.offeringIds.count, "one per barber")
            for id in entry.offeringIds {
                XCTAssertEqual(offerings[id]?.serviceId, entry.serviceId, id)
            }
            let option = Catalog.izzyClipz.firstAvailableOption(forService: entry.serviceId)
            XCTAssertEqual(entry.offeringIds.map { String($0.split(separator: "/")[0]) }, option?.barberIDs)
        }
        XCTAssertEqual(document.firstAvailable.map(\.serviceId), Catalog.izzyClipz.services.map(\.id).filter { byService[$0] != nil })
    }

    func testJSONFile() throws {
        let data = try CatalogExport.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("}\n"))
        XCTAssertFalse(text.contains("\\/"), "slashes in offering IDs stay readable")
        XCTAssertTrue(text.contains("\"flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a\""))
        XCTAssertFalse(text.contains("\"name\" : null"))
        XCTAssertEqual(try JSONDecoder().decode(CatalogExport.Document.self, from: data), document)
        let json = try JSONValue(data: data)
        XCTAssertEqual(json.keys, ["timeZone", "slotIntervalMinutes", "leadTimeMinutes", "windowDays", "hours", "services", "barbers", "offerings", "firstAvailable"])
        if case .array(let offerings) = json["offerings"], let first = offerings.first {
            XCTAssertEqual(first.keys, ["id", "serviceId", "barberId", "durationMinutes", "priceCents", "priceKind", "priceLabel"])
        } else {
            XCTFail("offerings isn't an array")
        }
        // The same bytes every time, so the committed file only changes when the data does.
        XCTAssertEqual(try CatalogExport.jsonData(), data)
    }

    /// `server/data/catalog.json` must say exactly what the Kit says.
    /// Regenerate it with `UPDATE_CATALOG_JSON=1 swift test`; set
    /// `CATALOG_JSON_PATH` to compare or write another file.
    func testTheServersCatalogMatchesTheKit() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = environment["CATALOG_JSON_PATH"].map { URL(fileURLWithPath: $0) }
            ?? TestPaths.repository.appendingPathComponent("server/data/catalog.json")
        let generated = try CatalogExport.jsonData()

        if environment["UPDATE_CATALOG_JSON"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try generated.write(to: url, options: .atomic)
            print("Wrote \(url.path)")
            return
        }
        guard let committed = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No catalog at \(url.path) yet. Create it with UPDATE_CATALOG_JSON=1 swift test --package-path Packages/IzzyClipzKit")
        }
        let differences = try JSONValue(data: committed).differences(from: try JSONValue(data: generated))
        XCTAssertTrue(
            differences.isEmpty,
            "\(url.path) differs from the Kit (first = the file, second = the Kit). "
                + "Regenerate it with UPDATE_CATALOG_JSON=1 swift test --package-path Packages/IzzyClipzKit\n"
                + differences.prefix(30).joined(separator: "\n")
        )
    }
}
