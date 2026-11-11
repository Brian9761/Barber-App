import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Take payment's ticket: adding, removing and editing items, totals, who it's for and who sold it,
/// and the sale it becomes. (The tests are async only so Linux's test runner takes them in a
/// main-actor class.)
@MainActor
final class CheckoutTicketTests: XCTestCase {
    private let catalog = Catalog.izzyClipz

    private func product(_ name: String, cents: Int?) -> IzzyAPI.Product {
        IzzyAPI.Product(id: "p-\(name)", name: name, description: nil, priceCents: cents, imageUrl: nil, visible: true)
    }

    func testAWalkInStartsEmptyWithTheBarberGiven() async {
        let ticket = CheckoutTicket(barberId: "carlos-rafael")
        XCTAssertTrue(ticket.isEmpty)
        XCTAssertEqual(ticket.totalCents, 0)
        XCTAssertEqual(ticket.barberId, "carlos-rafael")
        XCTAssertNil(ticket.appointment)
        XCTAssertNil(ticket.customerName, "A walk-in's name is optional")
    }

    func testServicesProductsAndAmountsAddUp() async throws {
        var ticket = CheckoutTicket(barberId: "israel-flores")
        let haircut = try XCTUnwrap(catalog.offerings.first { $0.barberID == "israel-flores" && $0.serviceID == "haircut" })
        ticket.addService(id: "haircut", name: "Haircut", price: haircut.price)
        ticket.addProduct(product("Pomade", cents: 1800), unitCents: 1800)
        ticket.addProduct(product("Pomade", cents: 1800), unitCents: 1800)
        ticket.addAmount(500, name: "  ")
        ticket.addAmount(2500, name: " Gift card ")
        XCTAssertEqual(ticket.items.map(\.name), ["Haircut", "Pomade", "Other", "Gift card"])
        XCTAssertEqual(ticket.items[1].quantity, 2, "The same product again is one more, not another line")
        XCTAssertEqual(ticket.items[1].priceLabel, "2 × $18.00")
        XCTAssertEqual(ticket.totalCents, 4000 + 3600 + 500 + 2500)
        XCTAssertEqual(Set(ticket.items.map(\.id)).count, 4, "Every line has its own id")
    }

    func testRemovingAndChangingItems() async throws {
        var ticket = CheckoutTicket(barberId: "israel-flores")
        ticket.addProduct(product("Pomade", cents: 1800), unitCents: 1800)
        ticket.addAmount(1000, name: "Tip")
        let pomade = try XCTUnwrap(ticket.items.first)
        ticket.setQuantity(3, of: pomade.id)
        XCTAssertEqual(ticket.totalCents, 6400)
        ticket.setQuantity(0, of: pomade.id)
        XCTAssertEqual(ticket.item(withID: pomade.id)?.quantity, 1, "At least 1")
        ticket.setQuantity(500, of: pomade.id)
        XCTAssertEqual(ticket.item(withID: pomade.id)?.quantity, 99, "At most 99")
        ticket.setPrice(1500, of: pomade.id)
        XCTAssertEqual(ticket.item(withID: pomade.id)?.unitCents, 1500)
        ticket.remove(pomade.id)
        XCTAssertEqual(ticket.items.map(\.name), ["Tip"])
        XCTAssertEqual(ticket.totalCents, 1000)
    }

    func testAFromPriceIsMarkedUntilItsChanged() async throws {
        var ticket = CheckoutTicket(barberId: "israel-flores")
        ticket.addService(id: "lightener", name: "Lightener", price: .startingAt(dollars: 80))
        let item = try XCTUnwrap(ticket.items.first)
        XCTAssertTrue(item.startsAtThisPrice)
        ticket.setPrice(9500, of: item.id)
        XCTAssertFalse(ticket.item(withID: item.id)?.startsAtThisPrice ?? true)
        XCTAssertEqual(ticket.totalCents, 9500)
    }

    func testAnAppointmentsTicketIsItsClientBarberAndServiceAtItsPrice() async throws {
        let harness = Harness()
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        var ticket = CheckoutTicket(appointment: andre, catalog: catalog, shopTime: TestClock.shopTime, now: TestClock.now)
        XCTAssertEqual(ticket.appointmentId, andre.id)
        XCTAssertEqual(ticket.appointment?.when, "Today at 11:30 AM")
        XCTAssertEqual(ticket.appointment?.priceLabel, "$55")
        XCTAssertEqual(ticket.barberId, "israel-flores")
        XCTAssertEqual(ticket.customerName, "Andre Sample")
        XCTAssertEqual(ticket.items.map(\.name), ["Haircut & Beard"])
        XCTAssertEqual(ticket.totalCents, 5500)

        // Not for this appointment: the same client as a walk-in, with what's on the ticket.
        ticket.forgetAppointment()
        XCTAssertNil(ticket.appointmentId)
        XCTAssertEqual(ticket.walkInName, "Andre Sample")
        XCTAssertEqual(ticket.customerName, "Andre Sample")
        XCTAssertEqual(ticket.totalCents, 5500)
    }

    func testWhatsMissingIsSaidBeforeRecording() async {
        var ticket = CheckoutTicket()
        XCTAssertEqual(ticket.problem(for: .cash), "Add a service, a product or an amount first.")
        ticket.addAmount(30, name: "")
        XCTAssertEqual(ticket.problem(for: .cash), "Pick who gets credit for this sale, under Sold by.")
        ticket.barberId = "israel-flores"
        XCTAssertNil(ticket.problem(for: .cash), "Cash can be any amount")
        XCTAssertEqual(ticket.problem(for: .card), Money.cardRangeText, "A card needs at least $0.50")
        ticket.walkInName = String(repeating: "n", count: 61)
        XCTAssertEqual(ticket.problem(for: .other), "Keep the client's name to 60 characters or fewer.")
        ticket.walkInName = ""
        ticket.addAmount(1_000_000, name: "Big")
        XCTAssertEqual(ticket.problem(for: .cash), "A sale can be at most $10,000. Split it into two sales.")
    }

    func testAtMostTwentyItems() async {
        var ticket = CheckoutTicket(barberId: "israel-flores")
        for index in 1...21 { ticket.addAmount(100, name: "Item \(index)") }
        XCTAssertEqual(ticket.problem(for: .cash), "A sale can have at most 20 items. Split it into two sales.")
    }

    func testTheSaleCarriesEveryPriceTheBarberAndTheClient() async throws {
        let harness = Harness()
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        var ticket = CheckoutTicket(appointment: andre, catalog: catalog, shopTime: TestClock.shopTime, now: TestClock.now)
        ticket.addProduct(product("Pomade", cents: 1800), unitCents: 1800)
        let sale = ticket.newSale(method: .cash)
        XCTAssertEqual(sale.method, .cash)
        XCTAssertEqual(sale.appointmentId, andre.id)
        XCTAssertEqual(sale.barberId, "israel-flores")
        XCTAssertEqual(sale.customerName, "Andre Sample")
        XCTAssertEqual(sale.items, [.service("haircut-and-beard", unitCents: 5500), .product("p-Pomade", unitCents: 1800)])
        XCTAssertEqual(sale.totalCents, 7300, "Every item has its price: the total the owner sees is the one recorded")
        XCTAssertTrue(sale.isValid)
    }

    func testTheCardDescriptionNamesWhatWasSoldAndWhoNeverTheClient() async throws {
        let harness = Harness()
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        var ticket = CheckoutTicket(appointment: andre, catalog: catalog, shopTime: TestClock.shopTime, now: TestClock.now)
        XCTAssertEqual(ticket.paymentDescription(barberName: "Izzy"), "Haircut & Beard with Izzy")
        ticket.addProduct(product("Pomade", cents: 1800), unitCents: 1800)
        ticket.addAmount(500, name: "Tip")
        ticket.addAmount(500, name: "Comb")
        XCTAssertEqual(ticket.paymentDescription(barberName: "Izzy"), "Haircut & Beard, Pomade and 2 more with Izzy")
        XCTAssertFalse(ticket.paymentDescription(barberName: "Izzy").contains("Andre"))
    }

    func testTheReceiptSaysWhatWasSoldHowAndByWhom() async {
        let sale = IzzyAPI.Sale(
            id: "s1", barberId: "carlos-rafael", barberName: "Carlos", customerName: "Diego Sample", method: .cash,
            items: [
                IzzyAPI.SaleItem(kind: .service, serviceId: "haircut", name: "Haircut", unitCents: 4000),
                IzzyAPI.SaleItem(kind: .product, productId: "p", name: "Pomade", quantity: 2, unitCents: 900),
            ],
            soldAt: TestClock.now
        )
        let receipt = SaleReceipt(sale: sale)
        XCTAssertEqual(receipt.summary, "Sold $58 · Cash · Carlos")
        XCTAssertEqual(receipt.summary, sale.receiptLine, "The Kit's words")
        XCTAssertEqual(receipt.lines.map(\.price), ["$40.00", "2 × $9.00"])
        XCTAssertEqual(receipt.lines.map(\.total), ["$40.00", "$18.00"])
        XCTAssertEqual(receipt.clientName, "Diego Sample")
    }
}

/// Recording cash and other sales: the question's words, the states, one sale per checkout however
/// many tries, and the barber remembered for the next walk-in.
@MainActor
final class SaleFlowTests: XCTestCase {
    private var harness: Harness!
    private var api: ScriptedAPI!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        harness = Harness()
        api = ScriptedAPI(base: harness.api)
        defaults = makeDefaults()
    }

    private func makeCheckout() -> CheckoutModel {
        let checkout = CheckoutModel(
            api: api, shopTime: TestClock.shopTime, clock: { TestClock.now },
            terminal: SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .zero),
            practiceTerminal: SimulatedPaymentTerminal(automaticOutcome: .approve, stepDelay: .zero),
            pending: PendingPayments(defaults: defaults), usesSampleServer: true, deviceSupportsTapToPay: true,
            defaults: defaults
        )
        checkout.update(stripe: .init(configured: true, mode: .test, locationId: "tml_sample_location"))
        return checkout
    }

    func testACashCheckoutOfAnAppointmentChecksItOutAndPaysIt() async throws {
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        let checkout = makeCheckout()
        var recorded = 0
        checkout.onSaleRecorded = { recorded += 1 }
        XCTAssertTrue(checkout.start(for: andre))
        checkout.record(.cash)
        XCTAssertEqual(checkout.phase, .recording(.cash))
        await checkout.waitUntilSettled()
        guard case .recorded(let receipt) = checkout.phase else { return XCTFail("Got \(checkout.phase)") }
        XCTAssertEqual(receipt.summary, "Sold $55 · Cash · Izzy")
        XCTAssertEqual(recorded, 1)
        let checkedOut = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        XCTAssertEqual(checkedOut.status, .completed)
        XCTAssertEqual(checkedOut.sale?.paidLabel, "Paid $55 · Cash")
        XCTAssertEqual(checkedOut.payment.status, .paid)
        XCTAssertEqual(AppointmentBadges(appointment: checkedOut).items.map(\.text), ["Completed", "Paid $55 · Cash"])
        XCTAssertEqual(PaymentSummary(appointment: checkedOut).value, "$55 · Cash")

        checkout.reset()
        XCTAssertTrue(checkout.ticket.isEmpty)
        XCTAssertEqual(checkout.ticket.barberId, "israel-flores", "The last barber stays for the next walk-in")
    }

    func testAProductOnlyWalkInPaidAnotherWay() async throws {
        let checkout = makeCheckout()
        checkout.chooseBarber("cristian-ceja")
        let pomade = try XCTUnwrap(harness.server.products.first { $0.name == "Sample pomade" })
        checkout.ticket.addProduct(pomade, unitCents: 1800)
        checkout.ticket.addProduct(pomade, unitCents: 1800)
        checkout.ticket.walkInName = "  Walk-in Sample "
        checkout.record(.other)
        await checkout.waitUntilSettled()
        guard case .recorded(let receipt) = checkout.phase else { return XCTFail("Got \(checkout.phase)") }
        XCTAssertEqual(receipt.summary, "Sold $36 · Other · Cristian")
        let sale = try XCTUnwrap(harness.server.sales.last)
        XCTAssertNil(sale.appointmentId)
        XCTAssertEqual(sale.customerName, "Walk-in Sample")
        XCTAssertEqual(sale.items.first?.quantity, 2)
    }

    func testAProductWithoutAPriceTakesTheOneTyped() async throws {
        let checkout = makeCheckout()
        checkout.chooseBarber("julian-ramos")
        let oil = try XCTUnwrap(harness.server.products.first { $0.name == "Sample beard oil" })
        XCTAssertNil(oil.priceCents)
        checkout.ticket.addProduct(oil, unitCents: 1200)
        checkout.record(.cash)
        await checkout.waitUntilSettled()
        XCTAssertEqual(harness.server.sales.last?.items.first?.unitCents, 1200)
        XCTAssertEqual(harness.server.sales.last?.items.first?.name, "Sample beard oil")
    }

    func testALostAnswerIsRecordedAgainWithTheSameKeyAndSavedOnce() async throws {
        harness.server.options.loseNextSaleAnswer = true
        let checkout = makeCheckout()
        checkout.ring(4000)
        checkout.record(.cash)
        await checkout.waitUntilSettled()
        guard case .recordUnknown(let message) = checkout.phase else { return XCTFail("Got \(checkout.phase)") }
        XCTAssertTrue(message.hasPrefix("We couldn't reach the server."), message)
        XCTAssertTrue(message.contains("the same sale is never saved twice"), message)
        let before = harness.server.sales.count

        checkout.recordAgain()
        await checkout.waitUntilSettled()
        guard case .recorded = checkout.phase else { return XCTFail("Got \(checkout.phase)") }
        XCTAssertEqual(harness.server.sales.count, before, "The first try had gone through: no second sale")
        XCTAssertEqual(api.saleKeys.count, 2)
        XCTAssertEqual(api.saleKeys[0], api.saleKeys[1], "The same key both times")

        // The next sale gets a new key.
        checkout.reset()
        checkout.ring(4000)
        checkout.record(.cash)
        await checkout.waitUntilSettled()
        XCTAssertNotEqual(api.saleKeys.last, api.saleKeys.first)
        XCTAssertEqual(harness.server.sales.count, before + 1)
    }

    func testAChangedTicketGetsANewKey() {
        let checkout = makeCheckout()
        checkout.ring(4000)
        let first = checkout.saleKey(for: checkout.ticket.newSale(method: .cash))
        XCTAssertEqual(checkout.saleKey(for: checkout.ticket.newSale(method: .cash)), first, "The same sale, the same key")
        checkout.ticket.addAmount(500, name: "Tip")
        XCTAssertNotEqual(checkout.saleKey(for: checkout.ticket.newSale(method: .cash)), first)
        XCTAssertNotEqual(checkout.saleKey(for: checkout.ticket.newSale(method: .other)), first)
    }

    func testTheServerTurningASaleDownSaysWhy() async throws {
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        let checkout = makeCheckout()
        checkout.start(for: andre)
        // Checked out meanwhile on the website.
        let draft = try harness.server.draftSale(barberId: nil, appointmentId: andre.id, customerName: nil, items: [.service(andre.serviceId)])
        harness.server.insertSale(draft, method: .other, paymentIntentId: nil, soldAt: TestClock.now)
        checkout.record(.cash)
        await checkout.waitUntilSettled()
        XCTAssertEqual(checkout.phase, .recordFailed("This appointment was already checked out."))
        checkout.backToEditing()
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertEqual(checkout.amountCents, 5500, "The ticket stays")
    }

    func testNothingIsSentForATicketThatIsntReady() async {
        let checkout = makeCheckout()
        checkout.record(.cash)
        XCTAssertEqual(checkout.phase, .editing)
        XCTAssertEqual(checkout.validationMessage, "Add a service, a product or an amount first.")
        XCTAssertTrue(api.saleKeys.isEmpty)
    }

    func testTheLastBarberChosenIsTheNextTicketsDefault() {
        let checkout = makeCheckout()
        XCTAssertNil(checkout.ticket.barberId, "Nobody yet on a new iPhone")
        checkout.chooseBarber("flowxbori")
        XCTAssertEqual(makeCheckout().ticket.barberId, "flowxbori", "Kept on this iPhone")
        checkout.chooseBarber("not-a-barber")
        XCTAssertEqual(checkout.ticket.barberId, "flowxbori", "Only barbers on the team")
    }

    func testACardPaymentRecordsItsSaleOnceItGoesThrough() async throws {
        let checkout = makeCheckout()
        let terminal = try XCTUnwrap(checkout.terminal as? SimulatedPaymentTerminal)
        let server = harness.server
        terminal.onApproved = { server.cardApproved(clientSecret: $0) }
        checkout.chooseBarber("carlos-rafael")
        checkout.ticket.addAmount(2500, name: "Gift card")
        var recorded = 0
        checkout.onSaleRecorded = { recorded += 1 }
        let before = harness.server.sales.count
        checkout.charge()
        await checkout.waitUntilSettled()
        guard case .succeeded(let receipt) = checkout.phase else { return XCTFail("Got \(checkout.phase)") }
        XCTAssertEqual(receipt.sale?.summary, "Sold $25 · Card · Carlos")
        XCTAssertEqual(harness.server.sales.count, before + 1)
        XCTAssertEqual(harness.server.sales.last?.method, .card)
        XCTAssertEqual(harness.server.sales.last?.items.first?.name, "Gift card")
        XCTAssertEqual(recorded, 1)
    }
}

/// Today's sales and voiding one.
@MainActor
final class SalesStoreTests: XCTestCase {
    func testTodaysSalesNewestFirstWithTheTotals() async {
        let harness = Harness()
        let store = SalesStore(api: harness.api, shopTime: TestClock.shopTime, clock: { TestClock.now })
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.sales.map(\.customerName), ["Diego Sample", "Marcus Sample"], "This morning's checkouts, newest first")
        let diego = store.sales[0]
        XCTAssertEqual(diego.receiptLine, "Sold $63 · Cash · Carlos", "Carlos's $45 haircut and the $18 sample pomade")
        XCTAssertEqual(store.rowDetail(for: diego), "11 AM · Diego Sample · Carlos · Cash")
        let marcus = store.sales[1]
        XCTAssertEqual(marcus.receiptLine, "Sold $40 · Card · Izzy", "His card payment's sale")
        XCTAssertNotNil(marcus.paymentIntentId)
        XCTAssertEqual(store.totalsText, "$103.00 · 2 sales")
    }

    func testVoidingACashSaleStopsItCountingAndUnpaysTheAppointment() async throws {
        let harness = Harness()
        let store = SalesStore(api: harness.api, shopTime: TestClock.shopTime, clock: { TestClock.now })
        var voided: [String] = []
        store.onVoided = { voided.append($0.id) }
        await store.refresh()
        let diego = try XCTUnwrap(store.sales.first)
        XCTAssertEqual(SalesStore.voidQuestion(for: diego), "Void this $63 cash sale?")
        XCTAssertEqual(SalesStore.voidExplanation(for: diego), "It stops counting in your sales, and the appointment can be checked out again.")

        let ok = await store.void(diego, reason: "  Rang it up twice ")
        XCTAssertTrue(ok)
        let after = try XCTUnwrap(store.sale(withID: diego.id))
        XCTAssertTrue(after.isVoided)
        XCTAssertEqual(after.voidReason, "Rang it up twice")
        XCTAssertEqual(store.totalsText, "$40.00 · 1 sale", "Voided sales don't count")
        XCTAssertEqual(store.voidMessages[diego.id], "The sale was voided, so it no longer counts in your sales.")
        XCTAssertEqual(voided, [diego.id])
        let appointment = try XCTUnwrap(harness.appointment(named: "Diego Sample"))
        XCTAssertNil(appointment.sale)
        XCTAssertEqual(appointment.payment.status, .unpaid)
        XCTAssertEqual(appointment.status, .completed, "It stays completed")
        XCTAssertTrue(appointment.canCheckOut, "…and can be checked out again")
    }

    func testVoidingACardSaleSaysToRefundTheCardInStripe() async throws {
        let card = IzzyAPI.Sale(id: "s", barberId: "israel-flores", barberName: "Izzy", method: .card, paymentIntentId: "pi_1", items: [], soldAt: TestClock.now)
        XCTAssertTrue(SalesStore.voidExplanation(for: card).contains("refund the card in your Stripe Dashboard"))
        XCTAssertEqual(IzzyAPI.VoidedSale(sale: card).message, "The sale was voided, so it no longer counts in your sales. Voiding doesn't refund the card: refunds are made in the Stripe Dashboard.")
    }

    func testAReasonOver200CharactersIsntSent() async throws {
        let harness = Harness()
        let store = SalesStore(api: harness.api, shopTime: TestClock.shopTime, clock: { TestClock.now })
        await store.refresh()
        let diego = try XCTUnwrap(store.sales.first)
        let ok = await store.void(diego, reason: String(repeating: "r", count: 201))
        XCTAssertFalse(ok)
        XCTAssertEqual(store.actionError, "Keep the reason to 200 characters or fewer.")
        XCTAssertFalse(harness.server.sales.first { $0.id == diego.id }?.isVoided ?? true)
    }

    func testSalesThatDontLoadSayWhy() async {
        var options = FakeServer.Options()
        options.offline = true
        let store = SalesStore(api: Harness(options: options).api, shopTime: TestClock.shopTime, clock: { TestClock.now })
        await store.refresh()
        XCTAssertEqual(store.loadState, .failed(ErrorText.message(for: APIError.offline)))
    }

    func testCheckOutFromTheScheduleOpensTakePaymentWithTheTicket() async throws {
        let environment = AppEnvironment.sample(arguments: [LaunchArgument.signedIn], stepDelay: .zero)
        let model = AppModel(environment: environment)
        await model.start()
        let workspace = try XCTUnwrap(model.workspace)
        await workspace.schedule.refresh()
        let andre = try XCTUnwrap(workspace.schedule.appointments.first { $0.customer.name == "Andre Sample" })
        XCTAssertTrue(workspace.checkOut(andre))
        XCTAssertEqual(workspace.selectedTab, .payment)
        XCTAssertEqual(workspace.checkout.ticket.appointmentId, andre.id)

        workspace.checkout.record(.cash)
        await workspace.checkout.waitUntilSettled()
        let shown = await eventually { workspace.schedule.appointment(withID: andre.id)?.sale != nil }
        XCTAssertTrue(shown, "The schedule shows it checked out")
        let listed = await eventually { workspace.sales.sales.contains { $0.appointmentId == andre.id } }
        XCTAssertTrue(listed, "Today's sales lists it")
    }
}
