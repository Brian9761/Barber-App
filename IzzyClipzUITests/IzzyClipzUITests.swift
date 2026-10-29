import XCTest

/// Walks through every screen the way a client would, books through the
/// in-app calendar, checks where each Squire, Bravo and Google link leads,
/// and saves screenshots along the way.
///
/// The app runs with `-ui-testing`, which starts from empty settings, shows
/// a link preview instead of loading web pages, never asks for notification
/// permission, and stands in for Apple's "New Event" screen, so tests don't
/// depend on the network or on what a previous run left behind.
///
/// The booking calendar starts from today, so no test names a date: they
/// take the day the calendar picks and its first open time.
final class IzzyClipzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 15), "The app didn't start on Home")
    }

    // MARK: Home

    func testHome() {
        XCTAssertTrue(element("shopStatus").exists)
        XCTAssertTrue(element("callButton").exists)
        XCTAssertTrue(element("directionsButton").exists)
        XCTAssertTrue(element("remindersButton").exists)
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing is booked yet")
        screenshot("01-Home")

        // Scrolled content should pass under the navy scrim, not the bare status bar.
        drag(.up)
        XCTAssertTrue(element("popular-haircut").exists)
        screenshot("02-Home-Scrolled")

        scroll(toReveal: element("homeBarber-israel-flores"))
        XCTAssertTrue(element("bravoBanner").exists)
        XCTAssertTrue(element("meetTeamButton").exists)
        screenshot("03-Home-Bravo")

        // The Bravo banner leads to the Shop tab.
        tap("bravoBanner")
        XCTAssertTrue(element("shopAllBravo").waitForExistence(timeout: 5), "The Bravo banner didn't open the Shop")
        openTab("Home")

        scroll(toReveal: element("seeAllReviews"))
        screenshot("04-Home-Reviews")
    }

    func testHomeBookButtonOpensBooking() {
        tap("homeBookButton")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 5))
    }

    // MARK: Services and the team

    func testServices() {
        openTab("Services")
        XCTAssertTrue(app.navigationBars["Services"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 5))
        screenshot("05-Services")

        tap("service-haircut")
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 5))
        XCTAssertTrue(element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41").exists)
        screenshot("06-Service-Detail")

        goBack()
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) || !search.isHittable {
            // The search bar can start tucked under the large title.
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("beard")
        XCTAssertTrue(element("service-haircut-and-beard").waitForExistence(timeout: 5))
        XCTAssertFalse(element("service-perm").exists)
        screenshot("07-Services-Search")
    }

    func testTeamAndBarber() {
        openTeam()
        screenshot("08-Team")

        tap("barber-carlos-rafael")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 5))
        XCTAssertTrue(element("favoriteButton").exists)
        screenshot("09-Barber-Detail")
    }

    func testFavoriteBarberShowsOnHome() {
        XCTAssertFalse(app.staticTexts["Your barber"].exists, "No favorite yet")
        openTeam()
        tap("barber-flowxbori")
        let favorite = element("favoriteButton")
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
        XCTAssertTrue(
            waitUntil(favorite, toMatch: NSPredicate(format: "label CONTAINS %@", "Remove favorite")),
            "Flowxbori didn't become the favorite"
        )

        goBack()
        XCTAssertTrue(element("barber-flowxbori").waitForExistence(timeout: 5))
        goBack()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Your barber"].waitForExistence(timeout: 5))
        let book = app.buttons["Book with Flowxbori"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        scroll(toReveal: book)
        book.tap()

        // Barber first: their own menu, to pick a service.
        let service = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "barberService-flowxbori/")).firstMatch
        XCTAssertTrue(service.waitForExistence(timeout: 5), "Booking with Flowxbori didn't show their services")
    }

    // MARK: Booking

    func testBookingFlowFirstAvailable() {
        openTab("Book")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 5))
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing is booked yet")
        screenshot("10-Book-Service")

        tap("bookService-haircut")
        XCTAssertTrue(element("chooseFirstAvailable").waitForExistence(timeout: 5))
        screenshot("11-Book-Barber")

        tap("chooseFirstAvailable")
        waitForCalendar()
        screenshot("12-Book-Calendar")

        pickFirstTime()
        screenshot("13-Book-Time-Picked")

        continueToReview()
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
        let remind = element("remindMeToggle")
        XCTAssertTrue(remind.exists)
        XCTAssertEqual(remind.value as? String, "1", "Reminders should start on")
        screenshot("15-Confirm-Booking")

        tap("saveAppointmentButton")
        XCTAssertTrue(element("addToCalendarButton").waitForExistence(timeout: 5), "Saving didn't show the success screen")
        XCTAssertTrue(element("confirmDoneButton").exists)
        screenshot("16-Booking-Saved")

        tap("addToCalendarButton")
        let eventTitle = element("calendarEventTitle")
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 10), "Add to Calendar didn't open")
        XCTAssertTrue(eventTitle.label.contains("Haircut"), eventTitle.label)
        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(waitForDisappearance(of: eventTitle, timeout: 10), "Add to Calendar didn't close")

        // Saved: the Book tab is back at step 1 with the appointment on top, and Home shows it.
        XCTAssertTrue(element("upcomingAppointment").waitForExistence(timeout: 5))
        XCTAssertTrue(element("bookService-haircut").exists)
        openTab("Home")
        XCTAssertTrue(element("upcomingAppointment").waitForExistence(timeout: 5))
        scroll(toReveal: element("appointmentAddToCalendar"))
        screenshot("17-Home-Appointment")
    }

    func testBookingSpecificBarberVIP() {
        openTab("Book")
        let vip = element("bookService-vip")
        XCTAssertTrue(vip.waitForExistence(timeout: 5))
        scroll(toReveal: vip)
        vip.tap()
        let izzy = element("choose-israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75")
        XCTAssertTrue(izzy.waitForExistence(timeout: 5))
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
        tap("notBookedButton")
        XCTAssertTrue(waitForDisappearance(of: element("confirmBookingSheet")), "\"I didn't book\" didn't close the sheet")

        // Nothing was saved: back on the review, and no appointment anywhere.
        XCTAssertTrue(element("confirmOnSquireButton").waitForExistence(timeout: 5))
        popToBookingStart()
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing should be saved")
        openTab("Home")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 5))
        XCTAssertFalse(element("upcomingAppointment").exists, "Nothing should be saved")
    }

    func testBookingFromServicePage() {
        openTab("Services")
        tap("service-haircut")
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        XCTAssertTrue(carlos.waitForExistence(timeout: 5))
        scroll(toReveal: carlos)
        carlos.tap()

        // Straight to the calendar on the Book tab, with Carlos and his haircut chosen.
        waitForCalendar()
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        assertSquireURL(webPageURL(), contains: "/barber/carlos-rafael/services?preselect=9343fc67-b196-4604-987e-a4a9b6b4cc41")
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tap("notBookedButton")
        XCTAssertTrue(waitForDisappearance(of: element("confirmBookingSheet")))
    }

    func testBookingFromBarberPage() {
        openTeam()
        tap("barber-julian-ramos")
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 5))
        tap("bookBarberButton")

        // Barber first: Julian's menu, then his haircut.
        let haircut = element("barberService-julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a")
        XCTAssertTrue(haircut.waitForExistence(timeout: 5), "Booking with Julian didn't show his services")
        scroll(toReveal: haircut)
        haircut.tap()

        waitForCalendar()
        pickFirstTime()
        continueToReview()
        confirmOnSquire()
        assertSquireURL(webPageURL(), contains: "/barber/julian-ramos/services?preselect=bbb0c294-87a6-465d-9f55-6f579dcb399a")
        closeWebPage()

        XCTAssertTrue(element("confirmBookingSheet").waitForExistence(timeout: 10), "Closing Squire didn't ask to save the booking")
        tap("notBookedButton")
        XCTAssertTrue(waitForDisappearance(of: element("confirmBookingSheet")))
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
        tap("saveAppointmentButton")
        XCTAssertTrue(element("confirmDoneButton").waitForExistence(timeout: 5))
        tap("confirmDoneButton")
        XCTAssertTrue(waitForDisappearance(of: element("confirmBookingSheet")))

        let card = element("upcomingAppointment")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "The saved appointment isn't on the Book tab")
        tap("appointmentMoreButton")
        let removeItem = app.buttons
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "removeAppointmentButton", "Remove"))
            .firstMatch
        XCTAssertTrue(removeItem.waitForExistence(timeout: 5), "The menu has no Remove")
        removeItem.tap()

        // "Remove this appointment?" Once it's up, the menu is gone and its
        // own "Remove" is the only one left.
        _ = app.staticTexts["Remove this appointment?"].waitForExistence(timeout: 5)
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Remove")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation to remove")
        confirm.tap()

        XCTAssertTrue(waitForDisappearance(of: card), "The appointment is still there")
        openTab("Home")
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 5))
        XCTAssertFalse(element("upcomingAppointment").exists)
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
        XCTAssertFalse(element("confirmBookingSheet").waitForExistence(timeout: 2))
    }

    // MARK: Shop

    func testShop() {
        openTab("Shop")
        XCTAssertTrue(element("shopAllBravo").waitForExistence(timeout: 5))
        screenshot("18-Shop")

        tap("shopAllBravo")
        let store = webPageURL()
        XCTAssertEqual(URL(string: store)?.host, "bravohairgel.com", store)
        XCTAssertTrue(store.contains("utm_source=izzyclipz-app"), store)
        closeWebPage()

        // The product grids load as they scroll into view.
        let gel = element("product-blue-bravo-hair-gel-16oz")
        scroll(toReveal: gel)
        screenshot("19-Shop-Products")

        gel.tap()
        XCTAssertTrue(element("buyProductButton").waitForExistence(timeout: 5))
        screenshot("20-Product-Detail")

        tap("buyProductButton")
        let product = webPageURL()
        XCTAssertTrue(product.hasPrefix("https://bravohairgel.com/products/blue-bravo-hair-gel-16oz"), product)
        XCTAssertTrue(product.contains("utm_source=izzyclipz-app"), product)
        closeWebPage()
        XCTAssertTrue(element("buyProductButton").waitForExistence(timeout: 5))
    }

    // MARK: Visit, reviews, gallery, reminders

    func testVisit() {
        openTab("Visit")
        XCTAssertTrue(element("mapDirections").waitForExistence(timeout: 5))
        screenshot("21-Visit")

        scroll(toReveal: element("hours-sunday"))
        XCTAssertTrue(element("hours-monday").exists)
        screenshot("22-Visit-Hours")

        let review = element("leaveReviewButton")
        scroll(toReveal: review)
        screenshot("23-Visit-Reviews")

        review.tap()
        let url = webPageURL()
        XCTAssertTrue(url.contains("search.google.com/local/writereview?placeid=ChIJGz5HChRv3IARYJJy_6jyRm8"), url)
        closeWebPage()
    }

    func testReviews() {
        tap("seeAllReviews")
        XCTAssertTrue(element("readGoogleReviewsButton").waitForExistence(timeout: 5), "Reviews didn't open")
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
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        screenshot("25-Gallery")

        first.tap()
        let close = element("closePhoto")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        screenshot("26-Photo-Viewer")
        app.swipeLeft()
        // A tap that lands while the swiped page is still settling can be taken
        // by the paging scroll, so try a few times before calling it a failure.
        // It's tapped where it is: after a page swipe XCUI can fail to "scroll"
        // the pinned button into view even though it's on screen.
        var closed = false
        for _ in 0..<3 where !closed {
            guard close.exists else {
                closed = true
                break
            }
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            closed = waitForDisappearance(of: close, timeout: 5)
        }
        XCTAssertTrue(closed, "The photo viewer didn't close")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }

    func testReminderSettings() {
        tap("remindersButton")
        XCTAssertTrue(element("remindersToggle").waitForExistence(timeout: 5))
        screenshot("27-Reminders")
        element("remindersDone").tap()
        XCTAssertTrue(waitForDisappearance(of: element("remindersToggle")))
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 5))
    }

    // MARK: Booking helpers

    /// Waits for the calendar step: a day already picked, Continue waiting for a time.
    private func waitForCalendar(file: StaticString = #filePath, line: UInt = #line) {
        let next = element("continueToReview")
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The calendar didn't open", file: file, line: line)
        XCTAssertTrue(element("calendarMonthTitle").waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element("selectedDayLabel").waitForExistence(timeout: 5), "No day was picked to start with", file: file, line: line)
        XCTAssertFalse(next.isEnabled, "Continue should wait for a time", file: file, line: line)
    }

    /// Taps the earliest start time on the picked day.
    private func pickFirstTime(file: StaticString = #filePath, line: UInt = #line) {
        let time = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "time-")).firstMatch
        scroll(toReveal: time, file: file, line: line)
        time.tap()
        XCTAssertTrue(
            waitUntil(element("continueToReview"), toMatch: NSPredicate(format: "isEnabled == true")),
            "Continue didn't turn on after picking a time",
            file: file,
            line: line
        )
    }

    private func continueToReview(file: StaticString = #filePath, line: UInt = #line) {
        let next = element("continueToReview")
        let review = element("confirmOnSquireButton")
        next.tap()
        if !review.waitForExistence(timeout: 5), !next.isEnabled {
            // The clock passed :00 or :30, so the picked time slipped inside
            // the lead time and the calendar's minute check dropped it. Pick
            // the new first time.
            pickFirstTime(file: file, line: line)
            next.tap()
        }
        XCTAssertTrue(review.waitForExistence(timeout: 5), "The review didn't open", file: file, line: line)
    }

    private func confirmOnSquire(file: StaticString = #filePath, line: UInt = #line) {
        let confirm = element("confirmOnSquireButton")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), file: file, line: line)
        scroll(toReveal: confirm, file: file, line: line)
        confirm.tap()
    }

    private func assertSquireURL(_ url: String, contains expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(url.hasPrefix("https://getsquire.com/booking/book/izzy-clipz-oceanside"), url, file: file, line: line)
        XCTAssertTrue(url.contains(expected), "\(url) doesn't contain \(expected)", file: file, line: line)
        XCTAssertTrue(url.contains("utm_source=izzyclipz-app"), url, file: file, line: line)
    }

    /// Goes back through the booking steps to step 1.
    private func popToBookingStart(file: StaticString = #filePath, line: UInt = #line) {
        let start = element("bookService-haircut")
        var pops = 0
        while !start.waitForExistence(timeout: 2), pops < 4 {
            goBack(file: file, line: line)
            pops += 1
        }
        XCTAssertTrue(start.exists, "Couldn't get back to step 1", file: file, line: line)
    }

    // MARK: Web pages

    /// The address of the web page on screen (a preview while UI testing).
    private func webPageURL(file: StaticString = #filePath, line: UInt = #line) -> String {
        let text = app.staticTexts["webURL"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), "The web page didn't open", file: file, line: line)
        return text.label
    }

    private func closeWebPage(file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts["webURL"]
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The web page has no Done button", file: file, line: line)
        done.tap()
        XCTAssertTrue(waitForDisappearance(of: text), "The web page didn't close", file: file, line: line)
    }

    // MARK: Navigation

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element, scrolls it into view and taps it.
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing \(identifier)", file: file, line: line)
        scroll(toReveal: target, file: file, line: line)
        target.tap()
    }

    private func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)", file: file, line: line)
        tab.tap()
    }

    /// Home → "Meet everyone".
    private func openTeam(file: StaticString = #filePath, line: UInt = #line) {
        tap("meetTeamButton", file: file, line: line)
        XCTAssertTrue(element("barber-israel-flores").waitForExistence(timeout: 5), "The team didn't open", file: file, line: line)
    }

    private func goBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No back button", file: file, line: line)
        back.tap()
    }

    // MARK: Scrolling

    private enum DragDirection {
        case up
        case down
    }

    /// Scrolls until the element is on screen and clear of the bars at the
    /// bottom (the tab bar, and the Continue bar on the calendar).
    ///
    /// Scrolls with slow drags that stop dead, so a short element can't fly
    /// past the screen in one fling. Elements above the screen scroll down.
    private func scroll(toReveal target: XCUIElement, maxDrags: Int = 14, file: StaticString = #filePath, line: UInt = #line) {
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
        return target.frame.midY <= screen.minY + screen.height * 0.7
    }

    /// Drags the page about a third of the screen, holding still before
    /// letting go so it doesn't keep scrolling.
    private func drag(_ direction: DragDirection) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let (start, end) = direction == .up ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    // MARK: Waiting

    private func waitUntil(_ element: XCUIElement, toMatch predicate: NSPredicate, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
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
