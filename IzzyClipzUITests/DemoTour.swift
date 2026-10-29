import XCTest

/// A paced walkthrough of the real app, recorded on video by the "Demo video"
/// workflow. Unlike the other UI tests it opens the live Squire and Bravo
/// pages, so it only runs when asked: `TEST_RUNNER_DEMO_TOUR=1 xcodebuild test ...`.
///
/// It books the way a client would: a service, a barber, a day and time on
/// the app's calendar, the review, Squire, then "Did you book it?" to save
/// the appointment. Steps are lenient on purpose: a slow web page shouldn't
/// stop the tour, but anything that goes wrong is logged and attached as a
/// screenshot.
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
        // Home: the logo, booking, Bravo, the team, fresh cuts and reviews
        expect("homeBookButton")
        pause(3)
        capture("Home")
        for _ in 0..<6 {
            app.swipeUp(velocity: .slow)
            pause(1.2)
        }
        capture("Home-Reviews")

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
        tap("continueToReview")
        pause(2.5)
        capture("Review")

        // Squire, then "Did you book it?"
        tap("confirmOnSquireButton")
        showWebPage(named: "Squire-Carlos-Haircut")
        expect("confirmBookingSheet")
        pause(2.5)
        capture("Did-You-Book")
        tap("saveAppointmentButton")
        allowNotificationsIfAsked()
        pause(2.5)
        capture("Booking-Saved")
        tap("confirmDoneButton")
        pause(1.5)

        // Home now shows the appointment
        tab("Home")
        pause(1)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(2.5)
        capture("Home-Appointment")

        // The team: Izzy's profile, made the favorite
        tap("meetTeamButton")
        pause(2.5)
        capture("Team")
        tap("barber-israel-flores")
        pause(2.5)
        tap("favoriteButton")
        pause(1.5)
        capture("Izzy-Profile")
        app.swipeUp(velocity: .slow)
        pause(2)
        back()
        pause(1)
        back()
        pause(1)

        // Shop: Bravo's products and one on bravohairgel.com
        tab("Shop")
        pause(3)
        capture("Shop")
        tap("product-blue-bravo-hair-gel-16oz")
        pause(2.5)
        capture("Bravo-Blue-Gel")
        tap("buyProductButton")
        showWebPage(named: "Bravo-Store", firstLook: 6, fullLoad: 6)

        // Visit: map, hours, info and reviews
        tab("Visit")
        pause(3)
        capture("Visit")
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            pause(1.5)
        }
        capture("Visit-Info")

        // Gallery and the photo viewer
        tab("Home")
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
        tap("closePhoto")
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

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        guard button.waitForExistence(timeout: 5) else {
            note("Missing tab \(name)")
            return
        }
        button.tap()
    }

    private func back() {
        let button = app.navigationBars.buttons.firstMatch
        guard button.waitForExistence(timeout: 5) else {
            note("No back button")
            return
        }
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
