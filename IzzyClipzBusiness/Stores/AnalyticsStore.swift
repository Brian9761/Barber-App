import Foundation
import IzzyClipzKit
import Observation

// Analytics: how the shop is doing, live, for the whole shop or one barber (GET /api/owner/analytics).
// The numbers come from the server, which defines every one of them (server/src/analytics.ts, in
// plain words in docs/analytics.md); this file picks the days and the barber, asks again every 30
// seconds while the tab is on screen, and puts the answer into words. The Business area of the
// website says the same things the same way (server/web/src/business/lib/periods.ts, leaderboard.ts).

// MARK: - Periods

/// Shop days, both ends included: `from` to `to`.
struct AnalyticsDayRange: Hashable, Sendable {
    var from: LocalDate
    var to: LocalDate

    /// How many days it covers (0 when `to` is before `from`).
    var dayCount: Int { IzzyAPI.AnalyticsQuery(from: from, to: to).dayCount }

    /// Days from `from` to `to`: negative when `to` is earlier.
    static func days(from: LocalDate, to: LocalDate) -> Int {
        to >= from ? IzzyAPI.AnalyticsQuery(from: from, to: to).dayCount - 1 : -(IzzyAPI.AnalyticsQuery(from: to, to: from).dayCount - 1)
    }
}

/// The days Analytics shows, on the shop's calendar (America/Los_Angeles): Today, Week (Monday to
/// today), Month (the 1st to today), Year (January 1 to today), or chosen dates.
enum AnalyticsPeriod: Hashable, Sendable {
    case today
    case week
    case month
    case year
    /// Chosen dates: at most 366 days, within 10 years of today (`AnalyticsPeriod.problem`).
    case custom(from: LocalDate, to: LocalDate)

    /// The segmented control's choices.
    static let presets: [AnalyticsPeriod] = [.today, .week, .month, .year]

    /// The longest range the server answers, in days.
    static let maxDays = IzzyAPI.AnalyticsQuery.maxDays
    /// How far from today chosen dates may be, in days: 10 years of 366 days, the server's limit.
    static let maxDaysFromToday = 3_660

    /// "Today", "Week", "Month", "Year", "Custom".
    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .custom: return "Custom"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// The days it covers when the shop's today is `today`.
    func range(today: LocalDate) -> AnalyticsDayRange {
        switch self {
        case .today:
            return AnalyticsDayRange(from: today, to: today)
        case .week:
            return AnalyticsDayRange(from: Self.monday(of: today), to: today)
        case .month:
            return AnalyticsDayRange(from: LocalDate(year: today.year, month: today.month, day: 1) ?? today, to: today)
        case .year:
            return AnalyticsDayRange(from: LocalDate(year: today.year, month: 1, day: 1) ?? today, to: today)
        case .custom(let from, let to):
            return AnalyticsDayRange(from: from, to: to)
        }
    }

    /// The Monday of `day`'s week: the shop's weeks start on Monday.
    static func monday(of day: LocalDate) -> LocalDate {
        // Weekday raw values: Sunday 1 … Saturday 7, so Monday is 0 days back and Sunday 6.
        day.adding(days: -((day.weekday.rawValue + 5) % 7))
    }

    /// What's wrong with chosen dates, in the website's words, or `nil` when the server will take them.
    static func problem(from: LocalDate, to: LocalDate, today: LocalDate) -> String? {
        if to < from { return "The end date is before the start date. Pick an end date on or after the start." }
        if AnalyticsDayRange(from: from, to: to).dayCount > maxDays { return "Pick at most \(maxDays) days (about a year)." }
        if abs(AnalyticsDayRange.days(from: today, to: from)) > maxDaysFromToday || abs(AnalyticsDayRange.days(from: today, to: to)) > maxDaysFromToday {
            return "Pick dates within 10 years of today."
        }
        return nil
    }
}

// MARK: - Words and numbers

/// Analytics' numbers and dates in words, the same way the website writes them.
enum AnalyticsText {
    static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
    ]

    /// "$1,240", "$17.50", "$0": with thousands commas, cents only when there are some.
    static func money(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = cents.magnitude
        let digits = String(absolute / 100)
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let rest = absolute % 100
        return sign + "$" + grouped + (rest == 0 ? "" : "." + (rest < 10 ? "0" : "") + String(rest))
    }

    /// "$450", "$1.2K", "$12K", "$1.3M": short amounts for a chart's axis.
    static func compactMoney(_ cents: Int) -> String {
        let dollars = Double(cents) / 100
        if dollars < 1_000 { return money(Int((dollars + 0.5).rounded(.down)) * 100) }
        func short(_ value: Double, _ suffix: String) -> String {
            if value < 10 {
                let tenths = Int((value * 10 + 0.5).rounded(.down))
                return "$" + (tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)") + suffix
            }
            return "$\(Int((value + 0.5).rounded(.down)))" + suffix
        }
        return dollars < 1_000_000 ? short(dollars / 1_000, "K") : short(dollars / 1_000_000, "M")
    }

    /// A whole number the way JavaScript's `Math.round` rounds (halves up), so the app and the
    /// website never round the same number differently.
    static func rounded(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    /// "12%", "100%": a share, rounded to the whole percent.
    static func percent(_ ratio: Double) -> String {
        "\(rounded(ratio * 100))%"
    }

    /// "1 service", "3 services".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// "Thu, Oct 29".
    static func shortDate(_ day: LocalDate) -> String {
        "\(day.weekday.shortName), \(monthShort[day.month - 1]) \(day.day)"
    }

    /// "Nov 2", or "Nov 2, 2025" when it isn't `thisYear`.
    private static func dayLabel(_ day: LocalDate, thisYear: Int) -> String {
        day.year == thisYear ? "\(monthShort[day.month - 1]) \(day.day)" : "\(monthShort[day.month - 1]) \(day.day), \(day.year)"
    }

    /// "Nov 2 – Nov 4", "Wed, Nov 4", "Dec 28, 2025 – Jan 3", "Feb 27 – Dec 31, 2025".
    static func rangeLabel(_ range: AnalyticsDayRange, today: LocalDate) -> String {
        let thisYear = today.year
        if range.from == range.to {
            return range.from.year == thisYear ? shortDate(range.from) : shortDate(range.from) + ", \(range.from.year)"
        }
        // Both in the same other year: the year once, at the end.
        if range.from.year != thisYear, range.from.year == range.to.year {
            return "\(dayLabel(range.from, thisYear: range.from.year)) – \(dayLabel(range.to, thisYear: thisYear))"
        }
        return "\(dayLabel(range.from, thisYear: thisYear)) – \(dayLabel(range.to, thisYear: thisYear))"
    }

    /// The period's name on the screen: "Today", "This week", "This month", "This year", or the dates.
    static func periodTitle(_ period: AnalyticsPeriod, range: AnalyticsDayRange, today: LocalDate) -> String {
        switch period {
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        case .custom: return rangeLabel(range, today: today)
        }
    }

    /// What the change is measured from, by name: "yesterday" for Today, otherwise the days
    /// themselves ("Oct 28 – Oct 31", "Sun, Nov 1"): the same number of days just before the
    /// period (the server's `previous`).
    static func comparedWith(previous: AnalyticsDayRange, range: AnalyticsDayRange, today: LocalDate) -> String {
        if range.from == today, range.to == today { return "yesterday" }
        return rangeLabel(previous, today: today)
    }

    /// Whether sales went up or down from the period before, for the change's arrow.
    enum Direction: Equatable {
        case up, down, none
    }

    /// The change in whole percent, rounded like the website; `nil` with no sales before.
    static func changePercent(current: Int, previous: Int) -> Int? {
        guard previous > 0 else { return nil }
        return rounded(Double(current - previous) / Double(previous) * 100)
    }

    static func direction(current: Int, previous: Int) -> Direction {
        guard let change = changePercent(current: current, previous: previous), change != 0 else { return .none }
        return change > 0 ? .up : .down
    }

    /// The change in sales from the same number of days just before (docs/analytics.md, "Compared
    /// with before"), naming them: "Up 12% from yesterday", "Down 6% from Oct 28 – Oct 31", "About
    /// the same as Oct 26 – Nov 1", or "No sales yesterday" ("No sales on Sun, Nov 1") when there's
    /// nothing to compare with.
    static func change(current: Int, previous: IzzyAPI.Analytics.Previous, range: AnalyticsDayRange, today: LocalDate) -> String {
        let before = AnalyticsDayRange(from: previous.from, to: previous.to)
        let named = comparedWith(previous: before, range: range, today: today)
        guard let change = changePercent(current: current, previous: previous.salesCents) else {
            if named == "yesterday" { return "No sales yesterday" }
            return previous.from == previous.to ? "No sales on \(named)" : "No sales \(named)"
        }
        if change == 0 { return "About the same as \(named)" }
        return "\(change > 0 ? "Up" : "Down") \(abs(change))% from \(named)"
    }

    /// A series entry's label on the chart: the day of the month ("3", or "Nov 1" on the 1st), or
    /// the month ("Nov").
    static func seriesTick(_ date: String) -> String {
        if let day = LocalDate(date) {
            return day.day == 1 ? "\(monthShort[day.month - 1]) 1" : "\(day.day)"
        }
        if let month = LocalDate(date + "-01") { return monthShort[month.month - 1] }
        return date
    }

    /// A series entry in words: "Tue, Nov 3", or "November 2026".
    static func seriesLabel(_ date: String) -> String {
        if let day = LocalDate(date) { return shortDate(day) }
        if let month = LocalDate(date + "-01") { return "\(monthNames[month.month - 1]) \(month.year)" }
        return date
    }
}

// MARK: - The leaderboard

/// What the leaderboard ranks by.
enum LeaderboardMetric: String, CaseIterable, Identifiable, Sendable {
    case sales
    case services
    case products
    case clients

    var id: String { rawValue }

    /// "Sales", "Services", "Products", "Clients served".
    var title: String {
        switch self {
        case .sales: return "Sales"
        case .services: return "Services"
        case .products: return "Products"
        case .clients: return "Clients served"
        }
    }

    /// The segmented control's shorter word, where one is needed ("Clients").
    var shortTitle: String {
        self == .clients ? "Clients" : title
    }

    func value(of entry: IzzyAPI.Analytics.LeaderboardEntry) -> Int {
        switch self {
        case .sales: return entry.salesCents
        case .services: return entry.servicesCount
        case .products: return entry.productsCount
        case .clients: return entry.clientsServed
        }
    }

    /// "$215", "3 services", "1 product", "12 clients".
    func label(for entry: IzzyAPI.Analytics.LeaderboardEntry) -> String {
        let value = value(of: entry)
        switch self {
        case .sales: return AnalyticsText.money(value)
        case .services: return AnalyticsText.count(value, "service", "services")
        case .products: return AnalyticsText.count(value, "product", "products")
        case .clients: return AnalyticsText.count(value, "client", "clients")
        }
    }

    /// The leaderboard in this metric's order, highest first. For sales it's the server's own order
    /// and places (sales, then services, then name). Otherwise the value, then the name; barbers with
    /// the same value share a place, and the next place skips (1, 1, 3).
    func ranked(_ entries: [IzzyAPI.Analytics.LeaderboardEntry]) -> [RankedBarber] {
        if self == .sales {
            return entries.map { RankedBarber(entry: $0, place: $0.rank, value: $0.salesCents) }
        }
        let sorted = entries.sorted { a, b in
            let (left, right) = (value(of: a), value(of: b))
            if left != right { return left > right }
            let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
            return nameA != nameB ? nameA < nameB : a.name < b.name
        }
        var place = 0
        return sorted.enumerated().map { index, entry in
            if index == 0 || value(of: sorted[index - 1]) != value(of: entry) { place = index + 1 }
            return RankedBarber(entry: entry, place: place, value: value(of: entry))
        }
    }
}

/// A barber's place on the leaderboard by one metric.
struct RankedBarber: Identifiable, Hashable {
    let entry: IzzyAPI.Analytics.LeaderboardEntry
    /// 1 for the most; barbers with the same value share it.
    let place: Int
    let value: Int

    var id: String { entry.barberId }

    /// The top three get a medal, once they have something to show for it.
    var hasMedal: Bool { place <= 3 && value > 0 }

    /// "1st", "2nd", "3rd", "4th".
    var placeLabel: String {
        let suffix: String
        switch (place % 10, place % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(place)\(suffix)"
    }
}

// MARK: - Business productivity

/// One productivity tile: its number, a few words under it, and what it means (docs/analytics.md).
struct ProductivityTile: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let caption: String
    /// One or two plain sentences, for the tile's ⓘ.
    let info: String

    /// The tiles for `analytics`, in the order they're shown.
    static func tiles(for analytics: IzzyAPI.Analytics) -> [ProductivityTile] {
        let productivity = analytics.productivity
        let appointments = productivity.appointments
        let totals = analytics.totals
        return [
            ProductivityTile(
                id: "chair", title: "Chair time booked",
                value: AnalyticsText.percent(productivity.chairTimeBookedShown),
                caption: "of open hours had a client",
                info: "Booked time divided by open hours. Open hours are each barber's hours on days up to today, less time off. "
                    + "It can pass 100% when barbers work past closing; this shows at most 100%."
            ),
            ProductivityTile(
                id: "clients", title: "Clients served",
                value: "\(totals.clientsServed)",
                caption: totals.clientsServed == 1 ? "client" : "clients",
                info: "Appointments marked Done (or checked out), plus sales to walk-ins."
            ),
            ProductivityTile(
                id: "ticket", title: "Average ticket",
                value: AnalyticsText.money(totals.averageTicketCents),
                caption: "per checkout",
                info: "Services, products and other, divided by checkouts (sales, plus appointments marked Done without a checkout). "
                    + "Fees aren't part of it."
            ),
            ProductivityTile(
                id: "hourly", title: "Sales per open hour",
                value: AnalyticsText.money(productivity.salesPerHourCents),
                caption: "per open hour",
                info: "Services, products and other, divided by the open hours."
            ),
            ProductivityTile(
                id: "noShows", title: "No-shows",
                value: "\(appointments.noShows)",
                caption: "\(AnalyticsText.percent(productivity.noShowRate)) of visits",
                info: "Appointments marked as no-shows. The share is no-shows divided by Done plus no-shows."
            ),
            ProductivityTile(
                id: "late", title: "Late cancellations",
                value: "\(appointments.lateCancellations)",
                caption: "of " + AnalyticsText.count(appointments.cancelled, "cancellation", "cancellations"),
                info: "Clients who cancelled in the app later than their booking's policy allowed for free (for example, less than 1 hour before), "
                    + "and more than 15 minutes after booking: cancelling within 15 minutes of booking is always free."
            ),
            ProductivityTile(
                id: "completion", title: "Completion rate",
                value: AnalyticsText.percent(productivity.completionRate),
                caption: "\(appointments.completed) done",
                info: "Done divided by Done plus no-shows."
            ),
            ProductivityTile(
                id: "attach", title: "Product attach rate",
                value: AnalyticsText.percent(productivity.productAttachRate),
                caption: "of sales included a product",
                info: "The share of sales that included at least one product."
            ),
            ProductivityTile(
                id: "upcoming", title: "Upcoming",
                value: "\(appointments.upcoming)",
                caption: appointments.upcoming == 1 ? "appointment still to come" : "appointments still to come",
                info: "Booked appointments that haven't started yet."
            ),
        ]
    }
}

// MARK: - Charts

/// One part of total sales, for the split under the big number.
struct SalesPart: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Sendable {
        case services, products, other, fees
    }

    let kind: Kind
    let cents: Int

    var id: Kind { kind }

    /// "Services", "Products", "Other", "No-show/late fees".
    var title: String {
        switch kind {
        case .services: return "Services"
        case .products: return "Products"
        case .other: return "Other"
        case .fees: return "No-show/late fees"
        }
    }

    /// Services · Products · Other · No-show/late fees, in that order, zeros included.
    static func parts(of totals: IzzyAPI.Analytics.Totals) -> [SalesPart] {
        [
            SalesPart(kind: .services, cents: totals.servicesCents),
            SalesPart(kind: .products, cents: totals.productsCents),
            SalesPart(kind: .other, cents: totals.otherCents),
            SalesPart(kind: .fees, cents: totals.feesCents),
        ]
    }
}

/// One piece of a day's (or a month's) bar in Daily sales: services, products, or other and fees together.
struct DailySegment: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Sendable {
        case services, products, otherAndFees

        /// "Services", "Products", "Other & fees".
        var title: String {
            switch self {
            case .services: return "Services"
            case .products: return "Products"
            case .otherAndFees: return "Other & fees"
            }
        }
    }

    /// The series entry's date: "2026-11-03", or "2026-11" by month.
    let date: String
    let kind: Kind
    let cents: Int

    var id: String { "\(date)|\(kind.rawValue)" }

    /// Three pieces for every day or month, zeros included, in the series' order.
    static func segments(of series: [IzzyAPI.Analytics.Period]) -> [DailySegment] {
        series.flatMap { period in
            [
                DailySegment(date: period.date, kind: .services, cents: period.servicesCents),
                DailySegment(date: period.date, kind: .products, cents: period.productsCents),
                DailySegment(date: period.date, kind: .otherAndFees, cents: period.otherCents + period.feesCents),
            ]
        }
    }
}

extension AnalyticsText {
    /// A day's (or month's) numbers, for the bar that was tapped and for VoiceOver: "Tue, Nov 3:
    /// $450. Services $380 · Products $54 · Other & fees $16", or "Sun, Nov 1: no sales".
    static func periodDetail(_ period: IzzyAPI.Analytics.Period) -> String {
        let label = seriesLabel(period.date)
        guard period.salesCents > 0 else { return "\(label): no sales" }
        let parts = [
            "Services \(money(period.servicesCents))",
            "Products \(money(period.productsCents))",
            "Other & fees \(money(period.otherCents + period.feesCents))",
        ]
        return "\(label): \(money(period.salesCents)). " + parts.joined(separator: " · ")
    }

    /// "18 services · 6 products".
    static func servicesAndProducts(services: Int, products: Int) -> String {
        "\(count(services, "service", "services")) · \(count(products, "product", "products"))"
    }
}

/// What the numbers mean, in the words of docs/analytics.md, for "What these numbers mean".
enum AnalyticsHelp {
    struct Topic: Identifiable, Hashable {
        let id: String
        let title: String
        let text: String
    }

    static let topics: [Topic] = [
        Topic(
            id: "sources", title: "Where the numbers come from",
            text: "Checkouts: the services, products and custom items like a gift card that you ring up, paid by card, cash or other. "
                + "Each sale gives credit to the barber who did the work. Appointments marked Done without a checkout count as the booked "
                + "service, at its booked price. No-show and late-cancellation fees count once Stripe has charged the card. "
                + "A voided sale doesn't count."
        ),
        Topic(
            id: "days", title: "Days",
            text: "Days are the shop's days, on Pacific time. A sale rung up at 11:30 PM counts on that day, not the next. "
                + "A week starts on Monday."
        ),
        Topic(
            id: "compared", title: "Compared with before",
            text: "Sales for the same number of days just before, so you can see if you're up or down. For a week, that's the week before."
        ),
        Topic(
            id: "leaderboard", title: "Leaderboard and top barber",
            text: "Every barber on the team, from the most to the least, even at $0. It's always the whole shop's, even on one barber's "
                + "page, so each barber can see where he stands. Barbers with the same number share a place. The top barber is #1 "
                + "by sales, once he has sold anything."
        ),
        Topic(
            id: "live", title: "Live",
            text: "The numbers update by themselves every 30 seconds while Analytics is on screen, and when you pull down."
        ),
        Topic(
            id: "privacy", title: "Clients' details",
            text: "Clients' names, numbers, emails and notes are removed 12 months after the appointment (the shop's Privacy Policy). "
                + "The appointments and sales stay, so every number here stays the same: Analytics never uses names, numbers, "
                + "emails or notes."
        ),
    ]
}

// MARK: - The store

/// Analytics' state: the days and the barber picked, the numbers on screen, and the live refresh.
///
/// It asks again every 30 seconds while the tab is on screen and the app is in the foreground
/// (`runLive()`, which the screen runs in `.task`, so SwiftUI stops it when the tab goes away or the
/// app leaves the foreground), and on pull to refresh. It never sends a second request while one is
/// on its way: a refresh for the same days and barber waits for that one, and a new choice cancels
/// it. What's on screen stays while it refreshes, and when a refresh fails (with a banner and Try
/// again); after a new choice, the numbers before stay, dimmed, until the new ones come.
@MainActor
@Observable
final class AnalyticsStore {
    /// How often Analytics refreshes by itself while it's on screen.
    static let refreshInterval: Duration = .seconds(30)

    /// The days on screen.
    private(set) var period: AnalyticsPeriod = .today
    /// One barber's ID, or `nil` for the whole shop.
    private(set) var barberId: String?
    /// What the leaderboard ranks by.
    var metric: LeaderboardMetric = .sales

    /// The numbers loaded last, and the request they answer (`query` may have changed since).
    private(set) var analytics: IzzyAPI.Analytics?
    private(set) var loadedQuery: IzzyAPI.AnalyticsQuery?
    /// A request is on its way.
    private(set) var isLoading = false
    /// Why the last request for the days and barber picked didn't work: a banner over the numbers
    /// from before, or (with nothing to show yet) the screen's message. `nil` after it works or a
    /// new choice.
    private(set) var errorMessage: String?

    let shopTime: ShopTime
    let catalog: Catalog
    @ObservationIgnored private let api: any OwnerAPI
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    /// The request on its way and what it asks for: there's never more than one.
    @ObservationIgnored private var inFlight: (query: IzzyAPI.AnalyticsQuery, task: Task<Void, Never>)?

    init(
        api: any OwnerAPI,
        shopTime: ShopTime,
        catalog: Catalog,
        clock: @escaping () -> Date,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.api = api
        self.shopTime = shopTime
        self.catalog = catalog
        self.clock = clock
        self.sleep = sleep
    }

    // MARK: What's picked

    /// The shop's today.
    var today: LocalDate { shopTime.day(containing: clock()) }

    /// The days the period covers today.
    var range: AnalyticsDayRange { period.range(today: today) }

    /// The request for the days and barber picked.
    var query: IzzyAPI.AnalyticsQuery {
        let range = self.range
        return IzzyAPI.AnalyticsQuery(from: range.from, to: range.to, barberId: barberId)
    }

    func select(_ period: AnalyticsPeriod) {
        guard period != self.period else { return }
        self.period = period
        errorMessage = nil
    }

    /// One barber, or `nil` for the whole shop.
    func selectBarber(_ id: String?) {
        guard id != barberId else { return }
        barberId = id
        errorMessage = nil
    }

    /// Chosen dates: picks them and returns `nil`, or says what's wrong and changes nothing.
    @discardableResult
    func selectCustom(from: LocalDate, to: LocalDate) -> String? {
        if let problem = AnalyticsPeriod.problem(from: from, to: to, today: today) { return problem }
        select(.custom(from: from, to: to))
        return nil
    }

    /// The days the custom sheet can offer: 10 years back to as far ahead as the shop takes bookings.
    var customDays: (first: LocalDate, last: LocalDate) {
        let today = self.today
        return (today.adding(days: -AnalyticsPeriod.maxDaysFromToday), today.adding(days: shopTime.bookingCalendar.windowDays))
    }

    /// The scope chips: the team, from the latest numbers (the server's list) or the menu.
    var barbers: [IzzyAPI.Analytics.Barber] {
        if let analytics, !analytics.barbers.isEmpty { return analytics.barbers }
        return catalog.barbers.map { IzzyAPI.Analytics.Barber(barberId: $0.id, name: $0.name) }
    }

    /// "Izzy", or "Whole shop".
    var scopeName: String {
        guard let barberId else { return "Whole shop" }
        return barbers.first { $0.barberId == barberId }?.name ?? catalog.barber(withID: barberId)?.name ?? "One barber"
    }

    /// The letters on a barber's chip: "IZ", "CA" (the menu's monogram).
    func monogram(for barber: IzzyAPI.Analytics.Barber) -> String {
        catalog.barber(withID: barber.barberId)?.monogram ?? String(barber.name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
    }

    /// "This week: Nov 2 – Nov 4 · Whole shop", "Today: Mon, Nov 2 · Izzy", "Oct 1 – Oct 31 · Izzy".
    var periodLine: String {
        let range = self.range
        let title = AnalyticsText.periodTitle(period, range: range, today: today)
        let days = period.isCustom ? title : "\(title): \(AnalyticsText.rangeLabel(range, today: today))"
        return "\(days) · \(scopeName)"
    }

    // MARK: What's on screen

    /// The numbers on screen answer the days and barber picked.
    var isCurrent: Bool { analytics != nil && loadedQuery == query }

    /// The numbers on screen are for an earlier choice, while the new ones load.
    var isStale: Bool { analytics != nil && loadedQuery != query && errorMessage == nil }

    /// The numbers to show: the current ones, or the earlier ones while the new ones load.
    var shown: IzzyAPI.Analytics? { isCurrent || isStale ? analytics : nil }

    /// A refresh failed while the numbers from before are on screen: the banner's message.
    var refreshError: String? { isCurrent ? errorMessage : nil }

    /// Nothing to show for the days and barber picked, and loading them didn't work.
    var loadError: String? { isCurrent ? nil : errorMessage }

    /// The live line: "Live · Updated 10:42 AM"; "Last updated 10:42 AM" while refreshing fails;
    /// "Loading…" before the numbers come.
    var liveText: String {
        guard isCurrent, let analytics else { return errorMessage == nil ? "Loading…" : "Not loaded yet" }
        let time = shopTime.time(analytics.generatedAt)
        return refreshError == nil ? "Live · Updated \(time)" : "Last updated \(time)"
    }

    /// The green dot: the numbers on screen are the latest.
    var isLive: Bool { isCurrent && refreshError == nil }

    /// Today: no sales yet ("No sales yet today. …"); otherwise "No sales in this period."
    var emptySalesText: String {
        period == .today ? "No sales yet today. Sales show up here as you check clients out." : "No sales in this period."
    }

    /// "Up 12% from yesterday", "No sales Oct 26 – Nov 1", for the numbers on screen.
    var changeText: String? {
        guard let analytics = shown else { return nil }
        return AnalyticsText.change(
            current: analytics.totals.salesCents, previous: analytics.previous,
            range: AnalyticsDayRange(from: analytics.from, to: analytics.to), today: today
        )
    }

    var changeDirection: AnalyticsText.Direction {
        guard let analytics = shown else { return .none }
        return AnalyticsText.direction(current: analytics.totals.salesCents, previous: analytics.previous.salesCents)
    }

    /// What the change compares with, for its ⓘ.
    var changeInfo: String? {
        guard let analytics = shown else { return nil }
        let previous = AnalyticsText.rangeLabel(AnalyticsDayRange(from: analytics.previous.from, to: analytics.previous.to), today: today)
        let whose = analytics.barberId == nil ? "the whole shop" : "the same barber"
        return "Sales for the same number of days just before this period (\(previous)), for \(whose). For a week, that's the week before."
    }

    /// The leaderboard by `metric`.
    var rankedLeaderboard: [RankedBarber] {
        metric.ranked(shown?.leaderboard ?? [])
    }

    var tiles: [ProductivityTile] {
        shown.map(ProductivityTile.tiles(for:)) ?? []
    }

    /// Numbers for a single day: Daily sales shows each barber's sales that day instead of one bar.
    func isSingleDay(_ analytics: IzzyAPI.Analytics) -> Bool {
        analytics.from == analytics.to
    }

    /// "Today by barber", or "Sun, Nov 1 by barber" for another single day.
    func byBarberTitle(_ analytics: IzzyAPI.Analytics) -> String {
        analytics.from == today ? "Today by barber" : "\(AnalyticsText.shortDate(analytics.from)) by barber"
    }

    /// "Daily sales", or "Sales by month" for a range longer than 62 days.
    func seriesTitle(_ analytics: IzzyAPI.Analytics) -> String {
        analytics.granularity == .month ? "Sales by month" : "Daily sales"
    }

    // MARK: Loading

    /// Loads the numbers for the days and barber picked. Never a second request at once: with one on
    /// its way for the same days and barber, this waits for it; one for an earlier choice is
    /// cancelled.
    func refresh() async {
        let query = self.query
        guard query.isValid else {
            errorMessage = "Pick at most \(AnalyticsPeriod.maxDays) days (about a year)."
            return
        }
        if let inFlight, inFlight.query == query {
            await inFlight.task.value
            return
        }
        inFlight?.task.cancel()
        isLoading = true
        let task = Task { await self.load(query) }
        inFlight = (query, task)
        await task.value
        if inFlight?.task == task {
            inFlight = nil
            isLoading = false
        }
    }

    private func load(_ query: IzzyAPI.AnalyticsQuery) async {
        do {
            let answer = try await api.analytics(query)
            // A newer choice (or a new day) wants other numbers: these aren't shown.
            guard !Task.isCancelled, query == self.query else { return }
            analytics = answer
            loadedQuery = query
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), query == self.query else { return }
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// Live tracking: loads now, then every 30 seconds, until the task running it is cancelled (the
    /// tab went away or the app left the foreground). A slow answer is waited for, never doubled.
    func runLive() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await sleep(Self.refreshInterval)
            } catch {
                return
            }
        }
    }
}
