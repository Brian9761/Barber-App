import Accessibility
import Charts
import IzzyClipzKit
import SwiftUI

/// The Analytics tab: how the shop is doing, live, for the whole shop or one barber. This file
/// replaces the tab's placeholder (`AnalyticsTab`, the same name and the same file).
struct AnalyticsTab: View {
    let workspace: Workspace

    var body: some View {
        AnalyticsView(store: workspace.analytics)
    }
}

/// The whole shop's (or one barber's) sales, top barber, leaderboard, services, products, daily
/// sales and productivity for Today, the week, the month, the year or chosen dates. It refreshes
/// every 30 seconds while it's on screen and the app is in the foreground, and on pull to refresh,
/// keeping the numbers on screen while it does. Every number is explained in docs/analytics.md,
/// and each tile's ⓘ says what it means in the same words.
struct AnalyticsView: View {
    @Bindable var store: AnalyticsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsCustomDates = false
    @State private var showsHelp = false
    /// The explanation open in a sheet (a tile's ⓘ, or the change's).
    @State private var info: AnalyticsInfo?
    /// The day (or month) whose bar was tapped in Daily sales.
    @State private var selectedDate: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ScopePicker(store: store)
                    PeriodPicker(store: store, showsCustomDates: $showsCustomDates)
                    content
                    Button {
                        showsHelp = true
                    } label: {
                        Label("What these numbers mean", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analyticsHelpFooter")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsHelp = true
                    } label: {
                        Label("What these numbers mean", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("analyticsHelp")
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showsCustomDates) {
                CustomDatesSheet(store: store)
            }
            .sheet(isPresented: $showsHelp) {
                AnalyticsHelpSheet()
            }
            .sheet(item: $info) { info in
                AnalyticsInfoSheet(info: info)
            }
        }
        // Live tracking, while the tab is on screen and the app is in the foreground: load now,
        // then every 30 seconds. SwiftUI cancels the task when the tab goes away or the app leaves
        // the foreground, and starts it again (loading right away) for a new choice of days or barber.
        .task(id: AnalyticsLiveKey(query: store.query, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await store.runLive()
        }
        .onChange(of: store.query) { _, _ in selectedDate = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the shop is doing, live: for the whole shop or one barber.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(store.isLive ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(store.liveText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(store.isLive ? .primary : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("analyticsLive")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let refreshError = store.refreshError {
            RefreshErrorBanner(message: refreshError) {
                Task { await store.refresh() }
            }
        }
        if let analytics = store.shown {
            AnalyticsCards(store: store, analytics: analytics, info: $info, selectedDate: $selectedDate)
                // The numbers before a new choice stay, faded, until the new ones come.
                .opacity(store.isStale ? 0.45 : 1)
                .accessibilityHint(store.isStale ? "Loading the numbers for \(store.periodLine)." : "")
        } else if let loadError = store.loadError {
            ContentUnavailableView {
                Label("Couldn't load the numbers", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try again") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retryAnalytics")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(cardBackground)
            .accessibilityIdentifier("analyticsLoadError")
        } else {
            LoadingCards()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
    }
}

/// What the live task depends on: a new choice, or the app coming back to the foreground, starts it again.
struct AnalyticsLiveKey: Hashable {
    let query: IzzyAPI.AnalyticsQuery
    let isActive: Bool
}

/// One explanation, for its sheet.
struct AnalyticsInfo: Identifiable, Hashable {
    let title: String
    let text: String

    var id: String { title }
}

/// The colors of the charts: each at least 3:1 against the cards (dark mode, which the app always uses).
enum AnalyticsColors {
    /// The shop's red: 3.3:1 on the cards.
    static let services = BusinessTheme.red
    static let products = Color.blue
    static let other = Color.teal
    static let fees = Color.orange
    static let otherAndFees = Color.orange
    static let bar = Color.blue
    static let highlight = BusinessTheme.red

    static func color(_ kind: SalesPart.Kind) -> Color {
        switch kind {
        case .services: return services
        case .products: return products
        case .other: return other
        case .fees: return fees
        }
    }

    static func color(_ kind: DailySegment.Kind) -> Color {
        switch kind {
        case .services: return services
        case .products: return products
        case .otherAndFees: return otherAndFees
        }
    }
}

// MARK: - Choosing the barber and the days

/// "Whole shop" and one chip per barber, with his initials.
private struct ScopePicker: View {
    let store: AnalyticsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ScopeChip(title: "Whole shop", monogram: nil, isSelected: store.barberId == nil) {
                    store.selectBarber(nil)
                }
                .accessibilityIdentifier("scope-shop")
                ForEach(store.barbers) { barber in
                    ScopeChip(title: barber.name, monogram: store.monogram(for: barber), isSelected: store.barberId == barber.barberId) {
                        store.selectBarber(barber.barberId)
                    }
                    .accessibilityIdentifier("scope-\(barber.barberId)")
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Whose numbers")
    }
}

private struct ScopeChip: View {
    let title: String
    let monogram: String?
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let monogram {
                        Text(monogram)
                            .font(.caption2.weight(.bold))
                    } else {
                        Image(systemName: "storefront")
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(isSelected ? Color.white.opacity(0.25) : Color(.systemGray4)))
                .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(minHeight: BusinessTheme.minimumTapSize)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(Capsule().fill(isSelected ? BusinessTheme.red : Color(.tertiarySystemFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "" : "Shows \(title == "Whole shop" ? "the whole shop's" : "\(title)'s") numbers.")
    }
}

/// Today · Week · Month · Year, and Custom… for chosen dates.
private struct PeriodPicker: View {
    let store: AnalyticsStore
    @Binding var showsCustomDates: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Period", selection: Binding<AnalyticsPeriod?>(
                get: { store.period.isCustom ? nil : store.period },
                set: { if let period = $0 { store.select(period) } }
            )) {
                ForEach(AnalyticsPeriod.presets, id: \.self) { period in
                    Text(period.title).tag(Optional(period))
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .accessibilityIdentifier("periodPicker")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    periodLine
                    Spacer(minLength: 8)
                    customButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    periodLine
                    customButton
                }
            }
        }
    }

    private var periodLine: some View {
        Text(store.periodLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("periodLine")
    }

    private var customButton: some View {
        Button {
            showsCustomDates = true
        } label: {
            Label(store.period.isCustom ? "Change dates…" : "Custom…", systemImage: "calendar")
                .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .accessibilityIdentifier("customDates")
    }
}

/// Two dates on the shop's calendar, at most 366 days apart.
private struct CustomDatesSheet: View {
    let store: AnalyticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date
    @State private var problem: String?

    init(store: AnalyticsStore) {
        self.store = store
        let range = store.range
        _from = State(initialValue: store.shopTime.noon(on: range.from))
        _to = State(initialValue: store.shopTime.noon(on: range.to))
    }

    private var bounds: ClosedRange<Date> {
        let days = store.customDays
        return store.shopTime.startOfDay(days.first)...store.shopTime.noon(on: days.last)
    }

    private var chosen: AnalyticsDayRange {
        AnalyticsDayRange(from: store.shopTime.day(containing: from), to: store.shopTime.day(containing: to))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $from, in: bounds, displayedComponents: .date)
                        .environment(\.timeZone, store.shopTime.timeZone)
                        .accessibilityIdentifier("customFrom")
                    DatePicker("To", selection: $to, in: bounds, displayedComponents: .date)
                        .environment(\.timeZone, store.shopTime.timeZone)
                        .accessibilityIdentifier("customTo")
                } header: {
                    Text("Show these days")
                } footer: {
                    Text("Up to \(AnalyticsPeriod.maxDays) days, on the shop's calendar. Both days are included.")
                }
                Section {
                    let range = chosen
                    Text(range.dayCount > 0
                        ? "\(AnalyticsText.rangeLabel(range, today: store.today)) · \(AnalyticsText.count(range.dayCount, "day", "days"))"
                        : AnalyticsText.rangeLabel(range, today: store.today))
                        .accessibilityIdentifier("customSummary")
                    if let problem {
                        InlineMessage(text: problem)
                            .accessibilityIdentifier("customProblem")
                    }
                }
            }
            .navigationTitle("Custom dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        let range = chosen
                        if let problem = store.selectCustom(from: range.from, to: range.to) {
                            self.problem = problem
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("showCustomDates")
                }
            }
            .onChange(of: from) { _, _ in problem = nil }
            .onChange(of: to) { _, _ in problem = nil }
        }
    }
}

// MARK: - The cards

/// Total sales, the top barber, the leaderboard, services, products, the daily chart and productivity.
private struct AnalyticsCards: View {
    @Bindable var store: AnalyticsStore
    let analytics: IzzyAPI.Analytics
    @Binding var info: AnalyticsInfo?
    @Binding var selectedDate: String?

    var body: some View {
        VStack(spacing: 16) {
            TotalSalesCard(store: store, analytics: analytics, info: $info)
            TopBarberCard(analytics: analytics)
            LeaderboardCard(store: store, analytics: analytics)
            TopServicesCard(analytics: analytics)
            ProductsSoldCard(analytics: analytics)
            if store.isSingleDay(analytics) {
                ByBarberCard(store: store, analytics: analytics)
            } else {
                DailySalesCard(store: store, analytics: analytics, selectedDate: $selectedDate)
            }
            ProductivityCard(store: store, info: $info)
        }
    }
}

/// A rounded card with a title.
private struct AnalyticsCard<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The ⓘ that opens an explanation: 44 points to tap.
private struct InfoButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.body)
                .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

/// A plain line in a card when there's nothing to show yet.
private struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TotalSalesCard: View {
    let store: AnalyticsStore
    let analytics: IzzyAPI.Analytics
    @Binding var info: AnalyticsInfo?

    var body: some View {
        let totals = analytics.totals
        AnalyticsCard(title: "Total sales", identifier: "totalSalesCard") {
            Text(AnalyticsText.money(totals.salesCents))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .accessibilityLabel("Total sales, \(AnalyticsText.money(totals.salesCents))")
                .accessibilityIdentifier("totalSalesValue")
            HStack(alignment: .center, spacing: 4) {
                changeLine
                Spacer(minLength: 0)
                InfoButton(label: "What the change compares with") {
                    info = AnalyticsInfo(title: "Compared with before", text: store.changeInfo ?? "")
                }
                .accessibilityIdentifier("info-change")
            }
            if totals.salesCents == 0 {
                EmptyLine(text: store.emptySalesText)
                    .accessibilityIdentifier("noSales")
            } else {
                SalesSplit(parts: SalesPart.parts(of: totals))
            }
        }
    }

    @ViewBuilder
    private var changeLine: some View {
        let direction = store.changeDirection
        Label {
            Text(store.changeText ?? "")
        } icon: {
            switch direction {
            case .up: Image(systemName: "arrow.up.right")
            case .down: Image(systemName: "arrow.down.right")
            case .none: Image(systemName: "minus")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(direction == .up ? Color.green : direction == .down ? Color.red : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.changeText ?? "")
        .accessibilityIdentifier("totalSalesChange")
    }
}

/// Services · Products · Other · No-show/late fees: one bar split by part, and each part in words.
private struct SalesSplit: View {
    let parts: [SalesPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(parts.filter { $0.cents > 0 }) { part in
                BarMark(x: .value("Amount", part.cents), y: .value("Sales", "Sales"))
                    .foregroundStyle(AnalyticsColors.color(part.kind))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 22)
            // The lines below say the same in words.
            .accessibilityHidden(true)
            ForEach(parts) { part in
                HStack(spacing: 8) {
                    Circle()
                        .fill(AnalyticsColors.color(part.kind))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(part.title)
                    Spacer(minLength: 8)
                    Text(AnalyticsText.money(part.cents))
                        .monospacedDigit()
                        .foregroundStyle(part.cents == 0 ? .secondary : .primary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("split-\(part.kind.rawValue)")
            }
        }
    }
}

private struct TopBarberCard: View {
    let analytics: IzzyAPI.Analytics

    var body: some View {
        AnalyticsCard(title: analytics.barberId == nil ? "Top sales barber" : "Top sales barber (whole shop)", identifier: "topBarberCard") {
            if let top = analytics.topBarber {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.name)
                            .font(.title2.weight(.bold))
                        Text(AnalyticsText.servicesAndProducts(services: top.servicesCount, products: top.productsCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(AnalyticsText.money(top.salesCents))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("topBarber")
            } else {
                EmptyLine(text: "No sales in this period yet. The barber with the most sales shows here.")
                    .accessibilityIdentifier("noTopBarber")
            }
        }
    }
}

private struct LeaderboardCard: View {
    @Bindable var store: AnalyticsStore
    let analytics: IzzyAPI.Analytics

    var body: some View {
        let ranked = store.rankedLeaderboard
        let most = ranked.map(\.value).max() ?? 0
        AnalyticsCard(title: "Leaderboard", identifier: "leaderboardCard") {
            Text("The whole shop, so each barber sees where he stands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Rank by", selection: $store.metric) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    Text(metric.shortTitle).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .accessibilityIdentifier("leaderboardMetric")
            VStack(spacing: 4) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, barber in
                    LeaderboardRow(
                        barber: barber, label: store.metric.label(for: barber.entry), most: most,
                        isSelected: barber.entry.barberId == analytics.barberId
                    )
                    .accessibilityIdentifier("leaderboard-\(index + 1)")
                }
            }
        }
    }
}

private struct LeaderboardRow: View {
    let barber: RankedBarber
    let label: String
    let most: Int
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                place
                    .frame(minWidth: 28)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        value
                    }
                } else {
                    name
                    Spacer(minLength: 8)
                    value
                }
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(isSelected ? AnalyticsColors.highlight : AnalyticsColors.bar)
                    .frame(width: most > 0 ? max(4, geometry.size.width * CGFloat(barber.value) / CGFloat(most)) : 4)
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? BusinessTheme.red.opacity(0.18) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var place: some View {
        if barber.hasMedal {
            Image(systemName: "medal.fill")
                .font(.title3)
                .foregroundStyle(medalColor)
        } else {
            Text("\(barber.place)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var name: some View {
        Text(barber.entry.name)
            .font(.body.weight(isSelected ? .bold : .regular))
    }

    private var value: some View {
        Text(label)
            .font(.body.weight(.semibold))
            .monospacedDigit()
    }

    private var medalColor: Color {
        switch barber.place {
        case 1: return Color(red: 1, green: 0.84, blue: 0)
        case 2: return Color(white: 0.78)
        default: return Color(red: 0.8, green: 0.52, blue: 0.25)
        }
    }

    private var medalName: String {
        switch barber.place {
        case 1: return "gold medal"
        case 2: return "silver medal"
        default: return "bronze medal"
        }
    }

    private var accessibilityText: String {
        var text = "\(barber.placeLabel), \(barber.entry.name), \(label)"
        if barber.hasMedal { text += ", \(medalName)" }
        return text
    }
}

private struct TopServicesCard: View {
    let analytics: IzzyAPI.Analytics

    var body: some View {
        AnalyticsCard(title: "Top services", identifier: "topServicesCard") {
            if analytics.services.isEmpty {
                EmptyLine(text: "No services in this period yet. They show up as you check clients out or mark them Done.")
                    .accessibilityIdentifier("noServices")
            } else {
                let top = Array(analytics.services.prefix(6))
                Chart(top) { service in
                    BarMark(x: .value("Sales", service.salesCents), y: .value("Service", service.name))
                        .foregroundStyle(AnalyticsColors.bar)
                        .accessibilityLabel(service.name)
                        .accessibilityValue("\(AnalyticsText.money(service.salesCents)), \(service.count) done")
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let cents = value.as(Int.self) { Text(AnalyticsText.compactMoney(cents)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: CGFloat(top.count) * 34 + 30)
                .accessibilityLabel("Top services chart")
                .accessibilityChartDescriptor(ServicesChartDescriptor(services: top))
                .accessibilityIdentifier("topServicesChart")
                VStack(spacing: 0) {
                    ForEach(analytics.services) { service in
                        HStack(spacing: 8) {
                            Text(service.name)
                            Spacer(minLength: 8)
                            Text("\(service.count) done")
                                .foregroundStyle(.secondary)
                            Text(AnalyticsText.money(service.salesCents))
                                .monospacedDigit()
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("service-\(service.serviceId)")
                    }
                }
            }
        }
    }
}

private struct ProductsSoldCard: View {
    let analytics: IzzyAPI.Analytics

    var body: some View {
        AnalyticsCard(title: "Products sold", identifier: "productsCard") {
            if analytics.products.isEmpty {
                EmptyLine(text: "No products sold in this period.")
                    .accessibilityIdentifier("noProducts")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(analytics.products.enumerated()), id: \.offset) { _, product in
                        HStack(spacing: 8) {
                            Text(product.name)
                            Spacer(minLength: 8)
                            Text("\(product.quantity) sold")
                                .foregroundStyle(.secondary)
                            Text(AnalyticsText.money(product.salesCents))
                                .monospacedDigit()
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("product-\(product.name)")
                    }
                }
            }
        }
    }
}

/// Today (or another single day): each barber's sales that day, from the leaderboard.
private struct ByBarberCard: View {
    let store: AnalyticsStore
    let analytics: IzzyAPI.Analytics

    var body: some View {
        let title = store.byBarberTitle(analytics) + (analytics.barberId == nil ? "" : " (whole shop)")
        AnalyticsCard(title: title, identifier: "byBarberCard") {
            Chart(analytics.leaderboard) { entry in
                BarMark(x: .value("Sales", entry.salesCents), y: .value("Barber", entry.name))
                    .foregroundStyle(entry.barberId == analytics.barberId ? AnalyticsColors.highlight : AnalyticsColors.bar)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(AnalyticsText.money(entry.salesCents))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(entry.name)
                    .accessibilityValue(AnalyticsText.money(entry.salesCents))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .chartXScale(domain: 0...max(1, (analytics.leaderboard.map(\.salesCents).max() ?? 0) * 13 / 10))
            .frame(height: CGFloat(max(analytics.leaderboard.count, 1)) * 34 + 16)
            .accessibilityLabel(title)
            .accessibilityChartDescriptor(ByBarberChartDescriptor(title: title, entries: analytics.leaderboard))
            .accessibilityIdentifier("byBarberChart")
        }
    }
}

/// Stacked bars by day (or month): services, products, and other with fees. Tapping a bar shows that day's numbers.
private struct DailySalesCard: View {
    let store: AnalyticsStore
    let analytics: IzzyAPI.Analytics
    @Binding var selectedDate: String?

    var body: some View {
        let title = store.seriesTitle(analytics)
        let selected = selectedDate.flatMap { date in analytics.series.first { $0.date == date } }
        AnalyticsCard(title: title, identifier: "dailySalesCard") {
            Text(selected.map(AnalyticsText.periodDetail) ?? (analytics.granularity == .month
                ? "Tap a bar to see that month's numbers."
                : "Tap a bar to see that day's numbers."))
                .font(.subheadline)
                .foregroundStyle(selected == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dailyDetail")
            Chart(DailySegment.segments(of: analytics.series)) { segment in
                BarMark(x: .value("Day", segment.date), y: .value("Sales", segment.cents))
                    .foregroundStyle(by: .value("Kind", segment.kind.title))
                    .opacity(selectedDate == nil || selectedDate == segment.date ? 1 : 0.4)
                    .accessibilityLabel(AnalyticsText.seriesLabel(segment.date))
                    .accessibilityValue("\(segment.kind.title) \(AnalyticsText.money(segment.cents))")
                    .accessibilityHidden(segment.cents == 0)
            }
            .chartForegroundStyleScale(
                domain: DailySegment.Kind.allCases.map(\.title),
                range: DailySegment.Kind.allCases.map(AnalyticsColors.color)
            )
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisValueLabel {
                        if let date = value.as(String.self) { Text(AnalyticsText.seriesTick(date)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let cents = value.as(Int.self) { Text(AnalyticsText.compactMoney(cents)) }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geometry[plot].origin.x
                            if let date: String = proxy.value(atX: x) { selectedDate = date }
                        }
                }
            }
            .frame(height: 220)
            .accessibilityLabel(title)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: title, series: analytics.series))
            .accessibilityIdentifier("dailySalesChart")
        }
    }

    /// At most about seven labels under the bars.
    private var ticks: [String] {
        let dates = analytics.series.map(\.date)
        guard dates.count > 8 else { return dates }
        let step = Int((Double(dates.count) / 7).rounded(.up))
        return dates.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }
}

private struct ProductivityCard: View {
    let store: AnalyticsStore
    @Binding var info: AnalyticsInfo?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        AnalyticsCard(title: "Business productivity", identifier: "productivityCard") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(store.tiles) { tile in
                    ProductivityTileView(tile: tile) {
                        info = AnalyticsInfo(title: tile.title, text: tile.info)
                    }
                }
            }
        }
    }
}

private struct ProductivityTileView: View {
    let tile: ProductivityTile
    let showInfo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(tile.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tile-\(tile.id)")
            InfoButton(label: "About \(tile.title)", action: showInfo)
                .padding(.top, -10)
                .padding(.trailing, -10)
                .accessibilityIdentifier("info-\(tile.id)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }
}

// MARK: - States

/// While the first numbers load: the cards' shapes, still (no shimmer or other motion).
private struct LoadingCards: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 12) {
                    Text(index == 0 ? "Total sales" : "Top sales barber")
                        .font(.headline)
                    Text("$1,234")
                        .font(.largeTitle.weight(.bold))
                    Text("Services · Products · Other · No-show/late fees")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the numbers")
        .accessibilityIdentifier("analyticsLoading")
    }
}

/// A refresh that failed while the numbers from before stay on screen.
private struct RefreshErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineMessage(text: "Couldn't refresh: \(message) Showing the numbers from before.")
            Button("Try again", action: retry)
                .buttonStyle(.bordered)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("retryAnalyticsRefresh")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BusinessTheme.caution.opacity(0.15)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analyticsRefreshError")
    }
}

// MARK: - Explanations

private struct AnalyticsInfoSheet: View {
    let info: AnalyticsInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(info.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .accessibilityIdentifier("infoText")
            }
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("infoDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AnalyticsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each number's ⓘ says what it means.")
                        .foregroundStyle(.secondary)
                }
                ForEach(AnalyticsHelp.topics) { topic in
                    Section(topic.title) {
                        Text(topic.text)
                            .accessibilityIdentifier("help-\(topic.id)")
                    }
                }
            }
            .navigationTitle("What these numbers mean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("helpDone")
                }
            }
        }
    }
}

// MARK: - Audio graphs

/// Daily (or monthly) sales for VoiceOver's audio graph.
private struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let series: [IzzyAPI.Analytics.Period]

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = series.map { AnalyticsText.seriesLabel($0.date) }
        let most = Double(series.map(\.salesCents).max() ?? 0) / 100
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Day", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(title: "Sales", range: 0...max(most, 1), gridlinePositions: []) { dollars in
            AnalyticsText.money(Int((dollars * 100).rounded()))
        }
        let points = zip(series, labels).map { period, label in
            AXDataPoint(x: label, y: Double(period.salesCents) / 100)
        }
        let total = series.reduce(0) { $0 + $1.salesCents }
        return AXChartDescriptor(
            title: title,
            summary: "\(AnalyticsText.money(total)) in all, over \(AnalyticsText.count(series.count, "bar", "bars")).",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Sales", isContinuous: false, dataPoints: points)]
        )
    }
}

/// Top services for VoiceOver's audio graph.
private struct ServicesChartDescriptor: AXChartDescriptorRepresentable {
    let services: [IzzyAPI.Analytics.ServiceSales]

    func makeChartDescriptor() -> AXChartDescriptor {
        let most = Double(services.map(\.salesCents).max() ?? 0) / 100
        return AXChartDescriptor(
            title: "Top services",
            summary: services.first.map { "\($0.name) brought in the most: \(AnalyticsText.money($0.salesCents))." },
            xAxis: AXCategoricalDataAxisDescriptor(title: "Service", categoryOrder: services.map(\.name)),
            yAxis: AXNumericDataAxisDescriptor(title: "Sales", range: 0...max(most, 1), gridlinePositions: []) { dollars in
                AnalyticsText.money(Int((dollars * 100).rounded()))
            },
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(
                name: "Sales", isContinuous: false,
                dataPoints: services.map { AXDataPoint(x: $0.name, y: Double($0.salesCents) / 100) }
            )]
        )
    }
}

/// Each barber's sales on one day, for VoiceOver's audio graph.
private struct ByBarberChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let entries: [IzzyAPI.Analytics.LeaderboardEntry]

    func makeChartDescriptor() -> AXChartDescriptor {
        let most = Double(entries.map(\.salesCents).max() ?? 0) / 100
        return AXChartDescriptor(
            title: title,
            summary: nil,
            xAxis: AXCategoricalDataAxisDescriptor(title: "Barber", categoryOrder: entries.map(\.name)),
            yAxis: AXNumericDataAxisDescriptor(title: "Sales", range: 0...max(most, 1), gridlinePositions: []) { dollars in
                AnalyticsText.money(Int((dollars * 100).rounded()))
            },
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(
                name: "Sales", isContinuous: false,
                dataPoints: entries.map { AXDataPoint(x: $0.name, y: Double($0.salesCents) / 100) }
            )]
        )
    }
}

#if DEBUG
struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        AnalyticsTab(workspace: workspace)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
    }
}
#endif
