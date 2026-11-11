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
        for tab in ["Schedule", "New booking", "Take payment", "Analytics", "Settings"] {
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
        XCTAssertTrue(element("appointment-Marcus Sample").label.contains("Paid $40 · Card"), "Marcus paid for his cut by card")
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
        XCTAssertFalse(element("checkOutAppointment").exists, "No checkout for a cancelled appointment")

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

    /// Check out Andre from the schedule and take his card with the simulated reader: the ticket has
    /// his Haircut & Beard at $55, sold by Izzy, and the card sale checks him out.
    func testTakePaymentForAnAppointmentWithTheSimulatedReader() {
        launch()
        tap("appointment-Andre Sample")
        tap("checkOutAppointment")
        XCTAssertTrue(waitUntil(tabButton("Take payment"), toMatch: NSPredicate(format: "isSelected == true")), "Didn't switch to Take payment")
        let amount = element("paymentAmount")
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.value as? String, "55 dollars", "Izzy's Haircut & Beard is $55")
        XCTAssertTrue(element("paymentAppointment").exists)
        XCTAssertTrue(element("ticketItem-Haircut & Beard").exists, "The appointment's service is on the ticket")
        XCTAssertTrue(element("soldBy-Izzy").isSelected, "Sold by the appointment's barber")
        XCTAssertTrue(element("testModeBanner").exists, "Test mode is labelled")
        let button = reveal("tapToPayButton")
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
        XCTAssertTrue(waitForLabel(element("saleReceiptLine"), containing: "Sold $55 · Card · Izzy"), "The sale went with the payment")
        XCTAssertTrue(element("emailReceipt").exists, "A receipt is offered once the card went through")
        screenshot("O12-Paid")
        tap("paymentDone")
        XCTAssertTrue(waitForDisappearance(of: paid))
        XCTAssertEqual(element("paymentAmount").value as? String, "0 dollars", "Ready for the next customer")
        XCTAssertTrue(reveal("sale-Andre Sample").label.contains("Card"), "Today's sales lists it")

        tap("paymentsTodayLink")
        XCTAssertTrue(waitForLabel(element("paymentsTotal"), containing: "$95.00"), "Marcus's $40 and Andre's $55")
        screenshot("O13-Payments-Today")

        // The schedule still shows Andre's details: he's checked out now.
        openTab("Schedule")
        XCTAssertTrue(app.navigationBars["Appointment"].waitForExistence(timeout: 10), "The schedule lost Andre's details")
        XCTAssertTrue(waitForLabel(reveal("detailPayment"), containing: "$55 · Card"), "The appointment shows the sale")
        XCTAssertFalse(element("checkOutAppointment").exists, "Checked out once")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(element("appointment-Andre Sample"), containing: "Paid $55 · Card"))
    }

    func testADeclinedCardCanBeTriedAgain() {
        launch()
        openTab("Take payment")
        ringUp("1250")
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
        ringUp("2000")
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
        ringUp("25")
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
        ringUp("500")
        tap("tapToPayButton")
        tap("simulateApprove")
        XCTAssertTrue(waitForLabel(element("statusPaid"), containing: "Test payment approved"))
        XCTAssertFalse(element("emailReceipt").exists, "Nothing went to Stripe in practice, so there's no receipt")
        tap("paymentDone")
        tap("stopPractice")
        XCTAssertTrue(element("paymentsUnavailable").waitForExistence(timeout: 10))
    }

    func testOnlyASucceededPaymentShowsPaid() {
        launch("-fake-payment-incomplete")
        openTab("Take payment")
        ringUp("3000")
        tap("tapToPayButton")
        tap("simulateApprove")
        let notPaid = element("statusNotPaid")
        XCTAssertTrue(notPaid.waitForExistence(timeout: 15), "The server said it isn't complete, so it isn't paid")
        XCTAssertFalse(element("statusPaid").exists)
        tap("backToAmount")
    }

    // MARK: Checkout

    /// Andre pays cash: Check out from the schedule, Cash asks first with the amount and the barber,
    /// the receipt says "Sold $55 · Cash · Izzy", and the schedule shows him paid.
    func testACashCheckoutOfAnAppointmentShowsItPaid() {
        launch()
        tap("appointment-Andre Sample")
        tap("checkOutAppointment")
        XCTAssertTrue(waitUntil(tabButton("Take payment"), toMatch: NSPredicate(format: "isSelected == true")), "Didn't switch to Take payment")
        XCTAssertTrue(element("paymentAppointment").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Andre Sample"].exists, "The appointment's client")
        XCTAssertTrue(element("ticketItem-Haircut & Beard").exists)
        tap("payCash")
        let question = text(containing: "Record a $55 cash sale for Izzy?")
        XCTAssertTrue(question.waitForExistence(timeout: 10), "Cash asks first, with the amount and the barber")
        screenshot("O46-Confirm-Cash-Sale")
        tapDialogButton("Record cash sale", identifier: "confirmRecordSale")
        let sold = element("statusSold")
        XCTAssertTrue(sold.waitForExistence(timeout: 15), "No receipt")
        XCTAssertEqual(sold.label, "Sold $55 · Cash · Izzy")
        XCTAssertTrue(element("saleReceipt").exists)
        screenshot("O47-Cash-Sale-Receipt")
        tap("saleDone")
        XCTAssertTrue(waitForDisappearance(of: sold))
        XCTAssertEqual(element("paymentAmount").value as? String, "0 dollars", "The ticket is cleared")
        XCTAssertTrue(reveal("sale-Andre Sample").label.contains("Sold $55 · Cash · Izzy"))

        openTab("Schedule")
        XCTAssertTrue(waitForLabel(reveal("detailPayment"), containing: "$55 · Cash"), "The appointment shows the sale")
        XCTAssertFalse(element("checkOutAppointment").exists)
        XCTAssertTrue(reveal("checkedOutStatus").exists, "It can't be reopened until its sale is voided")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = element("appointment-Andre Sample")
        XCTAssertTrue(waitForLabel(row, containing: "Paid $55 · Cash"), "Got: \(row.label)")
    }

    /// A walk-in buys two pomades and a beard oil (which has no price, so it asks for one), sold by
    /// Cristian, paid another way (Zelle, say).
    func testAProductOnlyWalkInSale() {
        launch()
        openTab("Take payment")
        XCTAssertTrue(element("ticketEmpty").waitForExistence(timeout: 10))
        tap("payOther")
        XCTAssertTrue(waitForLabel(element("paymentValidation"), containing: "Add a service, a product or an amount first."))
        tap("soldBy-Cristian")
        XCTAssertTrue(element("soldBy-Cristian").isSelected)
        tap("addProduct")
        tap("pickProduct-Sample pomade")
        let pomade = element("ticketItem-Sample pomade")
        XCTAssertTrue(pomade.waitForExistence(timeout: 10), "The pomade isn't on the ticket")
        // The stepper's + button: "Increment" on older iOS, "quantity-Sample pomade-Increment" (with
        // a label ending in "Increment") on iOS 26.
        let quantity = reveal("quantity-Sample pomade")
        quantity.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", "Increment", "Increment")).firstMatch.tap()
        XCTAssertTrue(waitUntil(element("paymentAmount"), toMatch: NSPredicate(format: "value == %@", "36 dollars")), "Two pomades: $36")

        tap("addProduct")
        tap("pickProduct-Sample beard oil")
        XCTAssertTrue(element("amountEntryValue").waitForExistence(timeout: 10), "A product without a price asks for one")
        enterAmount("1200")
        tap("saveAmount")
        XCTAssertTrue(element("ticketItem-Sample beard oil").waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(element("paymentAmount"), toMatch: NSPredicate(format: "value == %@", "48 dollars")))
        typeInto("walkInName", "Walk-in Sample")
        closeKeyboard()
        screenshot("O48-Walk-In-Ticket")

        tap("payOther")
        XCTAssertTrue(text(containing: "Record a $48 sale paid another way for Cristian?").waitForExistence(timeout: 10))
        tapDialogButton("Record sale", identifier: "confirmRecordSale")
        XCTAssertTrue(waitForLabel(element("statusSold"), containing: "Sold $48 · Other · Cristian"))
        tap("saleDone")
        let row = reveal("sale-Walk-in Sample")
        XCTAssertTrue(row.label.contains("Sold $48 · Other · Cristian"), "Got: \(row.label)")
    }

    /// Diego's cash sale from this morning is voided: it asks first (with an optional reason), and the
    /// sale stays in the list, struck through.
    func testVoidASale() {
        launch()
        openTab("Take payment")
        let diego = reveal("sale-Diego Sample")
        XCTAssertTrue(diego.label.contains("Sold $63 · Cash · Carlos"), "Got: \(diego.label)")
        diego.tap()
        XCTAssertTrue(waitForLabel(element("saleSummary"), containing: "Sold $63 · Cash · Carlos"))
        screenshot("O49-Sale")
        tap("voidSale")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Void asks first")
        XCTAssertTrue(alert.label.contains("Void this $63 cash sale?") || text(containing: "Void this $63 cash sale?").exists)
        let reason = alert.textFields.firstMatch
        if reason.waitForExistence(timeout: 5) {
            reason.tap()
            reason.typeText("Rang it up twice")
        }
        tapDialogButton("Void sale", identifier: "confirmVoidSale")
        XCTAssertTrue(reveal("saleVoided").exists, "The sale shows it's voided")
        XCTAssertTrue(waitForLabel(reveal("voidMessage"), containing: "no longer counts in your sales"))
        XCTAssertFalse(element("voidSale").exists, "Voided once")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(reveal("sale-Diego Sample"), containing: "voided"))
    }

    /// After a card payment, the client may ask for a receipt: Stripe emails it, and the address isn't
    /// kept. Nothing about an email is asked before the card.
    func testEmailAReceiptAfterACardPayment() {
        launch()
        openTab("Take payment")
        XCTAssertFalse(element("receiptEmail").exists, "No email before the payment")
        ringUp("2500", soldBy: "Julian")
        tap("tapToPayButton")
        tap("simulateApprove")
        XCTAssertTrue(element("statusPaid").waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel(element("saleReceiptLine"), containing: "Sold $25 · Card · Julian"))
        tap("emailReceipt")
        typeInto("receiptEmailField", "client@example.com")
        screenshot("O50-Email-A-Receipt")
        tap("sendReceipt")
        XCTAssertTrue(reveal("receiptSent").waitForExistence(timeout: 10), "The receipt wasn't sent")
        tap("paymentDone")
        XCTAssertEqual(element("paymentAmount").value as? String, "0 dollars")
    }

    // MARK: Products

    /// The shop's products are in Settings now (they used to have a tab).
    func testAddEditHideAndDeleteAProduct() {
        launch()
        openProducts()
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
        XCTAssertTrue(waitForLabel(reveal("stripeStatus"), containing: "Connected"))
        XCTAssertTrue(waitForLabel(reveal("stripeMode"), containing: "Test mode: no real money"))
        XCTAssertTrue(reveal("stripeLocation").label.contains("tml_sample_location"))
        screenshot("O18-Settings")
        reveal("serverStatus")
        let online = app.descendants(matching: .any).matching(identifier: "serverStatus")
            .matching(NSPredicate(format: "label CONTAINS %@", "Online")).firstMatch
        XCTAssertTrue(online.waitForExistence(timeout: 10), "The server's health check")

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

    // MARK: The shop's Stripe account

    /// The shop's own Stripe account isn't connected yet (`-fake-stripe-not-connected`): Take payment
    /// says how to connect, with a button to Settings, where Connect Stripe opens Stripe's window (a
    /// stand-in in UI tests) and comes back connected. Then Take payment takes cards.
    func testConnectStripeFromSettings() {
        launch("-fake-stripe-not-connected")
        openTab("Take payment")
        XCTAssertTrue(element("paymentsUnavailable").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Connect Stripe to take cards").exists)
        screenshot("O41-Payments-Connect-Stripe")
        tap("goToStripeSettings")
        XCTAssertTrue(waitUntil(tabButton("Settings"), toMatch: NSPredicate(format: "isSelected == true")), "Didn't go to Settings")
        let status = reveal("stripeStatus")
        XCTAssertTrue(waitForLabel(status, containing: "Not connected"), "Got: \(status.label)")
        XCTAssertTrue(reveal("stripeMessage").label.contains("Connect your Stripe account to take card payments in the app."))
        XCTAssertFalse(element("disconnectStripe").exists, "Nothing to disconnect yet")
        screenshot("O42-Settings-Stripe-Not-Connected")

        tap("connectStripe")
        XCTAssertTrue(waitForLabel(reveal("stripeResult"), containing: "You're connected. You can take card payments now."))
        let connected = reveal("stripeStatus")
        XCTAssertTrue(waitForLabel(connected, containing: "Connected"), "Got: \(connected.label)")
        XCTAssertTrue(connected.label.contains("Izzy Clipz Barbershop"), "Got: \(connected.label)")
        XCTAssertTrue(waitForLabel(reveal("stripeMessage"), containing: "Payouts to your bank are on."))
        XCTAssertTrue(reveal("openStripeDashboard").exists)
        XCTAssertTrue(reveal("disconnectStripe").exists)
        screenshot("O43-Settings-Stripe-Connected")

        openTab("Take payment")
        XCTAssertTrue(waitForDisappearance(of: element("paymentsUnavailable")), "Take payment still says to connect")
        XCTAssertTrue(element("testModeBanner").waitForExistence(timeout: 10))
    }

    /// Stripe still needs details after its window (`-fake-stripe-needs-info`): Settings says so, and
    /// Finish setting up opens it again.
    func testStripeStillNeedingDetailsOffersFinishSettingUp() {
        launch("-fake-stripe-needs-info")
        openTab("Settings")
        tap("connectStripe")
        XCTAssertTrue(waitForLabel(reveal("stripeResult"), containing: "Stripe still needs a few details: tap Finish setting up."))
        XCTAssertTrue(waitForLabel(reveal("stripeStatus"), containing: "Finish setting up"))
        let finish = reveal("connectStripe")
        XCTAssertTrue(waitForLabel(finish, containing: "Finish setting up"), "Got: \(finish.label)")
        screenshot("O44-Settings-Stripe-Needs-Info")
        finish.tap()
        XCTAssertTrue(waitForLabel(reveal("stripeResult"), containing: "You're connected."))
        XCTAssertTrue(waitForLabel(reveal("stripeStatus"), containing: "Connected"))
    }

    /// Closing Stripe's window (`-fake-stripe-cancel`) says nothing went wrong and shows no result:
    /// the account the server started stays, so the button reads Finish setting up.
    func testClosingStripesWindowShowsNoResult() {
        launch("-fake-stripe-cancel")
        openTab("Settings")
        tap("connectStripe")
        XCTAssertTrue(waitForLabel(reveal("connectStripe"), containing: "Finish setting up"))
        XCTAssertFalse(element("stripeResult").exists, "Closing the window isn't a result")
        XCTAssertFalse(element("stripeActionError").exists, "Closing the window isn't an error")
    }

    /// Disconnect asks first, says what stops, and leaves Connect Stripe.
    func testDisconnectStripeAsksFirst() {
        launch()
        openTab("Settings")
        tap("disconnectStripe")
        XCTAssertTrue(text(containing: "Card payments stop until you connect Stripe again.").waitForExistence(timeout: 10))
        tapDialogButton("Disconnect Stripe", identifier: "confirmDisconnectStripe")
        XCTAssertTrue(waitForLabel(reveal("stripeStatus"), containing: "Not connected"))
        XCTAssertTrue(waitForLabel(reveal("stripeResult"), containing: "Your Stripe account isn't closed"))
        XCTAssertTrue(reveal("connectStripe").exists)
    }

    // MARK: Use on a computer

    /// Settings → Use on a computer: the steps, a big code counting down (frozen at 10:00 with the
    /// UI tests' fixed clock), a new code, and the computers signed in, signed out one and then all.
    func testGetAComputerCodeAndSignComputersOut() {
        launch()
        openTab("Settings")
        let link = reveal("computerAccessLink")
        XCTAssertTrue(waitForLabel(link, containing: "2 computers signed in"), "Got: \(link.label)")
        link.tap()
        let code = element("computerCode")
        XCTAssertTrue(code.waitForExistence(timeout: 10), "No code")
        XCTAssertEqual(code.label, "Code 4 8 3, 9 2 0")
        XCTAssertTrue(waitForLabel(element("computerCodeExpiry"), containing: "Expires in 10:00"))
        XCTAssertTrue(element("computerSite").label.hasSuffix("/business"), "Got: \(element("computerSite").label)")
        XCTAssertTrue(element("computerIntro").label.contains("See your schedule, sales and analytics on a computer."))
        screenshot("O45-Use-On-A-Computer")

        tap("newComputerCode")
        XCTAssertTrue(waitForLabel(element("computerCode"), containing: "2 7 1, 8 4 6"))

        let mac = reveal("computer-Chrome on Mac")
        XCTAssertTrue(mac.label.contains("Last used today at 10:45 AM"), "Got: \(mac.label)")
        XCTAssertTrue(reveal("computer-Safari on iPad").exists)
        tap("signOutComputer-Chrome on Mac")
        XCTAssertTrue(waitForDisappearance(of: element("computer-Chrome on Mac")))
        tap("signOutAllComputers")
        XCTAssertTrue(text(containing: "Every computer goes back to the website's sign-in page.").waitForExistence(timeout: 10))
        tapDialogButton("Sign out all computers", identifier: "confirmSignOutAllComputers")
        XCTAssertTrue(reveal("computersEmpty").exists, "No computers left")
        XCTAssertFalse(element("computer-Safari on iPad").exists)
    }

    /// Settings → Legal opens the website's four policies in the in-app browser (UI tests see the
    /// address instead of Safari).
    func testTheLegalPagesOpenTheWebsite() {
        launch()
        openTab("Settings")
        let pages = [
            ("legal-privacy", "Privacy Policy", "/privacy"),
            ("legal-terms", "Terms of Service", "/terms"),
            ("legal-cancellation-policy", "Cancellation & No-Show Policy", "/cancellation-policy"),
            ("legal-accessibility", "Accessibility", "/accessibility"),
        ]
        for (identifier, title, path) in pages {
            let row = reveal(identifier)
            XCTAssertTrue(row.label.contains(title), "Got: \(row.label)")
            if identifier == "legal-privacy" { screenshot("O40-Settings-Legal") }
            row.tap()
            let address = element("webURL")
            XCTAssertTrue(address.waitForExistence(timeout: 10), "\(title) didn't open")
            XCTAssertEqual(address.label, "https://izzy-clipz.vercel.app" + path)
            tap("webDone")
            XCTAssertTrue(waitForDisappearance(of: address))
        }
    }

    // MARK: No-show protection

    /// Kim Sample booked online with a card on file (Visa 4242) for a $35 haircut at 10 AM and
    /// didn't come (`-fake-cards-on-file`). The owner marks the no-show (her appointment has ended), and
    /// the fee is charged once, after a question that names the amount and the card. Payments today
    /// lists it as a no-show fee, and the Payment section says the service itself isn't paid.
    func testChargeANoShowFeeToTheCardOnFile() {
        launch("-fake-cards-on-file")
        let row = reveal("appointment-Kim Sample")
        XCTAssertTrue(row.label.contains("No-show"), "Got: \(row.label)")
        XCTAssertTrue(row.label.contains("Card on file, Visa ending in 4242"), "Got: \(row.label)")
        row.tap()
        XCTAssertTrue(waitForLabel(element("detailClientName"), containing: "Kim Sample"))
        XCTAssertTrue(waitForLabel(reveal("detailCard"), containing: "Visa •••• 4242"))
        XCTAssertTrue(reveal("detailFee").label.contains("$35 (the full service price)"), "Got: \(element("detailFee").label)")

        // Mark no-show → charge → charged: reopened first (an uncharged no-show reopens without a
        // question), then marked a no-show, which her haircut's end (10:45 AM) allows at 11:05.
        tap("reopenAppointment")
        XCTAssertTrue(statusShows("Booked"))
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "If the client didn't come, mark a no-show."))
        XCTAssertFalse(element("chargeFee").exists, "Nothing to charge while it's booked")
        tap("markNoShow")
        XCTAssertTrue(statusShows("No-show"))
        let charge = reveal("chargeFee")
        XCTAssertTrue(waitForLabel(charge, containing: "Charge no-show fee ($35)"), "Got: \(charge.label)")
        XCTAssertTrue(reveal("detailPayment").label.contains("Not paid yet"), "Got: \(element("detailPayment").label)")
        screenshot("O23-No-Show-Fee")

        charge.tap()
        XCTAssertTrue(text(containing: "Charge $35 to Kim Sample's Visa •••• 4242?").waitForExistence(timeout: 10), "The question names the amount and the card")
        screenshot("O24-Confirm-No-Show-Fee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        let status = reveal("feeStatus")
        XCTAssertTrue(waitForLabel(status, containing: "No-show fee charged"), "Got: \(status.label)")
        XCTAssertTrue(status.label.contains("$35 to Visa •••• 4242"), "Got: \(status.label)")
        XCTAssertFalse(element("chargeFee").exists, "A fee is charged once")
        // The service itself isn't paid, and the fee is said apart, so it isn't taken again.
        let payment = reveal("detailPayment")
        XCTAssertTrue(waitForLabel(payment, containing: "Service not paid"), "Got: \(payment.label)")
        XCTAssertTrue(waitForLabel(reveal("detailPaymentFeeNote"), containing: "The $35 no-show fee was charged to the card on file."))
        screenshot("O25-No-Show-Fee-Charged")

        // Reopening doesn't refund it, and says so first.
        tap("reopenAppointment")
        XCTAssertTrue(text(containing: "reopening doesn't refund it. Refunds are made in the Stripe Dashboard.").waitForExistence(timeout: 10))
        tapDialogButton("Reopen", identifier: "confirmReopen")
        XCTAssertTrue(statusShows("Booked"))
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "No-show fee charged"))
        XCTAssertFalse(element("chargeFee").exists, "Still never twice")
        // Cancelling it doesn't refund the fee either, and the question says so (not "no fee").
        tap("cancelAppointment")
        let question = text(containing: "The $35 no-show fee stays charged: cancelling doesn't refund it.")
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertFalse(text(containing: "There's no fee when the shop cancels.").exists)
        tapDialogCancelButton("Keep it", identifier: "keepAppointment", closing: question)
        XCTAssertTrue(statusShows("Booked"))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(reveal("appointment-Kim Sample"), containing: "No-show fee $35 charged"))

        openTab("Take payment")
        tap("paymentsTodayLink")
        XCTAssertTrue(waitForLabel(element("paymentsTotal"), containing: "$75.00"), "Marcus's $40 cut and Kim's $35 fee")
        XCTAssertTrue(waitForLabel(element("paymentsFees"), containing: "$35.00"))
        let fee = reveal("feePayment")
        XCTAssertTrue(fee.label.contains("No-show fee"), "Got: \(fee.label)")
        XCTAssertTrue(fee.label.contains("Haircut with Flowxbori"), "Got: \(fee.label)")
        screenshot("O26-Payments-Today-Fee")
    }

    /// Lee Sample cancelled in the app at 10:50 AM, less than 1 hour before an 11:30 AM haircut
    /// booked with a card on file: a late cancellation the owner may charge.
    func testChargeALateCancellationFee() {
        launch("-fake-cards-on-file")
        let row = reveal("appointment-Lee Sample")
        XCTAssertTrue(row.label.contains("Cancelled late"), "Got: \(row.label)")
        row.tap()
        XCTAssertTrue(statusShows("Cancelled late"))
        XCTAssertTrue(waitForLabel(reveal("detailCustomerCancelled"), containing: "10:50 AM"))
        let charge = reveal("chargeFee")
        XCTAssertTrue(waitForLabel(charge, containing: "Charge late cancellation fee ($35)"), "Got: \(charge.label)")
        screenshot("O27-Late-Cancellation-Fee")

        charge.tap()
        XCTAssertTrue(text(containing: "Charge $35 to Lee Sample's Visa •••• 4242?").waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "the client cancelled at 10:50 AM, less than 1 hour before").exists, "The question says why")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "Late cancellation fee charged"))
        XCTAssertFalse(element("chargeFee").exists, "A fee is charged once")
        screenshot("O28-Late-Cancellation-Fee-Charged")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let charged = reveal("appointment-Lee Sample")
        XCTAssertTrue(waitForLabel(charged, containing: "Late cancellation fee $35 charged"), "Got: \(charged.label)")
        XCTAssertTrue(charged.label.contains("Cancelled late"), "Got: \(charged.label)")
        openTab("Take payment")
        tap("paymentsTodayLink")
        XCTAssertTrue(waitForLabel(reveal("feePayment"), containing: "Late cancellation fee"))
    }

    func testADeclinedFeeSaysWhyAndCanBeTriedAgain() {
        launch("-fake-cards-on-file", "-fake-no-show-declined")
        tap("appointment-Kim Sample")
        tap("chargeFee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        let status = reveal("feeStatus")
        XCTAssertTrue(waitForLabel(status, containing: "Declined"), "Got: \(status.label)")
        XCTAssertTrue(status.label.contains("there isn't enough money on it"), "Got: \(status.label)")
        screenshot("O29-No-Show-Fee-Declined")

        // Another try is a new charge, and it asks again.
        let again = reveal("chargeFee")
        XCTAssertTrue(waitForLabel(again, containing: "Charge again ($35)"), "Got: \(again.label)")
        again.tap()
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "No-show fee charged"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(reveal("appointment-Kim Sample"), containing: "No-show fee $35 charged"))
    }

    func testAFeeTheBankWantsTheClientToApproveSaysToAskThemToPayAtTheShop() {
        launch("-fake-cards-on-file", "-fake-no-show-needs-action")
        tap("appointment-Lee Sample")
        tap("chargeFee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        let status = reveal("feeStatus")
        XCTAssertTrue(waitForLabel(status, containing: "The card needs the client to approve it"), "Got: \(status.label)")
        XCTAssertTrue(status.label.contains("Ask them to pay at the shop"), "Got: \(status.label)")
        screenshot("O30-Fee-Needs-The-Client")
    }

    /// The charge never reaches Stripe (`-fake-no-show-unreachable`): nobody knows yet whether the
    /// card was charged, so the details offer Check again, which finishes the same try.
    func testAChargeWithoutAnAnswerOffersCheckAgain() {
        launch("-fake-cards-on-file", "-fake-no-show-unreachable")
        tap("appointment-Kim Sample")
        tap("chargeFee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        XCTAssertTrue(waitForLabel(reveal("feeError"), containing: "We don't know yet if the card was charged"))
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "Not confirmed yet"))
        // It says what Check again does: if Stripe never got the charge, it's sent now.
        XCTAssertTrue(element("feeStatus").label.contains("if Stripe never got it, it's sent now"), "Got: \(element("feeStatus").label)")
        let check = reveal("chargeFee")
        XCTAssertTrue(waitForLabel(check, containing: "Check again"), "Got: \(check.label)")
        // No second question: it only finishes the try that was confirmed.
        check.tap()
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "No-show fee charged"))
        XCTAssertTrue(waitForDisappearance(of: element("feeError")), "The old message goes")
    }

    /// The charge goes through, but its answer is lost on the way back (`-fake-no-show-answer-lost`):
    /// the app loads the day again, so the details show the fee charged, with nothing under it about
    /// not knowing, and Payments today lists it.
    func testAChargeWhoseAnswerIsLostShowsItCharged() {
        launch("-fake-cards-on-file", "-fake-no-show-answer-lost")
        tap("appointment-Kim Sample")
        tap("chargeFee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "No-show fee charged"))
        XCTAssertFalse(element("feeError").exists, "No \"we don't know yet\" under a fee Stripe charged")
        XCTAssertFalse(element("chargeFee").exists, "A fee is charged once")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTab("Take payment")
        tap("paymentsTodayLink")
        XCTAssertTrue(waitForLabel(element("paymentsFees"), containing: "$35.00"))
    }

    /// The same for a decline: it shows with the bank's reason and Charge again, and nothing else.
    func testADeclineWhoseAnswerIsLostShowsTheDecline() {
        launch("-fake-cards-on-file", "-fake-no-show-declined", "-fake-no-show-answer-lost")
        tap("appointment-Kim Sample")
        tap("chargeFee")
        tapDialogButton("Charge $35", identifier: "confirmChargeFee")
        let status = reveal("feeStatus")
        XCTAssertTrue(waitForLabel(status, containing: "Declined"), "Got: \(status.label)")
        XCTAssertTrue(status.label.contains("there isn't enough money on it"), "Got: \(status.label)")
        XCTAssertFalse(element("feeError").exists, "Stripe's answer is on screen")
        XCTAssertTrue(waitForLabel(reveal("chargeFee"), containing: "Charge again ($35)"))
    }

    /// Nia Sample booked online with a card for 2:30 PM. Until her haircut ends (3:15 PM) she may
    /// still come, so there's no Mark no-show yet, and no fee to charge. Once she's marked done and
    /// reopened, there's never one.
    func testANoShowWithACardWaitsForTheEnd() {
        launch("-fake-cards-on-file")
        let row = reveal("appointment-Nia Sample")
        XCTAssertTrue(row.label.contains("Card on file"), "Got: \(row.label)")
        row.tap()
        XCTAssertTrue(statusShows("Booked"))
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: "you can mark a no-show once the appointment has ended"))
        XCTAssertFalse(element("chargeFee").exists)
        XCTAssertTrue(reveal("markCompleted").exists)
        XCTAssertFalse(element("markNoShow").exists, "Not before the end")
        XCTAssertTrue(waitForLabel(reveal("noShowHint"), containing: "once the appointment ends at 3:15 PM"))

        // Marked done, then reopened: the client came, so it never becomes a no-show (the server's
        // `completedAt`), and the details say so in the server's words.
        tap("markCompleted")
        XCTAssertTrue(statusShows("Completed"))
        tap("reopenAppointment")
        XCTAssertTrue(statusShows("Booked"))
        let completedLine = "This appointment was marked completed, so it can't become a no-show."
        XCTAssertTrue(waitForLabel(reveal("noShowHint"), containing: completedLine))
        XCTAssertFalse(element("markNoShow").exists, "Never, once it was completed")
        XCTAssertTrue(waitForLabel(reveal("feeStatus"), containing: completedLine))
        XCTAssertFalse(element("chargeFee").exists)
        screenshot("O33-Completed-Then-Reopened")

        tap("cancelAppointment")
        XCTAssertTrue(text(containing: "There's no fee when the shop cancels.").waitForExistence(timeout: 10))
    }

    func testTurnOnNoShowProtectionWithAFlatFee() {
        launch()
        openTab("Settings")
        let link = reveal("noShowSettingsLink")
        XCTAssertTrue(waitForLabel(link, containing: "Off: clients book online without a card"), "Got: \(link.label)")
        link.tap()
        flipSwitch(reveal("noShowEnabled"))
        XCTAssertTrue(waitForLabel(reveal("noShowExample"), containing: "A $40 haircut: $40"))
        XCTAssertTrue(waitForLabel(reveal("noShowClientWarning"), containing: "Full Service Cancellation & No-Show Fee"))
        screenshot("O31-No-Show-Settings")

        // A flat amount the server wouldn't take is explained, and Save says so too.
        reveal("noShowFeeMode", searchingFirst: .up)
        tapButton("Flat amount")
        replaceText(in: "noShowFlatAmount", with: "600")
        XCTAssertTrue(waitForLabel(reveal("noShowSettingsProblem"), containing: "Pick a flat fee from $0.50 to $500."))
        tap("saveNoShowSettings")
        XCTAssertTrue(waitForLabel(reveal("noShowSaveError"), containing: "Pick a flat fee from $0.50 to $500."))
        // $25 for every booking: both messages go as soon as it's fixed, before any Save.
        reveal("noShowFlatAmount", searchingFirst: .up)
        replaceText(in: "noShowFlatAmount", with: "25")
        XCTAssertTrue(waitForDisappearance(of: element("noShowSettingsProblem")))
        closeKeyboard()
        XCTAssertTrue(waitForLabel(reveal("noShowExample"), containing: "A $40 haircut: $25"))
        XCTAssertTrue(waitForLabel(reveal("noShowCapNote"), containing: "A fee is never more than the booked service's price."))
        let warning = reveal("noShowClientWarning")
        XCTAssertTrue(waitForLabel(warning, containing: "Late Cancellation & No-Show Fee"), "Got: \(warning.label)")
        XCTAssertTrue(warning.label.contains("may be charged $25."), "Got: \(warning.label)")
        // The Save message sits just above Stripe's costs. It's looked for with those on screen:
        // under the keyboard, a busy simulator kept reporting it there after it had gone.
        reveal("noShowCosts")
        XCTAssertTrue(waitForDisappearance(of: element("noShowSaveError")), "The old Save message goes with the fix")
        tap("saveNoShowSettings")
        XCTAssertTrue(reveal("noShowSaved").exists, "Saved to the server")
        screenshot("O32-No-Show-Settings-Saved")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(reveal("noShowSettingsLink"), containing: "On: $25 flat for no-shows and cancellations less than 1 hour before"))
    }

    func testLateCancellationsCanBeOffOrGivenAnotherWindow() {
        launch()
        openTab("Settings")
        tap("noShowSettingsLink")
        flipSwitch(reveal("noShowEnabled"))
        tap("noShowWindow")
        tapButton("2 hours before")
        XCTAssertTrue(waitForLabel(reveal("noShowClientWarning"), containing: "Cancelling less than 2 hours before your appointment"))

        // Only no-shows.
        flipSwitch(reveal("noShowLateCancel", searchingFirst: .up))
        XCTAssertTrue(waitForDisappearance(of: element("noShowWindow")))
        let warning = reveal("noShowClientWarning")
        XCTAssertTrue(waitForLabel(warning, containing: "Not showing up may be charged the full service price ($40)."), "Got: \(warning.label)")
        tap("saveNoShowSettings")
        XCTAssertTrue(reveal("noShowSaved").exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForLabel(reveal("noShowSettingsLink"), containing: "On: the full service price for no-shows"))
    }

    /// The sample clients with a card on file booked with protection on, so it's on. Turning it off
    /// says plainly that their fees stay: each booking keeps the terms it was made with.
    func testTurningProtectionOffSaysBookingsWithACardKeepTheirFee() {
        launch("-fake-cards-on-file")
        openTab("Settings")
        let link = reveal("noShowSettingsLink")
        XCTAssertTrue(waitForLabel(link, containing: "On: the full service price for no-shows and cancellations less than 1 hour before"), "Got: \(link.label)")
        link.tap()
        flipSwitch(reveal("noShowEnabled"))
        XCTAssertTrue(
            text(containing: "Bookings already made with a card keep their fee, and you can still charge it.").waitForExistence(timeout: 10),
            "Off doesn't take away the fees already agreed"
        )
        XCTAssertFalse(text(containing: "no fee can be charged").exists)
        tap("cancelNoShowSettings")
        tapDialogButton("Discard changes", identifier: "confirmDiscardNoShowSettings")
        XCTAssertTrue(waitForLabel(reveal("noShowSettingsLink"), containing: "On:"), "Nothing was saved")
    }

    func testUnsavedNoShowChangesAskBeforeTheyreDiscarded() {
        launch()
        openTab("Settings")
        tap("noShowSettingsLink")
        flipSwitch(reveal("noShowEnabled"))
        tap("cancelNoShowSettings")
        tapDialogButton("Discard changes", identifier: "confirmDiscardNoShowSettings")
        XCTAssertTrue(waitForLabel(reveal("noShowSettingsLink"), containing: "Off: clients book online without a card"), "Nothing was saved")
    }

    func testNoShowSettingsOfflineOfferToTryAgain() {
        launch("-fake-offline")
        openTab("Settings")
        let link = reveal("noShowSettingsLink")
        XCTAssertTrue(waitForLabel(link, containing: "Couldn't load"), "Got: \(link.label)")
        link.tap()
        XCTAssertTrue(element("retryNoShowSettings").waitForExistence(timeout: 10), "No way to try again")
        XCTAssertTrue(text(containing: "Couldn't load the settings").exists)
    }

    // MARK: Empty and offline

    func testAnEmptyShop() {
        launch("-fake-empty")
        XCTAssertTrue(element("scheduleEmpty").waitForExistence(timeout: 10))
        screenshot("O20-Empty-Day")
        openProducts()
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
        ringUp("500")
        tap("tapToPayButton")
        tap("simulateApprove")
        XCTAssertTrue(waitForLabel(element("statusPaid"), containing: "Test payment approved"))
        tap("paymentDone")
    }

    // MARK: Helpers

    /// Settings → Products.
    private func openProducts(file: StaticString = #filePath, line: UInt = #line) {
        openTab("Settings", file: file, line: line)
        tap("productsLink", file: file, line: line)
        XCTAssertTrue(app.navigationBars["Products"].waitForExistence(timeout: 10), "Products didn't open", file: file, line: line)
    }

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

    /// Take payment: Sold by `barber`, and one amount on the ticket from the keypad ("1250" is $12.50).
    private func ringUp(_ digits: String, soldBy barber: String = "Izzy", file: StaticString = #filePath, line: UInt = #line) {
        tap("soldBy-\(barber)", file: file, line: line)
        tap("addAmount", file: file, line: line)
        XCTAssertTrue(element("amountEntryValue").waitForExistence(timeout: 10), "The keypad didn't open", file: file, line: line)
        enterAmount(digits)
        tap("saveAmount", file: file, line: line)
        XCTAssertTrue(waitForDisappearance(of: element("amountEntryValue")), "The keypad didn't close", file: file, line: line)
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
        // On a slow simulator the keyboard can still be with the previous field when typing starts,
        // and typing then fails ("Neither element nor any descendant has keyboard focus"). A tap
        // that was dropped is made again after 10 seconds, as elsewhere.
        if !waitForKeyboardFocus(on: field, timeout: 10) {
            field.tap()
            XCTAssertTrue(waitForKeyboardFocus(on: field), "\(identifier) didn't get the keyboard", file: file, line: line)
        }
        field.typeText(text)
    }

    /// Whether `field` has the keyboard within `timeout`. `hasKeyboardFocus` isn't in XCUIElement's
    /// public interface, so where it's missing this only waits for a keyboard to show.
    ///
    /// While a keyboard comes up, one look at a busy simulator's screen can take over 4 seconds:
    /// the product editor's Name field had the keyboard (the screen recording shows its cursor and
    /// the keyboard), but each 5-second wait fit in only one look, which ended too late, twice. The
    /// wait allows 20 seconds like the others; the field having the keyboard ends it at once.
    private func waitForKeyboardFocus(on field: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        guard field.responds(to: NSSelectorFromString("hasKeyboardFocus")) else {
            return app.keyboards.firstMatch.waitForExistence(timeout: timeout)
        }
        return waitUntil(field, toMatch: NSPredicate(format: "hasKeyboardFocus == true"), timeout: timeout)
    }

    /// Replaces a text field's text: taps its trailing end (so the cursor goes after the text),
    /// deletes what's there and types `text`.
    private func replaceText(in identifier: String, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = reveal(identifier, file: file, line: line)
        let trailingEnd = field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        trailingEnd.tap()
        if !waitForKeyboardFocus(on: field, timeout: 10) {
            trailingEnd.tap()
            XCTAssertTrue(waitForKeyboardFocus(on: field), "No keyboard for \(identifier)", file: file, line: line)
        }
        let value = field.value as? String ?? ""
        let current = value == field.placeholderValue ? "" : value
        // "\u{8}" is the keyboard's delete key (XCUIKeyboardKey.delete.rawValue).
        field.typeText(String(repeating: "\u{8}", count: current.count) + text)
    }

    /// Closes the keyboard with the Done button above it (a decimal pad has no return key). A busy
    /// simulator can take seconds to show Done, or to let the keyboard go after it, so Done is
    /// looked for until it shows, and tapped once more if the keyboard is still up after 10
    /// seconds: Done only ever closes the keyboard.
    private func closeKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let doneButtons = [element("flatAmountDone"), app.toolbars.buttons["Done"]]
        guard let done = firstToShow(doneButtons, timeout: 10) else {
            drag(.up)
            _ = waitForDisappearance(of: keyboard)
            return
        }
        done.tap()
        if !waitForDisappearance(of: keyboard, timeout: 10), let again = firstToShow(doneButtons, timeout: 2) {
            again.tap()
        }
        _ = waitForDisappearance(of: keyboard)
    }

    /// The first text on screen that contains `fragment`: a dialog's title or message, a footer.
    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
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

    /// On screen and tappable. isHittable is only asked about an element whose middle is on the
    /// screen: for one scrolled out of sight, XCUITest can fail the test ("Activation point
    /// invalid") instead of answering no.
    private func isOnScreen(_ target: XCUIElement) -> Bool {
        guard target.exists else { return false }
        let frame = target.frame
        guard !frame.isEmpty, app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return target.isHittable
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
    /// A busy simulator can take seconds to say what's on screen, so a wait can run out while the
    /// switch has already moved: it's tapped again only if it still reads as before, since a second
    /// tap on a switch that moved puts it back.
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
        if waitUntil(control, toMatch: flipped, timeout: 10) { return }
        if control.value as? String == before {
            // The tap was lost: tap the switch's end of the row.
            trailingEnd.tap()
        }
        XCTAssertTrue(waitUntil(control, toMatch: flipped, timeout: 10), "The switch didn't move", file: file, line: line)
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
        // Menus and pickers can show their choices as menu items, cells or text. A busy simulator
        // can take longer than 5 seconds to show them, so all of these are looked for until one shows.
        let choices = [button] + [app.menuItems, app.cells, app.staticTexts].map { $0.matching(predicate).firstMatch }
        guard let choice = firstToShow(choices, timeout: 15) else {
            XCTFail("Missing the \(label) button", file: file, line: line)
            return
        }
        choice.tap()
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

    /// Answers a confirmation dialog with its cancel button ("Keep it") and waits for `question`
    /// to go. iOS 26 shows a dialog that comes from a button on the screen as a popover without
    /// its cancel button: there, a tap outside the popover gives the same answer.
    private func tapDialogCancelButton(
        _ label: String,
        identifier: String,
        closing question: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let byIdentifier = element(identifier)
        let byLabel = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        let outside = app.otherElements["PopoverDismissRegion"]
        // A busy simulator can take seconds to show the dialog, so all three are looked for until
        // one shows.
        let shown = firstToShow([byIdentifier, byLabel, outside])
        if shown === outside {
            // The popover is narrower than the screen: its left edge is clear of it.
            outside.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        } else if let shown {
            shown.tap()
        } else {
            XCTFail("No \(label) button, and no popover to tap outside of", file: file, line: line)
        }
        XCTAssertTrue(waitForDisappearance(of: question), "The dialog didn't close", file: file, line: line)
    }

    /// The first of `elements` that's on the screen, looking at each in turn until one is or
    /// `timeout` runs out. One look at a busy simulator's screen can take seconds, so a single
    /// look at each isn't enough to say none of them is coming.
    private func firstToShow(_ elements: [XCUIElement], timeout: TimeInterval = 20) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let shown = elements.first(where: { $0.exists }) {
                return shown
            }
            guard Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.5)
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
