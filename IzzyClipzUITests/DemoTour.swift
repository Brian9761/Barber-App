import XCTest

/// A paced walkthrough of the real app, recorded on video by the "Demo video"
/// workflow. Unlike the other UI tests it opens the live Squire and Bravo
/// pages, including Bravo's checkout with the bag's items in its cart, so it
/// only runs when asked: `TEST_RUNNER_DEMO_TOUR=1 xcodebuild test ...`.
///
/// It books the way a client would: a service, a barber, a day and time on
/// the app's calendar, the review, Squire, then "Did you book it?" to save
/// the appointment (BOOKED). Then the crew, the Bravo bag and its checkout,
/// Visit and the gallery. Every tab switch plays the barber-pole sweep. It
/// never taps an Instagram link: outside UI tests those leave the app.
///
/// Steps are lenient on purpose: a slow web page shouldn't stop the tour, but
/// anything that goes wrong is logged and attached as a screenshot.
final class DemoTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEMO_TOUR"] == "1",
            "Run with TEST_RUNNER_DEMO_TOUR=1 to record the demo"
        )
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testTour() {
        // Home: the hero, Book, Directions and Call, then the menu, the crew, reviews, Instagram and Bravo
        expect("homeBookButton")
        pause(3)
        capture("Home")
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            pause(1.2)
        }
        capture("Home-Crew")
        reveal(element("instagramButton"))
        pause(1.2)
        capture("Home-Instagram")
        app.swipeUp(velocity: .slow)
        pause(1.2)
        capture("Home-Bravo")

        // Services: open Haircut and book Carlos on the calendar
        tab("Services")
        pause(2)
        tap("service-haircut")
        pause(2.5)
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        reveal(carlos)
        pause(1)
        capture("Haircut-Detail")
        tap(carlos, named: "Book with Carlos")

        // Day and time, then the review
        expect("continueToReview")
        pause(2.5)
        capture("Calendar")
        tap("calendarNextMonth")
        pause(1.5)
        tap("calendarPrevMonth")
        pause(1.5)
        let firstTime = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "time-")).firstMatch
        tap(firstTime, named: "the first open time")
        pause(1.5)
        capture("Time-Picked")
        tapPinned("continueToReview")
        pause(2.5)
        capture("Review")

        // Squire, then "Did you book it?" and BOOKED
        tap("confirmOnSquireButton")
        showWebPage(named: "Squire-Carlos-Haircut")
        expect("confirmBookingSheet")
        pause(2.5)
        capture("Did-You-Book")
        tapPinned("saveAppointmentButton")
        allowNotificationsIfAsked()
        pause(2.5)
        capture("Booked")
        tapPinned("confirmDoneButton")
        pause(1.5)
        capture("Book-Appointments")

        // Home now shows the ticket
        tab("Home")
        pause(1)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(2.5)
        capture("Home-Appointment")

        // The crew: Izzy's profile, made the favorite
        tap("meetTeamButton")
        pause(2.5)
        capture("Team")
        tap("barber-israel-flores")
        pause(2.5)
        tapPinned("favoriteButton")
        pause(1.5)
        capture("Izzy-Profile")
        app.swipeUp(velocity: .slow)
        pause(2)
        back()
        pause(1)
        back()
        pause(1)

        // Shop: two quick adds, the gel's sizes, then the bag and Bravo's checkout
        tab("Shop")
        pause(3)
        capture("Shop")
        tap("quickAdd-blue-bravo-hair-gel-16oz")
        pause(1.5)
        tap("quickAdd-bravo-matte-clay")
        pause(1.5)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(1)
        tap("product-blue-bravo-hair-gel-16oz")
        pause(2.5)
        tap("productSize-blue-bravo-hair-gel-4oz")
        pause(2)
        capture("Bravo-Gel-4oz")
        tap("productSize-blue-bravo-hair-gel-16oz")
        pause(1.5)
        tapPinned("productBagButton")
        expect("bagSheet")
        pause(2.5)
        capture("Bag")
        // The stepper's "+" is the 44 pt square at its right end.
        let gel = element("bagStepper-blue-bravo-hair-gel-16oz")
        if gel.waitForExistence(timeout: 5) {
            gel.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -22, dy: 0)).tap()
        } else {
            note("Missing the gel's stepper in the bag")
        }
        pause(2)
        capture("Bag-Two-Gels")
        tapPinned("bagCheckoutButton")
        showWebPage(named: "Bravo-Checkout", firstLook: 6, fullLoad: 8)
        answerCheckoutQuestion("Yes, empty my bag")
        pause(1.5)
        back()
        pause(1)

        // Visit: the storefront, Directions, hours, the map, Instagram and links
        tab("Visit")
        pause(3)
        capture("Visit")
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            pause(1.5)
        }
        capture("Visit-Info")
        reveal(element("visitInstagramMessage"))
        pause(1.5)
        capture("Visit-Instagram")

        // Gallery and the photo viewer
        tab("Home")
        pause(1)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(1)
        tap("seeAllPhotos")
        pause(2.5)
        tap("photo-2")
        pause(2.5)
        app.swipeLeft()
        pause(2)
        app.swipeLeft()
        pause(2)
        capture("Photo-Viewer")
        // Tapped where it is: after a page swipe XCUI can fail to "scroll" the
        // pinned button into view even though it's on screen.
        let close = element("closePhoto")
        if close.waitForExistence(timeout: 5) {
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            note("Missing closePhoto")
        }
        pause(2)
    }

    // MARK: Helpers

    /// Waits for a web page to load, shows it, then closes it.
    ///
    /// Squire sits behind a Cloudflare check that can take a while to clear
    /// for data-center traffic like CI runners, so it gets a generous wait.
    private func showWebPage(named name: String, firstLook: TimeInterval = 12, fullLoad: TimeInterval = 18) {
        pause(firstLook)
        capture("\(name)-\(Int(firstLook))s")
        pause(fullLoad)
        capture(name)
        let done = app.buttons.matching(NSPredicate(format: "label IN {'Done', 'Close'}")).firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
        } else {
            note("No Done button on the \(name) sheet; swiping it away")
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        pause(1.5)
    }

    /// "Did you finish checking out?", asked once Bravo's checkout closes.
    private func answerCheckoutQuestion(_ answer: String) {
        let button = app.alerts.buttons[answer]
        if button.waitForExistence(timeout: 10) {
            pause(1.5)
            button.tap()
        } else {
            note("No checkout question")
        }
    }

    /// Saving with reminders on asks for notification permission the first time.
    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            pause(1.5)
            allow.tap()
        } else {
            print("DEMO TOUR: No notification permission prompt")
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func expect(_ identifier: String) {
        if !element(identifier).waitForExistence(timeout: 10) {
            note("Missing \(identifier)")
        }
    }

    private func tap(_ identifier: String) {
        tap(element(identifier), named: identifier)
    }

    /// Scrolls to an element and taps it. Elements in lazy grids only exist
    /// once they're close to the screen, so a missing one is scrolled for.
    private func tap(_ target: XCUIElement, named name: String) {
        if !target.waitForExistence(timeout: 8) {
            reveal(target)
        }
        guard target.exists else {
            note("Couldn't find \(name)")
            return
        }
        reveal(target)
        target.tap()
    }

    /// Taps something pinned in place (a sticky bar, a navigation bar button, a
    /// sheet's button) without scrolling to it first.
    private func tapPinned(_ identifier: String) {
        let target = element(identifier)
        guard target.waitForExistence(timeout: 8) else {
            note("Couldn't find \(identifier)")
            return
        }
        target.tap()
    }

    /// Taps a tab in the floating bar; the barber pole sweeps across to it.
    private func tab(_ name: String) {
        let button = app.buttons["tab.\(name.lowercased())"]
        guard button.waitForExistence(timeout: 5) else {
            note("Missing tab \(name)")
            return
        }
        button.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
        if XCTWaiter().wait(for: [selected], timeout: 5) != .completed {
            note("\(name) didn't become the selected tab")
        }
    }

    /// The back button of the screen on top: the first navigation bar button
    /// that can be tapped (every tab keeps its own bar alive behind the others).
    private func back() {
        guard app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5) else {
            note("No back button")
            return
        }
        let leading = app.navigationBars.allElementsBoundByIndex.map { $0.buttons.element(boundBy: 0) }
        let button = leading.first { $0.exists && $0.isHittable } ?? app.navigationBars.buttons.firstMatch
        button.tap()
    }

    private func reveal(_ target: XCUIElement) {
        var swipes = 0
        while !(target.exists && target.isHittable), swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ message: String) {
        print("DEMO TOUR: \(message)")
        capture("Problem-\(message)")
    }
}
