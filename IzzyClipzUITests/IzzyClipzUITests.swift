import XCTest

/// Walks through every screen the way a client would, checks where each
/// booking path leads, and saves screenshots along the way.
///
/// The app runs with `-ui-testing`, which starts from empty settings and
/// shows the Squire link instead of loading Squire, so tests don't depend on
/// the network or on what a previous run left behind.
final class IzzyClipzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: Screens

    func testHome() {
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element("shopStatus").exists)
        XCTAssertTrue(element("callButton").exists)
        XCTAssertTrue(element("directionsButton").exists)
        screenshot("01-Home")

        scroll(toReveal: element("popular-haircut"))
        screenshot("02-Home-Popular")

        scroll(toReveal: element("seeAllPhotos"))
        screenshot("03-Home-Gallery")
    }

    func testServicesMenu() {
        openTab("Services")
        XCTAssertTrue(app.navigationBars["Services"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("service-haircut").exists)
        screenshot("04-Services")

        element("service-haircut").tap()
        XCTAssertTrue(element("bookFirstAvailable").waitForExistence(timeout: 5))
        screenshot("05-Service-Detail")
    }

    func testSearchingServices() {
        openTab("Services")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("beard")
        XCTAssertTrue(element("service-haircut-and-beard").waitForExistence(timeout: 5))
        XCTAssertFalse(element("service-perm").exists)
        screenshot("06-Services-Search")
    }

    func testTeam() {
        openTab("Team")
        XCTAssertTrue(element("barber-israel-flores").waitForExistence(timeout: 5))
        screenshot("07-Team")

        element("barber-carlos-rafael").tap()
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 5))
        screenshot("08-Barber-Detail")
    }

    func testVisit() {
        openTab("Visit")
        XCTAssertTrue(element("mapDirections").waitForExistence(timeout: 5))
        screenshot("09-Visit")
        app.swipeUp()
        screenshot("10-Visit-Hours")
        app.swipeUp()
        screenshot("11-Visit-Info")
    }

    func testGallery() {
        scroll(toReveal: element("seeAllPhotos"))
        element("seeAllPhotos").tap()
        XCTAssertTrue(element("photo-1").waitForExistence(timeout: 5))
        screenshot("12-Gallery")

        element("photo-1").tap()
        XCTAssertTrue(element("closePhoto").waitForExistence(timeout: 5))
        screenshot("13-Photo-Viewer")
        app.swipeLeft()
        element("closePhoto").tap()
        XCTAssertTrue(element("photo-1").waitForExistence(timeout: 5))
    }

    func testReminderSettings() {
        element("remindersButton").tap()
        XCTAssertTrue(element("remindersToggle").waitForExistence(timeout: 5))
        screenshot("14-Reminders")
        element("remindersDone").tap()
        XCTAssertTrue(element("homeBookButton").waitForExistence(timeout: 5))
    }

    // MARK: Booking paths

    func testBookTabFirstAvailable() {
        openTab("Book")
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 5))
        screenshot("15-Book-Service")

        element("bookService-haircut").tap()
        XCTAssertTrue(element("chooseFirstAvailable").waitForExistence(timeout: 5))
        screenshot("16-Book-Barber")

        element("chooseFirstAvailable").tap()
        XCTAssertTrue(element("chooseTimeButton").waitForExistence(timeout: 5))
        screenshot("17-Book-Review")

        element("chooseTimeButton").tap()
        assertBookingURL(contains: "/booking/book/izzy-clipz-oceanside/barber/any/services?preselect=bbb0c294-87a6-465d-9f55-6f579dcb399a")
    }

    func testBookTabSpecificBarber() {
        openTab("Book")
        let vip = element("bookService-vip")
        scroll(toReveal: vip)
        vip.tap()
        let izzy = element("choose-israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75")
        XCTAssertTrue(izzy.waitForExistence(timeout: 5))
        XCTAssertFalse(element("chooseFirstAvailable").exists, "Only Izzy offers VIP")
        izzy.tap()
        XCTAssertTrue(element("chooseTimeButton").waitForExistence(timeout: 5))
        element("chooseTimeButton").tap()
        assertBookingURL(contains: "/barber/israel-flores/services?preselect=9a33be59-43eb-445c-9c18-6435125b1f75")
    }

    func testBookingFromAServicePage() {
        openTab("Services")
        XCTAssertTrue(element("service-haircut").waitForExistence(timeout: 5))
        element("service-haircut").tap()
        let carlos = element("book-carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41")
        scroll(toReveal: carlos)
        carlos.tap()
        assertBookingURL(contains: "/barber/carlos-rafael/services?preselect=9343fc67-b196-4604-987e-a4a9b6b4cc41")
    }

    func testBookingFromABarberPage() {
        openTab("Team")
        let julian = element("barber-julian-ramos")
        scroll(toReveal: julian)
        julian.tap()
        XCTAssertTrue(element("bookBarberButton").waitForExistence(timeout: 5))
        element("bookBarberButton").tap()
        assertBookingURL(contains: "/barber/julian-ramos/services?utm_source=izzyclipz-app")
    }

    func testHomeBookButtonOpensTheBookTab() {
        element("homeBookButton").tap()
        XCTAssertTrue(element("bookService-haircut").waitForExistence(timeout: 5))
    }

    func testFavoriteBarberShowsOnHome() {
        openTab("Team")
        let flowxbori = element("barber-flowxbori")
        scroll(toReveal: flowxbori)
        flowxbori.tap()
        XCTAssertTrue(element("favoriteButton").waitForExistence(timeout: 5))
        element("favoriteButton").tap()
        openTab("Home")
        XCTAssertTrue(app.staticTexts["Your barber"].waitForExistence(timeout: 5))
        let book = app.buttons["Book with Flowxbori"]
        scroll(toReveal: book)
        book.tap()
        assertBookingURL(contains: "/barber/flowxbori/services")
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)")
        tab.tap()
    }

    private func scroll(toReveal target: XCUIElement, maxSwipes: Int = 10) {
        var swipes = 0
        while !(target.exists && target.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(target.exists && target.isHittable, "Couldn't scroll to \(target)")
    }

    private func assertBookingURL(contains expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["bookingURL"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "Booking didn't open", file: file, line: line)
        XCTAssertTrue(label.label.hasPrefix("https://getsquire.com/"), label.label, file: file, line: line)
        XCTAssertTrue(label.label.contains(expected), "\(label.label) doesn't contain \(expected)", file: file, line: line)
        XCTAssertTrue(label.label.contains("utm_source=izzyclipz-app"), file: file, line: line)
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForDisappearance(of: label), "Booking didn't close", file: file, line: line)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
