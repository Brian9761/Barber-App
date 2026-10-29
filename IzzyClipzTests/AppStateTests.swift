import XCTest
@testable import IzzyClipz

@MainActor
final class AppRouterTests: XCTestCase {
    // Friday, October 30, 2026, 2:30 PM in Oceanside.
    private let start = Date(timeIntervalSince1970: 1_793_395_800)

    private func haircutWithCarlos() throws -> Offering {
        try XCTUnwrap(AppData.catalog.offerings(forService: "haircut").first { $0.barberID == "carlos-rafael" })
    }

    private func plan() throws -> BookingPlan {
        BookingPlan(choice: .offering(try haircutWithCarlos()), start: start)
    }

    func testStartBookingFromScratchResetsTheFlow() {
        let router = AppRouter()
        router.bookingPath = [.chooseBarber(serviceID: "haircut")]
        router.present(.reminders)
        router.startBooking()
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [])
        XCTAssertNil(router.sheet)
    }

    func testStartBookingWithAServiceSkipsToChoosingABarber() {
        let router = AppRouter()
        router.present(.reminders)
        router.startBooking(serviceID: "vip")
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "vip")])
        XCTAssertNil(router.sheet)
    }

    func testStartBookingWithAChoiceGoesStraightToTheCalendar() throws {
        let router = AppRouter()
        let choice = BookingChoice.offering(try haircutWithCarlos())
        router.startBooking(choice: choice)
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "haircut"), .chooseTime(choice)])
    }

    func testStartBookingFromABarbersMenuGoesBackToTheirServices() throws {
        let router = AppRouter()
        let offering = try haircutWithCarlos()
        router.startBooking(fromBarberMenu: offering)
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [.chooseService(barberID: "carlos-rafael"), .chooseTime(.offering(offering))])
    }

    func testStartBookingWithABarberPicksTheirServiceFirst() {
        let router = AppRouter()
        router.selectedTab = .home
        router.startBooking(barberID: "julian-ramos")
        XCTAssertEqual(router.selectedTab, .book)
        XCTAssertEqual(router.bookingPath, [.chooseService(barberID: "julian-ramos")])
    }

    func testOpeningPagesSetsTheSheet() throws {
        let plan = try plan()
        let appointment = plan.appointment()
        let bravo = AppData.products.storeURL
        let cases: [(open: (AppRouter) -> Void, sheet: AppSheet)] = [
            ({ $0.openSquire(plan.choice.request, plan: plan) }, .squire(SquireHandoff(request: plan.choice.request, plan: plan))),
            ({ $0.openWeb(bravo) }, .web(bravo)),
            ({ $0.showReminders() }, .reminders),
            ({ $0.addToCalendar(appointment) }, .addToCalendar(appointment)),
        ]
        for (open, sheet) in cases {
            let router = AppRouter()
            open(router)
            XCTAssertEqual(router.sheet, sheet)
        }
    }

    func testClosingSquireAfterPickingATimeAsksWhetherItWasBooked() throws {
        let router = AppRouter()
        let plan = try plan()
        router.openSquire(plan.choice.request, plan: plan)

        // SwiftUI clears the binding when the sheet goes away, then calls onDismiss.
        router.sheet = nil
        router.sheetDidDismiss()

        XCTAssertEqual(router.sheet, .confirmBooking(plan))
    }

    func testBrowsingSquireAsksNothingAfterwards() {
        let router = AppRouter()
        router.openSquire(.anything, plan: nil)
        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testClosingTheConfirmationDoesNotReopenAnything() throws {
        let router = AppRouter()
        router.present(.confirmBooking(try plan()))
        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testClosingASheetOnPurposeSkipsTheFollowUp() throws {
        let router = AppRouter()
        let plan = try plan()
        router.openSquire(plan.choice.request, plan: plan)
        router.closeSheet()
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testOpeningASheetOverAnotherWaitsForItToClose() throws {
        let router = AppRouter()
        let plan = try plan()
        router.present(.confirmBooking(plan))

        // "Add to Calendar" on the "Did you book it?" sheet: that sheet closes first...
        let appointment = plan.appointment()
        router.addToCalendar(appointment)
        XCTAssertNil(router.sheet)

        // ...and the calendar opens once it has gone.
        router.sheetDidDismiss()
        XCTAssertEqual(router.sheet, .addToCalendar(appointment))

        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testSquireClosedToOpenSomethingElseDoesNotAskAboutTheBooking() throws {
        let router = AppRouter()
        let plan = try plan()
        router.openSquire(plan.choice.request, plan: plan)
        router.showReminders()
        router.sheetDidDismiss()
        XCTAssertEqual(router.sheet, .reminders)

        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testOpeningSquireAgainFromTheConfirmationComesBackToIt() throws {
        let router = AppRouter()
        let plan = try plan()
        router.present(.confirmBooking(plan))

        router.openSquire(plan.choice.request, plan: plan)
        router.sheetDidDismiss()
        XCTAssertEqual(router.sheet, .squire(SquireHandoff(request: plan.choice.request, plan: plan)))

        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertEqual(router.sheet, .confirmBooking(plan))
    }

    func testClosingTheSheetDropsAnythingWaiting() throws {
        let router = AppRouter()
        let plan = try plan()
        router.present(.confirmBooking(plan))
        router.addToCalendar(plan.appointment())
        router.startBooking()
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testFinishingABookingReturnsToTheFirstStep() throws {
        let router = AppRouter()
        let plan = try plan()
        router.bookingPath = [.chooseBarber(serviceID: "haircut"), .chooseTime(plan.choice), .review(plan)]
        XCTAssertEqual(router.finishedBookings, 0)
        router.finishBooking()
        XCTAssertEqual(router.bookingPath, [])
        // The Book tab scrolls back up to the new appointment on this.
        XCTAssertEqual(router.finishedBookings, 1)
    }

    func testSheetIdentitiesAreDistinct() throws {
        let plan = try plan()
        let sheets: [AppSheet] = [
            .reminders,
            .squire(SquireHandoff(request: .anything, plan: nil)),
            .squire(SquireHandoff(request: plan.choice.request, plan: plan)),
            .confirmBooking(plan),
            .web(AppData.products.storeURL),
            .web(AppData.shop.googleReviewURL),
            .addToCalendar(plan.appointment()),
        ]
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }
}

@MainActor
final class BookingChoiceTests: XCTestCase {
    func testAChoiceWithABarber() throws {
        let offering = try XCTUnwrap(AppData.catalog.offerings(forService: "vip").first)
        let choice = BookingChoice.offering(offering)
        XCTAssertEqual(choice.request, .offering(offering))
        XCTAssertEqual(choice.serviceID, "vip")
        XCTAssertEqual(choice.barberID, "israel-flores")
        XCTAssertEqual(choice.serviceName, "VIP")
        XCTAssertEqual(choice.barberName, "Izzy")
        XCTAssertEqual(choice.priceLabel, "$80")
        XCTAssertEqual(choice.durationMinutes, 75)
        XCTAssertEqual(choice.durationLabel, "1 hr 15 min")
        XCTAssertNil(choice.note)
    }

    func testABarbersNoteComesAlong() throws {
        let carlos = try XCTUnwrap(AppData.catalog.offerings(forService: "haircut").first { $0.barberID == "carlos-rafael" })
        XCTAssertNotNil(BookingChoice.offering(carlos).note)
    }

    func testFirstAvailable() throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        let choice = BookingChoice.firstAvailable(option)
        XCTAssertEqual(choice.request, .firstAvailable(option))
        XCTAssertEqual(choice.serviceID, "haircut")
        XCTAssertNil(choice.barberID)
        XCTAssertEqual(choice.barberName, "First available")
        XCTAssertEqual(choice.priceLabel, option.priceLabel)
        XCTAssertEqual(choice.durationLabel, option.durationLabel)
    }

    func testFirstAvailablePlansForTheLongestLength() throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "hot-towel-shave"))
        let lengths = AppData.catalog.offerings
            .filter { $0.squireServiceID == option.squireServiceID && option.barberIDs.contains($0.barberID) }
            .map(\.durationMinutes)
        XCTAssertEqual(BookingChoice.firstAvailable(option).durationMinutes, lengths.max())
    }

    func testAPlanBecomesAnAppointment() throws {
        let offering = try XCTUnwrap(AppData.catalog.offerings(forService: "vip").first)
        let start = Date(timeIntervalSince1970: 1_793_395_800)
        let moved = start.addingTimeInterval(30 * 60)
        let created = Date(timeIntervalSince1970: 1_793_300_000)
        let plan = BookingPlan(choice: .offering(offering), start: start)

        let appointment = plan.appointment(at: moved, createdAt: created)
        XCTAssertEqual(appointment.serviceID, "vip")
        XCTAssertEqual(appointment.serviceName, "VIP")
        XCTAssertEqual(appointment.barberID, "israel-flores")
        XCTAssertEqual(appointment.barberName, "Izzy")
        XCTAssertEqual(appointment.start, moved)
        XCTAssertEqual(appointment.durationMinutes, 75)
        XCTAssertEqual(appointment.priceLabel, "$80")
        XCTAssertEqual(appointment.createdAt, created)

        XCTAssertEqual(plan.appointment().start, start)
        XCTAssertNotEqual(plan.appointment().id, plan.appointment().id)
    }

    func testFirstAvailableAppointmentsSaySo() throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        let appointment = BookingPlan(choice: .firstAvailable(option), start: Date()).appointment()
        XCTAssertNil(appointment.barberID)
        XCTAssertEqual(appointment.barberName, "First available")
    }

    func testSquireLinksCarryTheChoice() throws {
        let offering = try XCTUnwrap(AppData.catalog.offerings(forService: "vip").first)
        let handoff = SquireHandoff(request: BookingChoice.offering(offering).request, plan: nil)
        XCTAssertTrue(handoff.url.absoluteString.contains("/barber/israel-flores/services?preselect=\(offering.squireServiceID)"))
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
