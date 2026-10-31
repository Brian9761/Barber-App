import XCTest

/// A paced walkthrough of the app, recorded on video by the "Demo video" workflow. It only runs
/// when asked: `TEST_RUNNER_DEMO_TOUR=1 xcodebuild test ...`.
///
/// It runs on the app's in-memory server (`-ui-testing`), so it never books anything real and
/// needs no network: the sample products and reviews it shows are test data. Animations stay on
/// (`-keepAnimations`) so the video looks like the app.
///
/// It books the way a client would: a service, a barber, a day and time from the live calendar,
/// their details, the review ("No payment now"), then "You're booked" and the appointment on
/// Home. Then the crew, the shop's products, the reviews, Visit and the gallery.
///
/// Steps are lenient on purpose: anything that goes wrong is logged and attached as a screenshot,
/// and the tour goes on.
final class DemoTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEMO_TOUR"] == "1",
            "Run with TEST_RUNNER_DEMO_TOUR=1 to record the demo"
        )
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-keepAnimations", "-fakeYelp"]
        app.launch()
    }

    func testTour() {
        // Home: the photos, Book, Directions and Call, then the menu, the crew, reviews and the shop
        expect("homeBookButton")
        pause(3)
        capture("Home")

        // A lap of the tab bar: no animation between tabs.
        for name in ["Services", "Book", "Shop", "Visit", "Home"] {
            tab(name)
            pause(2)
        }
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            pause(1.2)
        }
        capture("Home-Crew")
        reveal(element("homeShopCard"))
        pause(1.2)
        capture("Home-Reviews-And-Shop")

        // Services: open Haircut and book Carlos
        tab("Services")
        pause(2)
        tap("service-haircut")
        pause(2.5)
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        reveal(carlos)
        pause(1)
        capture("Haircut-Detail")
        tap(carlos, named: "Book with Carlos")

        // Day and time from the live calendar
        expect("selectedDayLabel")
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
        tapPinned("continueToDetails")
        pause(2)

        // Details, then the review
        type("Sample Client", into: "nameField")
        type("4425550123", into: "phoneField")
        pause(1.5)
        capture("Details")
        tapPinned("continueToReview")
        pause(2.5)
        capture("Review")

        // Booked
        tapPinned("bookAppointmentButton")
        expect("bookedTitle")
        pause(3)
        capture("Booked")
        tapPinned("bookedDoneButton")
        pause(2)
        capture("Book-Appointments")

        // Home now shows the appointment
        tab("Home")
        pause(1)
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
        back()
        pause(1)
        back()
        pause(1)

        // The reviews, live from Google and Yelp
        tap("homeReviews")
        pause(3)
        capture("Reviews")
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            pause(1.5)
        }
        capture("Reviews-Yelp")
        back()
        pause(1)

        // Shop: the shop's own products
        tab("Shop")
        pause(3)
        capture("Shop")
        tap("product-sample-pomade")
        pause(2.5)
        capture("Product")
        back()
        pause(1)

        // Visit: the storefront, Directions, hours, the map and links
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
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(1)
        tap("seeAllPhotos")
        pause(2.5)
        tap("photo-2")
        pause(2.5)
        app.swipeLeft()
        pause(2)
        capture("Photo-Viewer")
        let close = element("closePhoto")
        if close.waitForExistence(timeout: 5) {
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            note("Missing closePhoto")
        }
        pause(2)
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func expect(_ identifier: String) {
        if !element(identifier).waitForExistence(timeout: 15) {
            note("Missing \(identifier)")
        }
    }

    private func tap(_ identifier: String) {
        tap(element(identifier), named: identifier)
    }

    /// Scrolls to an element and taps it.
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

    /// Taps something pinned in place (a sticky bar, a navigation bar button) without scrolling.
    private func tapPinned(_ identifier: String) {
        let target = element(identifier)
        guard target.waitForExistence(timeout: 10) else {
            note("Couldn't find \(identifier)")
            return
        }
        target.tap()
    }

    private func type(_ text: String, into identifier: String) {
        let field = element(identifier)
        guard field.waitForExistence(timeout: 10) else {
            note("Couldn't find \(identifier)")
            return
        }
        field.tap()
        pause(0.8)
        field.typeText(text)
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
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

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
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
