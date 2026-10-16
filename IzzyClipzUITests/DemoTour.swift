import XCTest

/// A paced walkthrough of the real app, recorded on video by the "Demo video"
/// workflow. Unlike the other UI tests it opens the live Squire booking pages,
/// so it only runs when asked: `TEST_RUNNER_DEMO_TOUR=1 xcodebuild test ...`.
///
/// Steps are lenient on purpose: a slow web page shouldn't stop the tour,
/// but anything that goes wrong is logged and attached as a screenshot.
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
        // Home
        expect("homeBookButton")
        pause(3)
        capture("Home")
        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            pause(1.2)
        }
        capture("Home-Reviews")

        // Services: browse, open Haircut, book Carlos on Squire
        tab("Services")
        pause(2)
        tap("service-haircut")
        pause(2.5)
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        reveal(carlos)
        pause(1)
        capture("Haircut-Detail")
        carlos.tap()
        showSquire(named: "Squire-Carlos-Haircut")

        // Team: Izzy's profile, make him the favorite
        tab("Team")
        pause(2)
        tap("barber-israel-flores")
        pause(2.5)
        tap("favoriteButton")
        pause(1.5)
        capture("Izzy-Profile")
        app.swipeUp(velocity: .slow)
        pause(2)
        app.navigationBars.buttons.firstMatch.tap()
        pause(1)

        // Book: Haircut & Beard with whoever is free first
        tab("Book")
        pause(2)
        let combo = element("bookService-haircut-and-beard")
        reveal(combo)
        pause(1)
        combo.tap()
        pause(2.5)
        tap("chooseFirstAvailable")
        pause(2.5)
        capture("Review")
        tap("chooseTimeButton")
        showSquire(named: "Squire-First-Available")

        // Home now shows the favorite barber
        tab("Home")
        pause(1)
        app.swipeDown(velocity: .fast)
        pause(2.5)
        capture("Home-Favorite")

        // Visit: map, hours, info
        tab("Visit")
        pause(3)
        capture("Visit")
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            pause(1.5)
        }
        capture("Visit-Info")

        // Gallery and the photo viewer
        tab("Home")
        pause(1)
        let seeAll = element("seeAllPhotos")
        reveal(seeAll)
        seeAll.tap()
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

    /// Waits for the Squire page to load, shows it, then closes it.
    private func showSquire(named name: String) {
        pause(9)
        capture(name)
        let done = app.buttons.matching(NSPredicate(format: "label IN {'Done', 'Close'}")).firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
        } else {
            note("No Done button on the Squire sheet; swiping it away")
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        pause(1.5)
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
        let target = element(identifier)
        guard target.waitForExistence(timeout: 8) else {
            note("Couldn't find \(identifier)")
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
