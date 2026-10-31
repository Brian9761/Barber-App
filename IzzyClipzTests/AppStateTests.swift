import XCTest
@testable import IzzyClipz

@MainActor
final class AppRouterTests: XCTestCase {
    private func haircutWithCarlos() throws -> Offering {
        try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
    }

    private func draft() throws -> BookingDraft {
        BookingDraft(
            plan: BookingPlan(choice: .offering(try haircutWithCarlos()), start: TestData.friday),
            customer: CustomerDetails(name: "Alex", phone: "(442) 555-0123"),
            note: ""
        )
    }

    func testStartBookingFromScratchResetsTheFlow() {
        let router = AppRouter()
        router.bookingPath = [.chooseBarber(serviceID: "haircut")]
        router.selectedTab = .shop
        router.startBooking()
        XCTAssertEqual(router.bookingPath, [])
        XCTAssertEqual(router.selectedTab, .book)
    }

    func testStartBookingWithAServiceSkipsToChoosingABarber() {
        let router = AppRouter()
        router.startBooking(serviceID: "vip")
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "vip")])
        XCTAssertEqual(router.selectedTab, .book)
    }

    func testStartBookingWithAChoiceGoesStraightToTheTimes() throws {
        let router = AppRouter()
        let choice = BookingChoice.offering(try haircutWithCarlos())
        router.startBooking(choice: choice)
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "haircut"), .chooseTime(choice)])
    }

    func testStartBookingFromABarbersMenuGoesBackToTheirServices() throws {
        let router = AppRouter()
        let offering = try haircutWithCarlos()
        router.startBooking(fromBarberMenu: offering)
        XCTAssertEqual(router.bookingPath, [.chooseService(barberID: "carlos-rafael"), .chooseTime(.offering(offering))])
    }

    func testStartBookingWithABarberPicksTheirServiceFirst() {
        let router = AppRouter()
        router.startBooking(barberID: "julian-ramos")
        XCTAssertEqual(router.bookingPath, [.chooseService(barberID: "julian-ramos")])
    }

    func testStartingToBookClosesASheet() {
        let router = AppRouter()
        router.showReminders()
        router.startBooking()
        XCTAssertNil(router.sheet)
    }

    func testStepNumbers() throws {
        let draft = try draft()
        XCTAssertEqual(BookingStep.chooseBarber(serviceID: "haircut").number, 2)
        XCTAssertEqual(BookingStep.chooseService(barberID: "flowxbori").number, 2)
        XCTAssertEqual(BookingStep.chooseTime(draft.plan.choice).number, 3)
        XCTAssertEqual(BookingStep.details(draft.plan).number, 4)
        XCTAssertEqual(BookingStep.review(draft).number, 5)
        XCTAssertNil(BookingStep.booked(appointmentID: "x").number)
        XCTAssertEqual(BookingStep.count, 5)
    }

    /// A taken time sends the client back to the times, which get the message and reload.
    func testReturningToTheTimesDropsTheLaterSteps() throws {
        let router = AppRouter()
        let draft = try draft()
        router.bookingPath = [.chooseBarber(serviceID: "haircut"), .chooseTime(draft.plan.choice), .details(draft.plan), .review(draft)]
        router.returnToTimes(message: "Someone just booked 2:30 PM. Pick another time.", droppedStart: draft.plan.start)
        XCTAssertEqual(router.bookingPath, [.chooseBarber(serviceID: "haircut"), .chooseTime(draft.plan.choice)])
        XCTAssertEqual(router.timeStepNotice?.message, "Someone just booked 2:30 PM. Pick another time.")
        XCTAssertEqual(router.timeStepNotice?.droppedStart, draft.plan.start)

        let first = router.timeStepNotice?.id
        router.returnToTimes(message: "Again", droppedStart: nil)
        XCTAssertNotEqual(router.timeStepNotice?.id, first, "Each notice is new, so the time step reloads every time")
        router.clearTimeStepNotice()
        XCTAssertNil(router.timeStepNotice)
    }

    func testReturningToTheDetails() throws {
        let router = AppRouter()
        let draft = try draft()
        router.bookingPath = [.chooseBarber(serviceID: "haircut"), .chooseTime(draft.plan.choice), .details(draft.plan), .review(draft)]
        router.returnToDetails()
        XCTAssertEqual(router.bookingPath.last, .details(draft.plan))
        XCTAssertEqual(router.bookingPath.count, 3)
    }

    /// Once booked, the steps are gone, so going back can't book the same time again.
    func testBookingReplacesTheStepsWithTheConfirmation() throws {
        let router = AppRouter()
        let draft = try draft()
        router.bookingPath = [.chooseBarber(serviceID: "haircut"), .chooseTime(draft.plan.choice), .details(draft.plan), .review(draft)]
        router.showBooked(appointmentID: "abc")
        XCTAssertEqual(router.bookingPath, [.booked(appointmentID: "abc")])
        XCTAssertEqual(router.finishedBookings, 1)
        router.finishBooking()
        XCTAssertEqual(router.bookingPath, [])
    }

    func testOpeningPagesSetsTheSheet() {
        let website = AppData.shop.websiteURL
        let event = SavedAppointment(snapshot: TestData.appointment(), origin: .app, remind: true).calendarEvent
        let cases: [(open: (AppRouter) -> Void, sheet: AppSheet)] = [
            ({ $0.openWeb(website) }, .web(website)),
            ({ $0.showReminders() }, .reminders),
            ({ $0.addToCalendar(event) }, .addToCalendar(event)),
            ({ $0.editCustomerDetails() }, .customerDetails),
        ]
        for (open, sheet) in cases {
            let router = AppRouter()
            open(router)
            XCTAssertEqual(router.sheet, sheet)
        }
    }

    func testOpeningASheetOverAnotherWaitsForItToClose() {
        let router = AppRouter()
        router.showReminders()
        router.editCustomerDetails()
        XCTAssertNil(router.sheet, "The first sheet closes first")
        // A second tap while it closes doesn't queue it twice.
        router.editCustomerDetails()
        router.sheetDidDismiss()
        XCTAssertEqual(router.sheet, .customerDetails)
        router.sheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testClosingTheSheetDropsAnythingWaiting() {
        let router = AppRouter()
        router.showReminders()
        router.editCustomerDetails()
        router.closeSheet()
        router.sheetDidDismiss()
        XCTAssertNil(router.sheet)
    }

    func testSheetIdentitiesAreDistinct() {
        let event = SavedAppointment(snapshot: TestData.appointment(), origin: .app, remind: true).calendarEvent
        let sheets: [AppSheet] = [
            .reminders,
            .customerDetails,
            .web(AppData.shop.websiteURL),
            .web(AppData.shop.googleReviewURL),
            .addToCalendar(event),
        ]
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }
}

@MainActor
final class BookingChoiceTests: XCTestCase {
    func testAChoiceWithABarber() throws {
        let offering = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        let choice = BookingChoice.offering(offering)
        XCTAssertEqual(choice.serviceID, "haircut")
        XCTAssertEqual(choice.barberID, "carlos-rafael")
        XCTAssertEqual(choice.serviceName, "Haircut")
        XCTAssertEqual(choice.barberName, "Carlos")
        XCTAssertEqual(choice.priceLabel, "$45")
        XCTAssertEqual(choice.durationLabel, "45 min")
        XCTAssertNotNil(choice.note)
        // Offering IDs carry a "/", and go to the server as they are.
        XCTAssertEqual(choice.target, .offering(id: TestData.carlosHaircutID))
        XCTAssertTrue(TestData.carlosHaircutID.contains("/"))
    }

    func testAnyBarber() throws {
        let option = try XCTUnwrap(AppData.catalog.firstAvailableOption(forService: "haircut"))
        let choice = BookingChoice.anyBarber(option)
        XCTAssertNil(choice.barberID)
        XCTAssertEqual(choice.barberName, "Any barber")
        XCTAssertEqual(choice.target, .anyBarber(serviceId: "haircut"))
        XCTAssertEqual(choice.anyBarberNames, ["Flowxbori", "Cristian", "Julian"])
        XCTAssertNil(choice.note)
    }

    /// "Any barber" is only offered where the catalog (and so the server's catalog.json) has a
    /// first-available entry: never for a service only one barber does.
    func testAnyBarberOnlyWhereSeveralBarbersShareTheService() {
        let catalog = AppData.catalog
        for service in catalog.services {
            let barbers = catalog.barbers(offering: service.id)
            if barbers.count < 2 {
                XCTAssertNil(catalog.firstAvailableOption(forService: service.id), service.id)
            }
        }
        XCTAssertNil(catalog.firstAvailableOption(forService: "vip"), "Only Izzy does VIP")
        XCTAssertNotNil(catalog.firstAvailableOption(forService: "haircut-and-beard"))
    }

    /// Flowxbori has two haircuts: two choices with their own IDs, lengths and prices.
    func testFlowxboriHasTwoHaircuts() {
        let haircuts = AppData.catalog.offerings(forService: "haircut").filter { $0.barberID == "flowxbori" }
        XCTAssertEqual(haircuts.count, 2)
        XCTAssertEqual(Set(haircuts.map(\.id)).count, 2)
        XCTAssertEqual(Set(haircuts.map(\.durationMinutes)), [45, 60])
        let choices = haircuts.map(BookingChoice.offering)
        XCTAssertNotEqual(choices[0].target, choices[1].target)
    }
}

@MainActor
final class CustomerDetailsTests: XCTestCase {
    func testValidation() {
        XCTAssertNotNil(CustomerDetails(name: "  ", phone: "4425550123").nameProblem)
        XCTAssertNotNil(CustomerDetails(name: String(repeating: "a", count: 61), phone: "4425550123").nameProblem)
        XCTAssertNil(CustomerDetails(name: "Alex", phone: "4425550123").nameProblem)
        XCTAssertNotNil(CustomerDetails(name: "Alex", phone: "").phoneProblem)
        XCTAssertNotNil(CustomerDetails(name: "Alex", phone: "12345").phoneProblem)
        XCTAssertNotNil(CustomerDetails(name: "Alex", phone: "+44 20 7946 0958").phoneProblem, "US numbers only")
        // N11 codes (211, 911…) aren't area codes or exchanges: the server turns them down, so this step does too.
        XCTAssertNotNil(CustomerDetails(name: "Alex", phone: "(442) 911-3053").phoneProblem, "N11 exchange")
        XCTAssertNotNil(CustomerDetails(name: "Alex", phone: "(211) 555-0123").phoneProblem, "N11 area code")
        XCTAssertNil(CustomerDetails(name: "Alex", phone: "(442) 555-0123").phoneProblem)
        XCTAssertTrue(CustomerDetails(name: "Alex", phone: "+1 442 555 0123").isValid)
    }

    func testWhatTheServerGets() throws {
        let details = CustomerDetails(name: "  Alex N.  ", phone: "442.555.0123")
        XCTAssertEqual(details.newCustomer.name, "Alex N.")
        XCTAssertEqual(details.newCustomer.phone, "+14425550123")
        XCTAssertEqual(details.displayPhone, "(442) 555-0123")
    }

    func testRememberedForNextTime() {
        let defaults = TestData.defaults()
        let store = CustomerDetailsStore(defaults: defaults)
        XCTAssertNil(store.saved)
        store.remember(CustomerDetails(name: " Alex ", phone: "4425550123"))
        XCTAssertEqual(store.saved, CustomerDetails(name: "Alex", phone: "(442) 555-0123"))
        XCTAssertEqual(CustomerDetailsStore(defaults: defaults).saved, store.saved)

        store.forget()
        XCTAssertNil(store.saved)
        XCTAssertNil(CustomerDetailsStore(defaults: defaults).saved)
    }

    func testInvalidDetailsAreNotRemembered() {
        let defaults = TestData.defaults()
        let store = CustomerDetailsStore(defaults: defaults)
        store.remember(CustomerDetails(name: "", phone: "12"))
        XCTAssertNil(store.saved)
        defaults.set("Alex", forKey: "customer.name")
        defaults.set("not a number", forKey: "customer.phone")
        XCTAssertNil(CustomerDetailsStore(defaults: defaults).saved)
    }
}

@MainActor
final class FavoritesTests: XCTestCase {
    func testTogglingAFavorite() {
        let favorites = Favorites(defaults: TestData.defaults())
        XCTAssertNil(favorites.barber)

        favorites.toggle("carlos-rafael")
        XCTAssertTrue(favorites.isFavorite("carlos-rafael"))
        XCTAssertEqual(favorites.barber?.name, "Carlos")

        favorites.toggle("carlos-rafael")
        XCTAssertNil(favorites.barberID)
    }

    func testOnlyOneFavorite() {
        let favorites = Favorites(defaults: TestData.defaults())
        favorites.toggle("carlos-rafael")
        favorites.toggle("israel-flores")
        XCTAssertEqual(favorites.barberID, "israel-flores")
        XCTAssertFalse(favorites.isFavorite("carlos-rafael"))
    }

    func testFavoriteIsRemembered() {
        let defaults = TestData.defaults()
        Favorites(defaults: defaults).toggle("flowxbori")
        XCTAssertEqual(Favorites(defaults: defaults).barberID, "flowxbori")
    }

    func testForgetsBarbersWhoLeft() {
        let defaults = TestData.defaults()
        defaults.set("someone-who-left", forKey: "favorites.barberID")
        XCTAssertNil(Favorites(defaults: defaults).barberID)
    }
}
