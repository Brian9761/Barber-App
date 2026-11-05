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
    /// time books fine, with the note for the barber still there.
    func testSlotTakenPicksAnotherTime() {
        launch(UITestArguments.slotTaken, UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseAnyBarber")
        waitForTimes()
        let taken = pickFirstTime()
        continueToDetails()
        type("Low fade, please", into: "noteField")
        tapPinned("hideKeyboard")
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
        XCTAssertEqual(element("noteField").value as? String, "Low fade, please", "The note for the barber was lost")
        XCTAssertEqual(element("nameField").value as? String, "Sample Client")
        continueToReview()
        XCTAssertTrue(containing("Low fade, please").exists, "The note isn't on the review")
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
        XCTAssertTrue(error.waitForExistence(timeout: 15), "Offline, booking should say it isn't confirmed")
        XCTAssertTrue(error.label.contains("Not confirmed yet"), error.label)
        XCTAssertTrue(error.label.contains("won't book it twice"), error.label)
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
        // It did go through, so the app mustn't say it's not booked.
        XCTAssertTrue(error.label.contains("Not confirmed yet"), error.label)

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

    /// A booking that's slow to answer has no Start over. If the client leaves it anyway (another
    /// Book button, here Home's) and it then goes through, "You're booked" shows:
    /// they haven't seen it yet, and booking that time again would make a second appointment.
    func testABookingLeftWhileItsSentStillShowsBooked() {
        launch(UITestArguments.slowBooking, UITestArguments.savedDetails)
        openTab("Book")
        tap("bookService-haircut")
        tap("choose-\(Self.carlosHaircut)")
        waitForTimes()
        pickFirstTime()
        continueToDetails()
        continueToReview()
        tapPinned("bookAppointmentButton")
        XCTAssertTrue(waitUntil(element("bookAppointmentButton"), toMatch: NSPredicate(format: "isEnabled == false")), "It isn't booking")
        // The sample server holds the booking for up to 2 minutes, so a slow simulator can take its
        // time taking the button away.
        XCTAssertTrue(waitForDisappearance(of: element("bookingStartOver"), timeout: 30), "Start over shows while it's booking")

        // Another booking, started from Home while the first is still being sent. The sample
        // server holds the first booking's answer until the app asks for open times again, so
        // this doesn't depend on how fast the simulator is.
        openTab("Home")
        tap("homeBookButton")
        assertSelectedTab("Book")
        tap("bookService-haircut")
        XCTAssertTrue(element("chooseAnyBarber").waitForExistence(timeout: 10), "Home's button didn't start a booking")
        XCTAssertFalse(element("bookedSummary").exists, "The first booking answered before the client left it")
        // The new booking's times load, and the first booking's answer comes in.
        tap("chooseAnyBarber")

        let summary = element("bookedSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "It was booked, but nothing said so")
        XCTAssertTrue(summary.label.contains("Carlos"), summary.label)
        tapPinned("bookedDoneButton")
        let list = element("yourAppointments")
        XCTAssertTrue(list.waitForExistence(timeout: 10), "No list of appointments on the Book tab")
        XCTAssertEqual(list.descendants(matching: .any).matching(identifier: "appointmentCard").count, 1)
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
    /// another time, later than the cancelled one, puts the new appointment on Home under the
    /// shop's cancellation (it used to stay hidden until the cancelled time was over).
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
        // The cancelled one is 2 to 14 days out (FakeShopAPI.seedBooking), so this is after it.
        pickOpenDay(atLeast: 15)
        pickFirstTime()
        continueToDetails()
        continueToReview()
        bookAppointment()
        tapPinned("bookedDoneButton")
        openTab("Home")
        let next = labeled("Next appointment")
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Home doesn't show the new booking")
        XCTAssertTrue(element("cancelAppointmentButton").exists, "The new booking can be cancelled from Home")
        let cancelled = labeled("Cancelled by the shop")
        XCTAssertTrue(cancelled.exists, "Home no longer says the shop cancelled the earlier one")
        XCTAssertTrue(element("bookAgainButton").exists)
        XCTAssertLessThan(cancelled.frame.minY, next.frame.minY, "The earlier, cancelled appointment should come first")
    }

    /// Offline, Home still shows the appointment as it was, and says it couldn't check it with the
    /// shop (the shop may have cancelled it), when the app opens and after pulling down.
    func testHomeSaysWhenItCouldNotCheckTheAppointment() {
        launch(UITestArguments.bookedAppointment, UITestArguments.offline)
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 15), "Home doesn't show the booked appointment")
        let note = element("staleDataNote")
        XCTAssertTrue(note.waitForExistence(timeout: 15), "Home doesn't say it couldn't check the appointment")
        XCTAssertTrue(note.label.contains("Couldn't check for changes"), note.label)
        XCTAssertTrue(note.label.contains("internet"), note.label)

        app.swipeDown()
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10))
        XCTAssertTrue(element("staleDataNote").waitForExistence(timeout: 15), "After pulling down offline, Home doesn't say the check failed")
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

    // MARK: No-show protection

    /// The shop asks for a card (no-show protection on, its starting settings): the fee notice on
    /// Pick a day and time and on Review, Book waiting for a card, a card added on the stand-in for
    /// Stripe's page, the booking with it, the card on "You're booked" and on the appointment, and
    /// the next booking using the same card straight away.
    func testBookWithACardOnFile() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails)
        let lessThanAnHourAway = openReviewOfCarlosHaircut(checkingTheTimeStepWarning: true)

        let warning = element("noShowWarning")
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "No fee notice on Review")
        XCTAssertTrue(warning.label.contains("Full Service Cancellation & No-Show Fee"), warning.label)
        if let lessThanAnHourAway {
            // The same note on Review, for the same time.
            XCTAssertEqual(warning.label.contains("This time is less than 1 hour away"), lessThanAnHourAway, warning.label)
        }
        let policy = element("noShowPolicyText")
        XCTAssertTrue(policy.waitForExistence(timeout: 10), "No policy to agree to")
        XCTAssertTrue(policy.label.contains("No payment now"), policy.label)
        XCTAssertTrue(policy.label.contains("$45 (100% of the service)"), policy.label)
        let book = element("bookAppointmentButton")
        XCTAssertFalse(book.isEnabled, "Book should wait for a card")
        XCTAssertEqual(book.value as? String, "Add a card first")
        screenshot("51-Book-Review-Add-Card")

        tap("addCardButton")
        let saved = element("savedCard")
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "The card wasn't added")
        XCTAssertTrue(saved.label.contains("Visa ending in 4242"), saved.label)
        XCTAssertFalse(element("addCardButton").exists)
        XCTAssertTrue(element("changeCardButton").exists, "The card can be changed before booking")
        XCTAssertTrue(waitUntil(book, toMatch: NSPredicate(format: "isEnabled == true")), "Book didn't turn on once the card was added")
        screenshot("52-Book-Review-Card-Added")

        bookAppointment()
        let summary = element("bookedSummary")
        XCTAssertTrue(summary.label.contains("Visa ending in 4242"), summary.label)
        XCTAssertTrue(summary.label.contains("Nothing is charged now"), summary.label)
        let reminders = element("appointmentRemindersToggle")
        XCTAssertTrue(reminders.label.contains("Reminders also say until when you can cancel for free"), reminders.label)
        screenshot("53-Booked-With-Card")

        tapPinned("bookedDoneButton")
        let onCard = element("appointmentCardOnFile")
        XCTAssertTrue(onCard.waitForExistence(timeout: 10), "The appointment doesn't show its card on file")
        XCTAssertTrue(onCard.label.contains("Card on file for no-shows and late cancellations: Visa ending in 4242"), onCard.label)

        // The next booking: the same card, straight away.
        openReviewOfCarlosHaircut()
        XCTAssertTrue(element("savedCard").waitForExistence(timeout: 10), "The card isn't there for the next booking")
        XCTAssertFalse(element("addCardButton").exists)
        XCTAssertTrue(waitUntil(element("bookAppointmentButton"), toMatch: NSPredicate(format: "isEnabled == true")), "Book should be ready with the saved card")
        bookAppointment()
        XCTAssertTrue(element("bookedSummary").label.contains("Visa ending in 4242"))
    }

    /// Protection off (as the server starts): no notice, no card section, and Book works as before.
    func testWithoutNoShowProtectionNoCardIsAsked() {
        launch(UITestArguments.savedDetails)
        openReviewOfCarlosHaircut()
        let book = element("bookAppointmentButton")
        // Once Book is on, the shop has said whether a card is needed.
        XCTAssertTrue(waitUntil(book, toMatch: NSPredicate(format: "isEnabled == true")), "Book should be ready without a card")
        XCTAssertFalse(element("cardSection").exists, "No card section when the shop doesn't ask for one")
        XCTAssertFalse(element("addCardButton").exists)
        XCTAssertFalse(element("noShowWarning").exists)
        bookAppointment()
        XCTAssertFalse(element("bookedSummary").label.contains("Card on file"), element("bookedSummary").label)
        XCTAssertFalse(element("appointmentRemindersToggle").label.contains("cancel for free"), "Nothing about fees without a card")
        tapPinned("bookedDoneButton")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10))
        XCTAssertFalse(element("appointmentCardOnFile").exists)
    }

    /// Closing Stripe's page adds nothing: Book still waits, and adding the card again works.
    func testClosingTheCardPageKeepsBookOff() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails, UITestArguments.cardCancel)
        openReviewOfCarlosHaircut()
        let add = element("addCardButton")
        tap("addCardButton")
        // Back to "Add a card", with nothing added and nothing wrong.
        XCTAssertFalse(element("savedCard").waitForExistence(timeout: 3), "Closing the page added a card")
        XCTAssertFalse(element("cardError").exists, "Closing the page isn't an error")
        XCTAssertTrue(waitUntil(add, toMatch: NSPredicate(format: "isEnabled == true AND label == %@", "Add a card")), "The card page didn't close")
        XCTAssertFalse(element("bookAppointmentButton").isEnabled, "Book should still wait for a card")
        screenshot("55-Book-Review-Card-Page-Closed")

        tap("addCardButton")
        XCTAssertTrue(element("savedCard").waitForExistence(timeout: 15), "Adding the card again didn't work")
        XCTAssertTrue(waitUntil(element("bookAppointmentButton"), toMatch: NSPredicate(format: "isEnabled == true")))
    }

    /// The way back from Stripe's page goes wrong: the app says so, and Try again adds the card.
    func testACardPageThatFailsOffersTryAgain() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails, UITestArguments.cardFail)
        openReviewOfCarlosHaircut()
        tap("addCardButton")
        let error = element("cardError")
        XCTAssertTrue(error.waitForExistence(timeout: 15), "No message when the card wasn't added")
        XCTAssertTrue(error.label.contains("The card wasn't added"), error.label)
        let retry = element("addCardButton")
        XCTAssertTrue(waitUntil(retry, toMatch: NSPredicate(format: "isEnabled == true AND label == %@", "Try again")), "No Try again")
        XCTAssertFalse(element("bookAppointmentButton").isEnabled)
        screenshot("56-Book-Review-Card-Failed")
        retry.tap()
        XCTAssertTrue(element("savedCard").waitForExistence(timeout: 15), "Try again didn't add the card")
        XCTAssertTrue(waitForDisappearance(of: element("cardError")))
    }

    /// Late cancellations off in the shop's settings: the notice is about no-shows only.
    func testANoShowOnlyNotice() {
        launch(UITestArguments.noShowProtection, UITestArguments.noLateCancel)
        openTab("Book")
        tap("bookService-haircut")
        tap("choose-\(Self.carlosHaircut)")
        waitForTimes()
        let warning = element("noShowWarning")
        XCTAssertTrue(warning.waitForExistence(timeout: 15), "No fee notice on Pick a day and time")
        XCTAssertTrue(warning.label.contains("No-Show Fee"), warning.label)
        XCTAssertFalse(warning.label.contains("Cancellation"), warning.label)
        XCTAssertTrue(warning.label.contains("Cancelling in the app before your appointment is free"), warning.label)
    }

    /// An appointment with a card on file that starts in 45 minutes: cancelling it now warns first
    /// that it may be charged, then cancels.
    func testCancellingLateWarnsFirst() {
        launch(UITestArguments.bookedSoonWithCard)
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 15), "Home doesn't show the appointment")
        XCTAssertTrue(element("appointmentCardOnFile").waitForExistence(timeout: 10), "Home doesn't show its card on file")
        openTab("Book")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "Book doesn't show the appointment")
        let onCard = element("appointmentCardOnFile")
        XCTAssertTrue(onCard.waitForExistence(timeout: 10), "The appointment doesn't show its card on file")
        XCTAssertTrue(onCard.label.contains("Visa ending in 4242"), onCard.label)

        let cancel = element("cancelAppointmentButton")
        scroll(toReveal: cancel)
        cancel.tap()
        let warning = containing("may be charged $45, the full service price")
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "No late-cancellation warning before cancelling")
        XCTAssertTrue(containing("less than 1 hour before your appointment").exists)
        screenshot("54-Late-Cancel-Warning")
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Cancel appointment", "cancelAppointmentButton")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No Cancel appointment in the warning")
        confirm.tap()
        XCTAssertTrue(labeled("Cancelled").waitForExistence(timeout: 15), "The appointment doesn't say it's cancelled")
        XCTAssertTrue(waitForDisappearance(of: element("cancelAppointmentButton")))
    }

    /// Your details shows the card saved with the last booking; Remove card takes it off this
    /// iPhone, so the next booking asks for a card again.
    func testRemovingTheCardInYourDetails() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails)
        bookCarlosHaircutWithANewCard()

        openYourDetails()
        let card = element("detailsSheetCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Your details doesn't show the card")
        XCTAssertTrue(card.label.contains("Visa ending in 4242"), card.label)
        XCTAssertTrue(element("removeCardButton").exists)
        screenshot("57-Your-Details-Card")
        tapInSheet("removeCardButton")
        XCTAssertTrue(waitForDisappearance(of: card), "Remove card didn't take the card away")
        XCTAssertFalse(element("removeCardButton").exists)
        closeYourDetails()
        XCTAssertTrue(element("customerDetailsRow").exists, "Removing the card keeps the name and number")

        openReviewOfCarlosHaircut()
        XCTAssertTrue(element("addCardButton").waitForExistence(timeout: 10), "The next booking should ask for a card")
        XCTAssertFalse(element("savedCard").exists)
        XCTAssertFalse(element("bookAppointmentButton").isEnabled, "Book should wait for a card")
    }

    /// Forget my details asks about the card too, and forgets it with the name and number: the next
    /// booking asks for all three again.
    func testForgettingYourDetailsForgetsTheCard() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails)
        bookCarlosHaircutWithANewCard()

        openYourDetails()
        XCTAssertTrue(element("detailsSheetCard").waitForExistence(timeout: 10), "Your details doesn't show the card")
        tapInSheet("forgetDetailsButton")
        XCTAssertTrue(containing("Forget your name, number and card?").waitForExistence(timeout: 10), "The question doesn't say the card goes too")
        XCTAssertTrue(containing("and add a card, next time you book").exists)
        screenshot("58-Forget-Details-And-Card")
        let forget = app.buttons.matching(NSPredicate(format: "label == %@", "Forget")).firstMatch
        XCTAssertTrue(forget.waitForExistence(timeout: 10))
        forget.tap()
        XCTAssertTrue(waitForDisappearance(of: element("customerDetailsRow")), "The details are still remembered")

        openDetailsOfCarlosHaircut()
        type("Sample Client", into: "nameField")
        type("4425550123", into: "phoneField")
        tapPinned("hideKeyboard")
        continueToReview()
        XCTAssertTrue(element("addCardButton").waitForExistence(timeout: 10), "The card was remembered after Forget my details")
        XCTAssertFalse(element("savedCard").exists)
    }

    /// With Remember me off, a card added for this booking is used for it and then forgotten, with
    /// the name and number: the next booking asks for them again.
    func testRememberMeOffForgetsTheCardOnceBooked() {
        launch(UITestArguments.noShowProtection, UITestArguments.savedDetails)
        openDetailsOfCarlosHaircut()
        let remember = element("rememberDetailsToggle")
        scroll(toReveal: remember)
        XCTAssertTrue(remember.label.contains("your card stays saved"), remember.label)
        flipSwitch(remember)
        continueToReview()
        tap("addCardButton")
        XCTAssertTrue(element("savedCard").waitForExistence(timeout: 15), "The card wasn't added")
        bookAppointment()
        XCTAssertTrue(element("bookedSummary").label.contains("Visa ending in 4242"), "The booking has the card")
        tapPinned("bookedDoneButton")
        XCTAssertTrue(element("appointmentCard").waitForExistence(timeout: 10), "The appointment isn't on the Book tab")
        XCTAssertFalse(element("customerDetailsRow").exists, "Remember me off: the name and number aren't kept")

        openDetailsOfCarlosHaircut()
        type("Sample Client", into: "nameField")
        type("4425550123", into: "phoneField")
        tapPinned("hideKeyboard")
        continueToReview()
        XCTAssertTrue(element("addCardButton").waitForExistence(timeout: 10), "The card from the last booking should be gone")
        XCTAssertFalse(element("savedCard").exists)
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

    /// Book → Haircut → Carlos → the first open time → details (already remembered) → Review.
    /// With `checkingTheTimeStepWarning`, checks the fee notice shows on Pick a day and time first,
    /// and the note for a time less than an hour away (`checkLateCancelNotice`), and returns
    /// whether that note shows.
    @discardableResult
    private func openReviewOfCarlosHaircut(checkingTheTimeStepWarning: Bool = false, file: StaticString = #filePath, line: UInt = #line) -> Bool? {
        openTab("Book", file: file, line: line)
        tap("bookService-haircut", file: file, line: line)
        tap("choose-\(Self.carlosHaircut)", file: file, line: line)
        // The notice is checked before scrolling down to the times, so its screenshot shows it.
        waitForPickedDay(file: file, line: line)
        if checkingTheTimeStepWarning {
            let warning = element("noShowWarning")
            XCTAssertTrue(warning.waitForExistence(timeout: 15), "No fee notice on Pick a day and time", file: file, line: line)
            XCTAssertTrue(warning.label.contains("Full Service Cancellation & No-Show Fee"), warning.label, file: file, line: line)
            XCTAssertTrue(warning.label.contains("the full service price ($45)"), warning.label, file: file, line: line)
            screenshot("50-Book-Time-Fee-Warning")
        }
        let time = pickFirstTime(file: file, line: line)
        let lessThanAnHourAway = checkingTheTimeStepWarning ? checkLateCancelNotice(forTime: time, file: file, line: line) : nil
        continueToDetails(file: file, line: line)
        continueToReview(file: file, line: line)
        return lessThanAnHourAway
    }

    /// Book → Haircut → Carlos → the first open time → the details step.
    private func openDetailsOfCarlosHaircut(file: StaticString = #filePath, line: UInt = #line) {
        openTab("Book", file: file, line: line)
        tap("bookService-haircut", file: file, line: line)
        tap("choose-\(Self.carlosHaircut)", file: file, line: line)
        waitForTimes(file: file, line: line)
        pickFirstTime(file: file, line: line)
        continueToDetails(file: file, line: line)
    }

    /// Books Carlos's haircut with a card added on the stand-in for Stripe's page (details already
    /// remembered), and goes back to the Book tab.
    private func bookCarlosHaircutWithANewCard(file: StaticString = #filePath, line: UInt = #line) {
        openReviewOfCarlosHaircut(file: file, line: line)
        tap("addCardButton", file: file, line: line)
        XCTAssertTrue(element("savedCard").waitForExistence(timeout: 15), "The card wasn't added", file: file, line: line)
        bookAppointment(file: file, line: line)
        tapPinned("bookedDoneButton", file: file, line: line)
        XCTAssertTrue(element("customerDetailsRow").waitForExistence(timeout: 10), "The details aren't remembered", file: file, line: line)
    }

    /// Book → "Change" on "Booking as…": the Your details sheet.
    private func openYourDetails(file: StaticString = #filePath, line: UInt = #line) {
        openTab("Book", file: file, line: line)
        tap("changeCustomerDetails", file: file, line: line)
        XCTAssertTrue(element("detailsSheetName").waitForExistence(timeout: 10), "Change didn't open Your details", file: file, line: line)
    }

    private func closeYourDetails(file: StaticString = #filePath, line: UInt = #line) {
        tapToClose(app.navigationBars["Your details"].buttons["Cancel"], closing: element("detailsSheetName"), "Your details didn't close", file: file, line: line)
    }

    /// "This time is less than 1 hour away…" shows right over Continue exactly when the picked time
    /// (`identifier`, "time-1430") is today and less than an hour away, as the day's first times
    /// often are (the lead time is 30 minutes). Returns whether it should show, or `nil` for a time
    /// too close to an hour away to tell (the unit tests cover that moment).
    private func checkLateCancelNotice(forTime identifier: String, file: StaticString = #filePath, line: UInt = #line) -> Bool? {
        var shopCalendar = Calendar(identifier: .gregorian)
        // The shop's time zone (IzzyClipzData): the times are the shop's times.
        shopCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let digits = identifier.dropFirst("time-".count)
        guard digits.count == 4, let hour = Int(digits.prefix(2)), let minute = Int(digits.suffix(2)) else {
            XCTFail("Unexpected time identifier \(identifier)", file: file, line: line)
            return nil
        }
        // The picked day's heading, "Wednesday, November 4" (BookingCalendar.longLabel). Today's
        // cell in the calendar can be off screen: scrolled past, or on another month's page.
        let longDay = DateFormatter()
        longDay.calendar = shopCalendar
        longDay.timeZone = shopCalendar.timeZone
        longDay.locale = Locale(identifier: "en_US_POSIX")
        longDay.dateFormat = "EEEE, MMMM d"
        let now = Date()
        guard let start = shopCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        let isToday = element("selectedDayLabel").label == longDay.string(from: now)
        let minutesAway = start.timeIntervalSince(now) / 60
        if isToday, abs(minutesAway - 60) < 1 { return nil }
        let expected = isToday && minutesAway < 60
        let note = element("lateCancelNotice")
        if expected {
            XCTAssertTrue(note.waitForExistence(timeout: 10), "No note for a time \(Int(minutesAway)) minutes away", file: file, line: line)
            XCTAssertTrue(note.label.contains("less than 1 hour away, so cancelling it may be charged $45"), note.label, file: file, line: line)
            XCTAssertTrue(note.isHittable, "The note isn't on screen", file: file, line: line)
            XCTAssertLessThanOrEqual(
                note.frame.maxY, element("continueToDetails").frame.minY + 1,
                "The note should sit right over Continue", file: file, line: line
            )
            screenshot("50b-Book-Time-Less-Than-An-Hour")
        } else {
            XCTAssertFalse(note.exists, "A note for a time that isn't less than an hour away", file: file, line: line)
        }
        return expected
    }

    /// Flips a switch row. The switch sits at the row's trailing end (a tap on the row's middle
    /// lands on its label and does nothing), so this taps the switch itself and checks it moved.
    private func flipSwitch(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let inner = row.switches.firstMatch
        let control = inner.exists ? inner : row
        let before = control.value as? String
        let trailingEnd = row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        if inner.exists {
            inner.tap()
        } else {
            trailingEnd.tap()
        }
        guard let before, before == "0" || before == "1" else {
            XCTFail("\(row) isn't a switch", file: file, line: line)
            return
        }
        let flipped = NSPredicate(format: "value == %@", before == "1" ? "0" : "1")
        if !waitUntil(control, toMatch: flipped, timeout: 3) {
            trailingEnd.tap()
            XCTAssertTrue(waitUntil(control, toMatch: flipped, timeout: 5), "The switch didn't move", file: file, line: line)
        }
    }

    /// Waits for the day-and-time step to show a picked day with times, scrolling down to them.
    private func waitForTimes(file: StaticString = #filePath, line: UInt = #line) {
        waitForPickedDay(file: file, line: line)
        XCTAssertTrue(revealFirstTime(), "The picked day has no times", file: file, line: line)
    }

    /// Waits for the day-and-time step to open with a day picked (the first day with times).
    private func waitForPickedDay(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("continueToDetails").waitForExistence(timeout: 15), "The times didn't open", file: file, line: line)
        XCTAssertTrue(element("calendarMonthTitle").waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(element("selectedDayLabel").waitForExistence(timeout: 20), "No day was picked to start with", file: file, line: line)
    }

    private func firstTime() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "time-")).firstMatch
    }

    /// Scrolls down to the picked day's times, as a person would, until the first one is there,
    /// and says whether it is. The times are a lazy grid that only makes the buttons near the
    /// screen, and on a phone the fee notice (no-show protection) pushes them below it.
    private func revealFirstTime(maxDrags: Int = 6) -> Bool {
        let time = firstTime()
        if time.waitForExistence(timeout: 3) { return true }
        for _ in 0..<maxDrags {
            drag(.up)
            if time.waitForExistence(timeout: 2) { return true }
        }
        return time.waitForExistence(timeout: 10)
    }

    /// Picks the first day with open times at least `days` days after today in the shop, turning
    /// to the next month when the day is on it.
    private func pickOpenDay(atLeast days: Int, file: StaticString = #filePath, line: UInt = #line) {
        var shopCalendar = Calendar(identifier: .gregorian)
        // The shop's time zone (IzzyClipzData): the calendar's days are the shop's days.
        shopCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let dayID = DateFormatter()
        dayID.calendar = shopCalendar
        dayID.timeZone = shopCalendar.timeZone
        dayID.locale = Locale(identifier: "en_US_POSIX")
        dayID.dateFormat = "'day-'yyyy-MM-dd"
        let today = Date()
        for offset in days..<(days + 28) {
            guard let date = shopCalendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let identifier = dayID.string(from: date)
            let cell = element(identifier)
            if !cell.exists {
                let nextMonth = element("calendarNextMonth")
                XCTAssertTrue(nextMonth.isEnabled, "\(identifier) isn't on the calendar", file: file, line: line)
                nextMonth.tap()
                XCTAssertTrue(cell.waitForExistence(timeout: 10), "Next month didn't show \(identifier)", file: file, line: line)
            }
            // Days show as "checking" until their times load; then only a day with times is enabled.
            let checked = waitUntil(cell, toMatch: NSPredicate(format: "NOT (label CONTAINS[c] %@)", "checking"), timeout: 20)
            XCTAssertTrue(checked, "The times for \(identifier) didn't load", file: file, line: line)
            guard cell.isEnabled else { continue }
            scroll(toReveal: cell, file: file, line: line)
            cell.tap()
            XCTAssertTrue(waitUntil(cell, toMatch: selected()), "Didn't pick \(identifier)", file: file, line: line)
            return
        }
        XCTFail("No open day \(days) or more days out", file: file, line: line)
    }

    /// Taps the earliest time on the picked day and returns its identifier.
    @discardableResult
    private func pickFirstTime(file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertTrue(revealFirstTime(), "The picked day has no times", file: file, line: line)
        let identifier = firstTime().identifier
        let time = element(identifier)
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
    static let slowBooking = "-fakeSlowBooking"
    static let noProducts = "-fakeNoProducts"
    static let reviewsUnavailable = "-fakeReviewsUnavailable"
    static let yelp = "-fakeYelp"
    static let shopCancels = "-fakeShopCancels"
    static let bookedAppointment = "-fakeBookedAppointment"
    static let squireAppointment = "-fakeSquireAppointment"
    static let savedDetails = "-fakeSavedDetails"
    /// No-show protection on, with the server's starting settings: the full service price for a
    /// no-show or a cancellation less than 1 hour before.
    static let noShowProtection = "-fakeNoShowProtection"
    /// With `noShowProtection`: late cancellations off, so only no-shows can be charged.
    static let noLateCancel = "-fakeNoLateCancel"
    /// The first time Stripe's page opens, the client closes it.
    static let cardCancel = "-fakeCardCancel"
    /// The first time Stripe's page opens, the way back to the app goes wrong.
    static let cardFail = "-fakeCardFail"
    /// An appointment with a card on file that starts in 45 minutes.
    static let bookedSoonWithCard = "-fakeBookedSoonWithCard"
}
