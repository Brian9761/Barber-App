import Foundation
import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

private func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

private func range(_ from: String, _ to: String) -> AnalyticsDayRange {
    AnalyticsDayRange(from: day(from), to: day(to))
}

/// The days each period covers, on the shop's calendar.
@MainActor
final class AnalyticsPeriodTests: XCTestCase {
    func testAWeekStartsOnMonday() async {
        // Monday Nov 2, 2026: the week so far is that day.
        XCTAssertEqual(AnalyticsPeriod.week.range(today: day("2026-11-02")), range("2026-11-02", "2026-11-02"))
        // Every day of that week goes back to its Monday, Sunday last.
        for offset in 0..<7 {
            let today = day("2026-11-02").adding(days: offset)
            XCTAssertEqual(AnalyticsPeriod.week.range(today: today), AnalyticsDayRange(from: day("2026-11-02"), to: today), "\(today)")
        }
        XCTAssertEqual(AnalyticsPeriod.monday(of: day("2026-11-08")), day("2026-11-02"), "Sunday is the week's last day")
        XCTAssertEqual(AnalyticsPeriod.monday(of: day("2026-11-09")), day("2026-11-09"))
        // Across New Year: Saturday January 2, 2027 is in the week of Monday December 28, 2026.
        XCTAssertEqual(AnalyticsPeriod.week.range(today: day("2027-01-02")), range("2026-12-28", "2027-01-02"))
    }

    func testAMonthAndAYearStartOnTheFirst() async {
        XCTAssertEqual(AnalyticsPeriod.today.range(today: day("2026-11-02")), range("2026-11-02", "2026-11-02"))
        XCTAssertEqual(AnalyticsPeriod.month.range(today: day("2026-11-02")), range("2026-11-01", "2026-11-02"))
        XCTAssertEqual(AnalyticsPeriod.year.range(today: day("2026-11-02")), range("2026-01-01", "2026-11-02"))
        // On January 1 the year and the month are that day alone.
        XCTAssertEqual(AnalyticsPeriod.year.range(today: day("2027-01-01")), range("2027-01-01", "2027-01-01"))
        XCTAssertEqual(AnalyticsPeriod.month.range(today: day("2027-01-01")), range("2027-01-01", "2027-01-01"))
        // A leap year's last day: 366 days, still one request.
        let leapYear = AnalyticsPeriod.year.range(today: day("2028-12-31"))
        XCTAssertEqual(leapYear.dayCount, 366)
        XCTAssertTrue(IzzyAPI.AnalyticsQuery(from: leapYear.from, to: leapYear.to).isValid)
        // February in a leap year.
        XCTAssertEqual(AnalyticsPeriod.month.range(today: day("2028-02-29")), range("2028-02-01", "2028-02-29"))
    }

    func testTodayIsTheShopsDayAcrossDaylightSavingChanges() async {
        func store(at instant: String) -> AnalyticsStore {
            let now = IzzyAPI.Timestamp.date(from: instant)!
            return AnalyticsStore(api: Harness().api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { now })
        }
        // 11:30 PM on Saturday October 31 (daylight time) is still the 31st in the shop, though it's the 1st in UTC.
        XCTAssertEqual(store(at: "2026-11-01T06:30:00Z").today, day("2026-10-31"))
        // Sunday November 1 has 25 hours: 11:30 PM that night (standard time) is still the 1st.
        let longSunday = store(at: "2026-11-02T07:30:00Z")
        XCTAssertEqual(longSunday.today, day("2026-11-01"))
        longSunday.select(.week)
        XCTAssertEqual(longSunday.range, range("2026-10-26", "2026-11-01"), "Sunday ends the week that began on Monday the 26th")
        // The spring change: 11:30 PM on Sunday March 8, 2026 (daylight time) is the 8th.
        XCTAssertEqual(store(at: "2026-03-09T06:30:00Z").today, day("2026-03-08"))
        // And 12:30 AM the next morning is the 9th, a Monday: a new week.
        let monday = store(at: "2026-03-09T07:30:00Z")
        monday.select(.week)
        XCTAssertEqual(monday.range, range("2026-03-09", "2026-03-09"))
    }

    func testChosenDatesAreAtMost366DaysWithinTenYears() async {
        let today = day("2026-11-02")
        func problem(_ from: LocalDate, _ to: LocalDate) -> String? {
            AnalyticsPeriod.problem(from: from, to: to, today: today)
        }
        XCTAssertNil(problem(today, today), "one day")
        XCTAssertNil(problem(day("2025-11-02"), today), "366 days, both ends included")
        XCTAssertEqual(problem(day("2025-11-01"), today), "Pick at most 366 days (about a year).")
        XCTAssertEqual(problem(day("2026-11-03"), today), "The end date is before the start date. Pick an end date on or after the start.")
        XCTAssertNil(problem(today.adding(days: -3_660), today.adding(days: -3_600)), "10 years of 366 days back, as the server allows")
        XCTAssertEqual(problem(today.adding(days: -3_661), today.adding(days: -3_600)), "Pick dates within 10 years of today.")
        XCTAssertEqual(problem(today.adding(days: 3_600), today.adding(days: 3_661)), "Pick dates within 10 years of today.")
    }

    func testChoosingDatesThatDontWorkChangesNothing() async {
        let store = AnalyticsStore(api: Harness().api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { TestClock.now })
        XCTAssertEqual(store.selectCustom(from: day("2025-01-01"), to: day("2026-11-02")), "Pick at most 366 days (about a year).")
        XCTAssertEqual(store.period, .today)
        XCTAssertNil(store.selectCustom(from: day("2026-10-01"), to: day("2026-10-31")))
        XCTAssertEqual(store.period, .custom(from: day("2026-10-01"), to: day("2026-10-31")))
        XCTAssertEqual(store.query, IzzyAPI.AnalyticsQuery(from: day("2026-10-01"), to: day("2026-10-31")))
        XCTAssertEqual(store.periodLine, "Oct 1 – Oct 31 · Whole shop")
        // The custom sheet offers 10 years back to as far ahead as the shop takes bookings.
        XCTAssertEqual(store.customDays.first, TestClock.today.adding(days: -3_660))
        XCTAssertEqual(store.customDays.last, TestClock.today.adding(days: TestClock.shopTime.bookingCalendar.windowDays))
    }
}

/// Numbers and dates in words, the way the website writes them.
final class AnalyticsTextTests: XCTestCase {
    func testMoneyHasCommasAndCentsOnlyWhenThereAreSome() {
        XCTAssertEqual(AnalyticsText.money(0), "$0")
        XCTAssertEqual(AnalyticsText.money(4_000), "$40")
        XCTAssertEqual(AnalyticsText.money(1_750), "$17.50")
        XCTAssertEqual(AnalyticsText.money(1_705), "$17.05")
        XCTAssertEqual(AnalyticsText.money(124_000), "$1,240")
        XCTAssertEqual(AnalyticsText.money(100_000_005), "$1,000,000.05")
        XCTAssertEqual(AnalyticsText.money(-500), "-$5")
    }

    func testShortAmountsForTheChartsAxes() {
        XCTAssertEqual(AnalyticsText.compactMoney(0), "$0")
        XCTAssertEqual(AnalyticsText.compactMoney(45_000), "$450")
        XCTAssertEqual(AnalyticsText.compactMoney(100_000), "$1K")
        XCTAssertEqual(AnalyticsText.compactMoney(120_000), "$1.2K")
        XCTAssertEqual(AnalyticsText.compactMoney(1_200_000), "$12K")
        XCTAssertEqual(AnalyticsText.compactMoney(130_000_000), "$1.3M")
    }

    func testPercentsRoundHalvesUpLikeTheWebsite() {
        XCTAssertEqual(AnalyticsText.percent(0), "0%")
        XCTAssertEqual(AnalyticsText.percent(0.125), "13%")
        XCTAssertEqual(AnalyticsText.percent(0.375), "38%")
        XCTAssertEqual(AnalyticsText.percent(0.004), "0%")
        XCTAssertEqual(AnalyticsText.percent(1), "100%")
        XCTAssertEqual(AnalyticsText.rounded(-12.5), -12, "like JavaScript's Math.round")
        XCTAssertEqual(AnalyticsText.rounded(-12.6), -13)
    }

    func testTheChangeFromThePeriodBefore() {
        let today = day("2026-11-02")
        let todayRange = range("2026-11-02", "2026-11-02")
        let yesterday = { (cents: Int) in IzzyAPI.Analytics.Previous(from: day("2026-11-01"), to: day("2026-11-01"), salesCents: cents) }
        XCTAssertEqual(AnalyticsText.change(current: 11_200, previous: yesterday(10_000), range: todayRange, today: today), "Up 12% from yesterday")
        XCTAssertEqual(AnalyticsText.change(current: 9_400, previous: yesterday(10_000), range: todayRange, today: today), "Down 6% from yesterday")
        XCTAssertEqual(AnalyticsText.change(current: 10_040, previous: yesterday(10_000), range: todayRange, today: today), "About the same as yesterday")
        XCTAssertEqual(AnalyticsText.change(current: 8_750, previous: yesterday(10_000), range: todayRange, today: today), "Down 12% from yesterday", "-12.5% rounds like the website")
        XCTAssertEqual(AnalyticsText.change(current: 5_000, previous: yesterday(0), range: todayRange, today: today), "No sales yesterday")

        // A week names the week before.
        let lastWeek = { (cents: Int) in IzzyAPI.Analytics.Previous(from: day("2026-10-26"), to: day("2026-11-01"), salesCents: cents) }
        let week = range("2026-11-02", "2026-11-08")
        XCTAssertEqual(AnalyticsText.change(current: 15_000, previous: lastWeek(10_000), range: week, today: day("2026-11-08")), "Up 50% from Oct 26 – Nov 1")
        XCTAssertEqual(AnalyticsText.change(current: 15_000, previous: lastWeek(0), range: week, today: day("2026-11-08")), "No sales Oct 26 – Nov 1")
        // Another single day names it.
        let saturday = IzzyAPI.Analytics.Previous(from: day("2026-10-31"), to: day("2026-10-31"), salesCents: 0)
        XCTAssertEqual(AnalyticsText.change(current: 100, previous: saturday, range: range("2026-11-01", "2026-11-01"), today: today), "No sales on Sat, Oct 31")

        XCTAssertEqual(AnalyticsText.direction(current: 11_200, previous: 10_000), .up)
        XCTAssertEqual(AnalyticsText.direction(current: 9_400, previous: 10_000), .down)
        XCTAssertEqual(AnalyticsText.direction(current: 10_040, previous: 10_000), .none)
        XCTAssertEqual(AnalyticsText.direction(current: 10_000, previous: 0), .none)
    }

    func testRangesInWords() {
        let today = day("2026-11-04")
        XCTAssertEqual(AnalyticsText.rangeLabel(range("2026-11-02", "2026-11-04"), today: today), "Nov 2 – Nov 4")
        XCTAssertEqual(AnalyticsText.rangeLabel(range("2026-11-04", "2026-11-04"), today: today), "Wed, Nov 4")
        XCTAssertEqual(AnalyticsText.rangeLabel(range("2025-12-28", "2026-01-03"), today: today), "Dec 28, 2025 – Jan 3")
        XCTAssertEqual(AnalyticsText.rangeLabel(range("2025-02-27", "2025-12-31"), today: today), "Feb 27 – Dec 31, 2025")
        XCTAssertEqual(AnalyticsText.periodTitle(.week, range: range("2026-11-02", "2026-11-04"), today: today), "This week")
        XCTAssertEqual(AnalyticsText.periodTitle(.custom(from: day("2026-10-01"), to: day("2026-10-31")), range: range("2026-10-01", "2026-10-31"), today: today), "Oct 1 – Oct 31")
    }

    func testTheDailyChartsLabelsAndTheTappedDay() {
        XCTAssertEqual(AnalyticsText.seriesTick("2026-11-03"), "3")
        XCTAssertEqual(AnalyticsText.seriesTick("2026-11-01"), "Nov 1")
        XCTAssertEqual(AnalyticsText.seriesTick("2026-11"), "Nov")
        XCTAssertEqual(AnalyticsText.seriesLabel("2026-11-03"), "Tue, Nov 3")
        XCTAssertEqual(AnalyticsText.seriesLabel("2026-11"), "November 2026")
        let tuesday = IzzyAPI.Analytics.Period(
            date: "2026-11-03", salesCents: 45_000, servicesCents: 38_000, productsCents: 5_400, otherCents: 1_000, feesCents: 600
        )
        XCTAssertEqual(AnalyticsText.periodDetail(tuesday), "Tue, Nov 3: $450. Services $380 · Products $54 · Other & fees $16")
        XCTAssertEqual(AnalyticsText.periodDetail(IzzyAPI.Analytics.Period(date: "2026-11-01")), "Sun, Nov 1: no sales")
        XCTAssertEqual(AnalyticsText.servicesAndProducts(services: 18, products: 1), "18 services · 1 product")

        let segments = DailySegment.segments(of: [tuesday])
        XCTAssertEqual(segments.map(\.kind), [.services, .products, .otherAndFees])
        XCTAssertEqual(segments.map(\.cents), [38_000, 5_400, 1_600], "other and fees together")
        let parts = SalesPart.parts(of: IzzyAPI.Analytics.Totals(salesCents: 100, servicesCents: 40, productsCents: 30, otherCents: 20, feesCents: 10))
        XCTAssertEqual(parts.map(\.title), ["Services", "Products", "Other", "No-show/late fees"])
        XCTAssertEqual(parts.map(\.cents), [40, 30, 20, 10])
    }
}

/// The leaderboard by each metric.
final class LeaderboardMetricTests: XCTestCase {
    /// As the server ranks them: by sales, then services, then name.
    private let entries = [
        IzzyAPI.Analytics.LeaderboardEntry(rank: 1, barberId: "israel-flores", name: "Izzy", salesCents: 50_000, servicesCount: 10, productsCount: 2, clientsServed: 11),
        IzzyAPI.Analytics.LeaderboardEntry(rank: 2, barberId: "carlos-rafael", name: "Carlos", salesCents: 40_000, servicesCount: 8, productsCount: 9, clientsServed: 9),
        IzzyAPI.Analytics.LeaderboardEntry(rank: 3, barberId: "cristian-ceja", name: "Cristian", salesCents: 30_000, servicesCount: 12, productsCount: 2, clientsServed: 14),
        IzzyAPI.Analytics.LeaderboardEntry(rank: 4, barberId: "flowxbori", name: "Flowxbori"),
        IzzyAPI.Analytics.LeaderboardEntry(rank: 4, barberId: "julian-ramos", name: "Julian"),
    ]

    func testSalesKeepsTheServersOrderAndPlaces() {
        let ranked = LeaderboardMetric.sales.ranked(entries)
        XCTAssertEqual(ranked.map(\.entry.name), ["Izzy", "Carlos", "Cristian", "Flowxbori", "Julian"])
        XCTAssertEqual(ranked.map(\.place), [1, 2, 3, 4, 4])
    }

    func testEachMetricHasItsOwnOrder() {
        XCTAssertEqual(LeaderboardMetric.services.ranked(entries).map(\.entry.name), ["Cristian", "Izzy", "Carlos", "Flowxbori", "Julian"])
        XCTAssertEqual(LeaderboardMetric.clients.ranked(entries).map(\.entry.name), ["Cristian", "Izzy", "Carlos", "Flowxbori", "Julian"])
        // Izzy and Cristian sold 2 products each: they share 2nd place (by name), and the next place is 4th.
        let products = LeaderboardMetric.products.ranked(entries)
        XCTAssertEqual(products.map(\.entry.name), ["Carlos", "Cristian", "Izzy", "Flowxbori", "Julian"])
        XCTAssertEqual(products.map(\.place), [1, 2, 2, 4, 4])
        XCTAssertEqual(products.map(\.value), [9, 2, 2, 0, 0])
    }

    func testMedalsGoToTheTopThreeWithSomethingToShow() {
        let ranked = LeaderboardMetric.products.ranked(entries)
        XCTAssertEqual(ranked.map(\.hasMedal), [true, true, true, false, false])
        let nobody = LeaderboardMetric.sales.ranked(entries.map { IzzyAPI.Analytics.LeaderboardEntry(rank: 1, barberId: $0.barberId, name: $0.name) })
        XCTAssertFalse(nobody.contains(where: \.hasMedal), "no medal at $0")
    }

    func testPlacesAndValuesInWords() {
        let placeLabels = [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map {
            RankedBarber(entry: entries[0], place: $0, value: 1).placeLabel
        }
        XCTAssertEqual(placeLabels, ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th"])
        XCTAssertEqual(LeaderboardMetric.sales.label(for: entries[0]), "$500")
        XCTAssertEqual(LeaderboardMetric.services.label(for: entries[0]), "10 services")
        XCTAssertEqual(LeaderboardMetric.products.label(for: entries[0]), "2 products")
        XCTAssertEqual(LeaderboardMetric.clients.label(for: entries[0]), "11 clients")
        XCTAssertEqual(LeaderboardMetric.services.label(for: IzzyAPI.Analytics.LeaderboardEntry(rank: 1, barberId: "x", name: "X", servicesCount: 1)), "1 service")
        XCTAssertEqual(LeaderboardMetric.allCases.map(\.title), ["Sales", "Services", "Products", "Clients served"])
        XCTAssertEqual(LeaderboardMetric.clients.shortTitle, "Clients")
    }
}

/// Business productivity's tiles and what their ⓘ says.
final class ProductivityTileTests: XCTestCase {
    func testTheTilesInOrderWithTheirNumbers() throws {
        let analytics = IzzyAPI.Analytics(
            from: day("2026-11-02"), to: day("2026-11-02"), timeZone: "America/Los_Angeles", generatedAt: Date(timeIntervalSince1970: 0),
            totals: IzzyAPI.Analytics.Totals(clientsServed: 1, averageTicketCents: 4_250),
            previous: IzzyAPI.Analytics.Previous(from: day("2026-11-01"), to: day("2026-11-01"), salesCents: 0),
            productivity: IzzyAPI.Analytics.Productivity(
                openMinutes: 540, bookedMinutes: 600, chairTimeBooked: 600.0 / 540,
                appointments: IzzyAPI.Analytics.Productivity.Appointments(booked: 3, completed: 7, noShows: 1, cancelled: 2, lateCancellations: 1, upcoming: 1),
                completionRate: 0.875, noShowRate: 0.125, salesPerHourCents: 3_333, productAttachRate: 0.375
            )
        )
        let tiles = ProductivityTile.tiles(for: analytics)
        XCTAssertEqual(tiles.map(\.id), ["chair", "clients", "ticket", "hourly", "noShows", "late", "completion", "attach", "upcoming"])
        XCTAssertEqual(tiles.map(\.value), ["100%", "1", "$42.50", "$33.33", "1", "1", "88%", "38%", "1"])
        XCTAssertEqual(tiles.map(\.caption), [
            "of open hours had a client", "client", "per checkout", "per open hour", "13% of visits", "of 2 cancellations", "7 done",
            "of sales included a product", "appointment still to come",
        ])
        XCTAssertEqual(tiles.first?.title, "Chair time booked")
        // Each ⓘ explains in one or two plain sentences, in docs/analytics.md's words.
        for tile in tiles {
            XCTAssertFalse(tile.info.isEmpty, tile.id)
            XCTAssertLessThanOrEqual(tile.info.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count, 3, tile.id)
        }
        XCTAssertTrue(try XCTUnwrap(tiles.first).info.contains("at most 100%"))
        XCTAssertTrue(tiles[5].info.contains("within 15 minutes of booking is always free"))
    }

    func testWhatTheNumbersMeanSaysClientsDetailsDontChangeThem() throws {
        let privacy = try XCTUnwrap(AnalyticsHelp.topics.first { $0.id == "privacy" })
        XCTAssertTrue(privacy.text.contains("removed 12 months after the appointment"))
        XCTAssertTrue(privacy.text.contains("every number here stays the same"))
        XCTAssertEqual(Set(AnalyticsHelp.topics.map(\.id)).count, AnalyticsHelp.topics.count)
    }
}

/// Loading, live refresh and what's on screen meanwhile.
@MainActor
final class AnalyticsStoreTests: XCTestCase {
    private func makeStore(
        _ harness: Harness? = nil,
        clock: MovableClock? = nil,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> AnalyticsStore {
        let api = (harness ?? Harness()).api
        let clock = clock ?? MovableClock(TestClock.now)
        return AnalyticsStore(api: api, shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { clock.now }, sleep: sleep)
    }

    private func analyticsCalls(_ harness: Harness) -> Int {
        harness.server.calls.filter { $0 == "analytics" }.count
    }

    func testLoadsTodayForTheWholeShop() async throws {
        let harness = Harness()
        let store = makeStore(harness)
        XCTAssertEqual(store.liveText, "Loading…")
        XCTAssertFalse(store.isLive)
        await store.refresh()
        let analytics = try XCTUnwrap(store.shown)
        XCTAssertEqual(analytics.from, TestClock.today)
        XCTAssertNil(analytics.barberId)
        XCTAssertTrue(store.isCurrent)
        XCTAssertTrue(store.isLive)
        XCTAssertEqual(store.liveText, "Live · Updated 11:05 AM")
        XCTAssertEqual(store.periodLine, "Today: Mon, Nov 2 · Whole shop")
        XCTAssertEqual(store.emptySalesText, "No sales yet today. Sales show up here as you check clients out.")
        // Marcus's and Diego's cuts were marked Done without a checkout: each counts at its booked price.
        XCTAssertEqual(analytics.totals.salesCents, 4_000 + 4_500)
        XCTAssertEqual(analytics.totals.servicesCount, 2)
        XCTAssertEqual(store.changeText, "No sales yesterday")
        XCTAssertEqual(store.changeDirection, .none)
        XCTAssertEqual(store.tiles.count, 9)
        XCTAssertEqual(store.rankedLeaderboard.count, 5, "every barber, even at $0")
        XCTAssertEqual(store.barbers.map(\.name), ["Izzy", "Carlos", "Flowxbori", "Cristian", "Julian"])
        XCTAssertEqual(analyticsCalls(harness), 1)
    }

    func testABarberAndAPeriod() async throws {
        let store = makeStore()
        store.selectBarber("flowxbori")
        store.select(.month)
        XCTAssertEqual(store.query, IzzyAPI.AnalyticsQuery(from: day("2026-11-01"), to: day("2026-11-02"), barberId: "flowxbori"))
        XCTAssertEqual(store.scopeName, "Flowxbori")
        XCTAssertEqual(store.periodLine, "This month: Nov 1 – Nov 2 · Flowxbori")
        await store.refresh()
        let analytics = try XCTUnwrap(store.shown)
        XCTAssertEqual(analytics.barberId, "flowxbori")
        XCTAssertEqual(analytics.leaderboard.count, 5, "the leaderboard stays the whole shop's")
        XCTAssertEqual(store.emptySalesText, "No sales in this period.")
        XCTAssertEqual(store.monogram(for: IzzyAPI.Analytics.Barber(barberId: "israel-flores", name: "Izzy")), "IZ")
        XCTAssertEqual(store.changeInfo, "Sales for the same number of days just before this period (Oct 30 – Oct 31), for the same barber. For a week, that's the week before.")
        store.selectBarber(nil)
        XCTAssertEqual(store.scopeName, "Whole shop")
    }

    func testTwoRefreshesAtOnceAskOnce() async {
        var options = FakeServer.Options()
        options.latency = .milliseconds(80)
        let harness = Harness(options: options)
        let store = makeStore(harness)
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        XCTAssertEqual(analyticsCalls(harness), 1, "the second waits for the first instead of asking again")
        XCTAssertTrue(store.isCurrent)
        XCTAssertFalse(store.isLoading)
    }

    func testTheNumbersStayWhileRefreshingAndWhenARefreshFails() async throws {
        let harness = Harness()
        let store = makeStore(harness)
        await store.refresh()
        let before = try XCTUnwrap(store.shown)

        harness.server.options.latency = .milliseconds(150)
        let refreshing = Task { await store.refresh() }
        let happened = await eventually { store.isLoading }
        XCTAssertTrue(happened)
        XCTAssertEqual(store.shown, before, "the last numbers stay on screen while refreshing")
        XCTAssertTrue(store.isLive)
        await refreshing.value

        harness.server.options.latency = .zero
        harness.server.options.offline = true
        await store.refresh()
        XCTAssertEqual(store.shown, before, "a refresh that fails keeps the numbers")
        XCTAssertNotNil(store.refreshError)
        XCTAssertNil(store.loadError)
        XCTAssertFalse(store.isLive)
        XCTAssertEqual(store.liveText, "Last updated 11:05 AM")

        harness.server.options.offline = false
        await store.refresh()
        XCTAssertNil(store.refreshError)
        XCTAssertTrue(store.isLive)
    }

    func testNothingToShowYetAndLoadingFailsSaysSo() async {
        var options = FakeServer.Options()
        options.offline = true
        let store = makeStore(Harness(options: options))
        await store.refresh()
        XCTAssertNil(store.shown)
        XCTAssertNotNil(store.loadError)
        XCTAssertNil(store.refreshError)
        XCTAssertEqual(store.liveText, "Not loaded yet")
    }

    func testANewChoiceReplacesTheRequestOnItsWay() async throws {
        var options = FakeServer.Options()
        options.latency = .milliseconds(200)
        let harness = Harness(options: options)
        let store = makeStore(harness)
        let today = Task { await store.refresh() }
        let happened = await eventually { store.isLoading }
        XCTAssertTrue(happened)
        store.select(.year)
        await store.refresh()
        await today.value
        let analytics = try XCTUnwrap(store.shown)
        XCTAssertEqual(analytics.from, day("2026-01-01"), "the year's numbers, never today's arriving late")
        XCTAssertEqual(store.loadedQuery, store.query)
        XCTAssertFalse(store.isLoading)
    }

    func testTheNumbersBeforeANewChoiceStayFadedUntilTheNewOnesCome() async throws {
        let store = makeStore()
        await store.refresh()
        store.select(.week)
        XCTAssertTrue(store.isCurrent, "on a Monday the week so far is today: nothing to load")
        store.select(.month)
        XCTAssertFalse(store.isCurrent)
        XCTAssertTrue(store.isStale)
        XCTAssertNotNil(store.shown, "today's numbers stay, faded")
        XCTAssertEqual(store.liveText, "Loading…")
        await store.refresh()
        XCTAssertTrue(store.isCurrent)
        XCTAssertFalse(store.isStale)
    }

    func testTodayMovesOnAfterMidnight() async throws {
        let clock = MovableClock(TestClock.at(23, 50))
        let server = FakeServer(shopTime: TestClock.shopTime, now: { clock.now })
        let store = AnalyticsStore(
            api: server.api(ownerKey: FakeServer.ownerKey), shopTime: TestClock.shopTime, catalog: .izzyClipz, clock: { clock.now }
        )
        await store.refresh()
        XCTAssertEqual(store.shown?.from, TestClock.today)
        clock.now = TestClock.at(0, 5, on: TestClock.today.adding(days: 1))
        XCTAssertEqual(store.query.from, TestClock.today.adding(days: 1))
        XCTAssertTrue(store.isStale, "yesterday's numbers wait, faded, for today's")
        await store.refresh()
        XCTAssertEqual(store.shown?.from, TestClock.today.adding(days: 1))
        XCTAssertEqual(store.liveText, "Live · Updated 12:05 AM")
    }

    func testLiveRefreshesEvery30SecondsAndStopsWhenHidden() async throws {
        let harness = Harness()
        var waits: [Duration] = []
        // Each 30-second wait takes a moment here, so a few refreshes happen quickly.
        let store = makeStore(harness) { duration in
            waits.append(duration)
            try await Task.sleep(for: .milliseconds(15))
        }
        let live = Task { await store.runLive() }
        let happened = await eventually { self.analyticsCalls(harness) >= 3 }
        XCTAssertTrue(happened)
        live.cancel()
        await live.value
        let callsWhenHidden = analyticsCalls(harness)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(analyticsCalls(harness), callsWhenHidden, "nothing more once the tab is hidden or the app is in the background")
        XCTAssertFalse(waits.isEmpty)
        XCTAssertTrue(waits.allSatisfy { $0 == .seconds(30) })
        XCTAssertEqual(AnalyticsStore.refreshInterval, .seconds(30))
    }

    func testPullToRefreshJoinsTheRefreshOnItsWay() async throws {
        var options = FakeServer.Options()
        options.latency = .milliseconds(120)
        let harness = Harness(options: options)
        let store = makeStore(harness)
        let live = Task { await store.runLive() }
        let pull = Task { await store.refresh() }
        await pull.value
        XCTAssertEqual(analyticsCalls(harness), 1, "a slow answer is waited for, never asked for twice")
        XCTAssertTrue(store.isCurrent)
        live.cancel()
        await live.value
    }
}
