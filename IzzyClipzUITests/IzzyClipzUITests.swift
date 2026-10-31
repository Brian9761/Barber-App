import XCTest

/// Walks through every screen the way a client would: the five tabs of the floating bar and the
/// barber-pole sweep between them, booking on the in-app calendar through to BOOKED, the Bravo bag
/// and its hand-off to Bravo's own checkout, Instagram, and where each Squire, Bravo, Google and
/// Instagram link leads. Saves screenshots along the way.
///
/// The app runs with `-ui-testing`, which starts from empty settings (no favorite, no appointments,
/// an empty bag), shows a link preview instead of loading web pages or leaving the app, uses Bravo's
/// bundled prices, never asks for notification permission, and stands in for Apple's "New Event"
/// screen, so tests don't depend on the network or on what a previous run left behind.
///
/// The booking calendar starts from today, so no test names a date: they take the day the calendar
/// picks and its first open time.
///
/// Every tab stays alive behind the selected one (hidden from accessibility), so a tab keeps its
/// pushed screens and scroll position while another is showing.
final class IzzyClipzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 30), "The app didn't start on Home")
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 10), "No tab bar")
    }

    // MARK: Tab bar

    /// The floating bar: five tabs on one row at the bottom, each reachable and big enough to tap, the
    /// selected one marked, and a second tap on the selected tab back to its first screen.
    func testTabBar() {
        let screen = app.frame
        let home = tabButton("Home")
        let bar = home.frame
        // It sits on the screen's bottom edge, clear of the home indicator: not floating high above it
        // (iOS 26 once put it 34 pt too high) and not running into it.
        let gap = screen.maxY - bar.maxY
        XCTAssertLessThanOrEqual(gap, 60, "The tab bar floats \(gap) pt above the bottom of the screen")
        XCTAssertGreaterThanOrEqual(gap, 8, "The tab bar runs into the home indicator (\(gap) pt from the bottom)")

        var previousMaxX = screen.minX
        for name in Self.tabs {
            let frame = tabButton(name).frame
            XCTAssertEqual(frame.maxY, bar.maxY, accuracy: 2, "\(name) isn't on the same row as Home")
            XCTAssertGreaterThanOrEqual(frame.minX, previousMaxX - 1, "\(name) is out of order")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name) is too narrow to tap")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name) is too short to tap")
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
            previousMaxX = frame.maxX
        }
        assertSelectedTab("Home")

        // Every tab, in the bar's order and back the other way.
        for name in Self.tabs.dropFirst() + Self.tabs.reversed().dropFirst() {
            openTab(name)
            XCTAssertTrue(element(Self.landmarks[name] ?? "").waitForExistence(timeout: 10), "The \(name) tab didn't show")
            assertSelectedTab(name)
        }

        // Tapping the selected tab again pops it back to its first screen, on every tab.
        tap("meetTeamButton")
        assertRetappingPopsToRoot("Home", pushed: "barber-israel-flores")

        openTab("Services")
        tap("service-haircut")
        assertRetappingPopsToRoot("Services", pushed: "bookFirstAvailable")

        openTab("Book")
        tap("bookService-haircut")
        assertRetappingPopsToRoot("Book", pushed: "chooseFirstAvailable")

        openTab("Shop")
        tap("product-bravo-matte-clay")
        assertRetappingPopsToRoot("Shop", pushed: "addToBagButton")

        openTab("Visit")
        tap("visitSeeAllReviews")
        assertRetappingPopsToRoot("Visit", pushed: "readGoogleReviewsButton")
        // On the first screen, another tap goes back to the top.
        scroll(toReveal: element("leaveReviewButton"))
        let directions = element("visitDirectionsButton")
        XCTAssertFalse(directions.isHittable, "Visit should be scrolled down to its links")
        tabButton("Visit").tap()
        XCTAssertTrue(waitUntil(directions, toMatch: hittable()), "Tapping Visit again didn't scroll back to the top")
        assertSelectedTab("Visit")
    }

    /// The pole sweeps across for 0.46 s after a tab tap, but the new tab takes taps from the start,
    /// and every tab keeps its own screens while another one is showing.
    func testTabSwitchNeverBlocksTaps() {
        tabButton("Services").tap()
        let haircut = element("service-haircut")
        XCTAssertTrue(haircut.waitForExistence(timeout: 10), "The Services tab didn't show")
        // Straight away, without waiting for the pole to leave.
        haircut.tap()
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10), "A tap right after switching tabs didn't land")
        assertSelectedTab("Services")

        // Rapid taps: each one finishes the running sweep and starts the next. The last tab wins.
        tabButton("Shop").tap()
        tabButton("Visit").tap()
        tabButton("Book").tap()
        XCTAssertTrue(waitUntil(tabButton("Book"), toMatch: selected()), "Book didn't end up selected")
        let start = element("bookService-haircut")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(element("chooseFirstAvailable").waitForExistence(timeout: 10), "A tap after rapid tab switches didn't land")
        assertSelectedTab("Book")
        // The tabs passed through are hidden, not on top of Book.
        XCTAssertTrue(waitForDisappearance(of: element("shopBagButton")), "The Shop tab is still showing behind Book")
        XCTAssertFalse(element("visitDirectionsButton").exists, "The Visit tab is still showing behind Book")

        // Services kept the haircut's page.
        openTab("Services")
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10), "Services lost its pushed page")
        // And Book kept step 2.
        openTab("Book")
        XCTAssertTrue(element("chooseFirstAvailable").waitForExistence(timeout: 10), "Book lost its pushed step")
    }

    // MARK: Home

    func testHome() {
        // Top to bottom: the hero, Book, the walk-in line (nothing is booked), Directions and Call.
        XCTAssertTrue(element("shopStatus").exists)
        XCTAssertTrue(element("homeHeroPhotos").exists)
        XCTAssertTrue(element("seeAllPhotos").exists)
        XCTAssertTrue(element("homeWalkIns").exists, "With nothing booked, Home shows the walk-in line")
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing is booked yet")
        XCTAssertTrue(element("callButton").exists)
        XCTAssertTrue(element("directionsButton").exists)
        XCTAssertTrue(element("remindersButton").exists)
        XCTAssertFalse(element("homeFavoriteBook").exists, "No favorite barber yet")
        screenshot("01-Home")

        // Scrolled content passes under the pinned header, not the bare status bar.
        drag(.up)
        XCTAssertTrue(element("popular-haircut").exists)
        XCTAssertTrue(element("homeBarber-israel-flores").exists)
        screenshot("02-Home-Scrolled")

        scroll(toReveal: element("seeAllReviews"))
        XCTAssertTrue(element("meetTeamButton").exists)
        XCTAssertTrue(element("instagramButton").exists)
        screenshot("04-Home-Reviews")

        scroll(toReveal: element("bravoBanner"))
        screenshot("03-Home-Bravo")

        // The Bravo card leads to the Shop tab.
        tap("bravoBanner")
        XCTAssertTrue(element("shopBagButton").waitForExistence(timeout: 10), "The Bravo card didn't open the Shop")
        assertSelectedTab("Shop")

        // "All services ›" leads to the Services tab.
        openTab("Home")
        tap("allServicesButton")
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 10), "All services didn't open the Services tab")
        assertSelectedTab("Services")
    }

    func testHomeBookButtonOpensBooking() {
        tap("homeBookButton")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10))
        assertSelectedTab("Book")
    }

    /// The shop's Instagram: one card on Home, open and message on Visit, and Izzy's own account on
    /// his page. In UI tests they open the link preview instead of Instagram.
    func testInstagram() {
        let card = element("instagramButton")
        scroll(toReveal: card)
        XCTAssertTrue(card.label.contains("@izzy_clipz_barbershop_"), card.label)
        screenshot("30-Home-Instagram")
        card.tap()
        XCTAssertEqual(webPageURL(), "https://www.instagram.com/izzy_clipz_barbershop_/")
        closeWebPage()

        openTab("Visit")
        let message = element("visitInstagramMessage")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Visit has no Instagram card")
        scroll(toReveal: message)
        XCTAssertTrue(element("visitInstagramLink").exists)
        screenshot("34-Visit-Instagram")
        message.tap()
        XCTAssertEqual(webPageURL(), "https://ig.me/m/izzy_clipz_barbershop_")
        closeWebPage()

        tap("visitInstagramLink")
        XCTAssertEqual(webPageURL(), "https://www.instagram.com/izzy_clipz_barbershop_/")
        closeWebPage()

        // Izzy's page links his own account, not the shop's.
        openTab("Home")
        openTeam()
        tap("barber-israel-flores")
        tap("barberInstagram")
        let izzy = webPageURL()
        XCTAssertTrue(izzy.hasPrefix("https://www.instagram.com/izzy_clipz_/"), izzy)
        closeWebPage()
    }

    // MARK: Services and the team

    func testServices() {
        openTab("Services")
        XCTAssertTrue(app.navigationBars["Services"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 10))
        XCTAssertTrue(element("jump-haircuts").exists)
        screenshot("05-Services")

        // A jump chip scrolls its category up to the top, past the haircuts.
        let haircut = element("service-haircut")
        let package = element("service-haircut-and-beard")
        XCTAssertTrue(haircut.isHittable, "The menu should open on the haircuts")
        tap("jump-packages")
        XCTAssertTrue(
            waitUntil(haircut, toMatch: NSPredicate(format: "isHittable == false")),
            "The Packages chip didn't scroll past the haircuts"
        )
        XCTAssertTrue(waitUntil(package, toMatch: hittable()), "The Packages chip didn't scroll to the packages")

        tap("service-haircut")
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 10))
        XCTAssertTrue(element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41").exists)
        XCTAssertTrue(element("bookServiceButton").exists)
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
        XCTAssertTrue(
            waitUntil(search, toMatch: NSPredicate(format: "hasKeyboardFocus == true")),
            "The search field didn't take focus"
        )
        search.typeText("beard")
        XCTAssertTrue(waitForDisappearance(of: element("service-perm")), "Searching for beard didn't filter out Perm")
        XCTAssertTrue(element("service-haircut-and-beard").exists)
        if app.keyboards.firstMatch.exists {
            // The floating bar steps aside while typing instead of riding on the keyboard.
            XCTAssertTrue(waitForDisappearance(of: tabButton("Home")), "The tab bar stayed up over the keyboard")
        }
        screenshot("07-Services-Search")
    }

    func testTeamAndBarber() {
        openTeam()
        screenshot("08-Team")

        tap("barber-carlos-rafael")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element("favoriteButton").exists)
        XCTAssertTrue(element("barberMenu-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41").exists, "Carlos's menu is missing his haircut")
        XCTAssertFalse(element("barberInstagram").exists, "Carlos has no Instagram in the data")
        screenshot("09-Barber-Detail")
    }

    func testFavoriteBarberShowsOnHome() {
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

        // "YOUR BARBER" on Home, with a Book button that goes to their own menu.
        XCTAssertTrue(labeled("Your barber").waitForExistence(timeout: 10), "No YOUR BARBER on Home")
        let book = element("homeFavoriteBook")
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        XCTAssertEqual(book.label.lowercased(), "book with flowxbori")
        scroll(toReveal: book)
        screenshot("33-Home-Your-Barber")
        book.tap()

        // Barber first: their own menu, to pick a service.
        let service = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "barberService-flowxbori/")).firstMatch
        XCTAssertTrue(service.waitForExistence(timeout: 10), "Booking with Flowxbori didn't show their services")
        assertSelectedTab("Book")
    }

    // MARK: Booking

    func testBookingFlowFirstAvailable() {
        openTab("Book")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10))
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing is booked yet")
        XCTAssertTrue(stepIndicator(1, "Service").waitForExistence(timeout: 10), "No step 1 indicator")
        XCTAssertFalse(element("bookingStartOver").exists, "Step 1 has nothing to start over")
        screenshot("10-Book-Service")

        tap("bookService-haircut")
        XCTAssertTrue(element("chooseFirstAvailable").waitForExistence(timeout: 10))
        XCTAssertTrue(stepIndicator(2, "Barber").waitForExistence(timeout: 10), "No step 2 indicator")
        XCTAssertTrue(element("bookingStartOver").exists)
        screenshot("11-Book-Barber")

        tap("chooseFirstAvailable")
        waitForCalendar()
        XCTAssertTrue(stepIndicator(3, "Time").waitForExistence(timeout: 10), "No step 3 indicator")
        screenshot("12-Book-Calendar")

        pickFirstTime()
        screenshot("13-Book-Time-Picked")

        continueToReview()
        XCTAssertTrue(stepIndicator(4, "Review").waitForExistence(timeout: 10), "No step 4 indicator")
        screenshot("14-Book-Review")

        confirmOnSquire()
        assertSquireURL(
            webPageURL(),
            contains: "/booking/book/izzy-clipz-oceanside/barber/any/services?preselect=bbb0c294-87a6-465d-9f55-6f579dcb399a"
        )
        closeWebPage()

        // "Did you book it?"
        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        XCTAssertTrue(element("saveAppointmentButton").exists)
        XCTAssertTrue(element("notBookedButton").exists)
        XCTAssertTrue(element("openSquireAgainButton").exists)
        let remind = element("remindMeToggle")
        XCTAssertTrue(remind.exists)
        XCTAssertEqual(remind.value as? String, "1", "Reminders should start on")
        screenshot("15-Confirm-Booking")

        // BOOKED: the form gives way to the drip word and the ticket.
        tapInSheet("saveAppointmentButton")
        XCTAssertTrue(labeled("Booked. Appointment saved.").waitForExistence(timeout: 10), "Saving didn't show BOOKED")
        XCTAssertTrue(element("addToCalendarButton").waitForExistence(timeout: 10), "Saving didn't show the saved state")
        XCTAssertTrue(element("confirmDoneButton").exists)
        XCTAssertTrue(waitForDisappearance(of: element("saveAppointmentButton")), "The form is still showing after saving")
        screenshot("16-Booking-Saved")

        tapInSheet("addToCalendarButton")
        let eventTitle = element("calendarEventTitle")
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 10), "Add to Calendar didn't open")
        XCTAssertTrue(eventTitle.label.contains("Haircut"), eventTitle.label)
        tapToClose(app.buttons["Add"], closing: eventTitle, "Add to Calendar didn't close")

        // Saved: the Book tab is back at step 1 with the appointment on top, and Home shows it.
        XCTAssertTrue(element("upcomingAppointment").waitForExistence(timeout: 10))
        XCTAssertTrue(element("bookService-haircut").exists)
        let ticket = element("appointmentMoreButton")
        XCTAssertTrue(ticket.label.contains("Haircut with the first available barber"), ticket.label)
        assertSelectedTab("Book")
        screenshot("31-Book-Appointments")

        openTab("Home")
        XCTAssertTrue(element("upcomingAppointment").waitForExistence(timeout: 10))
        XCTAssertFalse(element("homeWalkIns").exists, "The ticket takes the walk-in line's place")
        scroll(toReveal: element("appointmentAddToCalendar"))
        screenshot("17-Home-Appointment")
    }

    func testBookingSpecificBarberVIP() {
        openTab("Book")
        let vip = element("bookService-vip")
        XCTAssertTrue(vip.waitForExistence(timeout: 10))
        scroll(toReveal: vip)
        vip.tap()
        let izzy = element("choose-israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75")
        XCTAssertTrue(izzy.waitForExistence(timeout: 10))
        XCTAssertFalse(element("chooseFirstAvailable").exists, "Only Izzy offers VIP")
        scroll(toReveal: izzy)
        izzy.tap()

        waitForCalendar()
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        assertSquireURL(webPageURL(), contains: "/barber/israel-flores/services?preselect=9a33be59-43eb-445c-9c18-6435125b1f75")
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tapToClose(element("notBookedButton"), closing: element("confirmBookingSheet"), "\"I didn't book\" didn't close the sheet")

        // Nothing was saved: back on the review, and no appointment anywhere.
        XCTAssertTrue(element("confirmOnSquireButton").waitForExistence(timeout: 10))
        popToBookingStart()
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing should be saved")
        openTab("Home")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing should be saved")
        XCTAssertTrue(element("homeWalkIns").exists)
    }

    func testBookingFromServicePage() {
        openTab("Services")
        tap("service-haircut")
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        XCTAssertTrue(carlos.waitForExistence(timeout: 10))
        scroll(toReveal: carlos)
        carlos.tap()

        // Straight to the calendar on the Book tab, with Carlos and his haircut chosen.
        waitForCalendar()
        assertSelectedTab("Book")
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        assertSquireURL(webPageURL(), contains: "/barber/carlos-rafael/services?preselect=9343fc67-b196-4604-987e-a4a9b6b4cc41")
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tapToClose(element("notBookedButton"), closing: element("confirmBookingSheet"), "\"I didn't book\" didn't close the sheet")
    }

    /// "Book this" on a service's page goes to picking a barber for it.
    func testBookThisFromServicePage() {
        openTab("Services")
        tap("service-vip")
        XCTAssertTrue(element("bookServiceButton").waitForExistence(timeout: 10))
        assertAboveTabBar("bookServiceButton")
        tapPinned("bookServiceButton")
        let izzy = element("choose-israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75")
        XCTAssertTrue(izzy.waitForExistence(timeout: 10), "Book this didn't open step 2 for VIP")
        XCTAssertFalse(element("chooseFirstAvailable").exists, "Only Izzy offers VIP")
        assertSelectedTab("Book")
    }

    func testBookingFromBarberPage() {
        openTeam()
        tap("barber-julian-ramos")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 10))
        assertAboveTabBar("bookBarberButton")
        tapPinned("bookBarberButton")

        // Barber first: Julian's menu, then his haircut.
        let haircut = element("barberService-julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a")
        XCTAssertTrue(haircut.waitForExistence(timeout: 10), "Booking with Julian didn't show his services")
        assertSelectedTab("Book")
        scroll(toReveal: haircut)
        haircut.tap()

        waitForCalendar()
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        assertSquireURL(webPageURL(), contains: "/barber/julian-ramos/services?preselect=bbb0c294-87a6-465d-9f55-6f579dcb399a")
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tapToClose(element("notBookedButton"), closing: element("confirmBookingSheet"), "\"I didn't book\" didn't close the sheet")
    }

    func testCalendarNavigation() {
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseFirstAvailable")
        waitForCalendar()

        let title = element("calendarMonthTitle")
        let month = title.label
        XCTAssertFalse(month.isEmpty)
        let next = element("calendarNextMonth")
        let previous = element("calendarPrevMonth")
        XCTAssertTrue(next.exists && previous.exists)
        // Booking opens 60 days ahead, so there's always a later month.
        XCTAssertTrue(next.isEnabled, "There should be a next month to show")

        next.tap()
        XCTAssertTrue(waitUntil(title, toMatch: NSPredicate(format: "label != %@", month)), "The month didn't change")
        XCTAssertTrue(previous.isEnabled, "There should be a way back")

        previous.tap()
        XCTAssertTrue(waitUntil(title, toMatch: NSPredicate(format: "label == %@", month)), "Didn't come back to \(month)")

        // The ✕ in the bar goes straight back to step 1.
        tapPinned("bookingStartOver")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 10), "Start over didn't go back to step 1")
        XCTAssertTrue(waitForDisappearance(of: element("continueToReview")), "The calendar is still showing")
    }

    func testRemovingAnAppointment() {
        openTab("Book")
        tap("bookService-haircut")
        tap("chooseFirstAvailable")
        waitForCalendar()
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        _ = webPageURL()
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tapInSheet("saveAppointmentButton")
        XCTAssertTrue(element("confirmDoneButton").waitForExistence(timeout: 10))
        tapToClose(element("confirmDoneButton"), closing: element("confirmBookingSheet"), "Done didn't close the sheet")

        // The ticket is the menu: Add to Calendar, Directions, Call the shop, Remove from this iPhone.
        let card = element("upcomingAppointment")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The saved appointment isn't on the Book tab")
        tap("appointmentMoreButton")
        let removeItem = app.buttons
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "removeAppointmentButton", "Remove from this iPhone"))
            .firstMatch
        XCTAssertTrue(removeItem.waitForExistence(timeout: 10), "The ticket's menu has no Remove from this iPhone")
        removeItem.tap()
        // The menu must be gone before looking for the dialog's "Remove".
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Call the shop"]), "The menu didn't close")

        // "Remove this appointment?"
        _ = app.staticTexts["Remove this appointment?"].waitForExistence(timeout: 10)
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Remove")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No confirmation to remove")
        confirm.tap()

        XCTAssertTrue(waitForDisappearance(of: card), "The appointment is still there")
        openTab("Home")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))
        XCTAssertFalse(element("upcomingAppointment").exists)
        XCTAssertTrue(element("homeWalkIns").exists)
    }

    func testBrowsingEverythingOnSquire() {
        openTab("Book")
        tap("browseSquireButton")
        let url = webPageURL()
        XCTAssertTrue(url.hasPrefix("https://getsquire.com/booking/book/izzy-clipz-oceanside"), url)
        XCTAssertFalse(url.contains("preselect="), url)
        XCTAssertTrue(url.contains("utm_source=izzyclipz-app"), url)
        closeWebPage()
        // No time was picked in the app, so there's nothing to save.
        XCTAssertFalse(element("confirmBookingSheet").waitForExistence(timeout: 3))
    }

    // MARK: Shop and the bag

    func testShop() {
        openTab("Shop")
        let bag = element("shopBagButton")
        XCTAssertTrue(bag.waitForExistence(timeout: 10), "The Shop didn't open")
        XCTAssertEqual(bag.value as? String, "Empty")
        XCTAssertTrue(element("product-blue-bravo-hair-gel-16oz").exists, "No featured gel")
        XCTAssertTrue(element("quickAdd-blue-bravo-hair-gel-16oz").exists, "The featured gel has no quick add")
        screenshot("18-Shop")

        // The grid: one tile per item. The 4 oz gels are a size on the gel's own page.
        let clay = element("product-bravo-matte-clay")
        scroll(toReveal: clay)
        XCTAssertTrue(element("quickAdd-bravo-matte-clay").exists)
        XCTAssertFalse(element("product-blue-bravo-hair-gel-4oz").exists, "The 4 oz gel should be a size, not a tile")
        screenshot("19-Shop-Products")

        tap("shopAllBravo")
        let store = webPageURL()
        XCTAssertEqual(URL(string: store)?.host, "bravohairgel.com", store)
        XCTAssertTrue(store.contains("utm_source=izzyclipz-app"), store)
        closeWebPage()

        tap("product-blue-bravo-hair-gel-16oz")
        XCTAssertTrue(element("addToBagButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element("productBagButton").exists)
        screenshot("20-Product-Detail")

        tap("buyProductButton")
        let product = webPageURL()
        XCTAssertTrue(product.hasPrefix("https://bravohairgel.com/products/blue-bravo-hair-gel-16oz"), product)
        XCTAssertTrue(product.contains("utm_source=izzyclipz-app"), product)
        closeWebPage()
        XCTAssertTrue(element("buyProductButton").waitForExistence(timeout: 10))
    }

    /// Blue Hair Gel comes in 4 oz and 16 oz: the size chips change the price, the bar, the store
    /// link and what goes in the bag.
    func testProductSizes() {
        openTab("Shop")
        XCTAssertTrue(element("shopBagButton").waitForExistence(timeout: 10), "The Shop didn't open")
        tap("product-blue-bravo-hair-gel-16oz")

        let big = element("productSize-blue-bravo-hair-gel-16oz")
        let small = element("productSize-blue-bravo-hair-gel-4oz")
        let add = element("addToBagButton")
        XCTAssertTrue(big.waitForExistence(timeout: 10), "No size chips")
        XCTAssertTrue(small.exists)
        XCTAssertTrue(add.exists)
        XCTAssertTrue(big.isSelected, "The page opens on the size that was tapped")
        XCTAssertFalse(small.isSelected)
        XCTAssertTrue(big.label.contains("$17.99"), big.label)
        XCTAssertTrue(small.label.contains("$11.99"), small.label)
        XCTAssertTrue(add.label.contains("$17.99"), add.label)
        XCTAssertTrue(priceBlock("$17.99").exists, "The page doesn't show the 16 oz price")

        tap("productSize-blue-bravo-hair-gel-4oz")
        XCTAssertTrue(waitUntil(small, toMatch: selected()), "4 oz didn't become the picked size")
        XCTAssertFalse(big.isSelected)
        XCTAssertTrue(
            waitUntil(add, toMatch: NSPredicate(format: "label CONTAINS %@", "$11.99")),
            "Picking 4 oz didn't change the price: \(add.label)"
        )
        XCTAssertTrue(add.label.contains("4 oz"), add.label)
        XCTAssertTrue(priceBlock("$11.99").waitForExistence(timeout: 10), "The page doesn't show the 4 oz price")
        screenshot("32-Product-Sizes")

        // The quantity multiplies the bar's price.
        let quantity = element("productQuantity")
        scroll(toReveal: quantity)
        increment(quantity, until: add, matches: NSPredicate(format: "label CONTAINS %@", "$23.98"), "Two 4 oz gels should be $23.98")
        XCTAssertTrue(waitUntil(quantity, toMatch: NSPredicate(format: "value == %@", "2")), "The quantity stepper doesn't show 2")

        // The store link follows the size.
        tap("buyProductButton")
        let url = webPageURL()
        XCTAssertTrue(url.hasPrefix("https://bravohairgel.com/products/blue-bravo-hair-gel-4oz"), url)
        closeWebPage()

        // Two 4 oz gels go in the bag.
        assertAboveTabBar("addToBagButton")
        tapPinned("addToBagButton")
        let bagButton = element("productBagButton")
        XCTAssertTrue(waitUntil(bagButton, toMatch: NSPredicate(format: "value == %@", "2 items")), "The bag didn't take two gels")
        tapPinned("productBagButton")
        XCTAssertTrue(element("bagSheet").waitForExistence(timeout: 10), "The bag didn't open")
        let line = element("bagStepper-blue-bravo-hair-gel-4oz")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "The 4 oz gel isn't in the bag")
        XCTAssertFalse(element("bagStepper-blue-bravo-hair-gel-16oz").exists, "The 16 oz gel went in instead")
        XCTAssertEqual(element("bagSubtotal").value as? String, "$23.98")
        tapToClose(element("bagDoneButton"), closing: element("bagSheet"), "The bag didn't close")
    }

    /// Quick add two products, change a quantity in the bag, check out on Bravo with the items in its
    /// cart, then answer "Did you finish checking out?" both ways.
    func testBagAndCheckoutOnBravo() {
        openTab("Shop")
        let bagButton = element("shopBagButton")
        XCTAssertTrue(bagButton.waitForExistence(timeout: 10), "The Shop didn't open")
        XCTAssertEqual(bagButton.value as? String, "Empty")

        tap("quickAdd-blue-bravo-hair-gel-16oz")
        XCTAssertTrue(waitUntil(bagButton, toMatch: NSPredicate(format: "value == %@", "1 item")), "Quick add didn't put the gel in the bag")
        tap("quickAdd-bravo-matte-clay")
        XCTAssertTrue(waitUntil(bagButton, toMatch: NSPredicate(format: "value == %@", "2 items")), "Quick add didn't put the clay in the bag")
        let barBag = element("shopBarBagButton")
        if barBag.exists {
            // Once the header has scrolled away, the navigation bar carries the bag too.
            XCTAssertEqual(barBag.value as? String, "2 items")
        }

        tap("shopBagButton")
        XCTAssertTrue(element("bagSheet").waitForExistence(timeout: 10), "The bag didn't open")
        let gel = element("bagStepper-blue-bravo-hair-gel-16oz")
        XCTAssertTrue(gel.waitForExistence(timeout: 10), "The gel isn't in the bag")
        XCTAssertTrue(element("bagStepper-bravo-matte-clay").exists, "The clay isn't in the bag")
        XCTAssertTrue(element("bagRemove-bravo-matte-clay").exists)
        let subtotal = element("bagSubtotal")
        XCTAssertEqual(subtotal.value as? String, "$35.98")

        // A second gel with the stepper: $53.97, $10.03 short of Bravo's free shipping at $64.
        increment(gel, until: subtotal, matches: NSPredicate(format: "value == %@", "$53.97"), "The stepper didn't add a gel")
        XCTAssertTrue(waitUntil(gel, toMatch: NSPredicate(format: "value == %@", "2")), "The gel's stepper doesn't show 2")
        let meter = element("bagShippingMeter")
        XCTAssertTrue(meter.label.contains("$10.03 away"), meter.label)
        screenshot("28-Shop-Bag")

        // Bravo's checkout, with both items in its cart. Tapped where it is: dragging a sheet can close it.
        tapInSheet("bagCheckoutButton")
        let checkout = webPageURL()
        XCTAssertTrue(checkout.hasPrefix("https://bravohairgel.com/cart/"), checkout)
        XCTAssertTrue(checkout.contains("44210083561649:2"), "Two 16 oz Blue Hair Gels should be in the cart: \(checkout)")
        XCTAssertTrue(checkout.contains("43628496945329:1"), "One Matte Clay should be in the cart: \(checkout)")
        XCTAssertEqual(checkout, "https://bravohairgel.com/cart/44210083561649:2,43628496945329:1")
        screenshot("29-Bag-Checkout")
        closeWebPage()

        // "Not yet" keeps the bag as it was.
        answerCheckoutQuestion("Not yet")
        XCTAssertTrue(waitUntil(bagButton, toMatch: NSPredicate(format: "value == %@", "3 items")), "Not yet changed the bag")

        // Checking out again, and this time it went through.
        tap("shopBagButton")
        XCTAssertTrue(element("bagSheet").waitForExistence(timeout: 10), "The bag didn't open again")
        XCTAssertEqual(element("bagSubtotal").value as? String, "$53.97")
        tapInSheet("bagCheckoutButton")
        XCTAssertEqual(webPageURL(), checkout)
        closeWebPage()
        answerCheckoutQuestion("Yes, empty my bag")
        XCTAssertTrue(waitUntil(bagButton, toMatch: NSPredicate(format: "value == %@", "Empty")), "The bag wasn't emptied")

        // The bag is empty now.
        tap("shopBagButton")
        let browse = element("bagBrowseShopButton")
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "The bag isn't empty after checking out")
        XCTAssertFalse(element("bagCheckoutButton").exists)
        XCTAssertFalse(element("bagSubtotal").exists)
        tapToClose(browse, closing: element("bagSheet"), "Browse the shop didn't close the bag")
        assertSelectedTab("Shop")
    }

    // MARK: Visit, reviews, gallery, reminders

    func testVisit() {
        openTab("Visit")
        XCTAssertTrue(element("visitDirectionsButton").waitForExistence(timeout: 10), "The Visit tab didn't show")
        XCTAssertTrue(element("visitCallButton").exists)
        XCTAssertTrue(element("copyAddressButton").exists)
        XCTAssertTrue(element("mapDirections").exists)
        screenshot("21-Visit")

        scroll(toReveal: element("hours-sunday"))
        XCTAssertTrue(element("hours-monday").exists)
        screenshot("22-Visit-Hours")

        let review = element("leaveReviewButton")
        scroll(toReveal: review)
        XCTAssertTrue(element("visitSeeAllReviews").exists)
        XCTAssertTrue(element("visitWebsiteLink").exists)
        screenshot("23-Visit-Reviews")

        review.tap()
        let url = webPageURL()
        XCTAssertTrue(url.contains("search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8"), url)
        closeWebPage()
    }

    func testReviews() {
        tap("seeAllReviews")
        XCTAssertTrue(element("readGoogleReviewsButton").waitForExistence(timeout: 10), "Reviews didn't open")
        screenshot("24-Reviews")

        let review = element("leaveReviewButton")
        scroll(toReveal: review)
        review.tap()
        let url = webPageURL()
        XCTAssertTrue(url.contains("search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8"), url)
        closeWebPage()
    }

    func testGallery() {
        tap("seeAllPhotos")
        let first = element("photo-1")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(element("galleryInstagramButton").exists)
        screenshot("25-Gallery")

        first.tap()
        let close = element("closePhoto")
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        screenshot("26-Photo-Viewer")
        // Read while the viewer is up; the button is pinned, so paging doesn't move it.
        let closeFrame = close.frame
        app.swipeLeft()
        // A tap that lands while the swiped page is still settling can be taken
        // by the paging scroll, so try a few times before calling it a failure.
        // It's tapped by screen position: after a page swipe XCUI can fail to
        // "scroll" the pinned button into view, and nothing is looked up again
        // at tap time.
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
        tapPinned("remindersButton")
        XCTAssertTrue(element("remindersToggle").waitForExistence(timeout: 10))
        screenshot("27-Reminders")
        tapToClose(element("remindersDone"), closing: element("remindersToggle"), "Done didn't close reminder settings")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))
    }

    // MARK: Booking helpers

    /// Waits for the calendar step: a day already picked, Continue waiting for a time.
    private func waitForCalendar(file: StaticString = #filePath, line: UInt = #line) {
        let next = element("continueToReview")
        XCTAssertTrue(next.waitForExistence(timeout: 15), "The calendar didn't open", file: file, line: line)
        XCTAssertTrue(element("calendarMonthTitle").waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(element("selectedDayLabel").waitForExistence(timeout: 10), "No day was picked to start with", file: file, line: line)
        XCTAssertFalse(next.isEnabled, "Continue should wait for a time", file: file, line: line)
    }

    /// Taps the earliest start time on the picked day.
    private func pickFirstTime(file: StaticString = #filePath, line: UInt = #line) {
        let time = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "time-")).firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 10), "The picked day has no times", file: file, line: line)
        scroll(toReveal: time, file: file, line: line)
        time.tap()
        XCTAssertTrue(
            waitUntil(element("continueToReview"), toMatch: NSPredicate(format: "isEnabled == true")),
            "Continue didn't turn on after picking a time",
            file: file,
            line: line
        )
    }

    /// Taps Continue (pinned above the tab bar) and waits for the review.
    private func continueToReview(file: StaticString = #filePath, line: UInt = #line) {
        let next = element("continueToReview")
        let review = element("confirmOnSquireButton")
        assertAboveTabBar("continueToReview", file: file, line: line)
        next.tap()
        if !review.waitForExistence(timeout: 10), next.exists {
            if !next.isEnabled {
                // The clock passed :00 or :30, so the picked time slipped inside
                // the lead time and the calendar's minute check dropped it.
                pickFirstTime(file: file, line: line)
            }
            // Retries a swallowed tap; the calendar ignores a second push.
            next.tap()
        }
        XCTAssertTrue(review.waitForExistence(timeout: 10), "The review didn't open", file: file, line: line)
    }

    private func confirmOnSquire(file: StaticString = #filePath, line: UInt = #line) {
        let confirm = element("confirmOnSquireButton")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), file: file, line: line)
        scroll(toReveal: confirm, file: file, line: line)
        confirm.tap()
    }

    private func assertSquireURL(_ url: String, contains expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(url.hasPrefix("https://getsquire.com/booking/book/izzy-clipz-oceanside"), url, file: file, line: line)
        XCTAssertTrue(url.contains(expected), "\(url) doesn't contain \(expected)", file: file, line: line)
        XCTAssertTrue(url.contains("utm_source=izzyclipz-app"), url, file: file, line: line)
    }

    /// Goes back through the booking steps to step 1 with the back button.
    private func popToBookingStart(file: StaticString = #filePath, line: UInt = #line) {
        let start = element("bookService-haircut")
        var pops = 0
        while !start.waitForExistence(timeout: 3), pops < 4 {
            // No back button: already at step 1, just slow to show.
            guard let back = backButton() else { break }
            back.tap()
            pops += 1
        }
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Couldn't get back to step 1", file: file, line: line)
    }

    /// "STEP 3 / 4 · TIME" over the pole progress bar, in the navigation bar.
    private func stepIndicator(_ step: Int, _ name: String) -> XCUIElement {
        labeled("Step \(step) of 4: \(name)")
    }

    // MARK: Bag helpers

    /// Answers "Did you finish checking out?", asked once Bravo's checkout closes.
    private func answerCheckoutQuestion(_ answer: String, file: StaticString = #filePath, line: UInt = #line) {
        let question = "Did you finish checking out?"
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Closing the checkout didn't ask whether it was finished", file: file, line: line)
        XCTAssertTrue(alert.label == question || alert.staticTexts[question].exists, "Unexpected alert: \(alert.label)", file: file, line: line)
        tapToClose(alert.buttons[answer], closing: alert, "\"\(answer)\" didn't close the question", file: file, line: line)
    }

    /// The product page's price with its source: "$11.99, price from bravohairgel.com".
    private func priceBlock(_ price: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(price), price from")).firstMatch
    }

    /// Taps a quantity stepper's "+" and waits for what that changes. The stepper is drawn as
    /// − / count / +, so the "+" is tapped where it's drawn, the 44 pt square at its right end.
    /// VoiceOver (and XCUI) see a standard stepper instead, so if nothing changed, its Increment
    /// button gets one more try.
    private func increment(
        _ stepper: XCUIElement,
        until effect: XCUIElement,
        matches predicate: NSPredicate,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "Missing \(stepper)", file: file, line: line)
        stepper.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -22, dy: 0))
            .tap()
        if !waitUntil(effect, toMatch: predicate, timeout: 5), stepper.buttons["Increment"].exists {
            stepper.buttons["Increment"].tap()
        }
        XCTAssertTrue(waitUntil(effect, toMatch: predicate), message, file: file, line: line)
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
        "Shop": "shopBagButton",
        "Visit": "visitDirectionsButton",
    ]

    private func tabButton(_ name: String) -> XCUIElement {
        app.buttons["tab.\(name.lowercased())"]
    }

    /// Taps a tab in the floating bar and waits until it's the selected one. The barber pole sweeps
    /// across for 0.46 s but never blocks taps, so this doesn't wait for it: callers wait for an
    /// element of the new tab. A tab that's already selected isn't tapped, since that would pop it
    /// to its first screen.
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

    /// Only `name` carries the selected trait.
    private func assertSelectedTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil(tabButton(name), toMatch: selected()), "\(name) isn't the selected tab", file: file, line: line)
        for other in Self.tabs where other != name {
            XCTAssertFalse(tabButton(other).isSelected, "\(other) is marked selected too", file: file, line: line)
        }
    }

    /// With `pushed` on screen in tab `name`, taps that (selected) tab again: back to its first screen.
    private func assertRetappingPopsToRoot(_ name: String, pushed: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(pushed).waitForExistence(timeout: 10), "\(pushed) didn't open", file: file, line: line)
        assertSelectedTab(name, file: file, line: line)
        tabButton(name).tap()
        XCTAssertTrue(waitForDisappearance(of: element(pushed)), "Tapping \(name) again didn't pop \(pushed)", file: file, line: line)
        let root = element(Self.landmarks[name] ?? "")
        XCTAssertTrue(root.waitForExistence(timeout: 10), "\(name) isn't back at its first screen", file: file, line: line)
        assertSelectedTab(name, file: file, line: line)
    }

    // MARK: Navigation

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Any element whose accessibility label is `label`, ignoring case.
    private func labeled(_ label: String) -> XCUIElement {
        // Case-insensitive: the type styles set many labels in capitals, and VoiceOver (and XCUI)
        // get them that way, e.g. "YOUR BARBER".
        app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
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

    /// Checks that a bar pinned to the bottom of a screen sits fully above the floating tab bar. On
    /// iOS 26, pushed screens once drew Continue, Book this and Add to bag behind it.
    private func assertAboveTabBar(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        let tabBar = app.buttons["tab.home"]
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)", file: file, line: line)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Missing the tab bar", file: file, line: line)
        XCTAssertLessThanOrEqual(
            target.frame.maxY, tabBar.frame.minY,
            "\(identifier) is behind the tab bar (\(target.frame) vs \(tabBar.frame))",
            file: file, line: line
        )
    }

    /// Taps a button in a sheet without dragging first: dragging a sheet can move or close it. XCUI
    /// scrolls the sheet's own content if the button is below the fold.
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
        let back = backButton()
        XCTAssertNotNil(back, "No back button", file: file, line: line)
        back?.tap()
    }

    /// The back button of the screen on top. Every tab keeps its own navigation bar alive behind the
    /// selected one, so this takes the first bar's leading button that can be tapped.
    private func backButton() -> XCUIElement? {
        guard app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10) else { return nil }
        let leading = app.navigationBars.allElementsBoundByIndex.map { $0.buttons.element(boundBy: 0) }
        return leading.first { $0.exists && $0.isHittable } ?? app.navigationBars.buttons.element(boundBy: 0)
    }

    // MARK: Scrolling

    private enum DragDirection {
        case up
        case down
    }

    /// Scrolls until the element is on screen and clear of what's pinned over the content: the
    /// navigation bar and Home's header at the top, and at the bottom the floating tab bar (its
    /// raised Book button tops out about 0.85 of the way down a 6.3" iPhone) and the sticky bars
    /// above it (Continue, Book this, Add to bag: their tops sit about 0.75 down).
    ///
    /// Scrolls with slow drags that stop dead, so a short element can't fly
    /// past the screen in one fling. Elements above the screen scroll down.
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
        // Below the status and navigation bars too: a clear bar still takes touches, and XCUI can
        // report what's under it as hittable.
        return midY >= screen.minY + screen.height * 0.2
            && midY <= screen.minY + screen.height * 0.7
    }

    /// Drags the page about a third of the screen, holding still before
    /// letting go so it doesn't keep scrolling. It starts at 0.7, above the
    /// sticky bars and the tab bar, so the drag lands on the page.
    private func drag(_ direction: DragDirection) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
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

    /// Taps a button that closes a sheet, page or alert, and waits for it to go.
    /// Taps once more if both are still there: slow simulators occasionally
    /// drop a tap. It doesn't scroll first, since dragging a sheet can close it.
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
