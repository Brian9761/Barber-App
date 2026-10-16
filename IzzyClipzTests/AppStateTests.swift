import XCTest
@testable import IzzyClipz

@MainActor
final class AppRouterTests: XCTestCase {
    func testBookingOpensTheBookingSheet() {
        let router = AppRouter()
        router.book(.barber("carlos-rafael"))
        XCTAssertEqual(router.sheet, .booking(.barber("carlos-rafael")))
    }

    func testStartBookingWithAServiceSkipsToChoosingABarber() {
        let router = AppRouter()
        router.sheet = .reminders
        router.startBooking(serviceID: "vip")
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "vip")])
        XCTAssertNil(router.sheet)
    }

    func testStartBookingFromScratchResetsTheFlow() {
        let router = AppRouter()
        router.bookingPath = [.chooseBarber(serviceID: "haircut")]
        router.startBooking()
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [])
    }

    func testSheetIdentitiesAreDistinct() throws {
        let offering = try XCTUnwrap(AppData.catalog.offerings.first)
        let sheets: [AppSheet] = [.reminders, .booking(.anything), .booking(.barber(offering.barberID)), .booking(.offering(offering))]
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }

    func testChoicesTurnIntoBookingRequests() throws {
        let offering = try XCTUnwrap(AppData.catalog.offerings(forService: "vip").first)
        XCTAssertEqual(BookingChoice.offering(offering).request, .offering(offering))
        XCTAssertEqual(BookingChoice.offering(offering).serviceID, "vip")

        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        XCTAssertEqual(BookingChoice.firstAvailable(option).request, .firstAvailable(option))
        XCTAssertEqual(BookingChoice.firstAvailable(option).serviceID, "haircut")
    }
}

@MainActor
final class FavoritesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "FavoritesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testTogglingAFavorite() {
        let favorites = Favorites(defaults: makeDefaults())
        XCTAssertNil(favorites.barber)

        favorites.toggle("carlos-rafael")
        XCTAssertTrue(favorites.isFavorite("carlos-rafael"))
        XCTAssertEqual(favorites.barber?.name, "Carlos")

        favorites.toggle("carlos-rafael")
        XCTAssertNil(favorites.barberID)
    }

    func testOnlyOneFavorite() {
        let favorites = Favorites(defaults: makeDefaults())
        favorites.toggle("carlos-rafael")
        favorites.toggle("israel-flores")
        XCTAssertEqual(favorites.barberID, "israel-flores")
        XCTAssertFalse(favorites.isFavorite("carlos-rafael"))
    }

    func testFavoriteIsRemembered() {
        let defaults = makeDefaults()
        Favorites(defaults: defaults).toggle("flowxbori")
        XCTAssertEqual(Favorites(defaults: defaults).barberID, "flowxbori")
    }

    func testForgetsBarbersWhoLeft() {
        let defaults = makeDefaults()
        defaults.set("someone-who-left", forKey: "favorites.barberID")
        XCTAssertNil(Favorites(defaults: defaults).barberID)
    }
}
