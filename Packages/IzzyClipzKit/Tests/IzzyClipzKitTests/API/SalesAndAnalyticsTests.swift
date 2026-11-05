import XCTest
@testable import IzzyClipzKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sales at checkout in the Kit: the models, the appointment's checkout (which only the shop
/// sees), card payments with a ticket, and the Kit's copy of the server's rules for fakes.
final class SaleModelTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testASale() throws {
        let sale = try decoder.decode(IzzyAPI.SaleResponse.self, from: try kitFixture("sale.json")).sale
        XCTAssertEqual(sale, IzzyAPI.Sale(
            id: "7f8a9b0c-1d2e-4f3a-8b4c-5d6e7f8a9b0c", barberId: "carlos-rafael", barberName: "Carlos",
            appointmentId: "4e5f6a7b-8c9d-4eaf-9b0c-3d4e5f6a7b8c", customerName: "Test Customer", method: .cash,
            items: [
                IzzyAPI.SaleItem(kind: .service, serviceId: "haircut", name: "Haircut", unitCents: 4500),
                IzzyAPI.SaleItem(kind: .product, productId: "6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a", name: "Sample pomade", quantity: 2, unitCents: 1800),
            ],
            soldAt: utc(2026, 11, 2, 20, 5, 12)
        ))
        XCTAssertEqual(sale.totalCents, 8100, "the items' total")
        XCTAssertEqual(sale.totalLabel, "$81")
        XCTAssertEqual(sale.receiptLine, "Sold $81 · Cash · Carlos")
        XCTAssertFalse(sale.isVoided)
        XCTAssertEqual(sale.items.map(\.priceLabel), ["$45", "2 × $18"])
        XCTAssertEqual(IzzyAPI.SaleMethod.allCases.map(\.title), ["Card", "Cash", "Other"])
        // Written back with every field, null when empty.
        let json = try encodeAPI(sale)
        XCTAssertEqual(json["paymentIntentId"], .null)
        XCTAssertEqual(json["voidedAt"], .null)
        XCTAssertEqual(json["voidReason"], .null)
        XCTAssertEqual(json["items"], .array([
            .object(["kind": .string("service"), "serviceId": .string("haircut"), "productId": .null, "name": .string("Haircut"),
                     "quantity": .number(1), "unitCents": .number(4500), "totalCents": .number(4500)]),
            .object(["kind": .string("product"), "serviceId": .null, "productId": .string("6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a"),
                     "name": .string("Sample pomade"), "quantity": .number(2), "unitCents": .number(1800), "totalCents": .number(3600)]),
        ]))
    }

    func testAVoidedCardSaleSaysTheCardIsntRefunded() throws {
        let voided = try decoder.decode(IzzyAPI.VoidedSale.self, from: try kitFixture("sale-voided.json"))
        XCTAssertTrue(voided.sale.isVoided)
        XCTAssertEqual(voided.sale.voidReason, "Charged twice")
        XCTAssertEqual(voided.sale.method, .card)
        XCTAssertEqual(voided.sale.paymentIntentId, "pi_3SampleSampleSample04")
        XCTAssertEqual(voided.message, IzzyAPI.VoidedSale.message(for: .card))
        XCTAssertTrue(voided.message.contains("refunds are made in the Stripe Dashboard"))
        XCTAssertEqual(IzzyAPI.VoidedSale.message(for: .cash), "The sale was voided, so it no longer counts in your sales.")
        XCTAssertEqual(IzzyAPI.VoidedSale(sale: voided.sale), voided, "a fake answers in the server's words")

        // Voiding again changes nothing, like the server.
        let sale = try decoder.decode(IzzyAPI.SaleResponse.self, from: try kitFixture("sale.json")).sale
        let once = sale.voided(at: utc(2026, 11, 2, 21), reason: "  Rang up twice ")
        XCTAssertEqual(once.voidedAt, utc(2026, 11, 2, 21))
        XCTAssertEqual(once.voidReason, "Rang up twice")
        XCTAssertEqual(once.voided(at: utc(2026, 11, 2, 22), reason: "Again"), once)
        XCTAssertNil(sale.voided(at: utc(2026, 11, 2, 21), reason: " ").voidReason)
    }

    func testTheDaysSales() throws {
        let day = try decoder.decode(IzzyAPI.SalesDay.self, from: try kitFixture("sales-day.json"))
        XCTAssertEqual(day.date, LocalDate("2026-11-02"))
        XCTAssertEqual(day.sales.map(\.method), [.other, .card, .cash, .card])
        XCTAssertEqual(day.sales.map(\.isVoided), [false, true, false, false])
        XCTAssertEqual(day.totals, IzzyAPI.SalesDay.Totals(totalCents: 21_100, count: 3), "voided sales don't count")
        XCTAssertEqual(day.totals.totalLabel, "$211")
        XCTAssertEqual(IzzyAPI.SalesDay(date: day.date, sales: day.sales), day, "a fake adds them up like the server")
    }

    /// The Kit adds up a day and words a void exactly like the server, for the server's own examples.
    func testTheKitAddsUpLikeTheServer() throws {
        let day = try decoder.decode(IzzyAPI.SalesDay.self, from: try serverFixture("sales-day.json"))
        XCTAssertTrue(day.sales.contains(where: \.isVoided))
        XCTAssertEqual(IzzyAPI.SalesDay(date: day.date, sales: day.sales).totals, day.totals)
        for sale in day.sales {
            XCTAssertEqual(sale.totalCents, sale.items.reduce(0) { $0 + $1.totalCents }, sale.id)
            for item in sale.items {
                XCTAssertEqual(IzzyAPI.SaleItem(kind: item.kind, serviceId: item.serviceId, productId: item.productId, name: item.name,
                                                quantity: item.quantity, unitCents: item.unitCents), item)
            }
        }
        let voided = try decoder.decode(IzzyAPI.VoidedSale.self, from: try serverFixture("sale-voided.json"))
        XCTAssertEqual(voided.message, IzzyAPI.VoidedSale.message(for: voided.sale.method))
        let created = try decoder.decode(IzzyAPI.SaleResponse.self, from: try serverFixture("sale-created.json")).sale
        XCTAssertEqual(created.items.map(\.kind), [.service, .product, .custom])
    }

    /// A method or item kind a newer server adds reads as other or custom: recorded money, never lost.
    func testUnknownMethodsAndKindsAreKept() throws {
        let text = String(decoding: try kitFixture("sale.json"), as: UTF8.self)
            .replacingOccurrences(of: #""method": "cash""#, with: #""method": "giftCard""#)
            .replacingOccurrences(of: #""kind": "product""#, with: #""kind": "bundle""#)
        let sale = try decodeAPI(IzzyAPI.SaleResponse.self, text).sale
        XCTAssertEqual(sale.method, .other)
        XCTAssertEqual(sale.items.map(\.kind), [.service, .custom])
        XCTAssertEqual(sale.totalCents, 8100)
    }

    func testTheAppointmentsCheckoutOnlyTheShopSees() throws {
        let owner = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json")).appointments
        XCTAssertEqual(owner[0].sale, IzzyAPI.AppointmentSale(id: "6e7f8a9b-0c1d-4e2f-9a3b-4c5d6e7f8a9b", totalCents: 8000, method: .card))
        XCTAssertEqual(owner[0].sale?.paidLabel, "Paid $80 · Card")
        XCTAssertTrue(owner[0].isCheckedOut)
        XCTAssertFalse(owner[0].canCheckOut, "checked out already")
        XCTAssertEqual(owner.dropFirst().map(\.sale), [nil, nil, nil])
        XCTAssertEqual(owner.map(\.canCheckOut), [false, false, false, false], "a no-show or a cancelled one is reopened first")
        // Each is written back as it was read: the shop's view has `sale`, null or not.
        for appointment in owner {
            XCTAssertNotNil(try encodeAPI(appointment)["sale"])
        }
        XCTAssertEqual(try encodeAPI(owner[1])["sale"], .null)

        // The client's own view doesn't have it, and doesn't get it back either.
        let mine = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("appointment.json")).appointment
        XCTAssertNil(mine.sale)
        XCTAssertNil(try encodeAPI(mine)["sale"])
        // Whether the field was there isn't part of the value.
        var members = try XCTUnwrap(JSONSerialization.jsonObject(with: try IzzyAPI.makeEncoder().encode(owner[1])) as? [String: Any])
        XCTAssertNotNil(members.removeValue(forKey: "sale"))
        let customerView = try decoder.decode(IzzyAPI.Appointment.self, from: try JSONSerialization.data(withJSONObject: members))
        XCTAssertNil(try encodeAPI(customerView)["sale"])
        XCTAssertEqual(customerView, owner[1])
        XCTAssertEqual(Set([customerView, owner[1]]).count, 1)

        // Constructed, it's written once it has a sale.
        var made = owner[2]
        made.sale = IzzyAPI.AppointmentSale(id: "s1", totalCents: 4500, method: .other)
        XCTAssertEqual(try encodeAPI(made)["sale"], .object(["id": .string("s1"), "totalCents": .number(4500), "method": .string("other")]))
        XCTAssertNil(try encodeAPI(IzzyAPI.Appointment(
            id: "a1", offeringId: "flowxbori/x", serviceId: "haircut", serviceName: "Haircut", barberId: "flowxbori", barberName: "Flowxbori",
            start: utc(2026, 11, 2, 18), end: utc(2026, 11, 2, 18, 45), durationMinutes: 45, priceLabel: "$35",
            customer: IzzyAPI.Customer(name: "Test"), createdAt: utc(2026, 10, 31)
        ))["sale"])
    }

    func testWhichAppointmentsCanBeCheckedOut() throws {
        var appointment = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("booking-confirmation.json")).appointment
        XCTAssertEqual(appointment.status, .booked)
        XCTAssertTrue(appointment.canCheckOut)
        appointment.status = .completed
        XCTAssertTrue(appointment.canCheckOut, "marked done without a checkout")
        for status in [IzzyAPI.AppointmentStatus.cancelled, .noShow] {
            appointment.status = status
            XCTAssertFalse(appointment.canCheckOut, "\(status)")
        }
        appointment.status = .completed
        let sale = try decoder.decode(IzzyAPI.SaleResponse.self, from: try kitFixture("sale.json")).sale
        appointment.sale = IzzyAPI.AppointmentSale(sale: sale)
        XCTAssertEqual(appointment.sale, IzzyAPI.AppointmentSale(id: sale.id, totalCents: 8100, method: .cash))
        XCTAssertFalse(appointment.canCheckOut)

        // The server's own owner view with a checkout.
        let server = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try serverFixture("owner-appointments-with-sale.json")).appointments
        let checkedOut = try XCTUnwrap(server.first { $0.sale != nil })
        XCTAssertEqual(checkedOut.status, .completed)
        XCTAssertFalse(checkedOut.canCheckOut)
    }

    func testAPaymentKnowsItsSale() throws {
        let payment = try decoder.decode(IzzyAPI.PaymentResponse.self, from: try kitFixture("payment.json")).payment
        XCTAssertEqual(payment.saleId, "6e7f8a9b-0c1d-4e2f-9a3b-4c5d6e7f8a9b")
        let payments = try decoder.decode(IzzyAPI.PaymentsResponse.self, from: try kitFixture("payments.json")).payments
        XCTAssertEqual(payments.map(\.saleId), ["6e7f8a9b-0c1d-4e2f-9a3b-4c5d6e7f8a9b", nil, nil])
        // From a server before sales: none, written back as null.
        let old = try decodeAPI(IzzyAPI.Payment.self, #"{ "id": "pi_1", "amountCents": 500, "description": null, "appointmentId": null, "status": "succeeded", "createdAt": "2026-11-02T19:00:00Z", "kind": "inPerson" }"#)
        XCTAssertNil(old.saleId)
        XCTAssertEqual(try encodeAPI(old)["saleId"], .null)
        let server = try decoder.decode(IzzyAPI.PaymentResponse.self, from: try serverFixture("payment-completed-with-sale.json")).payment
        XCTAssertNotNil(server.saleId)
        XCTAssertTrue(server.isSucceeded)
    }
}

/// What the owner app sends for a checkout.
final class NewSaleTests: XCTestCase {
    let ticketItems: [IzzyAPI.NewSaleItem] = [
        .service("haircut"),
        .product("6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a", quantity: 2),
        .custom(name: " Gift card ", unitCents: 2_500),
    ]

    func testACashSaleSendsOnlyWhatsSet() throws {
        let sale = IzzyAPI.NewSale(
            method: .cash, barberId: "carlos-rafael", appointmentId: " 4e5f6a7b-8c9d-4eaf-9b0c-3d4e5f6a7b8c ", customerName: "  Test Customer ",
            items: ticketItems
        )
        XCTAssertEqual(try encodeAPI(sale), .object([
            "method": .string("cash"),
            "barberId": .string("carlos-rafael"),
            "appointmentId": .string("4e5f6a7b-8c9d-4eaf-9b0c-3d4e5f6a7b8c"),
            "customerName": .string("Test Customer"),
            "items": .array([
                .object(["kind": .string("service"), "serviceId": .string("haircut"), "quantity": .number(1)]),
                .object(["kind": .string("product"), "productId": .string("6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a"), "quantity": .number(2)]),
                .object(["kind": .string("custom"), "name": .string("Gift card"), "unitCents": .number(2_500), "quantity": .number(1)]),
            ]),
        ]))
        // A walk-in with no name: just the method, the barber and the items.
        let walkIn = IzzyAPI.NewSale(method: .other, barberId: "julian-ramos", customerName: " ", items: [.service("haircut", unitCents: 3_500)])
        XCTAssertEqual(try encodeAPI(walkIn), .object([
            "method": .string("other"), "barberId": .string("julian-ramos"),
            "items": .array([.object(["kind": .string("service"), "serviceId": .string("haircut"), "unitCents": .number(3_500), "quantity": .number(1)])]),
        ]))
    }

    func testACardPaymentCarriesItsTicketWithoutTheMethod() throws {
        let ticket = IzzyAPI.NewSale(method: .card, appointmentId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", items: [.service("vip", unitCents: 8_000)])
        let payment = IzzyAPI.NewPayment(amountCents: 8_000, appointmentId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", sale: ticket)
        XCTAssertEqual(try encodeAPI(payment), .object([
            "amountCents": .number(8_000),
            "appointmentId": .string("0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"),
            "sale": .object([
                "appointmentId": .string("0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"),
                "items": .array([.object(["kind": .string("service"), "serviceId": .string("vip"), "unitCents": .number(8_000), "quantity": .number(1)])]),
            ]),
        ]))
        XCTAssertTrue(payment.isAmountAllowed)
        // The amount must be the ticket's total.
        XCTAssertFalse(IzzyAPI.NewPayment(amountCents: 7_999, sale: ticket).isAmountAllowed)
        // When the server fills in a price, only it can tell.
        XCTAssertTrue(IzzyAPI.NewPayment(amountCents: 4_500, sale: IzzyAPI.NewSale(method: .card, items: [.service("haircut")])).isAmountAllowed)
        // Without a ticket, as before.
        XCTAssertNil(try encodeAPI(IzzyAPI.NewPayment(amountCents: 4_500))["sale"])
    }

    func testTotals() {
        XCTAssertNil(IzzyAPI.NewSale(method: .cash, items: ticketItems).totalCents, "the server fills in the haircut's price")
        let priced = IzzyAPI.NewSale(method: .cash, items: [
            .service("haircut", unitCents: 4_500), .product("p1", unitCents: 1_800, quantity: 2), .custom(name: "Gift card", unitCents: 2_500),
        ])
        XCTAssertEqual(priced.totalCents, 4_500 + 3_600 + 2_500)
        XCTAssertEqual(priced.items.map(\.totalCents), [4_500, 3_600, 2_500])
        var item = IzzyAPI.NewSaleItem.product("p1", unitCents: 1_800)
        item.quantity += 2
        XCTAssertEqual(item.totalCents, 5_400)
    }

    func testWhatTheServerTakes() {
        XCTAssertTrue(IzzyAPI.NewSale(method: .cash, items: ticketItems).isValid)
        XCTAssertFalse(IzzyAPI.NewSale(method: .cash, items: []).isValid, "at least one item")
        XCTAssertTrue(IzzyAPI.NewSale(method: .cash, items: Array(repeating: .service("haircut"), count: 20)).isValid)
        XCTAssertFalse(IzzyAPI.NewSale(method: .cash, items: Array(repeating: .service("haircut"), count: 21)).isValid, "at most 20")
        for item: IzzyAPI.NewSaleItem in [
            .service("haircut", quantity: 0), .service("haircut", quantity: 100), .service(" "),
            .product("p1", unitCents: -1), .product("p1", unitCents: 1_000_001), .product(""),
            .custom(name: "  ", unitCents: 100), .custom(name: String(repeating: "x", count: 81), unitCents: 100),
        ] {
            XCTAssertFalse(item.isValid, "\(item)")
            XCTAssertFalse(IzzyAPI.NewSale(method: .cash, items: [item]).isValid, "\(item)")
        }
        XCTAssertTrue(IzzyAPI.NewSaleItem.custom(name: String(repeating: "x", count: 80), unitCents: 0).isValid, "a free item, with a long name")
        XCTAssertTrue(IzzyAPI.NewSaleItem.service("haircut", quantity: 99).isValid)
        // The total is at most $10,000.
        XCTAssertTrue(IzzyAPI.NewSale(method: .cash, items: [.custom(name: "Gift card", unitCents: 1_000_000)]).isValid)
        XCTAssertFalse(IzzyAPI.NewSale(method: .cash, items: [.custom(name: "Gift card", unitCents: 500_000, quantity: 3)]).isValid)
        // The client's name: 60 characters, counted like the server does.
        XCTAssertTrue(IzzyAPI.NewSale(method: .cash, customerName: String(repeating: "é", count: 60), items: ticketItems).isValid)
        XCTAssertFalse(IzzyAPI.NewSale(method: .cash, customerName: String(repeating: "a", count: 61), items: ticketItems).isValid)
    }

    /// What the server compares when the same key comes back: keep the key while it stays the same.
    func testTheRetryKeyIsWhatTheServerCompares() {
        let sale = IzzyAPI.NewSale(method: .cash, barberId: "carlos-rafael", appointmentId: "A1", customerName: "Test", items: ticketItems)
        var same = sale
        same.customerName = "  Test "
        same.appointmentId = " a1"
        XCTAssertEqual(same.retryKey, sale.retryKey)
        for change in [
            { (s: inout IzzyAPI.NewSale) in s.method = .other },
            { (s: inout IzzyAPI.NewSale) in s.barberId = "julian-ramos" },
            { (s: inout IzzyAPI.NewSale) in s.appointmentId = nil },
            { (s: inout IzzyAPI.NewSale) in s.items[0].quantity = 2 },
            { (s: inout IzzyAPI.NewSale) in s.items[0].unitCents = 4_000 },
            { (s: inout IzzyAPI.NewSale) in s.items.removeLast() },
            { (s: inout IzzyAPI.NewSale) in s.items.reverse() },
        ] {
            var changed = sale
            change(&changed)
            XCTAssertNotEqual(changed.retryKey, sale.retryKey)
        }
    }

    func testTheNewErrorCodes() throws {
        for (code, status, message) in [
            ("not_checkoutable", 409, "This appointment was cancelled, so it can't be checked out. Reopen it first, or check out without the appointment."),
            ("already_checked_out", 409, "This appointment was already checked out."),
            ("amount_mismatch", 400, "The amount doesn't match the items."),
        ] {
            let error = APIError.fromResponse(status: status, body: Data(#"{"error":{"code":"\#(code)","message":"\#(message)"}}"#.utf8))
            XCTAssertEqual(error, .server(code: code, message: message, status: status))
            XCTAssertEqual(error.userMessage, message)
            XCTAssertFalse(error.isRetryable)
            let envelope = try IzzyAPI.makeDecoder().decode(IzzyAPI.ErrorEnvelope.self, from: try serverFixture("errors/\(code).json"))
            XCTAssertEqual(envelope.error.code, code)
        }
        XCTAssertEqual(
            [IzzyAPI.ErrorCode.notCheckoutable, IzzyAPI.ErrorCode.alreadyCheckedOut, IzzyAPI.ErrorCode.amountMismatch],
            ["not_checkoutable", "already_checked_out", "amount_mismatch"]
        )
    }
}

/// The analytics in the Kit: the models, the helpers the Analytics tab needs, and the query.
final class AnalyticsTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testTheShopsDay() throws {
        let analytics = try decoder.decode(IzzyAPI.Analytics.self, from: try kitFixture("analytics.json"))
        XCTAssertEqual(analytics.from, LocalDate("2026-11-02"))
        XCTAssertEqual(analytics.to, LocalDate("2026-11-02"))
        XCTAssertNil(analytics.barberId)
        XCTAssertEqual(analytics.shopTimeZone?.identifier, "America/Los_Angeles")
        XCTAssertEqual(analytics.generatedAt, utc(2026, 11, 2, 23))
        XCTAssertEqual(analytics.granularity, .day)
        XCTAssertEqual(analytics.totals, IzzyAPI.Analytics.Totals(
            salesCents: 24_600, servicesCents: 12_500, productsCents: 3_600, otherCents: 5_000, feesCents: 3_500,
            servicesCount: 2, productsCount: 2, clientsServed: 3, checkouts: 3, averageTicketCents: 7_033
        ))
        XCTAssertEqual(analytics.previous, IzzyAPI.Analytics.Previous(from: LocalDate("2026-11-01")!, to: LocalDate("2026-11-01")!, salesCents: 0))
        XCTAssertNil(analytics.salesChange, "no sales the day before")
        let productivity = analytics.productivity
        XCTAssertEqual(productivity.openMinutes, 2_700)
        XCTAssertEqual(productivity.chairTimeBooked, 120.0 / 2_700.0)
        XCTAssertEqual(productivity.chairTimeBookedShown, 120.0 / 2_700.0)
        XCTAssertEqual(productivity.appointments, IzzyAPI.Analytics.Productivity.Appointments(completed: 2, noShows: 1, cancelled: 2, lateCancellations: 1))
        XCTAssertEqual(productivity.completionRate, 2.0 / 3.0)
        XCTAssertEqual(productivity.noShowRate, 1.0 / 3.0)
        XCTAssertEqual(productivity.salesPerHourCents, 469)
        XCTAssertEqual(analytics.topBarber, IzzyAPI.Analytics.TopBarber(barberId: "carlos-rafael", name: "Carlos", salesCents: 8_100, servicesCount: 1, productsCount: 2))
        XCTAssertEqual(analytics.leaderboard.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(analytics.leaderboard.map(\.id), ["carlos-rafael", "israel-flores", "julian-ramos", "flowxbori", "cristian-ceja"])
        XCTAssertEqual(analytics.entry(for: "flowxbori")?.salesCents, 3_500)
        XCTAssertNil(analytics.entry(for: "nobody"))
        XCTAssertEqual(analytics.services.map(\.id), ["vip", "haircut"])
        XCTAssertEqual(analytics.products, [IzzyAPI.Analytics.ProductSales(productId: "6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a", name: "Sample pomade", quantity: 2, salesCents: 3_600)])
        XCTAssertEqual(analytics.series.map(\.start), [LocalDate("2026-11-02")])
        XCTAssertEqual(analytics.series.map(\.isMonth), [false])
        XCTAssertEqual(analytics.barbers.map(\.name), ["Izzy", "Carlos", "Flowxbori", "Cristian", "Julian"])
    }

    /// The server's own examples (a hand-checked week at the shop, and one barber's) add up the way
    /// the Analytics tab reads them.
    func testTheServersWeek() throws {
        let shop = try decoder.decode(IzzyAPI.Analytics.self, from: try serverFixture("analytics.json"))
        XCTAssertNil(shop.barberId)
        let query = IzzyAPI.AnalyticsQuery(from: shop.from, to: shop.to)
        XCTAssertEqual(query.granularity, shop.granularity)
        XCTAssertEqual(query.previousPeriod.from, shop.previous.from)
        XCTAssertEqual(query.previousPeriod.to, shop.previous.to)
        XCTAssertEqual(shop.series.count, query.dayCount, "every day, zeros included")
        XCTAssertEqual(shop.series.map(\.start), (0..<query.dayCount).map { Optional(shop.from.adding(days: $0)) })
        XCTAssertEqual(shop.series.reduce(0) { $0 + $1.salesCents }, shop.totals.salesCents)
        XCTAssertEqual(shop.totals.salesCents, shop.totals.servicesCents + shop.totals.productsCents + shop.totals.otherCents + shop.totals.feesCents)
        let top = try XCTUnwrap(shop.topBarber)
        XCTAssertEqual(shop.leaderboard.first?.barberId, top.barberId)
        XCTAssertEqual(shop.leaderboard.count, shop.barbers.count, "every active barber, even at $0")
        XCTAssertNotNil(shop.salesChange)
        XCTAssertLessThanOrEqual(shop.productivity.chairTimeBookedShown, 1)

        let barber = try decoder.decode(IzzyAPI.Analytics.self, from: try serverFixture("analytics-barber.json"))
        let barberId = try XCTUnwrap(barber.barberId)
        XCTAssertEqual(barber.topBarber, shop.topBarber, "always the whole shop's")
        XCTAssertEqual(barber.leaderboard, shop.leaderboard, "so a barber's page still shows his rank")
        XCTAssertNotNil(barber.entry(for: barberId))
        XCTAssertLessThanOrEqual(barber.totals.salesCents, shop.totals.salesCents)
    }

    func testTheHelpers() {
        var analytics = IzzyAPI.Analytics(
            from: LocalDate("2026-11-02")!, to: LocalDate("2026-11-08")!, timeZone: "America/Los_Angeles", generatedAt: utc(2026, 11, 8, 20),
            totals: IzzyAPI.Analytics.Totals(salesCents: 11_200),
            previous: IzzyAPI.Analytics.Previous(from: LocalDate("2026-10-26")!, to: LocalDate("2026-11-01")!, salesCents: 10_000)
        )
        XCTAssertEqual(analytics.salesChange ?? 0, 0.12, accuracy: 1e-9)
        analytics.totals.salesCents = 5_000
        XCTAssertEqual(analytics.salesChange ?? 0, -0.5, accuracy: 1e-9)
        analytics.productivity.chairTimeBooked = 1.3
        XCTAssertEqual(analytics.productivity.chairTimeBookedShown, 1, "capped at 100%")
        analytics.productivity.chairTimeBooked = -0.1
        XCTAssertEqual(analytics.productivity.chairTimeBookedShown, 0)
        XCTAssertNil(analytics.topBarber)

        let month = IzzyAPI.Analytics.Period(date: "2026-11")
        XCTAssertEqual(month.start, LocalDate("2026-11-01"))
        XCTAssertTrue(month.isMonth)
        XCTAssertEqual(IzzyAPI.Analytics.Period(date: "2026-02-28").start, LocalDate("2026-02-28"))
        XCTAssertNil(IzzyAPI.Analytics.Period(date: "2026-W45").start)
        XCTAssertFalse(IzzyAPI.Analytics.Period(date: "2026-W45").isMonth)
    }

    /// A deleted product keeps its name; a split this version doesn't know reads as by day.
    func testTolerantDecoding() throws {
        let text = String(decoding: try kitFixture("analytics.json"), as: UTF8.self)
            .replacingOccurrences(of: #""productId": "6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a""#, with: #""productId": null"#)
            .replacingOccurrences(of: #""granularity": "day""#, with: #""granularity": "week""#)
            .replacingOccurrences(of: #""topBarber": { "barberId": "carlos-rafael", "name": "Carlos", "salesCents": 8100, "servicesCount": 1, "productsCount": 2 }"#, with: #""topBarber": null"#)
        let analytics = try decodeAPI(IzzyAPI.Analytics.self, text)
        XCTAssertNil(analytics.products.first?.productId)
        XCTAssertEqual(analytics.products.first?.name, "Sample pomade")
        XCTAssertEqual(analytics.granularity, .day)
        XCTAssertNil(analytics.topBarber)
        XCTAssertEqual(try encodeAPI(analytics)["topBarber"], .null)
        XCTAssertEqual(try encodeAPI(analytics)["products"], .array([
            .object(["productId": .null, "name": .string("Sample pomade"), "quantity": .number(2), "salesCents": .number(3_600)]),
        ]))
    }

    func testTheQuery() {
        let nov1 = LocalDate("2026-11-01")!
        let week = IzzyAPI.AnalyticsQuery(from: nov1, to: LocalDate("2026-11-07")!)
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertTrue(week.isValid)
        XCTAssertEqual(week.granularity, .day)
        XCTAssertEqual(week.previousPeriod.from, LocalDate("2026-10-25"))
        XCTAssertEqual(week.previousPeriod.to, LocalDate("2026-10-31"))
        let today = IzzyAPI.AnalyticsQuery(day: LocalDate("2026-03-08")!, barberId: "flowxbori")
        XCTAssertEqual(today.dayCount, 1, "the day clocks change is still one day")
        XCTAssertEqual(today.previousPeriod.from, LocalDate("2026-03-07"))
        XCTAssertEqual(today.previousPeriod.to, LocalDate("2026-03-07"))
        XCTAssertEqual(IzzyAPI.AnalyticsQuery(from: nov1, to: nov1.adding(days: 61)).granularity, .day, "62 days")
        XCTAssertEqual(IzzyAPI.AnalyticsQuery(from: nov1, to: nov1.adding(days: 62)).granularity, .month, "63 days")
        XCTAssertTrue(IzzyAPI.AnalyticsQuery(from: LocalDate("2028-01-01")!, to: LocalDate("2028-12-31")!).isValid, "a leap year: 366 days")
        XCTAssertFalse(IzzyAPI.AnalyticsQuery(from: nov1, to: nov1.adding(days: 366)).isValid, "367 days")
        XCTAssertFalse(IzzyAPI.AnalyticsQuery(from: nov1, to: nov1.adding(days: -1)).isValid, "from after to")
        XCTAssertEqual(IzzyAPI.AnalyticsQuery(from: nov1, to: nov1.adding(days: -1)).dayCount, 0)
    }
}

/// The client's requests for sales and analytics.
final class SalesClientTests: XCTestCase {
    let ownerKey = "owner-key-0123456789abcdef0123456789abcdef"
    var client: IzzyAPIClient!

    typealias Reply = StubURLProtocol.Reply

    override func setUp() {
        super.setUp()
        client = IzzyAPIClient(baseURL: URL(string: "https://api.test")!, session: StubURLProtocol.session(), ownerKey: ownerKey)
        StubURLProtocol.reply { _ in Reply() }
    }

    func only(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Sent {
        let sent = StubURLProtocol.sent
        XCTAssertEqual(sent.count, 1, "requests sent", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    /// A sale carries its Idempotency-Key, Save again sends the same one, and the server's 200 for a
    /// sale that key already recorded decodes like a new one.
    func testASaleSendsItsIdempotencyKey() async throws {
        let key = IzzyAPI.IdempotencyKey.generate()
        let sale = IzzyAPI.NewSale(method: .cash, appointmentId: "4e5f6a7b-8c9d-4eaf-9b0c-3d4e5f6a7b8c", items: [.service("haircut"), .product("6d7e8f9a-0b1c-4d2e-8f3a-4b5c6d7e8f9a", quantity: 2)])
        StubURLProtocol.reply { _ in .fixture("sale.json", status: 201) }
        let first = try await client.recordSale(sale, idempotencyKey: key)
        XCTAssertEqual(first.receiptLine, "Sold $81 · Cash · Carlos")
        var sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/owner/sales")
        XCTAssertEqual(sent.header("Idempotency-Key"), key.rawValue)
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)
        XCTAssertEqual(sent.json?["method"], .string("cash"))

        StubURLProtocol.reply { _ in .fixture("sale.json", status: 200) }
        let again = try await client.recordSale(sale, idempotencyKey: key)
        XCTAssertEqual(again, first)
        sent = try only()
        XCTAssertEqual(sent.header("Idempotency-Key"), key.rawValue)

        // The server's no: in its own words.
        StubURLProtocol.reply { _ in .json(409, #"{"error":{"code":"already_checked_out","message":"This appointment was already checked out."}}"#) }
        do {
            _ = try await client.recordSale(sale, idempotencyKey: .generate())
            XCTFail("expected already_checked_out")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: IzzyAPI.ErrorCode.alreadyCheckedOut, message: "This appointment was already checked out.", status: 409))
        }
    }

    func testTheDaysSalesAndVoiding() async throws {
        StubURLProtocol.reply { _ in .fixture("sales-day.json") }
        let day = try await client.sales(on: LocalDate("2026-11-02")!)
        XCTAssertEqual(day.totals.count, 3)
        var sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/owner/sales")
        XCTAssertEqual(sent.query, "date=2026-11-02")
        XCTAssertNil(sent.body)

        StubURLProtocol.reply { _ in .fixture("sale-voided.json") }
        let voided = try await client.voidSale(id: "1d2e3f4a-5b6c-4d7e-8f9a-0b1c2d3e4f5a", reason: "  Charged twice ")
        XCTAssertTrue(voided.sale.isVoided)
        sent = try only()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/owner/sales/1d2e3f4a-5b6c-4d7e-8f9a-0b1c2d3e4f5a/void")
        XCTAssertEqual(sent.json, .object(["reason": .string("Charged twice")]))
        XCTAssertNil(sent.header("Idempotency-Key"), "voiding is safe to repeat as it is")

        // Without a reason: an empty body; an id can't change the path.
        StubURLProtocol.reply { _ in .fixture("sale-voided.json") }
        _ = try await client.voidSale(id: "../payments")
        sent = try only()
        XCTAssertEqual(sent.path, "/api/owner/sales/..%2Fpayments/void")
        XCTAssertEqual(sent.json, .object([:]))
        StubURLProtocol.reply { _ in .fixture("sale-voided.json") }
        _ = try await client.voidSale(id: "s1", reason: " ")
        XCTAssertEqual(try only().json, .object([:]))
    }

    func testACardCheckoutSendsItsTicket() async throws {
        StubURLProtocol.reply { _ in .fixture("payment-intent.json", status: 201) }
        let ticket = IzzyAPI.NewSale(method: .card, barberId: "israel-flores", items: [.service("vip", unitCents: 8_000)])
        _ = try await client.createPayment(IzzyAPI.NewPayment(amountCents: 8_000, sale: ticket))
        let sent = try only()
        XCTAssertEqual(sent.path, "/api/owner/payments")
        XCTAssertEqual(sent.json, .object([
            "amountCents": .number(8_000),
            "sale": .object([
                "barberId": .string("israel-flores"),
                "items": .array([.object(["kind": .string("service"), "serviceId": .string("vip"), "unitCents": .number(8_000), "quantity": .number(1)])]),
            ]),
        ]))
        StubURLProtocol.reply { _ in .json(400, #"{"error":{"code":"amount_mismatch","message":"The amount doesn't match the items."}}"#) }
        do {
            _ = try await client.createPayment(IzzyAPI.NewPayment(amountCents: 7_000, sale: ticket))
            XCTFail("expected amount_mismatch")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(code: IzzyAPI.ErrorCode.amountMismatch, message: "The amount doesn't match the items.", status: 400))
        }
    }

    func testTheAnalyticsQuery() async throws {
        StubURLProtocol.reply { _ in .fixture("analytics.json") }
        let analytics = try await client.analytics(IzzyAPI.AnalyticsQuery(from: LocalDate("2026-11-01")!, to: LocalDate("2026-11-07")!))
        XCTAssertEqual(analytics.totals.salesCents, 24_600)
        var sent = try only()
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/owner/analytics")
        XCTAssertEqual(sent.query, "from=2026-11-01&to=2026-11-07")
        XCTAssertEqual(sent.header("Authorization"), "Bearer " + ownerKey)

        StubURLProtocol.reply { _ in .fixture("analytics.json") }
        _ = try await client.analytics(IzzyAPI.AnalyticsQuery(day: LocalDate("2026-11-02")!, barberId: "carlos-rafael"))
        XCTAssertEqual(try only().query, "from=2026-11-02&to=2026-11-02&barberId=carlos-rafael")
        // Escaped like every value; a blank barber is the whole shop.
        StubURLProtocol.reply { _ in .fixture("analytics.json") }
        _ = try await client.analytics(IzzyAPI.AnalyticsQuery(day: LocalDate("2026-11-02")!, barberId: "a&b=c"))
        sent = try only()
        XCTAssertEqual(sent.query, "from=2026-11-02&to=2026-11-02&barberId=a%26b%3Dc")
        StubURLProtocol.reply { _ in .fixture("analytics.json") }
        _ = try await client.analytics(IzzyAPI.AnalyticsQuery(day: LocalDate("2026-11-02")!, barberId: " "))
        XCTAssertEqual(try only().query, "from=2026-11-02&to=2026-11-02")
    }

    func testOwnerCallsWithoutAKeyNeverLeaveThePhone() async throws {
        let signedOut = client.withOwnerKey(nil)
        let sale = IzzyAPI.NewSale(method: .cash, items: [.service("haircut")])
        for call in [
            { _ = try await signedOut.recordSale(sale, idempotencyKey: .generate()) },
            { _ = try await signedOut.sales(on: LocalDate("2026-11-02")!) },
            { _ = try await signedOut.voidSale(id: "s1", reason: nil) },
            { _ = try await signedOut.analytics(IzzyAPI.AnalyticsQuery(day: LocalDate("2026-11-02")!)) },
        ] as [() async throws -> Void] {
            do {
                try await call()
                XCTFail("expected unauthorized")
            } catch let error as APIError {
                XCTAssertEqual(error, .unauthorized)
            }
        }
        XCTAssertEqual(StubURLProtocol.sent.count, 0)
    }
}

/// An `OwnerAPI` written before sales, Stripe Connect and computers (like an app's fake that
/// hasn't been taught them yet) still builds, and answers those calls like a server without them.
final class OwnerAPIDefaultsTests: XCTestCase {
    private struct OlderOwnerAPI: OwnerAPI {
        func health() async throws -> IzzyAPI.Health { IzzyAPI.Health(version: "old") }
        func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { throw APIError.offline }
        func ownerStatus() async throws -> IzzyAPI.OwnerStatus { IzzyAPI.OwnerStatus(stripe: IzzyAPI.StripeStatus(configured: false)) }
        func ownerAvailability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { throw APIError.offline }
        func appointments(on date: LocalDate) async throws -> [IzzyAPI.Appointment] { [] }
        func appointments(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.Appointment] { [] }
        func createAppointment(_ appointment: IzzyAPI.NewAppointment, idempotencyKey: IzzyAPI.IdempotencyKey) async throws -> IzzyAPI.Appointment { throw APIError.offline }
        func setStatus(_ status: IzzyAPI.AppointmentStatus, ofAppointment id: String) async throws -> IzzyAPI.Appointment { throw APIError.offline }
        func chargeNoShowFee(appointmentId: String) async throws -> IzzyAPI.Appointment { throw APIError.offline }
        func noShowSettings() async throws -> IzzyAPI.NoShowSettings { .default }
        func updateNoShowSettings(_ update: IzzyAPI.NoShowSettingsUpdate) async throws -> IzzyAPI.NoShowSettings { .default }
        func timeOff(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.TimeOff] { [] }
        func createTimeOff(_ timeOff: IzzyAPI.NewTimeOff) async throws -> IzzyAPI.TimeOff { throw APIError.offline }
        func deleteTimeOff(id: String) async throws {}
        func allProducts() async throws -> [IzzyAPI.Product] { [] }
        func createProduct(_ product: IzzyAPI.NewProduct) async throws -> IzzyAPI.Product { throw APIError.offline }
        func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) async throws -> IzzyAPI.Product { throw APIError.offline }
        func deleteProduct(id: String) async throws {}
        func uploadProductPhoto(id: String, jpegData: Data) async throws -> IzzyAPI.Product { throw APIError.offline }
        func connectionToken() async throws -> String { "pst_test_old" }
        func createPayment(_ payment: IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated { throw APIError.offline }
        func completePayment(id: String) async throws -> IzzyAPI.Payment { throw APIError.offline }
        func payments(on date: LocalDate) async throws -> [IzzyAPI.Payment] { [] }
    }

    func testTheNewCallsAnswerLikeAServerWithoutThem() async {
        let api: any OwnerAPI = OlderOwnerAPI()
        let day = LocalDate("2026-11-02")!
        let calls: [(String, () async throws -> Void)] = [
            ("stripe", { _ = try await api.stripeConnection() }),
            ("connect", { _ = try await api.connectStripe() }),
            ("disconnect", { _ = try await api.disconnectStripe() }),
            ("code", { _ = try await api.createComputerCode() }),
            ("computers", { _ = try await api.computerSessions() }),
            ("sign out", { try await api.signOutComputer(id: "c1") }),
            ("sign out all", { try await api.signOutAllComputers() }),
            ("sale", { _ = try await api.recordSale(IzzyAPI.NewSale(method: .cash, items: [.service("haircut")]), idempotencyKey: .generate()) }),
            ("sales", { _ = try await api.sales(on: day) }),
            ("void", { _ = try await api.voidSale(id: "s1") }),
            ("analytics", { _ = try await api.analytics(IzzyAPI.AnalyticsQuery(day: day)) }),
            ("receipt", { _ = try await api.sendReceipt(paymentId: "pi_1", email: "client@example.com") }),
        ]
        for (name, call) in calls {
            do {
                try await call()
                XCTFail("\(name): expected not_found")
            } catch let error as APIError {
                XCTAssertEqual(error.code, IzzyAPI.ErrorCode.notFound, name)
                XCTAssertTrue(error.userMessage.hasSuffix("."), name)
            } catch {
                XCTFail("\(name): \(error)")
            }
        }
        // What it already had still works.
        let health = try? await api.health()
        XCTAssertEqual(health?.version, "old")
    }
}
