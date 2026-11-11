import Foundation
import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

private func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

/// The sample server's analytics, definition by definition (docs/analytics.md), on small sets of
/// appointments and sales made by hand. "Now" is Monday, November 2, 2026 at 11:05 AM in the shop.
@MainActor
final class FakeAnalyticsTests: XCTestCase {
    private let catalog = Catalog.izzyClipz
    private var number = 0
    private let pomade = IzzyAPI.Product(id: "p-pomade", name: "Sample pomade", description: nil, priceCents: 1_800, imageUrl: nil, visible: true)

    private func offering(_ service: String, _ barber: String) -> Offering {
        catalog.offerings.first { $0.serviceID == service && $0.barberID == barber }!
    }

    private func appointment(
        _ service: String, _ barber: String, at start: Date, _ status: IzzyAPI.AppointmentStatus = .booked,
        cancelledBy: IzzyAPI.CancelledBy? = nil, createdAt: Date? = nil
    ) -> IzzyAPI.Appointment {
        number += 1
        let offering = offering(service, barber)
        return IzzyAPI.Appointment(
            id: "appointment-\(number)", offeringId: offering.id, serviceId: service, serviceName: catalog.service(withID: service)!.name,
            barberId: barber, barberName: catalog.barber(withID: barber)!.name, start: start,
            end: start.addingTimeInterval(TimeInterval(offering.durationMinutes * 60)), durationMinutes: offering.durationMinutes,
            priceLabel: offering.price.label, status: status, cancelledBy: cancelledBy,
            customer: IzzyAPI.Customer(name: "Client Sample \(number)", phone: "+14425550150", email: "client@example.com"),
            note: "A note", createdAt: createdAt ?? start.addingTimeInterval(-2 * 86_400)
        )
    }

    private func sale(
        _ barber: String, at soldAt: Date, for appointment: IzzyAPI.Appointment? = nil, _ items: [IzzyAPI.SaleItem], voided: Bool = false
    ) -> IzzyAPI.Sale {
        number += 1
        return IzzyAPI.Sale(
            id: "sale-\(number)", barberId: barber, barberName: catalog.barber(withID: barber)!.name, appointmentId: appointment?.id,
            customerName: appointment?.customer.name, method: .cash, items: items, soldAt: soldAt,
            voidedAt: voided ? soldAt.addingTimeInterval(60) : nil, voidReason: voided ? "Rung up twice" : nil
        )
    }

    private func service(_ id: String, _ cents: Int) -> IzzyAPI.SaleItem {
        IzzyAPI.SaleItem(kind: .service, serviceId: id, name: catalog.service(withID: id)!.name, unitCents: cents)
    }

    private func product(_ product: IzzyAPI.Product, quantity: Int = 1) -> IzzyAPI.SaleItem {
        IzzyAPI.SaleItem(kind: .product, productId: product.id, name: product.name, quantity: quantity, unitCents: product.priceCents ?? 0)
    }

    /// Checked out: completed, with its sale.
    private func checkedOut(_ appointment: IzzyAPI.Appointment, by sale: IzzyAPI.Sale) -> IzzyAPI.Appointment {
        var appointment = appointment
        appointment.status = .completed
        appointment.sale = IzzyAPI.AppointmentSale(sale: sale)
        appointment.payment = IzzyAPI.AppointmentPayment(status: .paid, amountCents: sale.totalCents, paidAt: sale.soldAt)
        return appointment
    }

    private func withCard(_ appointment: IzzyAPI.Appointment, fee: IzzyAPI.NoShowFee) -> IzzyAPI.Appointment {
        var appointment = appointment
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = fee
        return appointment
    }

    private func at(_ hour: Int, _ minute: Int = 0, on dayText: String? = nil) -> Date {
        TestClock.at(hour, minute, on: dayText.map(day))
    }

    private func analytics(
        _ query: IzzyAPI.AnalyticsQuery,
        appointments: [IzzyAPI.Appointment] = [],
        sales: [IzzyAPI.Sale] = [],
        timeOff: [IzzyAPI.TimeOff] = [],
        products: [IzzyAPI.Product]? = nil
    ) throws -> IzzyAPI.Analytics {
        try FakeAnalytics.analytics(
            query,
            records: FakeAnalytics.Records(appointments: appointments, sales: sales, timeOff: timeOff, products: products ?? [pomade]),
            catalog: catalog, shopTime: TestClock.shopTime, now: TestClock.now
        )
    }

    // MARK: Sales

    func testCheckoutsAndAppointmentsDoneWithoutOne() async throws {
        let carlos = appointment("haircut", "carlos-rafael", at: at(10))
        let carlosSale = sale("carlos-rafael", at: at(10, 50), for: carlos, [
            service("haircut", 4_500), product(pomade, quantity: 2), IzzyAPI.SaleItem(kind: .custom, name: "Gift card", unitCents: 2_500),
        ])
        let records = [
            checkedOut(carlos, by: carlosSale),
            appointment("haircut", "israel-flores", at: at(10), .completed), // Done, no checkout: $40
            appointment("haircut", "cristian-ceja", at: at(10), .noShow),
            appointment("haircut", "julian-ramos", at: at(13)), // still booked, later today
        ]
        let sales = [
            carlosSale,
            sale("flowxbori", at: at(10, 30), [service("haircut", 3_500)], voided: true),
            sale("flowxbori", at: at(10, 40), [product(pomade)]), // a walk-in buys a pomade
        ]
        let result = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), appointments: records, sales: sales)
        let totals = result.totals
        XCTAssertEqual(totals.servicesCents, 4_500 + 4_000, "the checkout's service, and the visit at its booked price")
        XCTAssertEqual(totals.servicesCount, 2)
        XCTAssertEqual(totals.productsCents, 3_600 + 1_800)
        XCTAssertEqual(totals.productsCount, 3)
        XCTAssertEqual(totals.otherCents, 2_500)
        XCTAssertEqual(totals.feesCents, 0)
        XCTAssertEqual(totals.salesCents, 8_500 + 5_400 + 2_500, "the voided sale doesn't count")
        XCTAssertEqual(totals.checkouts, 3, "two live sales and one appointment done without a checkout")
        XCTAssertEqual(totals.clientsServed, 3, "two appointments done and one walk-in")
        XCTAssertEqual(totals.averageTicketCents, 5_467, "round(164.00 / 3)")
        XCTAssertEqual(result.services, [IzzyAPI.Analytics.ServiceSales(serviceId: "haircut", name: "Haircut", count: 2, salesCents: 8_500)])
        XCTAssertEqual(result.products, [IzzyAPI.Analytics.ProductSales(productId: "p-pomade", name: "Sample pomade", quantity: 3, salesCents: 5_400)])

        let appointments = result.productivity.appointments
        XCTAssertEqual(appointments, IzzyAPI.Analytics.Productivity.Appointments(booked: 1, completed: 2, noShows: 1, upcoming: 1))
        XCTAssertEqual(result.productivity.completionRate, 2.0 / 3)
        XCTAssertEqual(result.productivity.noShowRate, 1.0 / 3)
        XCTAssertEqual(result.productivity.productAttachRate, 1, "both live sales had a product")

        XCTAssertEqual(result.leaderboard.map(\.name), ["Carlos", "Izzy", "Flowxbori", "Cristian", "Julian"])
        XCTAssertEqual(result.leaderboard.map(\.rank), [1, 2, 3, 4, 4], "nothing sold: Cristian and Julian share 4th")
        XCTAssertEqual(result.topBarber, IzzyAPI.Analytics.TopBarber(barberId: "carlos-rafael", name: "Carlos", salesCents: 10_600, servicesCount: 1, productsCount: 2))
        XCTAssertEqual(result.barbers.map(\.barberId), catalog.barbers.map(\.id))
        XCTAssertEqual(result.generatedAt, TestClock.now)
        XCTAssertEqual(result.timeZone, "America/Los_Angeles")
    }

    func testFeesCountTheDayStripeChargedThem() async throws {
        let charged = withCard(
            appointment("haircut", "flowxbori", at: at(10, on: "2026-11-01"), .noShow),
            fee: IzzyAPI.NoShowFee(amountCents: 3_500, fullPrice: true, status: .charged, chargedAt: at(10, 30), reason: .noShow)
        )
        let declined = withCard(
            appointment("haircut", "julian-ramos", at: at(10, on: "2026-11-01"), .noShow),
            fee: IzzyAPI.NoShowFee(amountCents: 3_500, status: .declined, message: "The card was declined.", reason: .noShow)
        )
        let today = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), appointments: [charged, declined])
        XCTAssertEqual(today.totals.feesCents, 3_500, "charged today for yesterday's no-show; the declined one doesn't count")
        XCTAssertEqual(today.totals.salesCents, 3_500)
        XCTAssertEqual(today.totals.averageTicketCents, 0, "fees aren't part of the average ticket")
        XCTAssertEqual(today.leaderboard.first?.name, "Flowxbori", "the appointment's barber gets it")
        XCTAssertEqual(today.series.first?.feesCents, 3_500)
        let yesterday = try analytics(IzzyAPI.AnalyticsQuery(day: day("2026-11-01")), appointments: [charged, declined])
        XCTAssertEqual(yesterday.totals.feesCents, 0)
        XCTAssertEqual(yesterday.productivity.appointments.noShows, 2, "appointments count on the day they start")
    }

    func testASaleLateAtNightCountsOnTheShopsDay() async throws {
        // 11:30 PM on Sunday November 1 in the shop is 7:30 AM on the 2nd in UTC.
        let late = sale("carlos-rafael", at: IzzyAPI.Timestamp.date(from: "2026-11-02T07:30:00Z")!, [product(pomade, quantity: 2)])
        let result = try analytics(IzzyAPI.AnalyticsQuery(from: day("2026-11-01"), to: day("2026-11-02")), sales: [late])
        XCTAssertEqual(result.granularity, .day)
        XCTAssertEqual(result.series.map(\.date), ["2026-11-01", "2026-11-02"], "every day, zeros included")
        XCTAssertEqual(result.series.map(\.productsCents), [3_600, 0])
        let monday = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), sales: [late])
        XCTAssertEqual(monday.totals.salesCents, 0)
        XCTAssertEqual(monday.previous, IzzyAPI.Analytics.Previous(from: day("2026-11-01"), to: day("2026-11-01"), salesCents: 3_600))
    }

    func testThePeriodBeforeForTheShopOrTheBarber() async throws {
        let sales = [
            sale("flowxbori", at: at(12, on: "2026-10-27"), [service("haircut", 3_500)]),
            sale("israel-flores", at: at(12, on: "2026-11-01"), [service("haircut", 4_000)]),
            sale("flowxbori", at: at(12, on: "2026-10-25"), [service("haircut", 3_500)]), // the week before that
            sale("flowxbori", at: at(10, 30), [service("haircut", 3_500)]),
        ]
        let week = IzzyAPI.AnalyticsQuery(from: day("2026-11-02"), to: day("2026-11-08"))
        XCTAssertEqual(try analytics(week, sales: sales).previous, IzzyAPI.Analytics.Previous(from: day("2026-10-26"), to: day("2026-11-01"), salesCents: 7_500))
        var flowxbori = week
        flowxbori.barberId = "flowxbori"
        let his = try analytics(flowxbori, sales: sales)
        XCTAssertEqual(his.previous.salesCents, 3_500)
        XCTAssertEqual(his.totals.salesCents, 3_500)
        XCTAssertEqual(his.series.count, 7, "the whole week, days to come included")
    }

    func testOneBarbersPageKeepsTheShopsLeaderboard() async throws {
        let sales = [
            sale("flowxbori", at: at(10, 30), [service("haircut", 3_500), product(pomade)]),
            sale("israel-flores", at: at(10, 40), [service("vip", 8_000)]),
        ]
        var query = IzzyAPI.AnalyticsQuery(day: TestClock.today)
        query.barberId = "flowxbori"
        let result = try analytics(query, sales: sales)
        XCTAssertEqual(result.barberId, "flowxbori")
        XCTAssertEqual(result.totals.salesCents, 5_300)
        XCTAssertEqual(result.services.map(\.serviceId), ["haircut"])
        XCTAssertEqual(result.products.count, 1)
        XCTAssertEqual(result.series.first?.salesCents, 5_300)
        XCTAssertEqual(result.leaderboard.count, 5)
        XCTAssertEqual(result.leaderboard.first?.name, "Izzy", "the whole shop's")
        XCTAssertEqual(result.topBarber?.name, "Izzy")
    }

    func testLeaderboardTiesShareAPlaceAndNobodyIsTopWithoutSales() async throws {
        let sales = [
            sale("julian-ramos", at: at(10, 30), [service("haircut", 3_500)]),
            sale("cristian-ceja", at: at(10, 30), [service("haircut", 3_500)]),
            sale("carlos-rafael", at: at(10, 30), [product(pomade)]),
        ]
        let result = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), sales: sales)
        XCTAssertEqual(result.leaderboard.map(\.name), ["Cristian", "Julian", "Carlos", "Flowxbori", "Izzy"])
        XCTAssertEqual(result.leaderboard.map(\.rank), [1, 1, 3, 4, 4])
        let nothing = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today))
        XCTAssertNil(nothing.topBarber)
        XCTAssertEqual(nothing.leaderboard.count, 5, "every barber, even at $0")
    }

    func testLongerRangesGoByMonth() async throws {
        let october = sale("israel-flores", at: at(12, on: "2026-10-15"), [service("haircut", 4_000)])
        let year = try analytics(IzzyAPI.AnalyticsQuery(from: day("2026-01-01"), to: TestClock.today), sales: [october])
        XCTAssertEqual(year.granularity, .month)
        XCTAssertEqual(year.series.map(\.date), (1...11).map { String(format: "2026-%02d", $0) })
        XCTAssertEqual(year.series.first { $0.date == "2026-10" }?.salesCents, 4_000)
        XCTAssertEqual(try analytics(IzzyAPI.AnalyticsQuery(from: day("2026-09-01"), to: day("2026-11-01"))).granularity, .day, "62 days")
        let sixtyThree = try analytics(IzzyAPI.AnalyticsQuery(from: day("2026-08-31"), to: day("2026-11-01")))
        XCTAssertEqual(sixtyThree.granularity, .month)
        XCTAssertEqual(sixtyThree.series.map(\.date), ["2026-08", "2026-09", "2026-10", "2026-11"], "the first and last months hold only the range's days")
    }

    // MARK: Productivity

    func testOpenHoursLessTimeOffBookedTimeAndChairTime() async throws {
        let timeOff = [
            IzzyAPI.TimeOff(id: "t1", barberId: "julian-ramos", start: at(13), end: at(14), reason: "Dentist"),
            IzzyAPI.TimeOff(id: "t2", barberId: nil, start: at(13, 30), end: at(15), reason: "Meeting"), // overlaps: counted once
        ]
        let appointments = [
            appointment("haircut", "julian-ramos", at: at(10), .completed), // 45 minutes
            appointment("haircut", "julian-ramos", at: at(16)), // booked later today: 45 minutes
            appointment("haircut", "julian-ramos", at: at(11, on: "2026-11-03")), // tomorrow: not yet
        ]
        let sales = [sale("julian-ramos", at: at(10, 50), [product(pomade)])]
        var query = IzzyAPI.AnalyticsQuery(from: TestClock.today, to: day("2026-11-03"))
        query.barberId = "julian-ramos"
        let julian = try analytics(query, appointments: appointments, sales: sales, timeOff: timeOff)
        XCTAssertEqual(julian.productivity.openMinutes, 540 - 120, "10 AM – 7 PM, less 1–3 PM; tomorrow hasn't come")
        XCTAssertEqual(julian.productivity.bookedMinutes, 90)
        XCTAssertEqual(julian.productivity.chairTimeBooked, 90.0 / 420)
        XCTAssertEqual(julian.productivity.salesPerHourCents, (3_500 + 1_800) * 60 / 420, "services, products and other per open hour")
        let shop = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), appointments: appointments, timeOff: timeOff)
        XCTAssertEqual(shop.productivity.openMinutes, 5 * 540 - 120 - 4 * 90, "the shop's block takes 90 minutes from everyone else")
    }

    func testLateCancellationsFollowTheFeeRule() async throws {
        let start = at(15)
        func cancelled(minutesBefore: Int, bookedMinutesBefore: Int = 2 * 24 * 60, by: IzzyAPI.CancelledBy = .customer, card: Bool = true, window: Int? = 60) -> IzzyAPI.Appointment {
            let booked = appointment("haircut", "flowxbori", at: start, .cancelled, cancelledBy: by, createdAt: start.addingTimeInterval(-Double(bookedMinutesBefore * 60)))
            guard card else { return booked }
            return withCard(booked, fee: IzzyAPI.NoShowFee(
                amountCents: 3_500, fullPrice: true, customerCancelledAt: start.addingTimeInterval(-Double(minutesBefore * 60)), lateCancelWindowMinutes: window
            ))
        }
        let records = [
            cancelled(minutesBefore: 30), // late
            cancelled(minutesBefore: 120), // in time
            cancelled(minutesBefore: 30, bookedMinutesBefore: 40), // 10 minutes after booking: always free
            cancelled(minutesBefore: 30, by: .shop),
            cancelled(minutesBefore: 30, card: false),
            cancelled(minutesBefore: 30, window: nil), // a policy without a window
        ]
        let result = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), appointments: records)
        XCTAssertEqual(result.productivity.appointments.cancelled, 6)
        XCTAssertEqual(result.productivity.appointments.lateCancellations, 1)
    }

    // MARK: Names

    func testServicesAndProductsByNameAndOrder() async throws {
        let renamed = IzzyAPI.Product(id: "p-pomade", name: "Matte pomade", description: nil, priceCents: 1_800, imageUrl: nil, visible: true)
        let gel = IzzyAPI.Product(id: "p-gel", name: "Old gel", description: nil, priceCents: 1_000, imageUrl: nil, visible: true)
        let sales = [
            sale("carlos-rafael", at: at(10, 30), [product(pomade), product(gel, quantity: 2)]),
            sale("carlos-rafael", at: at(10, 40), [service("military-haircut", 3_500), service("haircut", 2_000)]),
            sale("israel-flores", at: at(10, 45), [service("haircut", 1_500)]),
        ]
        // The pomade was renamed since, and the gel deleted.
        let result = try analytics(IzzyAPI.AnalyticsQuery(day: TestClock.today), sales: sales, products: [renamed])
        XCTAssertEqual(result.products, [
            IzzyAPI.Analytics.ProductSales(productId: nil, name: "Old gel", quantity: 2, salesCents: 2_000),
            IzzyAPI.Analytics.ProductSales(productId: "p-pomade", name: "Matte pomade", quantity: 1, salesCents: 1_800),
        ])
        // Haircut and Military Haircut both brought in $35: more of them first.
        XCTAssertEqual(result.services.map(\.name), ["Haircut", "Military Haircut"])
        XCTAssertEqual(result.services.map(\.count), [2, 1])
    }

    func testRequestsTheServerTurnsDown() async {
        func message(_ query: IzzyAPI.AnalyticsQuery) -> String? {
            do {
                _ = try analytics(query)
                return nil
            } catch APIError.server(_, let message, let status) {
                XCTAssertEqual(status, 400)
                return message
            } catch {
                return "\(error)"
            }
        }
        let today = TestClock.today
        XCTAssertEqual(message(IzzyAPI.AnalyticsQuery(from: today.adding(days: -366), to: today)), "Ask for at most 366 days at a time.")
        XCTAssertNil(message(IzzyAPI.AnalyticsQuery(from: today.adding(days: -365), to: today)))
        XCTAssertEqual(message(IzzyAPI.AnalyticsQuery(from: today, to: today.adding(days: -1))), "to must be on or after from.")
        XCTAssertEqual(message(IzzyAPI.AnalyticsQuery(day: today, barberId: "nobody")), "That barber isn't on the team.")
        XCTAssertEqual(message(IzzyAPI.AnalyticsQuery(day: today.adding(days: -3_661))), "Pick dates within 10 years of today.")
    }

    // MARK: Clients' details

    /// The Privacy Policy removes clients' names, numbers, emails and notes 12 months after the
    /// appointment, and the name on a sale (docs/analytics.md, "Good to know"): every number stays.
    func testRemovingClientsDetailsChangesNoNumber() async throws {
        let history = FakeSampleHistory.make(catalog: catalog, shopTime: TestClock.shopTime, now: TestClock.now, products: [pomade])
        let removed = history.appointments.map { appointment -> IzzyAPI.Appointment in
            var appointment = appointment
            appointment.customer = IzzyAPI.Customer(name: "Name removed", phone: nil, email: nil)
            appointment.note = nil
            appointment.noShowFee?.message = nil
            return appointment
        }
        let anonymousSales = history.sales.map { sale -> IzzyAPI.Sale in
            var sale = sale
            sale.customerName = nil
            sale.voidReason = nil
            return sale
        }
        XCTAssertNotEqual(removed, history.appointments)
        for query in [
            IzzyAPI.AnalyticsQuery(from: day("2026-01-01"), to: TestClock.today),
            IzzyAPI.AnalyticsQuery(from: day("2026-10-01"), to: day("2026-10-31"), barberId: "carlos-rafael"),
        ] {
            let before = try analytics(query, appointments: history.appointments, sales: history.sales)
            let after = try analytics(query, appointments: removed, sales: anonymousSales)
            XCTAssertEqual(after, before, "\(query)")
            XCTAssertGreaterThan(before.totals.salesCents, 0)
        }
    }

    // MARK: The sample server

    func testTheSampleServerCountsItsOwnCheckoutsAndVisits() async throws {
        var options = FakeServer.Options()
        options.sampleHistory = true
        let harness = Harness(options: options)
        let query = IzzyAPI.AnalyticsQuery(day: TestClock.today)
        let before = try await harness.api.analytics(query)
        XCTAssertEqual(before.totals.servicesCents, 4_000 + 4_500, "Marcus's and Diego's cuts, checked out earlier this morning")

        // Andre's Haircut & Beard ($55) is marked Done: it counts at its booked price.
        let andre = try XCTUnwrap(harness.appointment(named: "Andre Sample"))
        _ = try await harness.api.setStatus(.completed, ofAppointment: andre.id)
        let done = try await harness.api.analytics(query)
        XCTAssertEqual(done.totals.servicesCents, before.totals.servicesCents + 5_500)
        XCTAssertEqual(done.totals.clientsServed, before.totals.clientsServed + 1)

        // A walk-in buys a pomade at the counter: the checkout records a sale.
        harness.server.sales.append(sale("carlos-rafael", at: TestClock.now, [product(pomade)]))
        let sold = try await harness.api.analytics(query)
        XCTAssertEqual(sold.totals.productsCents, done.totals.productsCents + 1_800)
        XCTAssertEqual(sold.totals.checkouts, done.totals.checkouts + 1)
        XCTAssertEqual(harness.server.calls.filter { $0 == "analytics" }.count, 3)

        // Owner routes need the owner key.
        do {
            _ = try await harness.server.api(ownerKey: "not-the-key").analytics(query)
            XCTFail("answered without the owner key")
        } catch {
            guard case .unauthorized? = error as? APIError else { return XCTFail("Got \(error)") }
        }
    }
}

/// The sample shop's last 8 weeks (`FakeSampleHistory`).
@MainActor
final class FakeSampleHistoryTests: XCTestCase {
    private let products = [
        IzzyAPI.Product(id: "p-pomade", name: "Sample pomade", description: nil, priceCents: 1_800, imageUrl: nil, visible: true),
        IzzyAPI.Product(id: "p-oil", name: "Sample beard oil", description: nil, priceCents: nil, imageUrl: nil, visible: false),
    ]

    private func history(now: Date? = nil) -> FakeSampleHistory.History {
        FakeSampleHistory.make(catalog: .izzyClipz, shopTime: TestClock.shopTime, now: now ?? TestClock.now, products: products)
    }

    func testTheSameEveryTime() async {
        let first = history()
        let second = history()
        XCTAssertEqual(first.appointments, second.appointments)
        XCTAssertEqual(first.sales, second.sales)
        XCTAssertNotEqual(history(now: TestClock.at(11, 5, on: TestClock.today.adding(days: 1))).appointments, first.appointments, "it follows today")
    }

    func testTheEightWeeksBeforeToday() async {
        let history = history()
        let shopTime = TestClock.shopTime
        let days = Set(history.appointments.map { shopTime.day(containing: $0.start) })
        let expected = Set((1...FakeSampleHistory.days).map { TestClock.today.adding(days: -$0) })
        XCTAssertEqual(days, expected, "every day of the 8 weeks before today (the shop opens every day), and nothing else")
        XCTAssertTrue(history.sales.allSatisfy { expected.contains(shopTime.day(containing: $0.soldAt)) })
        XCTAssertEqual(Set(history.appointments.map(\.id)).count, history.appointments.count)
        XCTAssertEqual(Set(history.sales.map(\.id)).count, history.sales.count)
        XCTAssertGreaterThan(history.appointments.count, 1_000)
    }

    func testEverythingFollowsTheShopsRules() async throws {
        let history = history()
        let shopTime = TestClock.shopTime
        let sales = Dictionary(uniqueKeysWithValues: history.sales.map { ($0.id, $0) })
        var byBarberAndDay: [String: [IzzyAPI.Appointment]] = [:]
        for appointment in history.appointments {
            let open = try XCTUnwrap(shopTime.openInterval(on: shopTime.day(containing: appointment.start)))
            XCTAssertTrue(appointment.start >= open.start && appointment.end <= open.end, "inside opening hours")
            XCTAssertNotNil(Catalog.izzyClipz.offering(withID: appointment.offeringId))
            byBarberAndDay["\(appointment.barberId)|\(shopTime.day(containing: appointment.start))", default: []].append(appointment)

            if let saleSummary = appointment.sale {
                // Checked out: completed and paid with its sale, whose service is the one booked.
                let sale = try XCTUnwrap(sales[saleSummary.id])
                XCTAssertEqual(appointment.status, .completed)
                XCTAssertEqual(sale.appointmentId, appointment.id)
                XCTAssertEqual(sale.barberId, appointment.barberId)
                XCTAssertEqual(sale.items.first?.serviceId, appointment.serviceId)
                XCTAssertEqual(appointment.payment.status, .paid)
                XCTAssertEqual(appointment.payment.amountCents, sale.totalCents)
                XCTAssertGreaterThanOrEqual(sale.soldAt, appointment.end)
            } else {
                XCTAssertEqual(appointment.payment.status, .unpaid)
            }
            XCTAssertTrue(appointment.customer.name.hasSuffix(" Sample"))
            if let phone = appointment.customer.phone {
                XCTAssertTrue(phone.hasPrefix("+144255501"), "numbers kept for examples")
            }
            // A fee only with a card on file, charged after a no-show ended or for a late cancellation.
            if let fee = appointment.noShowFee {
                XCTAssertNotNil(appointment.card)
                if fee.status == .charged {
                    let chargedAt = try XCTUnwrap(fee.chargedAt)
                    switch fee.reason {
                    case .noShow?:
                        XCTAssertEqual(appointment.status, .noShow)
                        XCTAssertGreaterThan(chargedAt, appointment.end)
                    case .lateCancel?:
                        XCTAssertEqual(appointment.status, .cancelled)
                        XCTAssertEqual(appointment.cancelledBy, .customer)
                        let cancelledAt = try XCTUnwrap(fee.customerCancelledAt)
                        XCTAssertTrue(IzzyAPI.NoShowRule.cancelledLate(
                            start: appointment.start, customerCancelledAt: cancelledAt, lateCancelWindowMinutes: fee.lateCancelWindowMinutes,
                            createdAt: appointment.createdAt
                        ))
                    default:
                        XCTFail("a charged fee says what it was for")
                    }
                }
            } else {
                XCTAssertNil(appointment.card)
            }
        }
        // A barber has one client at a time.
        for (key, appointments) in byBarberAndDay {
            let sorted = appointments.sorted { $0.start < $1.start }
            for (earlier, later) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(earlier.end, later.start, key)
            }
        }
        for sale in history.sales {
            XCTAssertEqual(sale.totalCents, sale.items.reduce(0) { $0 + $1.totalCents })
            XCTAssertEqual(sale.method == .card, sale.paymentIntentId != nil)
            XCTAssertTrue(sale.items.allSatisfy { $0.kind != .product || products.map(\.id).contains($0.productId ?? "") })
        }
        XCTAssertTrue(history.sales.contains { $0.appointmentId == nil }, "walk-ins")
        XCTAssertTrue(history.sales.contains { $0.items.contains { $0.kind == .custom } }, "now and then a gift card")
        XCTAssertTrue(history.appointments.contains { $0.noShowFee?.status == .charged }, "a few fees")
        XCTAssertTrue(history.appointments.contains { $0.status == .completed && $0.sale == nil }, "some marked Done without a checkout")
    }

    /// The demo version, with the real clock: every period has numbers (at least this morning's
    /// sample visits), and the four weeks before today look like a working shop.
    func testTheDemoHasNumbersForEveryPeriod() async throws {
        let environment = DemoMode.environment()
        guard case .sample(let server) = environment.backend else { return XCTFail("not the sample server") }
        server.options.latency = .zero
        let store = AnalyticsStore(
            api: environment.api(ownerKey: FakeServer.ownerKey), shopTime: environment.shopTime, catalog: environment.catalog,
            clock: environment.clock
        )
        for period in AnalyticsPeriod.presets {
            store.select(period)
            await store.refresh()
            let analytics = try XCTUnwrap(store.shown, period.title)
            XCTAssertTrue(store.isLive, period.title)
            XCTAssertGreaterThan(analytics.totals.salesCents, 0, period.title)
            XCTAssertEqual(analytics.leaderboard.count, 5, period.title)
            XCTAssertNotNil(analytics.topBarber, period.title)
        }
        let today = store.today
        XCTAssertNil(store.selectCustom(from: today.adding(days: -28), to: today.adding(days: -1)))
        await store.refresh()
        let weeks = try XCTUnwrap(store.shown)
        XCTAssertGreaterThan(weeks.previous.salesCents, 0, "the four weeks before that have history too")
        XCTAssertGreaterThan(weeks.productivity.chairTimeBooked, 0.3)
        XCTAssertLessThan(weeks.productivity.chairTimeBooked, 0.9)
        XCTAssertFalse(weeks.products.isEmpty)
        XCTAssertGreaterThan(weeks.totals.feesCents, 0)
        XCTAssertEqual(store.rankedLeaderboard.first?.entry.name, "Izzy")
    }

    func testNoHistoryClientIsOneOfTodaysSampleClients() async {
        let todays = Set(Harness(options: FakeServer.Options()).server.appointments.map(\.customer.name))
        let history = Set(history().appointments.map(\.customer.name))
        XCTAssertTrue(todays.isDisjoint(with: history))
    }

    func testTheSampleServerHasHistoryOnlyWhenAsked() async {
        func days(_ options: FakeServer.Options) -> Set<LocalDate> {
            Set(Harness(options: options).server.appointments.map { TestClock.shopTime.day(containing: $0.start) })
        }
        XCTAssertEqual(days(FakeServer.Options()), [TestClock.today], "unit tests start with today alone")
        var options = FakeServer.Options()
        options.sampleHistory = true
        XCTAssertEqual(days(options).count, FakeSampleHistory.days + 1)
        options.empty = true
        XCTAssertEqual(days(options), [], "-fake-empty has no history either")
        guard case .sample(let server) = AppEnvironment.sample().backend else { return XCTFail("not the sample server") }
        XCTAssertTrue(server.options.sampleHistory, "the UI tests and the demo have it")
    }

    /// What the UI tests count on: this year, Izzy sells the most, Carlos sells the most products,
    /// and Cristian does the most services for the most clients, each by a wide margin (so today's
    /// checkouts can't change the order).
    func testTheLeaderboardsOrderChangesWithWhatItRanks() async throws {
        var options = FakeServer.Options()
        options.sampleHistory = true
        let harness = Harness(options: options)
        let year = try await harness.api.analytics(IzzyAPI.AnalyticsQuery(from: day("2026-01-01"), to: TestClock.today))
        func leaders(_ metric: LeaderboardMetric) -> [RankedBarber] { metric.ranked(year.leaderboard) }
        let board = year.leaderboard.map { "\($0.name) $\($0.salesCents / 100) \($0.servicesCount)s \($0.productsCount)p \($0.clientsServed)c" }
            .joined(separator: " | ")
        XCTAssertEqual(leaders(.sales).first?.entry.name, "Izzy", board)
        XCTAssertEqual(leaders(.products).first?.entry.name, "Carlos", board)
        XCTAssertEqual(leaders(.services).first?.entry.name, "Cristian", board)
        XCTAssertEqual(leaders(.clients).first?.entry.name, "Cristian", board)
        let sales = leaders(.sales).map(\.value)
        XCTAssertGreaterThan(sales[0] - sales[1], 50_000, "Izzy leads by more than $500: \(board)")
        let products = leaders(.products).map(\.value)
        XCTAssertGreaterThan(products[0] - products[1], 20, board)
        XCTAssertEqual(year.topBarber?.name, "Izzy")
        XCTAssertEqual(year.granularity, .month)
        XCTAssertGreaterThan(year.totals.feesCents, 0)
        XCTAssertGreaterThan(year.totals.otherCents, 0)
        XCTAssertEqual(year.products.map(\.name).sorted(), ["Sample beard oil", "Sample pomade"])

        // The month so far (Sunday, from the history, and today) has numbers, and so did the days before.
        let month = try await harness.api.analytics(IzzyAPI.AnalyticsQuery(from: day("2026-11-01"), to: TestClock.today))
        XCTAssertGreaterThan(month.series.first?.salesCents ?? 0, 0)
        XCTAssertGreaterThan(month.previous.salesCents, 0, "Oct 30 – 31 had sales")

        // Four weeks inside the history: the chairs were busy about half the time.
        let fourWeeks = try await harness.api.analytics(IzzyAPI.AnalyticsQuery(from: day("2026-10-05"), to: day("2026-11-01")))
        XCTAssertGreaterThan(fourWeeks.productivity.chairTimeBooked, 0.3)
        XCTAssertLessThan(fourWeeks.productivity.chairTimeBooked, 0.9)
        XCTAssertGreaterThan(fourWeeks.productivity.completionRate, 0.8)
        XCTAssertGreaterThan(fourWeeks.productivity.productAttachRate, 0.1)
    }
}
