import XCTest
@testable import IzzyClipzKit

final class CatalogTests: XCTestCase {
    let catalog = Catalog.izzyClipz

    // MARK: Integrity

    func testShopDataIsValid() {
        XCTAssertEqual(catalog.validationProblems(), [])
    }

    func testEveryServiceHasAnOffering() {
        for service in catalog.services {
            XCTAssertFalse(catalog.offerings(forService: service.id).isEmpty, service.id)
        }
    }

    func testEveryBarberHasOfferings() {
        for barber in catalog.barbers {
            XCTAssertFalse(catalog.offerings(forBarber: barber.id).isEmpty, barber.id)
        }
    }

    func testSquireIDsAreLowercaseUUIDs() {
        for offering in catalog.offerings {
            XCTAssertNotNil(UUID(uuidString: offering.squireServiceID), offering.id)
            XCTAssertEqual(offering.squireServiceID, offering.squireServiceID.lowercased())
        }
    }

    func testValidationCatchesBrokenData() {
        let service = Service(id: "cut", name: "Cut", category: .haircuts, summary: "A cut", symbol: "scissors")
        let unoffered = Service(id: "lonely", name: "Lonely", category: .addOns, summary: "Nobody does this", symbol: "eye")
        let barber = Barber(id: "a-b", name: "A", listedName: "A B.", title: "Barber", bio: "", specialties: [], rating: nil)
        let badSlug = Barber(id: "Bad Slug", name: "B", listedName: "B", title: "Barber", bio: "", specialties: [], rating: nil)
        let uuid = "bbb0c294-87a6-465d-9f55-6f579dcb399a"
        let broken = Catalog(
            services: [service, service, unoffered],
            barbers: [barber, badSlug],
            offerings: [
                Offering(squireServiceID: uuid, serviceID: "cut", barberID: "a-b", price: .dollars(10), durationMinutes: 30),
                Offering(squireServiceID: uuid, serviceID: "ghost", barberID: "Bad Slug", price: .dollars(10), durationMinutes: 30),
                Offering(squireServiceID: "not-a-uuid", serviceID: "cut", barberID: "nobody", price: .dollars(10), durationMinutes: 30),
            ]
        )
        let problems = broken.validationProblems()
        XCTAssertTrue(problems.contains("Duplicate service ID 'cut'"), "\(problems)")
        XCTAssertTrue(problems.contains("Nobody offers 'lonely'"), "\(problems)")
        XCTAssertTrue(problems.contains("Barber ID 'Bad Slug' isn't a URL slug"), "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("unknown service 'ghost'") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("unknown barber 'nobody'") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("invalid Squire ID") }, "\(problems)")
        XCTAssertTrue(problems.contains("Squire item '\(uuid)' is mapped to several services"), "\(problems)")
    }

    // MARK: Lookup and grouping

    func testLookups() {
        XCTAssertEqual(catalog.service(withID: "vip")?.name, "VIP")
        XCTAssertEqual(catalog.barber(withID: "carlos-rafael")?.name, "Carlos")
        XCTAssertNil(catalog.service(withID: "nope"))
        XCTAssertNil(catalog.barber(withID: "nope"))
        let offering = catalog.offerings(forBarber: "carlos-rafael")[0]
        XCTAssertEqual(catalog.offering(withID: offering.id), offering)
    }

    func testCategoriesInMenuOrder() {
        XCTAssertEqual(catalog.categories, [.haircuts, .packages, .shaves, .colorAndTexture, .addOns])
    }

    func testPopularServices() {
        XCTAssertEqual(catalog.popularServices.map(\.id), ["haircut", "haircut-and-beard", "vip", "hot-towel-shave"])
    }

    func testOfferingsForAServiceAreCheapestFirstThenInTeamOrder() {
        let haircuts = catalog.offerings(forService: "haircut")
        XCTAssertEqual(haircuts.map(\.barberID), [
            "flowxbori", "cristian-ceja", "julian-ramos", // $35
            "israel-flores", "flowxbori", // $40
            "carlos-rafael", // $45
        ])
        XCTAssertEqual(haircuts.map(\.price.cents), [3500, 3500, 3500, 4000, 4000, 4500])
    }

    func testOfferingsForABarberAreInMenuOrder() {
        XCTAssertEqual(catalog.offerings(forBarber: "carlos-rafael").map(\.serviceID), [
            "haircut", "military-haircut", "haircut-and-beard", "hot-lather-shave", "eyebrows", "mustache", "enhancements",
        ])
        // Flowxbori offers two haircuts; the shorter, cheaper one comes first.
        XCTAssertEqual(catalog.offerings(forBarber: "flowxbori").prefix(2).map(\.durationMinutes), [45, 60])
    }

    func testServicesOfferedByABarber() {
        XCTAssertEqual(catalog.services(offeredBy: "israel-flores").map(\.id), [
            "haircut", "military-haircut", "haircut-and-beard", "vip", "hot-towel-shave", "lightener", "perm",
        ])
        XCTAssertEqual(catalog.services(offeredBy: "nobody"), [])
    }

    func testBarbersOfferingAService() {
        XCTAssertEqual(catalog.barbers(offering: "vip").map(\.id), ["israel-flores"])
        XCTAssertEqual(catalog.barbers(offering: "haircut-and-beard").count, 5)
        XCTAssertEqual(catalog.barbers(offering: "seniors-haircut").map(\.id), ["flowxbori", "julian-ramos"])
    }

    // MARK: Summaries

    func testPriceSummaries() {
        let expected = [
            "haircut": "$35–$45",
            "military-haircut": "$25–$35",
            "seniors-haircut": "$16",
            "haircut-and-beard": "$55–$60",
            "vip": "$80",
            "hot-towel-shave": "$30",
            "lightener": "From $80",
            "perm": "$150",
            "hot-lather-shave": "$5",
            "eyebrows": "Included with cut",
            "mustache": "Included with cut",
            "enhancements": "$5",
        ]
        XCTAssertEqual(Set(expected.keys), Set(catalog.services.map(\.id)))
        for (id, label) in expected {
            XCTAssertEqual(catalog.priceSummary(forService: id), label, id)
        }
    }

    func testDurationSummaries() {
        XCTAssertEqual(catalog.durationSummary(forService: "haircut"), "45 min – 1 hr")
        XCTAssertEqual(catalog.durationSummary(forService: "military-haircut"), "45 min")
        XCTAssertEqual(catalog.durationSummary(forService: "vip"), "1 hr 15 min")
        XCTAssertEqual(catalog.durationSummary(forService: "hot-towel-shave"), "15–30 min")
        XCTAssertEqual(catalog.durationSummary(forService: "lightener"), "2 hr")
        XCTAssertEqual(catalog.durationSummary(forService: "perm"), "4 hr")
    }

    func testLowestPriceForABarber() {
        XCTAssertEqual(catalog.lowestPrice(forService: "haircut", barber: "israel-flores"), .dollars(40))
        XCTAssertEqual(catalog.lowestPrice(forService: "haircut", barber: "carlos-rafael"), .dollars(45))
        XCTAssertEqual(catalog.lowestPrice(forService: "haircut", barber: "flowxbori"), .dollars(35))
        XCTAssertNil(catalog.lowestPrice(forService: "vip", barber: "carlos-rafael"))
    }

    // MARK: First available

    func testFirstAvailablePicksTheMostSharedMenuItem() throws {
        let haircut = try XCTUnwrap(catalog.firstAvailableOption(forService: "haircut"))
        XCTAssertEqual(haircut.squireServiceID, IzzyClipzMenu.haircut45)
        XCTAssertEqual(haircut.barberIDs, ["flowxbori", "cristian-ceja", "julian-ramos"])
        XCTAssertEqual(haircut.priceLabel, "$35")
        XCTAssertEqual(haircut.durationLabel, "45 min")

        let combo = try XCTUnwrap(catalog.firstAvailableOption(forService: "haircut-and-beard"))
        XCTAssertEqual(combo.squireServiceID, IzzyClipzMenu.haircutAndBeard)
        XCTAssertEqual(combo.barberIDs, catalog.barbers.map(\.id))
        XCTAssertEqual(combo.priceLabel, "$55–$60")

        let military = try XCTUnwrap(catalog.firstAvailableOption(forService: "military-haircut"))
        XCTAssertEqual(military.squireServiceID, IzzyClipzMenu.military)
        XCTAssertEqual(military.barberIDs, ["israel-flores", "flowxbori", "cristian-ceja", "julian-ramos"])
        XCTAssertEqual(military.priceLabel, "$25")

        let shave = try XCTUnwrap(catalog.firstAvailableOption(forService: "hot-towel-shave"))
        XCTAssertEqual(shave.squireServiceID, IzzyClipzMenu.hotTowelShave30)
        XCTAssertEqual(shave.barberIDs, ["israel-flores", "flowxbori", "julian-ramos"])
    }

    func testFirstAvailableNeedsAtLeastTwoBarbers() {
        XCTAssertNil(catalog.firstAvailableOption(forService: "vip"))
        XCTAssertNil(catalog.firstAvailableOption(forService: "perm"))
        XCTAssertNil(catalog.firstAvailableOption(forService: "eyebrows"))
        XCTAssertNil(catalog.firstAvailableOption(forService: "unknown"))
    }

    func testFirstAvailableBreaksTiesByPrice() throws {
        let cheap = "11111111-1111-1111-1111-111111111111"
        let pricey = "22222222-2222-2222-2222-222222222222"
        let service = Service(id: "cut", name: "Cut", category: .haircuts, summary: "A cut", symbol: "scissors")
        let barbers = ["a", "b", "c", "d"].map {
            Barber(id: $0, name: $0, listedName: $0, title: "Barber", bio: "", specialties: [], rating: nil)
        }
        let tied = Catalog(services: [service], barbers: barbers, offerings: [
            Offering(squireServiceID: pricey, serviceID: "cut", barberID: "a", price: .dollars(50), durationMinutes: 30),
            Offering(squireServiceID: pricey, serviceID: "cut", barberID: "b", price: .dollars(50), durationMinutes: 30),
            Offering(squireServiceID: cheap, serviceID: "cut", barberID: "c", price: .dollars(20), durationMinutes: 30),
            Offering(squireServiceID: cheap, serviceID: "cut", barberID: "d", price: .dollars(20), durationMinutes: 30),
        ])
        XCTAssertEqual(try XCTUnwrap(tied.firstAvailableOption(forService: "cut")).squireServiceID, cheap)
    }

    // MARK: Search

    func testEmptySearchReturnsEverything() {
        XCTAssertEqual(catalog.search("").count, catalog.services.count)
        XCTAssertEqual(catalog.search("   ").count, catalog.services.count)
    }

    func testSearchMatchesNamesDescriptionsAndCategories() {
        XCTAssertEqual(catalog.search("beard").map(\.id), ["haircut-and-beard"])
        XCTAssertEqual(catalog.search("facial").map(\.id), ["vip"])
        XCTAssertEqual(catalog.search("add-ons").map(\.id), ["hot-lather-shave", "eyebrows", "mustache", "enhancements"])
        XCTAssertTrue(catalog.search("SHAVE").map(\.id).contains("hot-towel-shave"))
    }

    func testSearchNeedsEveryWord() {
        XCTAssertEqual(catalog.search("hot towel").map(\.id), ["haircut-and-beard", "hot-towel-shave"])
        XCTAssertEqual(catalog.search("hot nonsense"), [])
    }

    func testSearchIgnoresAccents() {
        XCTAssertEqual(catalog.search("Militäry").map(\.id), ["military-haircut"])
    }

    // MARK: Barbers

    func testInitials() {
        XCTAssertEqual(catalog.barber(withID: "israel-flores")?.initials, "IF")
        XCTAssertEqual(catalog.barber(withID: "carlos-rafael")?.initials, "CR")
        XCTAssertEqual(catalog.barber(withID: "flowxbori")?.initials, "F")
    }

    func testOwnerIsListedFirst() {
        XCTAssertEqual(catalog.barbers.first?.id, "israel-flores")
    }
}
