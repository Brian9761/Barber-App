import XCTest

/// The Analytics tab, the way the shop owner uses it, with screenshots ("O70-Analytics-Today", …).
///
/// The app runs with `-ui-testing`: the in-memory sample server with its 8 weeks of sample history
/// (`FakeSampleHistory`), and a fixed "now" of Monday, November 2, 2026 at 11:05 AM in the shop, so
/// the numbers are the same on every run. This year, Izzy sells the most, Carlos sells the most
/// products, and Cristian does the most services for the most clients, each by a wide margin. The
/// helpers are IzzyClipzBusinessUITests' own.
final class AnalyticsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: String...) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-signed-in"] + arguments
        app.launch()
        XCTAssertTrue(tabButton("Schedule").waitForExistence(timeout: 30), "The app didn't open signed in")
    }

    /// Opens Analytics and waits for the numbers.
    private func openAnalytics(file: StaticString = #filePath, line: UInt = #line) {
        openTab("Analytics", file: file, line: line)
        let live = element("analyticsLive")
        XCTAssertTrue(waitForLabel(live, containing: "Live · Updated 11:05 AM"), "Got: \(live.label)", file: file, line: line)
    }

    // MARK: Analytics

    func testTodayForTheWholeShop() {
        launch()
        openAnalytics()
        XCTAssertTrue(app.navigationBars["Analytics"].exists)
        XCTAssertTrue(element("scope-shop").isSelected, "the whole shop to start")
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "Today: Mon, Nov 2 · Whole shop"))
        // This morning's visits count: the total isn't $0, and it's compared with yesterday (Sunday).
        let total = element("totalSalesValue")
        XCTAssertTrue(total.label.contains("$"), "Got: \(total.label)")
        XCTAssertFalse(total.label.hasSuffix(" $0"), "Got: \(total.label)")
        XCTAssertTrue(element("totalSalesChange").label.contains("yesterday"), "Got: \(element("totalSalesChange").label)")
        XCTAssertTrue(element("split-services").exists)
        screenshot("O70-Analytics-Today")

        XCTAssertTrue(reveal("topBarber").label.contains("Carlos"), "Diego's $63 checkout (a cut and the pomade) beats Marcus's $40 cut")
        XCTAssertTrue(reveal("leaderboard-5").exists, "every barber, even at $0")
        XCTAssertTrue(reveal("byBarberCard").exists, "for one day, each barber's sales instead of one bar")
        XCTAssertTrue(app.staticTexts["Today by barber"].exists)
        XCTAssertTrue(reveal("tile-chair").label.contains("of open hours had a client"))
        XCTAssertTrue(reveal("tile-upcoming").exists)
        screenshot("O71-Analytics-Today-Productivity")
    }

    func testSwitchingTheBarberAndThePeriod() {
        launch()
        openAnalytics()
        tapSegment("Year", of: "periodPicker")
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "This year: Jan 1 – Nov 2 · Whole shop"))
        XCTAssertTrue(waitForLabel(element("analyticsLive"), containing: "Live"))
        XCTAssertTrue(waitForLabel(reveal("topBarber"), containing: "Izzy"), "Izzy sold the most this year")
        XCTAssertTrue(app.staticTexts["Top sales barber"].exists)
        screenshot("O72-Analytics-Year")
        XCTAssertTrue(reveal("dailySalesCard").exists)
        XCTAssertTrue(app.staticTexts["Sales by month"].exists, "a year goes by month")
        XCTAssertTrue(reveal("product-Sample pomade").exists, "products sold")
        XCTAssertTrue(reveal("service-haircut").exists, "top services")

        // One barber: his numbers, and the leaderboard and top barber stay the whole shop's.
        tap("scope-israel-flores", searchingFirst: .up)
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "This year: Jan 1 – Nov 2 · Izzy"))
        XCTAssertTrue(waitUntil(element("scope-israel-flores"), toMatch: NSPredicate(format: "isSelected == true")))
        XCTAssertTrue(waitForLabel(element("analyticsLive"), containing: "Live"))
        XCTAssertTrue(app.staticTexts["Top sales barber (whole shop)"].waitForExistence(timeout: 20))
        let izzy = reveal("leaderboard-1")
        XCTAssertTrue(izzy.label.contains("Izzy"), "Got: \(izzy.label)")
        XCTAssertTrue(izzy.isSelected, "the barber picked is highlighted")
        screenshot("O73-Analytics-Izzy-Year")

        // The month so far, by day: tapping a bar shows that day's numbers.
        tapSegment("Month", of: "periodPicker")
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "This month: Nov 1 – Nov 2 · Izzy"))
        XCTAssertTrue(waitForLabel(element("analyticsLive"), containing: "Live"))
        let detail = reveal("dailyDetail")
        XCTAssertTrue(app.staticTexts["Daily sales"].exists)
        XCTAssertTrue(detail.label.contains("Tap a bar"), "Got: \(detail.label)")
        tapChart("dailySalesChart", inCard: "dailySalesCard")
        XCTAssertTrue(waitUntil(detail, toMatch: NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Sun, Nov 1", "Mon, Nov 2")), "Got: \(detail.label)")
        screenshot("O74-Analytics-Month-Day-Tapped")

        // Back to the whole shop.
        tap("scope-shop", searchingFirst: .up)
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "This month: Nov 1 – Nov 2 · Whole shop"))
    }

    func testTheLeaderboardMetricChangesTheOrder() {
        launch()
        openAnalytics()
        tapSegment("Year", of: "periodPicker")
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "This year"))
        XCTAssertTrue(waitForLabel(element("analyticsLive"), containing: "Live"))
        let first = reveal("leaderboard-1")
        XCTAssertTrue(waitForLabel(first, containing: "Izzy"), "by sales: Got \(first.label)")
        XCTAssertTrue(first.label.contains("gold medal"))

        tapSegment("Products", of: "leaderboardMetric")
        XCTAssertTrue(waitForLabel(element("leaderboard-1"), containing: "Carlos"), "by products: Got \(element("leaderboard-1").label)")
        XCTAssertTrue(element("leaderboard-1").label.contains("products"))
        screenshot("O75-Analytics-Leaderboard-Products")

        tapSegment("Services", of: "leaderboardMetric")
        XCTAssertTrue(waitForLabel(element("leaderboard-1"), containing: "Cristian"), "by services: Got \(element("leaderboard-1").label)")
        tapSegment("Clients", of: "leaderboardMetric")
        XCTAssertTrue(waitForLabel(element("leaderboard-1"), containing: "Cristian"), "by clients: Got \(element("leaderboard-1").label)")
        XCTAssertTrue(element("leaderboard-1").label.contains("clients"))
        tapSegment("Sales", of: "leaderboardMetric")
        XCTAssertTrue(waitForLabel(element("leaderboard-1"), containing: "Izzy"))
    }

    func testTheInfoSheetsExplainTheNumbers() {
        launch()
        openAnalytics()
        tap("info-chair")
        let text = element("infoText")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "The tile's ⓘ didn't open its explanation")
        XCTAssertTrue(text.label.contains("Booked time divided by open hours"), "Got: \(text.label)")
        XCTAssertTrue(app.staticTexts["Chair time booked"].exists)
        screenshot("O76-Analytics-Info")
        tap("infoDone")
        XCTAssertTrue(waitForDisappearance(of: text))

        tap("info-change", searchingFirst: .up)
        XCTAssertTrue(waitForLabel(element("infoText"), containing: "the same number of days just before"))
        tap("infoDone")
        XCTAssertTrue(waitForDisappearance(of: element("infoText")))

        tap("analyticsHelp", searchingFirst: .up)
        let privacy = reveal("help-privacy")
        XCTAssertTrue(privacy.label.contains("every number here stays the same"), "Got: \(privacy.label)")
        screenshot("O77-Analytics-What-The-Numbers-Mean")
        tap("helpDone", searchingFirst: .up)
        XCTAssertTrue(waitForDisappearance(of: element("helpDone")))
    }

    func testChosenDates() {
        launch()
        openAnalytics()
        tap("customDates")
        let summary = element("customSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Custom… didn't open the dates")
        XCTAssertTrue(summary.label.contains("Mon, Nov 2 · 1 day"), "Got: \(summary.label)")
        screenshot("O78-Analytics-Custom-Dates")
        tap("showCustomDates")
        XCTAssertTrue(waitForDisappearance(of: summary))
        XCTAssertTrue(waitForLabel(element("periodLine"), containing: "Mon, Nov 2 · Whole shop"))
        XCTAssertTrue(waitForLabel(element("customDates"), containing: "Change dates"))
    }

    func testAnEmptyShop() {
        launch("-fake-empty")
        openAnalytics()
        XCTAssertTrue(waitForLabel(element("noSales"), containing: "No sales yet today. Sales show up here as you check clients out."))
        XCTAssertTrue(reveal("noTopBarber").exists)
        XCTAssertTrue(reveal("noProducts").label.contains("No products sold in this period."))
        screenshot("O79-Analytics-Empty")
    }

    func testOfflineOffersToTryAgain() {
        launch("-fake-offline")
        openTab("Analytics")
        let message = app.staticTexts["Couldn't load the numbers"]
        XCTAssertTrue(message.waitForExistence(timeout: 20), "No message when the numbers can't load")
        tap("retryAnalytics")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "Still offline: the message stays")
        XCTAssertTrue(element("retryAnalytics").exists)
    }

    // MARK: Helpers (IzzyClipzBusinessUITests' own)

    /// Taps a segment of a segmented control: inside the control when SwiftUI passes its identifier
    /// on, otherwise the segment's button by its name.
    private func tapSegment(_ name: String, of identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        var segment = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if element(identifier).waitForExistence(timeout: 5) {
            let control = reveal(identifier, searchingFirst: .up, file: file, line: line)
            if control.buttons[name].exists { segment = control.buttons[name] }
        }
        XCTAssertTrue(segment.waitForExistence(timeout: 10), "No \(name) in \(identifier)", file: file, line: line)
        segment.tap()
        if !waitUntil(segment, toMatch: NSPredicate(format: "isSelected == true"), timeout: 10) {
            // Slow simulators occasionally drop a tap.
            segment.tap()
        }
        XCTAssertTrue(waitUntil(segment, toMatch: NSPredicate(format: "isSelected == true")), "\(name) wasn't chosen", file: file, line: line)
    }

    /// Taps the middle of a chart: the chart itself when it's an element, otherwise its card's middle.
    private func tapChart(_ identifier: String, inCard card: String) {
        let chart = element(identifier)
        if chart.exists, !chart.frame.isEmpty {
            chart.tap()
        } else {
            reveal(card).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        }
    }

    private func tabButton(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name]
    }

    private func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tabButton(name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing the \(name) tab", file: file, line: line)
        tab.tap()
        if !waitUntil(tab, toMatch: NSPredicate(format: "isSelected == true"), timeout: 10) {
            // Slow simulators occasionally drop a tap.
            tab.tap()
        }
        XCTAssertTrue(waitUntil(tab, toMatch: NSPredicate(format: "isSelected == true")), "\(name) didn't open", file: file, line: line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element, scrolls it into view if needed, and taps it.
    private func tap(_ identifier: String, searchingFirst first: Direction = .down, file: StaticString = #filePath, line: UInt = #line) {
        reveal(identifier, searchingFirst: first, file: file, line: line).tap()
    }

    private enum Direction {
        /// Further down the screen (a swipe up).
        case down
        /// Back up the screen (a swipe down).
        case up
    }

    /// Finds an element and scrolls it onto the screen.
    @discardableResult
    private func reveal(_ identifier: String, searchingFirst first: Direction = .down, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let target = element(identifier)
        // Most are on screen already, or show up once the screen has loaded.
        if target.waitForExistence(timeout: 8), isOnScreen(target) {
            return target
        }
        let other: Direction = first == .down ? .up : .down
        for attempt in 0..<16 {
            if isOnScreen(target) {
                settle(target)
                return target
            }
            if target.exists, !target.frame.isEmpty {
                // Built but out of sight: scroll toward it.
                drag(target.frame.midY < app.frame.midY ? .up : .down)
            } else {
                drag(attempt < 8 ? first : other)
            }
        }
        XCTAssertTrue(isOnScreen(target), "Couldn't find \(identifier) on the screen", file: file, line: line)
        return target
    }

    /// On screen and tappable. isHittable is only asked about an element whose middle is on the screen.
    private func isOnScreen(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        let frame = target.frame
        guard !frame.isEmpty, app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return target.isHittable
    }

    /// Drags the page about a third of the screen and holds still before letting go, so it doesn't keep gliding.
    private func drag(_ direction: Direction) {
        let lowY = 0.7
        let highY = 0.35
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: lowY))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: highY))
        let (start, end) = direction == .down ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    /// Waits until the element stops moving, up to two seconds.
    private func settle(_ target: XCUIElement) {
        var last = target.frame
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            guard target.exists else { return }
            let now = target.frame
            if now == last { return }
            last = now
        }
    }

    /// Waits for what's on screen to match. The default is long because a busy simulator can take
    /// seconds to answer each look at the screen; a match ends the wait straight away.
    private func waitUntil(_ element: XCUIElement, toMatch predicate: NSPredicate, timeout: TimeInterval = 20) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 20) -> Bool {
        waitUntil(element, toMatch: NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        waitUntil(element, toMatch: NSPredicate(format: "exists == false"), timeout: timeout)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
