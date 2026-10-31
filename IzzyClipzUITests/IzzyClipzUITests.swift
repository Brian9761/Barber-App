import XCTest

/// Walks through every screen the way a client would: the five tabs, booking through to "You're
/// booked" (with any barber, with a chosen barber, Flowxbori's second haircut), what happens when a
/// time is taken or the phone is offline, cancelling, the shop's products, the live reviews, Visit,
/// the gallery and reminders. Saves screenshots along the way.
///
/// The app runs with `-ui-testing`: it starts from empty settings, never touches the network (an
/// in-memory server stands in for the shop's, with a "now" frozen at launch, sample bookings,
/// sample products without photos and sample reviews), shows a link preview instead of loading
/// web pages or leaving the app, never asks for notification permission, and stands in for
/// Apple's "New Event" screen. Launch arguments make the in-memory server misbehave on purpose
/// (`-fakeOffline`, `-fakeSlotTaken`, …) or start with an appointment.
///
/// The calendar starts from today, so no test names a date: they take the day the app picks
/// and its first open time.
final class IzzyClipzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches the app with `-ui-testing` and `arguments`, and waits for Home.
    private func launch(_ arguments: String..., file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 30), "The app didn't start on Home", file: file, line: line)
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 10), "No tab bar", file: file, line: line)
    }

    // MARK: Tabs

    /// The system tab bar: five tabs in order, each big enough to tap, the selected one marked, and
    /// every tab keeping its own pushed screens while another one is showing.
    func testTabs() {
        launch()
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.exists)
        // Left to right. (iOS 26's floating bar lets neighbors' frames overlap, so compare centers.)
        var previousMidX = app.frame.minX
        for name in Self.tabs {
            let button = tabButton(name)
            XCTAssertTrue(button.exists, "Missing the \(name) tab")
            XCTAssertGreaterThan(button.frame.midX, previousMidX, "\(name) is out of order")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(name) is too short to tap")
            previousMidX = button.frame.midX
        }
        assertSelectedTab("Home")

        // Every tab, in the bar's order and back the other way.
        for name in Self.tabs.dropFirst() + Self.tabs.reversed().dropFirst() {
            openTab(name)
            XCTAssertTrue(element(Self.landmarks[name] ?? "").waitForExistence(timeout: 15), "The \(name) tab didn't show")
            assertSelectedTab(name)
        }

        // A tab keeps its pushed screen while another tab is showing.
        openTab("Services")
        tap("service-haircut")
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10))
        openTab("Book")
        tap("bookService-haircut")
        XCTAssertTrue(element("chooseAnyBarber").waitForExistence(timeout: 10))
        openTab("Services")
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10), "Services lost its pushed page")
        openTab("Book")
        XCTAssertTrue(element("chooseAnyBarber").waitForExistence(timeout: 10), "Book lost its pushed step")
    }

    // MARK: Home

    func testHome() {
        launch()
        XCTAssertTrue(element("shopStatus").exists)
        XCTAssertTrue(element("homeHeroPhotos").exists)
        XCTAssertTrue(element("seeAllPhotos").exists)
        XCTAssertTrue(element("homeWalkIns").exists, "With nothing booked, Home shows the walk-in line")
        XCTAssertFalse(element("appointmentCard").exists, "Nothing is booked yet")
        XCTAssertTrue(element("callButton").exists)
        XCTAssertTrue(element("directionsButton").exists)
        XCTAssertTrue(element("remindersButton").exists)
        XCTAssertTrue(element("homeBookButton").label.contains("Book an appointment"), element("homeBookButton").label)
        screenshot("01-Home")

        drag(.up)
        XCTAssertTrue(element("popular-haircut").waitForExistence(timeout: 10))
        XCTAssertTrue(element("homeBarber-israel-flores").exists)
        screenshot("02-Home-Scrolled")

        // A plain link to the reviews: Home never loads them (each Google answer counts against
        // the server's daily limit), so no rating shows here.
        let reviews = element("homeReviews")
        scroll(toReveal: reviews)
        XCTAssertTrue(reviews.label.contains("See what clients say"), reviews.label)
        XCTAssertFalse(reviews.label.contains("Rated"), "Home shouldn't show a rating it didn't load: \(reviews.label)")
        scroll(toReveal: element("homeShopCard"))
        XCTAssertTrue(element("instagramButton").exists || element("meetTeamButton").exists)
        screenshot("03-Home-Reviews-And-Shop")

        // The shop card leads to the Shop tab.
        tap("homeShopCard")
        XCTAssertTrue(element("product-sample-pomade").waitForExistence(timeout: 15), "The shop card didn't open the Shop")
        assertSelectedTab("Shop")

        // "All services ›" leads to the Services tab.
        openTab("Home")
        tap("allServicesButton")
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 10), "All services didn't open the Services tab")
        assertSelectedTab("Services")
    }

    func testHomeBookButtonOpensBooking() {
        launch()
        tap("homeBookButton")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10))
        assertSelectedTab("Book")
    }

    /// The shop's Instagram on Home and Visit, and Izzy's own account on his page.
    func testInstagram() {
        launch()
        let card = element("instagramButton")
        scroll(toReveal: card)
        XCTAssertTrue(card.label.contains("@izzy_clipz_barbershop_"), card.label)
        card.tap()
        XCTAssertEqual(webPageURL(), "https://www.instagram.com/izzy_clipz_barbershop_/")
        closeWebPage()

        openTab("Visit")
        let message = element("visitInstagramMessage")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Visit has no Instagram card")
        scroll(toReveal: message)
        XCTAssertTrue(element("visitInstagramLink").exists)
        screenshot("40-Visit-Instagram")
        message.tap()
        XCTAssertEqual(webPageURL(), "https://ig.me/m/izzy_clipz_barbershop_")
        closeWebPage()

        openTab("Home")
        openTeam()
        tap("barber-israel-flores")
        let izzy = element("barberInstagram")
        XCTAssertTrue(izzy.waitForExistence(timeout: 10), "Izzy's page has no Instagram link")
        scroll(toReveal: izzy)
        izzy.tap()
        XCTAssertEqual(webPageURL(), "https://www.instagram.com/izzy_clipz_/")
        closeWebPage()
    }

    // MARK: Services and the crew

    func testServices() {
        launch()
        openTab("Services")
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 10))
        XCTAssertTrue(element("jump-haircuts").exists)
        screenshot("05-Services")

        // A jump chip scrolls its category up, past the haircuts.
        let haircut = element("service-haircut")
        let package = element("service-haircut-and-beard")
        tap("jump-packages")
        XCTAssertTrue(waitUntil(package, toMatch: hittable()), "The Packages chip didn't scroll to the packages")

        scroll(toReveal: haircut)
        haircut.tap()
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10))
        XCTAssertTrue(element("book-\(Self.carlosHaircut)").exists)
        XCTAssertTrue(element("bookServiceButton").exists)
        assertAboveTabBar("bookServiceButton")
        screenshot("06-Service-Detail")

        goBack()
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        var pulls = 0
        while pulls < 3, !(search.waitForExistence(timeout: 3) && search.isHittable) {
            // The search bar can start tucked under the large title.
            app.swipeDown()
            pulls += 1
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10), "No search field")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "The search field didn't take focus")
        search.typeText("beard")
        XCTAssertTrue(waitForDisappearance(of: element("service-perm")), "Searching for beard didn't filter out Perm")
        XCTAssertTrue(element("service-haircut-and-beard").exists)
        screenshot("07-Services-Search")

        // Nothing matches: a way to ask the shop.
        search.typeText("xyz")
        XCTAssertTrue(labeled("Not on the menu").waitForExistence(timeout: 10), "No empty state for a search with no results")
    }

    func testTeamAndBarber() {
        launch()
        openTeam()
        screenshot("08-Team")

        tap("barber-carlos-rafael")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element("favoriteButton").exists)
        XCTAssertTrue(element("barberMenu-\(Self.carlosHaircut)").exists, "Carlos's menu is missing his haircut")
        XCTAssertFalse(element("barberInstagram").exists, "Carlos has no Instagram in the data")
        XCTAssertFalse(containing("Squire").exists, "Nothing mentions Squire")
        screenshot("09-Barber-Detail")
    }

    func testFavoriteBarberShowsOnHome() {
        launch()
        XCTAssertFalse(labeled("Your barber").exists, "No favorite yet")
        openTeam()
        tap("barber-flowxbori")
        let favorite = element("favoriteButton")
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertTrue(
            waitUntil(favorite, toMatch: NSPredicate(format: "label CONTAINS %@", "Remove favorite")),
            "Flowxbori didn't become the favorite"
        )
        goBack()
        XCTAssertTrue(element("barber-flowxbori").waitForExistence(timeout: 10))
        goBack()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))

        XCTAssertTrue(labeled("Your barber").waitForExistence(timeout: 10), "No \"Your barber\" on Home")
        let book = element("homeFavoriteBook")
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        XCTAssertEqual(book.label.lowercased(), "book with flowxbori")
        scroll(toReveal: book)
        screenshot("39-Home-Your-Barber")
        book.tap()

        // Barber first: their own menu, to pick a service.
        let service = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "barberService-flowxbori/")).firstMatch
        XCTAssertTrue(service.waitForExistence(timeout: 10), "Booking with Flowxbori didn't show their services")
        assertSelectedTab("Book")
        XCTAssertTrue(labeled("Step 2 of 5").exists)
    }

    // MARK: Booking

    /// The whole flow with "Any barber": service, barber, day and time, details, review ("No
    /// payment now"), booked, Add to Calendar, then the appointment on Book and on Home.
    func testBookWithAnyBarber() {
        launch()
        openTab("Book")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10))
        XCTAssertFalse(element("appointmentCard").exists, "Nothing is booked yet")
        XCTAssertTrue(labeled("Step 1 of 5").waitForExistence(timeout: 10), "No step 1 indicator")
        XCTAssertFalse(element("bookingStartOver").exists, "Step 1 has nothing to start over")
        screenshot("10-Book-Service")

        tap("bookService-haircut")
        XCTAssertTrue(element("chooseAnyBarber").waitForExistence(timeout: 10))
        XCTAssertTrue(labeled("Step 2 of 5").waitForExistence(timeout: 10), "No step 2 indicator")
        XCTAssertTrue(element("bookingStartOver").exists)
        // Flowxbori offers two haircuts: two rows.
        XCTAssertTrue(element("choose-\(Self.flowxboriHaircut45)").exists)
        XCTAssertTrue(element("choose-\(Self.flowxboriHaircut60)").exists)
        screenshot("11-Book-Barber")

        tap("chooseAnyBarber")
        waitForTimes()
        XCTAssertTrue(labeled("Step 3 of 5").waitForExistence(timeout: 10), "No step 3 indicator")
        XCTAssertFalse(element("continueToDetails").isEnabled, "Continue should wait for a time")
        screenshot("12-Book-Calendar")

        pickFirstTime()
        screenshot("13-Book-Time-Picked")

        continueToDetails()
        XCTAssertTrue(labeled("Step 4 of 5").waitForExistence(timeout: 10), "No step 4 indicator")
        // Continuing with nothing filled in says what's missing.
        tapPinned("continueToReview")
        XCTAssertTrue(element("nameFieldProblem").waitForExistence(timeout: 10), "No message for a missing name")
        XCTAssertTrue(element("phoneFieldProblem").exists, "No message for a missing number")
        screenshot("41-Book-Details-Missing")
        type("Sample Client", into: "nameField")
        type("4425550123", into: "phoneField")
        type("Low fade, please", into: "noteField")
        tapPinned("hideKeyboard")
        XCTAssertTrue(waitForDisappearance(of: app.keyboards.firstMatch), "Hide keyboard didn't put it away")
        XCTAssertTrue(waitForDisappearance(of: element("hideKeyboard")), "The button stays only while typing")
        XCTAssertEqual(element("rememberDetailsToggle").value as? String, "1", "Remember me starts on")
        screenshot("14-Book-Details")

        continueToReview()
        XCTAssertTrue(labeled("Step 5 of 5").waitForExistence(timeout: 10), "No step 5 indicator")
        let note = element("payAtShopNote")
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("No payment now"), note.label)
        XCTAssertTrue(element("bookingSummary").waitForExistence(timeout: 10))
        XCTAssertTrue(containing("Any barber").exists, "The review should say any barber")
        XCTAssertTrue(containing("Low fade, please").exists, "The note is on the review")
        screenshot("15-Book-Review")

        bookAppointment()
        let booked = element("bookedSummary")
        XCTAssertTrue(booked.waitForExistence(timeout: 10))
        XCTAssertFalse(booked.label.contains("Any barber"), "The shop assigned a barber: \(booked.label)")
        let reminders = element("appointmentRemindersToggle")
        XCTAssertTrue(reminders.exists)
        XCTAssertEqual(reminders.value as? String, "1", "Reminders start on")
        screenshot("16-Booked")

        // Add to Calendar (a stand-in for Apple's screen in UI tests).
        tap("addToCalendarButton")
        let eventTitle = element("calendarEventTitle")
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 10), "Add to Calendar didn't open")
        XCTAssertTrue(eventTitle.label.contains("Haircut"), eventTitle.label)
        tapToClose(app.buttons["Add"], closing: eventTitle, "Add to Calendar didn't close")

        tapPinned("bookedDoneButton")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10), "Done didn't go back to step 1")
        let card = element("appointmentCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The appointment isn't on the Book tab")
        XCTAssertTrue(element("customerDetailsRow").exists, "The details are remembered for next time")
        screenshot("18-Book-Appointments")

        openTab("Home")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "Home doesn't show the appointment")
        XCTAssertFalse(element("homeWalkIns").exists, "The appointment takes the walk-in line's place")
        XCTAssertTrue(labeled("Next appointment").exists)
        scroll(toReveal: element("cancelAppointmentButton"))
        screenshot("17-Home-Appointment")
    }

    /// A specific barber: Carlos's haircut from the service page, straight to the times. The details
    /// are already remembered.
    func testBookSpecificBarber() {
        launch(UITestArguments.savedDetails)
        openTab("Services")
        tap("service-haircut")
        let carlos = element("book-\(Self.carlosHaircut)")
        XCTAssertTrue(carlos.waitForExistence(timeout: 10))
        scroll(toReveal: carlos)
        carlos.tap()

        waitForTimes()
        assertSelectedTab("Book")
        pickFirstTime()
        continueToDetails()
        XCTAssertEqual(element("nameField").value as? String, "Sample Client", "The remembered name isn't filled in")
        continueToReview()
        XCTAssertTrue(containing("Carlos").exists, "The review should name Carlos")
        bookAppointment()
        XCTAssertTrue(element("bookedSummary").label.contains("Carlos"), element("bookedSummary").label)
    }

    /// Flowxbori's second haircut (an hour) is its own offering, booked as such.
    func testBookFlowxborisSecondHaircut() {
        launch(UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("choose-\(Self.flowxboriHaircut60)")
        waitForTimes()
        XCTAssertTrue(containing("Haircut with Flowxbori").exists, "The times are for Flowxbori's haircut")
        pickFirstTime()
        continueToDetails()
        continueToReview()
        bookAppointment()
        let summary = element("bookedSummary")
        XCTAssertTrue(summary.label.contains("Flowxbori"), summary.label)
        XCTAssertTrue(summary.label.contains("1 hr"), "The hour-long haircut: \(summary.label)")
        screenshot("38-Booked-Flowxbori-Hour")
    }

    /// From a barber's page: their menu, then the times.
    func testBookFromBarberPage() {
        launch(UITestArguments.savedDetails)
        openTeam()
        tap("barber-julian-ramos")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 10))
        assertAboveTabBar("bookBarberButton")
        tapPinned("bookBarberButton")
        let haircut = element("barberService-julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a")
        XCTAssertTrue(haircut.waitForExistence(timeout: 10), "Booking with Julian didn't show his services")
        assertSelectedTab("Book")
        scroll(toReveal: haircut)
        haircut.tap()
        waitForTimes()
        pickFirstTime()
        continueToDetails()
        continueToReview()
        bookAppointment()
        XCTAssertTrue(element("bookedSummary").label.contains("Julian"))
    }

    /// Someone else books the time first: back to the times, refreshed, with a note, and another
    /// time books fine.
    func testSlotTakenPicksAnotherTime() {
        launch(UITestArguments.slotTaken, UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        waitForTimes()
        let taken = pickFirstTime()
        continueToDetails()
        continueToReview()
        tapPinned("bookAppointmentButton")

        let notice = element("timeNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "A taken time didn't go back to the times with a note")
        XCTAssertTrue(notice.label.contains("Someone just booked"), notice.label)
        XCTAssertTrue(waitForDisappearance(of: element(taken)), "The taken time is still offered")
        XCTAssertFalse(element("continueToDetails").isEnabled, "The taken time is still picked")
        screenshot("31-Book-Slot-Taken")

        pickFirstTime()
        continueToDetails()
        continueToReview()
        bookAppointment()
    }

    /// Offline: the times can't load, with Try again and Call the shop.
    func testOfflineShowsErrorWithRetry() {
        launch(UITestArguments.offline)
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        let error = element("timesError")
        XCTAssertTrue(error.waitForExistence(timeout: 15), "Offline, the times should say they couldn't load")
        XCTAssertTrue(element("errorMessage").label.contains("internet"), element("errorMessage").label)
        XCTAssertTrue(element("retryButton").exists)
        XCTAssertTrue(element("errorCallButton").exists)
        screenshot("32-Book-Offline")

        tap("retryButton")
        XCTAssertTrue(element("timesError").waitForExistence(timeout: 15), "Still offline after trying again")

        // The shop and the reviews say so too.
        openTab("Shop")
        XCTAssertTrue(element("shopError").waitForExistence(timeout: 15), "The shop doesn't show the error")
        openTab("Home")
        let reviews = element("homeReviews")
        scroll(toReveal: reviews)
        XCTAssertTrue(reviews.label.contains("See what clients say"), reviews.label)
        reviews.tap()
        XCTAssertTrue(element("reviewsError").waitForExistence(timeout: 15), "Offline, the reviews should say they couldn't load")
    }

    /// The connection drops while booking: "Try again" books it.
    func testBookingOfflineThenTryAgain() {
        launch(UITestArguments.bookingOffline, UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        waitForTimes()
        pickFirstTime()
        continueToDetails()
        continueToReview()
        tapPinned("bookAppointmentButton")
        let error = element("bookingError")
        XCTAssertTrue(error.waitForExistence(timeout: 15), "Offline, booking should say it didn't go through")
        XCTAssertTrue(error.label.contains("Not booked yet"), error.label)
        XCTAssertTrue(element("bookingCallButton").exists)
        screenshot("33-Book-Offline-Booking")
        tap("retryBookingButton")
        XCTAssertTrue(element("bookedTitle").waitForExistence(timeout: 15), "Trying again didn't book it")
    }

    /// The booking goes through, but its answer is lost on the way back, so it looks like the
    /// connection dropped. "Try again" sends the same booking with the same token: the app gets
    /// the appointment that was made, not "Someone just booked" for its own time, and there's one
    /// appointment, not two.
    func testLostBookingAnswerThenTryAgain() {
        launch(UITestArguments.loseBookingResponse, UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        waitForTimes()
        pickFirstTime()
        continueToDetails()
        continueToReview()
        tapPinned("bookAppointmentButton")
        let error = element("bookingError")
        XCTAssertTrue(error.waitForExistence(timeout: 15), "A lost answer should look like the connection dropped")
        XCTAssertTrue(error.label.contains("Not booked yet"), error.label)

        tap("retryBookingButton")
        // With a new token the retry would find its own time taken and go back to the times.
        XCTAssertTrue(element("bookedTitle").waitForExistence(timeout: 15), "Trying again didn't find the booking that went through")
        screenshot("42-Booked-After-Lost-Answer")

        tapPinned("bookedDoneButton")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10), "Done didn't go back to step 1")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "The appointment isn't on the Book tab")
        let list = element("yourAppointments")
        XCTAssertTrue(list.exists, "No list of appointments on the Book tab")
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "appointmentCard").count, 1, "One booking, not two")
        openTab("Home")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "Home doesn't show the appointment")
    }

    func testCalendarNavigationAndStartOver() {
        launch()
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        waitForTimes()

        let title = element("calendarMonthTitle")
        let month = title.label
        XCTAssertFalse(month.isEmpty)
        let next = element("calendarNextMonth")
        let previous = element("calendarPrevMonth")
        // Booking opens 60 days ahead, so there's always a later month.
        XCTAssertTrue(next.isEnabled, "There should be a next month to show")
        next.tap()
        XCTAssertTrue(waitUntil(title, toMatch: NSPredicate(format: "label != %@", month)), "The month didn't change")
        XCTAssertTrue(previous.isEnabled, "There should be a way back")
        previous.tap()
        XCTAssertTrue(waitUntil(title, toMatch: NSPredicate(format: "label == %@", month)), "Didn't come back to \(month)")

        tapPinned("bookingStartOver")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10), "Start over didn't go back to step 1")
        XCTAssertTrue(waitForDisappearance(of: element("continueToDetails")), "The times are still showing")
    }

    // MARK: Appointments

    /// An appointment booked in the app can be cancelled from it, after a confirmation.
    func testCancelAnAppointment() {
        launch(UITestArguments.bookedAppointment)
        let card = element("appointmentCard")
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Home doesn't show the booked appointment")
        XCTAssertTrue(labeled("Next appointment").waitForExistence(timeout: 10))

        openTab("Book")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "Book doesn't show the booked appointment")
        let cancel = element("cancelAppointmentButton")
        scroll(toReveal: cancel)
        cancel.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Cancel appointment", "cancelAppointmentButton")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No confirmation before cancelling")
        screenshot("34-Cancel-Confirmation")
        confirm.tap()

        XCTAssertTrue(labeled("Cancelled").waitForExistence(timeout: 15), "The appointment doesn't say it's cancelled")
        XCTAssertTrue(waitForDisappearance(of: element("cancelAppointmentButton")), "A cancelled appointment can't be cancelled again")
        screenshot("35-Cancelled")

        // Home goes back to the walk-in line; a cancelled one can be cleared away.
        openTab("Home")
        XCTAssertTrue(element("homeWalkIns").waitForExistence(timeout: 10))
        XCTAssertFalse(element("appointmentCard").exists)
        openTab("Book")
        tap("removeAppointmentButton")
        let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "No confirmation to remove")
        remove.tap()
        XCTAssertTrue(waitForDisappearance(of: element("appointmentCard")), "The appointment is still listed")
    }

    /// The shop cancelled it: the app finds out when it opens and says so, on Home too. Booking
    /// another time puts the new appointment on Home.
    func testShopCancelledAppointment() {
        launch(UITestArguments.bookedAppointment, UITestArguments.shopCancels, UITestArguments.savedDetails)
        XCTAssertTrue(labeled("Cancelled by the shop").waitForExistence(timeout: 20), "Home doesn't say the shop cancelled it")
        XCTAssertTrue(element("bookAgainButton").exists)
        XCTAssertFalse(element("cancelAppointmentButton").exists)
        scroll(toReveal: element("bookAgainButton"))
        screenshot("36-Cancelled-By-The-Shop")
        tap("bookAgainButton")
        XCTAssertTrue(element("chooseAnyBarber").waitForExistence(timeout: 10), "Book another time didn't start booking the service")
        assertSelectedTab("Book")

        tap("chooseAnyBarber")
        waitForTimes()
        pickFirstTime()
        continueToDetails()
        continueToReview()
        bookAppointment()
        tapPinned("bookedDoneButton")
        openTab("Home")
        XCTAssertTrue(labeled("Next appointment").waitForExistence(timeout: 10), "Home doesn't show the new booking")
        XCTAssertTrue(element("cancelAppointmentButton").exists, "The new booking can be cancelled from Home")
    }

    /// An appointment the previous version saved after booking on Squire stays listed, read-only,
    /// until it's over.
    func testAppointmentFromThePreviousVersion() {
        launch(UITestArguments.squireAppointment)
        openTab("Book")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "The previous version's appointment is gone")
        let note = element("appointmentNote")
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("call the shop") || note.label.contains("Call the shop"), note.label)
        XCTAssertFalse(element("cancelAppointmentButton").exists, "It can't be cancelled in the app")
        XCTAssertTrue(element("appointmentCallButton").exists)
        XCTAssertTrue(element("appointmentAddToCalendar").exists)
        screenshot("37-Previous-Version-Appointment")
    }

    func testChangingRememberedDetails() {
        launch(UITestArguments.savedDetails)
        openTab("Book")
        XCTAssertTrue(element("customerDetailsRow").waitForExistence(timeout: 10))
        XCTAssertTrue(containing("Booking as Sample Client").exists, "The remembered name isn't shown")
        tap("changeCustomerDetails")
        XCTAssertTrue(element("detailsSheetName").waitForExistence(timeout: 10), "Change didn't open the details")
        tapInSheet("forgetDetailsButton")
        let forget = app.buttons.matching(NSPredicate(format: "label == %@", "Forget")).firstMatch
        XCTAssertTrue(forget.waitForExistence(timeout: 10))
        forget.tap()
        XCTAssertTrue(waitForDisappearance(of: element("customerDetailsRow")), "The details are still remembered")
    }

    // MARK: Shop

    func testShopWithProducts() {
        launch()
        openTab("Shop")
        let pomade = element("product-sample-pomade")
        XCTAssertTrue(pomade.waitForExistence(timeout: 15), "The shop's products didn't load")
        XCTAssertTrue(pomade.label.contains("$18"), pomade.label)
        XCTAssertTrue(pomade.label.contains("available at the shop"), pomade.label)
        XCTAssertTrue(element("product-sample-beard-oil").exists)
        XCTAssertFalse(element("product-sample-beard-oil").label.contains("$"), "No price was listed, so none is shown")
        screenshot("19-Shop")

        pomade.tap()
        XCTAssertTrue(element("productDetail").waitForExistence(timeout: 10))
        XCTAssertEqual(element("productPrice").label, "$18")
        XCTAssertTrue(containing("Available at the shop").exists)
        screenshot("20-Product")
    }

    func testShopWithoutProducts() {
        launch(UITestArguments.noProducts)
        openTab("Shop")
        let empty = element("shopEmpty")
        XCTAssertTrue(empty.waitForExistence(timeout: 15), "No empty state")
        XCTAssertTrue(empty.label.contains("New products are coming soon. Ask at the shop what's in stock."), empty.label)
        screenshot("21-Shop-Empty")
    }

    // MARK: Reviews

    /// Google's reviews live, in their own section with "Reviews from Google Maps", and a button to
    /// Yelp's page when the server has no Yelp data.
    func testReviews() {
        launch()
        tap("homeReviews")
        let google = element("googleReviews")
        XCTAssertTrue(google.waitForExistence(timeout: 15), "Google's reviews didn't load")
        XCTAssertTrue(element("googleAttribution").label.contains("Google Maps"))
        XCTAssertTrue(element("googleRating").exists)
        XCTAssertTrue(element("googleOrderNotice").label.contains("Most relevant on Google"))
        XCTAssertTrue(element("thirdPartyReview").exists)
        screenshot("25-Reviews")

        let link = element("reviewLink")
        scroll(toReveal: link)
        link.tap()
        XCTAssertTrue(webPageURL().hasPrefix("https://www.google.com/maps/"), "Each review links to Google Maps")
        closeWebPage()

        let yelp = element("yelpReviewsButton")
        scroll(toReveal: yelp)
        XCTAssertFalse(element("yelpReviews").exists, "No Yelp data, so no Yelp section")
        yelp.tap()
        XCTAssertEqual(webPageURL(), "https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside")
        closeWebPage()

        let review = element("leaveReviewButton")
        scroll(toReveal: review)
        review.tap()
        XCTAssertTrue(webPageURL().contains("search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8"))
        closeWebPage()
        XCTAssertTrue(element("googleTermsLink").exists)
    }

    func testReviewsWithYelp() {
        launch(UITestArguments.yelp)
        tap("homeReviews")
        XCTAssertTrue(element("googleReviews").waitForExistence(timeout: 15))
        let yelp = element("yelpReviews")
        scroll(toReveal: yelp)
        XCTAssertTrue(yelp.exists, "The server has Yelp data: its own section")
        XCTAssertTrue(element("yelpRating").exists)
        screenshot("26-Reviews-Yelp")
    }

    func testReviewsUnavailable() {
        launch(UITestArguments.reviewsUnavailable)
        let home = element("homeReviews")
        scroll(toReveal: home)
        XCTAssertTrue(home.label.contains("See what clients say"), "Home links to the reviews: \(home.label)")
        home.tap()
        XCTAssertTrue(element("googleReviewsUnavailable").waitForExistence(timeout: 15))
        tap("seeAllGoogleReviews")
        XCTAssertTrue(webPageURL().hasPrefix("https://www.google.com/maps/search/"))
        closeWebPage()
        XCTAssertTrue(element("yelpReviewsButton").exists)
        screenshot("27-Reviews-Unavailable")
    }

    // MARK: Visit, gallery, reminders

    func testVisit() {
        launch()
        openTab("Visit")
        XCTAssertTrue(element("visitDirectionsButton").waitForExistence(timeout: 10), "The Visit tab didn't show")
        XCTAssertTrue(element("visitCallButton").exists)
        XCTAssertTrue(element("copyAddressButton").exists)
        XCTAssertTrue(element("mapDirections").exists)
        screenshot("22-Visit")

        scroll(toReveal: element("hours-sunday"))
        XCTAssertTrue(element("hours-monday").exists)
        screenshot("23-Visit-Hours")

        let reviews = element("visitSeeAllReviews")
        scroll(toReveal: reviews)
        XCTAssertTrue(element("visitWebsiteLink").exists)
        screenshot("24-Visit-Links")
        reviews.tap()
        XCTAssertTrue(element("googleReviews").waitForExistence(timeout: 15), "Visit's reviews link didn't open the reviews")
    }

    func testGallery() {
        launch()
        tap("seeAllPhotos")
        let first = element("photo-1")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(element("galleryInstagramButton").exists)
        screenshot("28-Gallery")

        first.tap()
        let close = element("closePhoto")
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        screenshot("29-Photo-Viewer")
        let closeFrame = close.frame
        app.swipeLeft()
        // A tap that lands while the swiped page is still settling can be taken by the paging
        // scroll, so it's tried a few times, by screen position (the button is pinned).
        var closed = false
        for _ in 0..<3 where !closed {
            guard close.exists else {
                closed = true
                break
            }
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: closeFrame.midX, dy: closeFrame.midY))
                .tap()
            closed = waitForDisappearance(of: close, timeout: 10)
        }
        XCTAssertTrue(closed, "The photo viewer didn't close")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
    }

    func testReminderSettings() {
        launch()
        tapPinned("remindersButton")
        let toggle = element("remindersToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        screenshot("30-Reminders")
        tapToClose(element("remindersDone"), closing: toggle, "Done didn't close reminder settings")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))
    }

    // MARK: Booking helpers

    /// Waits for the day-and-time step to show a picked day with times.
    private func waitForTimes(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("continueToDetails").waitForExistence(timeout: 15), "The times didn't open", file: file, line: line)
        XCTAssertTrue(element("calendarMonthTitle").waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(element("selectedDayLabel").waitForExistence(timeout: 20), "No day was picked to start with", file: file, line: line)
        XCTAssertTrue(firstTime().waitForExistence(timeout: 20), "The picked day has no times", file: file, line: line)
    }

    private func firstTime() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "time-")).firstMatch
    }

    /// Taps the earliest time on the picked day and returns its identifier.
    @discardableResult
    private func pickFirstTime(file: StaticString = #filePath, line: UInt = #line) -> String {
        let time = firstTime()
        XCTAssertTrue(time.waitForExistence(timeout: 20), "The picked day has no times", file: file, line: line)
        let identifier = time.identifier
        scroll(toReveal: time, file: file, line: line)
        time.tap()
        let next = element("continueToDetails")
        if !waitUntil(next, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 5) {
            // Slow simulators occasionally drop a tap.
            element(identifier).tap()
        }
        XCTAssertTrue(waitUntil(next, toMatch: NSPredicate(format: "isEnabled == true")), "Continue didn't turn on after picking a time", file: file, line: line)
        return identifier
    }

    private func continueToDetails(file: StaticString = #filePath, line: UInt = #line) {
        assertAboveTabBar("continueToDetails", file: file, line: line)
        tapUntil(element("continueToDetails"), shows: element("nameField"), "The details step didn't open", file: file, line: line)
    }

    private func continueToReview(file: StaticString = #filePath, line: UInt = #line) {
        tapUntil(element("continueToReview"), shows: element("bookAppointmentButton"), "The review didn't open", file: file, line: line)
    }

    /// Books from the review and waits for "You're booked".
    private func bookAppointment(file: StaticString = #filePath, line: UInt = #line) {
        assertAboveTabBar("bookAppointmentButton", file: file, line: line)
        tapUntil(element("bookAppointmentButton"), shows: element("bookedTitle"), "Booking didn't finish", timeout: 20, file: file, line: line)
    }

    /// Taps a field and types into it.
    private func type(_ text: String, into identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        scroll(toReveal: field, file: file, line: line)
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            field.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "No keyboard for \(identifier)", file: file, line: line)
        dismissKeyboardTip()
        field.typeText(text)
    }

    /// The first time a keyboard shows, iOS 26 can put a "slide to type" tip in its place, over the
    /// bottom of the screen. (CI also turns it off on the simulator.)
    private func dismissKeyboardTip() {
        let tipContinue = app.keyboards.buttons["Continue"]
        if tipContinue.exists, tipContinue.isHittable {
            tipContinue.tap()
        }
    }

    // MARK: Web pages

    /// The address of the web page on screen (a preview while UI testing).
    private func webPageURL(file: StaticString = #filePath, line: UInt = #line) -> String {
        let text = app.staticTexts["webURL"]
        XCTAssertTrue(text.waitForExistence(timeout: 15), "The web page didn't open", file: file, line: line)
        return text.label
    }

    private func closeWebPage(file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts["webURL"]
        tapToClose(app.buttons["Done"], closing: text, "The web page didn't close", file: file, line: line)
    }

    // MARK: Tabs

    private static let tabs = ["Home", "Services", "Book", "Shop", "Visit"]

    /// Something each tab's first screen always shows.
    private static let landmarks = [
        "Home": "homeBookButton",
        "Services": "service-haircut",
        "Book": "bookService-haircut",
        "Shop": "product-sample-pomade",
        "Visit": "visitDirectionsButton",
    ]

    private static let carlosHaircut = "carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41"
    private static let flowxboriHaircut45 = "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"
    private static let flowxboriHaircut60 = "flowxbori/0d069a9e-c5ea-4cca-ae34-3f38bf668940"

    private func tabButton(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name]
    }

    /// Taps a tab and waits until it's the selected one. A tab that's already selected isn't
    /// tapped (a second tap is the system's own business).
    private func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tabButton(name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing tab \(name)", file: file, line: line)
        guard !tab.isSelected else { return }
        tab.tap()
        if !waitUntil(tab, toMatch: selected()), !tab.isSelected {
            // Slow simulators occasionally drop a tap.
            tab.tap()
        }
        XCTAssertTrue(waitUntil(tab, toMatch: selected()), "\(name) didn't become the selected tab", file: file, line: line)
    }

    /// Only `name` is selected.
    private func assertSelectedTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil(tabButton(name), toMatch: selected()), "\(name) isn't the selected tab", file: file, line: line)
        for other in Self.tabs where other != name {
            XCTAssertFalse(tabButton(other).isSelected, "\(other) is marked selected too", file: file, line: line)
        }
    }

    // MARK: Finding and tapping

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Any element whose accessibility label is `label`, ignoring case.
    private func labeled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    /// Any element whose accessibility label contains `text`, ignoring case.
    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Waits for an element, scrolls it into view and taps it.
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        scroll(toReveal: target, file: file, line: line)
        target.tap()
    }

    /// Taps something pinned in place, where scrolling wouldn't move it: a sticky bar above the tab
    /// bar, a navigation bar button, Home's header.
    private func tapPinned(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        XCTAssertTrue(waitUntil(target, toMatch: hittable()), "\(identifier) can't be tapped", file: file, line: line)
        target.tap()
    }

    /// Taps `button` until `next` shows: slow simulators occasionally drop a tap, and every
    /// screen here ignores a second push.
    private func tapUntil(
        _ button: XCUIElement,
        shows next: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(button)", file: file, line: line)
        XCTAssertTrue(waitUntil(button, toMatch: hittable()), "\(button) can't be tapped", file: file, line: line)
        button.tap()
        if !next.waitForExistence(timeout: timeout), button.exists, button.isHittable, button.isEnabled {
            button.tap()
        }
        XCTAssertTrue(next.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    /// A bar pinned to the bottom of a screen sits fully above the tab bar.
    private func assertAboveTabBar(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        guard bar.exists else { return }
        XCTAssertLessThanOrEqual(
            target.frame.maxY, bar.frame.minY + 1,
            "\(identifier) is behind the tab bar (\(target.frame) vs \(bar.frame))",
            file: file, line: line
        )
    }

    /// Taps a button in a sheet without dragging first: dragging a sheet can move or close it.
    private func tapInSheet(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        target.tap()
    }

    /// Home → "All 5 barbers".
    private func openTeam(file: StaticString = #filePath, line: UInt = #line) {
        tap("meetTeamButton", file: file, line: line)
        XCTAssertTrue(element("barber-israel-flores").waitForExistence(timeout: 10), "The team didn't open", file: file, line: line)
    }

    private func goBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "No back button", file: file, line: line)
        back.tap()
    }

    // MARK: Scrolling

    private enum DragDirection {
        case up
        case down
    }

    /// Scrolls until the element is on screen and clear of the bars at the top and the bottom.
    /// Slow drags that stop dead, so a short element can't fly past in one fling. Elements above
    /// the screen scroll down.
    private func scroll(toReveal target: XCUIElement, maxDrags: Int = 16, file: StaticString = #filePath, line: UInt = #line) {
        var drags = 0
        while drags < maxDrags, !isComfortablyVisible(target) {
            let before: CGRect? = target.exists ? target.frame : nil
            if let before = before, before.midY < app.frame.minY + app.frame.height * 0.25 {
                drag(.down)
            } else {
                drag(.up)
            }
            drags += 1
            if let before = before, target.exists, target.frame == before {
                // The page can't scroll any further.
                break
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Couldn't scroll to \(target)", file: file, line: line)
    }

    private func isComfortablyVisible(_ target: XCUIElement) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let screen = app.frame
        guard !screen.isEmpty else { return true }
        let midY = target.frame.midY
        // Clear of the sticky bar, which rides on top of the keyboard while one is up.
        let bottom = min(0.75, pageBottom() - 0.12)
        return midY >= screen.minY + screen.height * 0.18 && midY <= screen.minY + screen.height * bottom
    }

    /// Where the page ends, as a fraction of the screen's height: the keyboard's top while one is up.
    private func pageBottom() -> CGFloat {
        let keyboard = app.keyboards.firstMatch
        let screen = app.frame
        guard keyboard.exists, !screen.isEmpty, keyboard.frame.minY > screen.minY else { return 1 }
        return max(0.45, (keyboard.frame.minY - screen.minY) / screen.height)
    }

    /// Drags the page about a third of the screen, holding still before letting go so it doesn't
    /// keep scrolling. It starts at 0.7, above the sticky bars and the tab bar, or higher, above
    /// the keyboard and the bar on top of it, while a keyboard is up.
    private func drag(_ direction: DragDirection) {
        let lowY = min(0.7, pageBottom() - 0.15)
        let highY = max(0.2, lowY - 0.35)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: lowY))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: highY))
        let (start, end) = direction == .up ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    // MARK: Waiting

    private func selected() -> NSPredicate {
        NSPredicate(format: "isSelected == true")
    }

    private func hittable() -> NSPredicate {
        NSPredicate(format: "isHittable == true")
    }

    private func waitUntil(_ element: XCUIElement, toMatch predicate: NSPredicate, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps a button that closes a sheet, page or alert, and waits for it to go. Taps once more if
    /// both are still there. It doesn't scroll first, since dragging a sheet can close it.
    private func tapToClose(
        _ button: XCUIElement,
        closing gone: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(button)", file: file, line: line)
        button.tap()
        if !waitForDisappearance(of: gone), gone.exists, button.exists {
            button.tap()
        }
        XCTAssertTrue(waitForDisappearance(of: gone), message, file: file, line: line)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitUntil(element, toMatch: NSPredicate(format: "exists == false"), timeout: timeout)
    }

    // MARK: Screenshots

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The launch arguments the app's in-memory server and test setup understand (see `FakeShopAPI`
/// and `UITestSetup` in the app).
enum UITestArguments {
    static let offline = "-fakeOffline"
    static let bookingOffline = "-fakeBookingOffline"
    static let loseBookingResponse = "-fakeLoseBookingResponse"
    static let slotTaken = "-fakeSlotTaken"
    static let noProducts = "-fakeNoProducts"
    static let reviewsUnavailable = "-fakeReviewsUnavailable"
    static let yelp = "-fakeYelp"
    static let shopCancels = "-fakeShopCancels"
    static let bookedAppointment = "-fakeBookedAppointment"
    static let squireAppointment = "-fakeSquireAppointment"
    static let savedDetails = "-fakeSavedDetails"
}
