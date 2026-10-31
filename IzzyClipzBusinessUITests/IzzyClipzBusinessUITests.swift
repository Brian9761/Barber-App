import XCTest

/// Every flow of the owner app, the way the shop owner uses it, with
/// screenshots ("O01-Sign-In", "O02-…").
///
/// The app runs with `-ui-testing`: the in-memory sample server, an in-memory
/// keychain, the simulated card reader ("Test mode — no real charge"), and a
/// fixed "now" of Monday, November 2, 2026 at 11:05 AM in the shop, so the
/// schedule and the open times are the same on every run. `-signed-in` starts
/// with the sample owner key; `-fake-…` arguments make the sample server fail
/// in specific ways.
final class IzzyClipzBusinessUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The sample server's owner key (FakeServer.ownerKey).
    private let ownerKey = "izzy-clipz-demo-owner-key-0123456789"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(signedIn: Bool = true, _ arguments: String...) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (signedIn ? ["-signed-in"] : []) + arguments
        app.launch()
        if signedIn {
            XCTAssertTrue(tabButton("Schedule").waitForExistence(timeout: 30), "The app didn't open signed in")
        } else {
            XCTAssertTrue(element("ownerKeyField").waitForExistence(timeout: 30), "The app didn't open on sign in")
        }
    }

    // MARK: Sign in

    func testSignInWithTheOwnerKey() {
        launch(signedIn: false)
        XCTAssertTrue(element("ownerKeyField").exists)
        screenshot("O01-Sign-In")
        signIn(with: ownerKey)
        XCTAssertTrue(tabButton("Schedule").waitForExistence(timeout: 15), "Signing in didn't open the schedule")
        for tab in ["Schedule", "New booking", "Take payment", "Products", "Settings"] {
            XCTAssertTrue(tabButton(tab).exists, "Missing the \(tab) tab")
        }
        XCTAssertTrue(element("appointment-Andre Sample").waitForExistence(timeout: 10))
    }

    func testAWrongKeyIsTurnedDown() {
        launch(signedIn: false)
        signIn(with: String(repeating: "x", count: 40))
        let error = element("signInError")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("isn't right"), "Got: \(error.label)")
        XCTAssertFalse(tabButton("Schedule").exists)
        screenshot("O02-Sign-In-Error")
    }

    func testAShortKeyIsExplained() {
        launch(signedIn: false)
        signIn(with: "too-short")
        XCTAssertTrue(waitForLabel(element("signInError"), containing: "too short"))
    }

    func testAnUnreachableServerIsExplained() {
        launch(signedIn: false, "-fake-offline")
        signIn(with: ownerKey)
        XCTAssertTrue(waitForLabel(element("signInError"), containing: "couldn't reach the server"))
    }

    func testAServerWithoutAnOwnerKeyIsExplained() {
        launch(signedIn: false, "-fake-owner-not-configured")
        signIn(with: ownerKey)
        XCTAssertTrue(waitForLabel(element("signInError"), containing: "OWNER_KEY"))
    }

    // MARK: Schedule

    func testScheduleShowsTheDayAndFiltersByBarber() {
        launch()
        let andre = element("appointment-Andre Sample")
        XCTAssertTrue(andre.waitForExistence(timeout: 10))
        XCTAssertTrue(andre.label.contains("11:30 AM"), "Got: \(andre.label)")
        XCTAssertTrue(andre.label.contains("Haircut & Beard with Izzy"))
        XCTAssertTrue(element("appointment-Marcus Sample").label.contains("Paid $40.00"), "Marcus paid for his cut")
        XCTAssertTrue(element("timeOff-Lunch").exists, "Flowxbori's lunch is blocked")
        XCTAssertTrue(app.staticTexts["Today"].exists)
        screenshot("O03-Schedule")
        // Further down the day: a cancelled appointment stays on the schedule, marked.
        XCTAssertTrue(reveal("appointment-Sam Sample").label.contains("Cancelled"))
        reveal("previousDay", searchingFirst: .up)

        // Izzy's day only: Cristian's 10 AM client and Flowxbori's lunch go; Izzy's clients stay.
        XCTAssertTrue(element("appointment-Jay Sample").exists)
        tap("barberFilter")
        tapButton("Izzy")
        XCTAssertTrue(waitForDisappearance(of: element("appointment-Jay Sample")), "Cristian's client still shows")
        XCTAssertTrue(element("appointment-Andre Sample").exists)
        XCTAssertTrue(element("appointment-Marcus Sample").exists)
        XCTAssertFalse(element("timeOff-Lunch").exists)
        screenshot("O04-Schedule-Filtered")
        tap("barberFilter")
        tapButton("Everyone")
        XCTAssertTrue(element("appointment-Jay Sample").waitForExistence(timeout: 10))
        XCTAssertTrue(reveal("appointment-Luis Sample").exists, "Julian's client is back")
        reveal("nextDay", searchingFirst: .up)

        tap("nextDay")
        XCTAssertTrue(element("scheduleEmpty").waitForExistence(timeout: 10), "Tuesday has nothing booked")
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
        tap("backToToday")
        XCTAssertTrue(element("appointment-Andre Sample").waitForExistence(timeout: 10))
    }

    func testMarkCompletedReopenAndCancelAnAppointment() {
        launch()
        tap("appointment-Andre Sample")
        XCTAssertTrue(element("detailClientName").waitForExistence(timeout: 10))
        XCTAssertEqual(element("detailClientName").label, "Andre Sample")
        XCTAssertTrue(element("callClient").exists)
        XCTAssertTrue(element("textClient").exists)
        XCTAssertTrue(waitForLabel(element("detailNote"), containing: "Likes a low fade"), "The client's note shows")
        screenshot("O05-Appointment")

        tap("markCompleted")
        XCTAssertTrue(statusShows("Completed"))
        tap("reopenAppointment")
        XCTAssertTrue(statusShows("Booked"))
        tap("markNoShow")
        XCTAssertTrue(statusShows("No-show"))
        tap("reopenAppointment")
        XCTAssertTrue(statusShows("Booked"))

        tap("cancelAppointment")
        tapDialogButton("Cancel appointment", identifier: "confirmCancelAppointment")
        XCTAssertTrue(statusShows("Cancelled"))
        XCTAssertTrue(reveal("detailPayment").label.contains("Not paid yet"))
        XCTAssertFalse(element("takePaymentForAppointment").exists, "No payment for a cancelled appointment")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(element("appointment-Andre Sample"), containing: "Cancelled"))
    }

    func testBlockTimeAndRemoveIt() {
        launch()
        tap("blockTimeButton")
        XCTAssertTrue(element("saveBlock").waitForExistence(timeout: 10))
        let reason = element("blockReason")
        reason.tap()
        reason.typeText("Staff meeting")
        screenshot("O06-Block-Time")
        tap("saveBlock")
        let block = element("timeOff-Staff meeting")
        XCTAssertTrue(block.waitForExistence(timeout: 10), "The new block isn't on the schedule")
        XCTAssertTrue(block.label.contains("Whole shop"), "Got: \(block.label)")
        XCTAssertTrue(block.label.contains("11:30 AM"), "It starts at the next half hour: \(block.label)")

        block.swipeLeft()
        tapButton("Remove")
        tapDialogButton("Remove blocked time", identifier: "confirmRemoveBlock")
        XCTAssertTrue(waitForDisappearance(of: block), "The block wasn't removed")
    }

    // MARK: New booking

    func testWalkInTakesTheNextOpenSlot() {
        launch()
        openTab("New booking")
        XCTAssertTrue(element("servicePicker").waitForExistence(timeout: 10))
        chooseService("Haircut")
        tap("nextOpenSlot")
        let slot = element("slot-11:30 AM")
        XCTAssertTrue(waitUntil(slot, toMatch: NSPredicate(format: "isSelected == true")), "11:30 AM wasn't picked")
        typeInto("clientName", "Walk-in Sample")
        screenshot("O07-New-Booking")
        tap("bookButton")
        let title = element("bookedTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "No confirmation")
        XCTAssertEqual(title.label, "Booked Walk-in Sample")
        screenshot("O08-Booked")
        tap("bookedDone")
        XCTAssertTrue(waitForDisappearance(of: title))

        openTab("Schedule")
        let row = element("appointment-Walk-in Sample")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The walk-in isn't on the schedule")
        XCTAssertTrue(row.label.contains("11:30 AM"))
    }

    /// A walk-in who's here at 11:05 is booked from 11:05. Izzy has Andre at 11:30, so an
    /// hour's cut with him doesn't fit in now; any barber who's free does.
    func testAWalkInWhosHereIsBookedForNow() {
        launch()
        openTab("New booking")
        chooseService("Haircut")
        tap("barberPicker")
        tapButton("Izzy · 1 hr · $40")
        XCTAssertTrue(element("servicePicker").waitForExistence(timeout: 10))
        let now = reveal("bookNow")
        XCTAssertTrue(waitForLabel(now, containing: "Now (11:05 AM)"), "Got: \(now.label)")
        now.tap()
        XCTAssertTrue(waitUntil(element("bookNow"), toMatch: NSPredicate(format: "isSelected == true")), "Now wasn't picked")
        typeInto("clientName", "Now Sample")
        tap("bookButton")
        XCTAssertTrue(waitForLabel(reveal("bookingError"), containing: "Izzy can't fit this in right now"))

        reveal("barberPicker", searchingFirst: .up).tap()
        tapButton("Any barber (first free)")
        XCTAssertTrue(element("servicePicker").waitForExistence(timeout: 10))
        tap("bookNow")
        XCTAssertTrue(waitUntil(element("bookNow"), toMatch: NSPredicate(format: "isSelected == true")))
        screenshot("O22-Walk-In-Now")
        tap("bookButton")
        XCTAssertTrue(waitForLabel(element("bookedTitle"), containing: "Now Sample"))
        tap("bookedDone")

        openTab("Schedule")
        let row = reveal("appointment-Now Sample")
        XCTAssertTrue(row.label.contains("11:05 AM"), "Got: \(row.label)")
    }

    func testPhoneBookingWithABarber() {
        launch()
        openTab("New booking")
        chooseService("Haircut")
        tap("barberPicker")
        tapButton("Julian · 45 min · $35")
        XCTAssertTrue(element("servicePicker").waitForExistence(timeout: 10))
        tap("slot-2 PM")
        typeInto("clientName", "Phone Sample")
        typeInto("clientPhone", "4425550123")
        tap("bookButton")
        XCTAssertTrue(waitForLabel(element("bookedTitle"), containing: "Phone Sample"))
        tap("bookedDone")
    }

    func testASlotTakenMeanwhileAsksForAnotherTime() {
        launch("-fake-slot-taken")
        openTab("New booking")
        chooseService("Haircut")
        tap("nextOpenSlot")
        XCTAssertTrue(waitUntil(element("slot-11:30 AM"), toMatch: NSPredicate(format: "isSelected == true")))
        typeInto("clientName", "Late Sample")
        tap("bookButton")
        XCTAssertTrue(waitForLabel(reveal("bookingError"), containing: "Someone just took that time"))
        screenshot("O09-Slot-Taken")
        // The list was refreshed: another time works.
        tap("slot-12 PM")
        tap("bookButton")
        XCTAssertTrue(waitForLabel(element("bookedTitle"), containing: "Late Sample"))
    }

    // MARK: Take payment

    func testTakePaymentForAnAppointmentWithTheSimulatedReader() {
        launch()
        tap("appointment-Andre Sample")
        tap("takePaymentForAppointment")
        XCTAssertTrue(waitUntil(tabButton("Take payment"), toMatch: NSPredicate(format: "isSelected == true")), "Didn't switch to Take payment")
        let amount = element("paymentAmount")
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.value as? String, "55 dollars", "Izzy's Haircut & Beard is $55")
        XCTAssertTrue(element("paymentAppointment").exists)
        XCTAssertTrue(element("testModeBanner").exists, "Test mode is labelled")
        let button = element("tapToPayButton")
        XCTAssertEqual(button.label, "Tap to Pay on iPhone")
        screenshot("O10-Take-Payment")

        button.tap()
        let approve = element("simulateApprove")
        XCTAssertTrue(approve.waitForExistence(timeout: 15), "The simulated Tap to Pay screen didn't show")
        screenshot("O11-Simulated-Tap")
        approve.tap()
        let paid = element("statusPaid")
        XCTAssertTrue(paid.waitForExistence(timeout: 15), "No result")
        XCTAssertEqual(paid.label, "Test payment approved")
        XCTAssertTrue(app.staticTexts["$55.00. Test mode: no card was charged."].exists)
        screenshot("O12-Paid")
        tap("paymentDone")
        XCTAssertTrue(waitForDisappearance(of: paid))
        XCTAssertEqual(element("paymentAmount").value as? String, "0 dollars", "Ready for the next customer")

        tap("paymentsTodayLink")
        XCTAssertTrue(waitForLabel(element("paymentsTotal"), containing: "$95.00"), "Marcus's $40 and Andre's $55")
        screenshot("O13-Payments-Today")

        // The schedule still shows Andre's details: they're paid now.
        openTab("Schedule")
        XCTAssertTrue(app.navigationBars["Appointment"].waitForExistence(timeout: 10), "The schedule lost Andre's details")
        XCTAssertTrue(waitForLabel(reveal("detailPayment"), containing: "$55.00"), "The appointment shows the payment")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(element("appointment-Andre Sample"), containing: "Paid $55.00"))
    }

    func testADeclinedCardCanBeTriedAgain() {
        launch()
        openTab("Take payment")
        enterAmount("1250")
        XCTAssertEqual(element("paymentAmount").value as? String, "12 dollars and 50 cents")
        tap("tapToPayButton")
        tap("simulateDecline")
        let declined = element("statusDeclined")
        XCTAssertTrue(declined.waitForExistence(timeout: 15))
        screenshot("O14-Declined")
        tap("retryPayment")
        tap("simulateApprove")
        XCTAssertTrue(element("statusPaid").waitForExistence(timeout: 15))
        tap("paymentDone")
    }

    func testTheCustomerCancellingKeepsTheAmount() {
        launch()
        openTab("Take payment")
        enterAmount("2000")
        tap("tapToPayButton")
        tap("simulateCancel")
        XCTAssertTrue(element("statusCancelled").waitForExistence(timeout: 15))
        tap("backToAmount")
        XCTAssertTrue(waitForDisappearance(of: element("statusCancelled")))
        XCTAssertEqual(element("paymentAmount").value as? String, "20 dollars")
    }

    func testATooSmallAmountIsExplained() {
        launch()
        openTab("Take payment")
        enterAmount("25")
        tap("tapToPayButton")
        XCTAssertTrue(waitForLabel(element("paymentValidation"), containing: "$0.50 to $1,000.00"))
        XCTAssertFalse(element("statusPreparing").exists || element("simulateApprove").exists, "No payment started")
    }

    func testWithoutStripeTakePaymentExplainsAndOffersTestMode() {
        launch("-fake-stripe-not-configured")
        openTab("Take payment")
        let card = element("paymentsUnavailable")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Card payments aren't set up yet"].exists)
        screenshot("O15-Payments-Not-Set-Up")
        tap("startPractice")
        XCTAssertTrue(element("testModeBanner").waitForExistence(timeout: 10))
        enterAmount("500")
        tap("tapToPayButton")
        tap("simulateApprove")
        XCTAssertTrue(waitForLabel(element("statusPaid"), containing: "Test payment approved"))
        tap("paymentDone")
        tap("stopPractice")
        XCTAssertTrue(element("paymentsUnavailable").waitForExistence(timeout: 10))
    }

    func testOnlyASucceededPaymentShowsPaid() {
        launch("-fake-payment-incomplete")
        openTab("Take payment")
        enterAmount("3000")
        tap("tapToPayButton")
        tap("simulateApprove")
        let notPaid = element("statusNotPaid")
        XCTAssertTrue(notPaid.waitForExistence(timeout: 15), "The server said it isn't complete, so it isn't paid")
        XCTAssertFalse(element("statusPaid").exists)
        tap("backToAmount")
    }

    // MARK: Products

    func testAddEditHideAndDeleteAProduct() {
        launch()
        openTab("Products")
        XCTAssertTrue(element("product-Sample pomade").waitForExistence(timeout: 10))
        XCTAssertTrue(element("product-Sample beard oil").label.contains("hidden"))
        screenshot("O16-Products")

        tap("addProduct")
        typeInto("productName", "Sample wax")
        typeInto("productPrice", "15")
        tap("useTestPhoto")
        XCTAssertTrue(element("newPhotoPreview").waitForExistence(timeout: 10), "The photo wasn't prepared")
        screenshot("O17-Product-Editor")
        tap("saveProduct")
        let row = element("product-Sample wax")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The new product isn't listed")
        XCTAssertTrue(row.label.contains("$15.00"), "Got: \(row.label)")

        // Edit: hide it from the customer app in the editor.
        row.tap()
        flipSwitch(reveal("productVisible"))
        tap("saveProduct")
        XCTAssertTrue(waitForLabel(element("product-Sample wax"), containing: "hidden"))

        // Show it again with a swipe.
        element("product-Sample wax").swipeLeft()
        tapButton("Show")
        XCTAssertTrue(waitUntil(element("product-Sample wax"), toMatch: NSPredicate(format: "NOT (label CONTAINS %@)", "hidden")))

        element("product-Sample wax").swipeLeft()
        tapButton("Delete")
        tapDialogButton("Delete Sample wax", identifier: "confirmDeleteProduct")
        XCTAssertTrue(waitForDisappearance(of: element("product-Sample wax")))
    }

    // MARK: Settings

    func testSettingsShowStatusHowToTapAndSignOut() {
        launch()
        openTab("Settings")
        XCTAssertTrue(waitForLabel(element("stripeMode"), containing: "Test mode: no real money"))
        XCTAssertTrue(element("stripeLocation").label.contains("tml_sample_location"))
        let online = app.descendants(matching: .any).matching(identifier: "serverStatus")
            .matching(NSPredicate(format: "label CONTAINS %@", "Online")).firstMatch
        XCTAssertTrue(online.waitForExistence(timeout: 10), "The server's health check")
        screenshot("O18-Settings")

        tap("howToTap")
        XCTAssertTrue(element("howToTapDone").waitForExistence(timeout: 10))
        screenshot("O19-How-To-Tap")
        tap("howToTapDone")
        XCTAssertTrue(waitForDisappearance(of: element("howToTapDone")))

        XCTAssertTrue(reveal("appVersion").label.contains("Version"))
        tap("signOut")
        tapDialogButton("Sign out", identifier: "confirmSignOut")
        XCTAssertTrue(element("ownerKeyField").waitForExistence(timeout: 10), "Signing out didn't go back to sign in")
    }

    // MARK: Empty and offline

    func testAnEmptyShop() {
        launch("-fake-empty")
        XCTAssertTrue(element("scheduleEmpty").waitForExistence(timeout: 10))
        screenshot("O20-Empty-Day")
        openTab("Products")
        XCTAssertTrue(element("productsEmpty").waitForExistence(timeout: 10))
    }

    func testOfflineScheduleOffersToTryAgain() {
        launch("-fake-offline")
        XCTAssertTrue(element("retrySchedule").waitForExistence(timeout: 10), "No way to try again")
        XCTAssertTrue(app.staticTexts["Couldn't load the schedule"].exists)
        screenshot("O21-Offline")
    }

    func testOfflineTakePaymentSaysWhyAndOffersTestMode() {
        launch("-fake-offline")
        openTab("Take payment")
        let card = element("paymentsStatusUnknown")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Take payment kept saying it was checking")
        XCTAssertTrue(app.staticTexts["We couldn't reach the server. Check your internet connection and try again."].exists)
        screenshot("O22-Payments-Offline")
        tap("checkStripeAgain")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Still offline: the card says so again")
        tap("startPractice")
        XCTAssertTrue(element("testModeBanner").waitForExistence(timeout: 10))
        enterAmount("500")
        tap("tapToPayButton")
        tap("simulateApprove")
        XCTAssertTrue(waitForLabel(element("statusPaid"), containing: "Test payment approved"))
        tap("paymentDone")
    }

    // MARK: Helpers

    private func signIn(with key: String) {
        let field = element("ownerKeyField")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(key)
        tap("signInButton")
    }

    private func chooseService(_ name: String) {
        tap("servicePicker")
        tapButton(name)
        XCTAssertTrue(element("servicePicker").waitForExistence(timeout: 10), "Didn't come back from the service list")
    }

    /// Types an amount on the keypad: "1250" is $12.50.
    private func enterAmount(_ digits: String) {
        for digit in digits {
            tap("key-\(digit)")
        }
    }

    private func typeInto(_ identifier: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = reveal(identifier, file: file, line: line)
        field.tap()
        field.typeText(text)
    }

    private func tabButton(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name]
    }

    private func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tabButton(name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing the \(name) tab", file: file, line: line)
        tab.tap()
        if !waitUntil(tab, toMatch: NSPredicate(format: "isSelected == true")) {
            // Slow simulators occasionally drop a tap.
            tab.tap()
        }
        XCTAssertTrue(waitUntil(tab, toMatch: NSPredicate(format: "isSelected == true")), "\(name) didn't open", file: file, line: line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element, scrolls it into view if needed, and taps it.
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(identifier, file: file, line: line).tap()
    }

    private enum Direction {
        /// Further down the screen (a swipe up).
        case down
        /// Back up the screen (a swipe down).
        case up
    }

    /// Finds an element and scrolls it onto the screen. Lists and forms only build the rows on
    /// screen, so a row further down (or one scrolled past) isn't there until it's scrolled to.
    @discardableResult
    private func reveal(_ identifier: String, searchingFirst first: Direction = .down, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let target = element(identifier)
        // Most are on screen already, or show up once the screen has loaded.
        if target.waitForExistence(timeout: 8), target.isHittable {
            return target
        }
        for direction in first == .down ? [Direction.down, .up] : [.up, .down] {
            for _ in 0..<8 {
                if target.exists, target.isHittable {
                    settle(target)
                    return target
                }
                drag(direction)
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Couldn't find \(identifier) on the screen", file: file, line: line)
        return target
    }

    /// Drags the page about a third of the screen and holds still before letting go, so it
    /// doesn't keep gliding: a tap on a list that's still moving only stops it. The drag stays
    /// above the keyboard while one is up.
    private func drag(_ direction: Direction) {
        let lowY = min(0.7, pageBottom() - 0.1)
        let highY = max(0.2, lowY - 0.35)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: lowY))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: highY))
        let (start, end) = direction == .down ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    /// Where the page ends, as a fraction of the screen's height: the keyboard's top while one is up.
    private func pageBottom() -> CGFloat {
        let keyboard = app.keyboards.firstMatch
        let screen = app.frame
        guard keyboard.exists, !screen.isEmpty, keyboard.frame.minY > screen.minY else { return 1 }
        return max(0.45, (keyboard.frame.minY - screen.minY) / screen.height)
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
        guard let before, before == "0" || before == "1" else { return }
        let flipped = NSPredicate(format: "value == %@", before == "1" ? "0" : "1")
        if !waitUntil(control, toMatch: flipped, timeout: 3) {
            trailingEnd.tap()
            XCTAssertTrue(waitUntil(control, toMatch: flipped, timeout: 5), "The switch didn't move", file: file, line: line)
        }
    }

    /// The appointment's status, at the top of its details.
    private func statusShows(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        waitForLabel(reveal("detailStatus", searchingFirst: .up, file: file, line: line), containing: text)
    }

    /// Taps a button by its label: menu items, picker rows, swipe actions.
    private func tapButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
            return
        }
        // Menus and pickers can show their choices as menu items, cells or text.
        for query in [app.menuItems, app.cells, app.staticTexts] {
            let match = query.matching(predicate).firstMatch
            if match.exists {
                match.tap()
                return
            }
        }
        XCTFail("Missing the \(label) button", file: file, line: line)
    }

    /// Taps a button in a confirmation dialog: by identifier when SwiftUI
    /// passes it on, otherwise the dialog's button with that label (the last
    /// one, since the dialog is on top of a button with the same name).
    private func tapDialogButton(_ label: String, identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let byIdentifier = element(identifier)
        if byIdentifier.waitForExistence(timeout: 3) {
            byIdentifier.tap()
            return
        }
        let inSheet = app.sheets.buttons[label]
        if inSheet.exists {
            inSheet.tap()
            return
        }
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "No \(label) button in the dialog", file: file, line: line)
        matches.element(boundBy: max(matches.count - 1, 0)).tap()
    }

    private func waitUntil(_ element: XCUIElement, toMatch predicate: NSPredicate, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        waitUntil(element, toMatch: NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitUntil(element, toMatch: NSPredicate(format: "exists == false"), timeout: timeout)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
