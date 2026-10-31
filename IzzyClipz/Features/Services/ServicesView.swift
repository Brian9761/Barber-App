import SwiftUI

/// The Services tab: the shop's real menu, every service in the data's categories, each with its
/// price range and length across the barbers who offer it. Searchable, with a row of jump chips that
/// scroll to a category. Tapping a service pushes its page.
///
/// No red on this screen: the raised Book button is its only red.
struct ServicesView: View {
    @State private var query = ""
    /// Popped back to the menu when the Services tab is tapped again.
    @State private var path = NavigationPath()
    /// Goes up when the tab is tapped again while the menu itself is showing: back to the top.
    @State private var scrollToTop = 0
    private let catalog = AppData.catalog

    var body: some View {
        let results = catalog.search(query)
        NavigationStack(path: $path) {
            ServicesMenu(results: results, isSearching: isSearching, scrollToTop: scrollToTop)
                .reservesTabBarSpace()
                .overlay {
                    if results.isEmpty {
                        noResults
                    }
                }
                // Under the title, as on iOS 17 and 18, also on iOS 26 (whose automatic placement
                // can move it to the bottom, where the floating tab bar is).
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search services"
                )
                // The native large title (Archivo, from NavigationBarAppearance) sits above the search
                // field, which is where search belongs; it folds into the bar as the menu scrolls.
                .navigationTitle("Services")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Service.self) { ServiceDetailView(service: $0).barberPolePushRide().reservesTabBarSpace() }
                .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0).barberPolePushRide().reservesTabBarSpace() }
        }
        .onTabReselect {
            if path.isEmpty {
                scrollToTop += 1
            } else {
                path = NavigationPath()
            }
        }
    }

    /// Whether the client has typed something to search for. Spaces alone still show the whole menu.
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var noResults: some View {
        EmptyStateView(
            title: "Not on the menu",
            symbol: Symbol.services,
            message: "Nothing matches “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”. The shop can tell you if they do it."
        ) {
            CallButton {
                Text("Call \(AppData.shop.phone.display)")
            }
            .buttonStyle(.secondary)
        }
    }
}

/// What a jump chip or a reselected tab scrolls to.
private enum ServicesMenuAnchor: Hashable {
    case top
    case category(ServiceCategory)
}

/// The menu itself: the kicker, the jump chips and a section per category.
private struct ServicesMenu: View {
    let results: [Service]
    let isSearching: Bool
    let scrollToTop: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver follows a jump to the section's header.
    @AccessibilityFocusState private var focusedCategory: ServiceCategory?
    private let catalog = AppData.catalog

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Kicker(kicker)
                        .accessibilityLabel(kicker.menuSpokenList)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, Theme.Space.xs)
                        .id(ServicesMenuAnchor.top)
                    if !isSearching {
                        jumpChips(proxy)
                            .padding(.top, Theme.Space.s)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        ForEach(catalog.categories) { category in
                            let services = results.filter { $0.category == category }
                            if !services.isEmpty {
                                section(category, services: services)
                                    .id(ServicesMenuAnchor.category(category))
                            }
                        }
                        if !results.isEmpty {
                            Text("Prices are from the shop's booking menu and can differ by barber.")
                                .textRole(.caption)
                                .foregroundStyle(Theme.smoke)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, isSearching ? Theme.Space.l : Theme.Space.xl)
                    .padding(.bottom, Theme.Space.xxl)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .screenBackground()
            .onChange(of: scrollToTop) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    proxy.scrollTo(ServicesMenuAnchor.top, anchor: .top)
                }
            }
        }
    }

    /// "The menu · 12 services", or "3 of 12 services" while searching (set in capitals).
    private var kicker: String {
        let total = catalog.services.count
        guard isSearching else { return "The menu · \(total) services" }
        return "\(results.count) of \(total) services"
    }

    // MARK: Jump chips

    /// One chip per category. They scroll the menu; they don't filter it, so none is ever selected.
    private func jumpChips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(catalog.categories) { category in
                    FilterChip(title: category.title, isSelected: false) {
                        jump(to: category, proxy: proxy)
                    }
                    .accessibilityHint("Jumps to \(category.title)")
                    .accessibilityIdentifier("jump-\(category.id)")
                }
            }
        }
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
    }

    private func jump(to category: ServiceCategory, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            proxy.scrollTo(ServicesMenuAnchor.category(category), anchor: .top)
        }
        focusedCategory = category
    }

    // MARK: Sections

    private func section(_ category: ServiceCategory, services: [Service]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // The count beside the title, or under it once the two don't fit side by side.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    categoryTitle(category)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    categoryCount(services.count)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    categoryTitle(category)
                    categoryCount(services.count)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(category.title), \(Self.count(services.count))")
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusedCategory, equals: category)

            VStack(spacing: Theme.Space.m) {
                ForEach(services) { service in
                    ServiceMenuLink(service: service)
                }
            }
        }
    }

    private func categoryTitle(_ category: ServiceCategory) -> some View {
        MenuTitleText(category.title, role: .displayM)
            .foregroundStyle(Theme.bone)
    }

    private func categoryCount(_ count: Int) -> some View {
        Text(Self.count(count))
            .textRole(.monoTag)
            .foregroundStyle(Theme.smoke)
            .lineLimit(1)
    }

    /// "3 services", "1 service".
    private static func count(_ count: Int) -> String {
        count == 1 ? "1 service" : "\(count) services"
    }
}

// MARK: - Rows

/// A service card that opens the service's page.
private struct ServiceMenuLink: View {
    let service: Service

    var body: some View {
        NavigationLink(value: service) {
            ServiceMenuCard(service: service)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows each barber's price")
        .accessibilityIdentifier("service-\(service.id)")
    }

    private var accessibilityText: String {
        var parts = [ServiceRow.accessibilityText(for: service)]
        if service.id == MenuFeaturedService.id {
            parts.append(MenuFeaturedService.tag)
        }
        parts.append(service.summary)
        return parts.joined(separator: ", ")
    }
}

/// An `ink3` card (bone for the featured service): the service's symbol on a 56 pt tile, its name,
/// the length range in mono with the price range across from it, its description in two lines,
/// and a chevron.
/// At accessibility text sizes the tile moves above the text so the name keeps the full width.
private struct ServiceMenuCard: View {
    let service: Service

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let catalog = AppData.catalog

    private var isFeatured: Bool { service.id == MenuFeaturedService.id }
    private var tone: SurfaceTone { isFeatured ? .bone : .ink }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: Theme.Space.l) {
            mainLayout {
                ServiceIcon(symbol: service.symbol, size: 56)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MenuChevron()
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(isFeatured ? Theme.bone : Theme.ink3, in: shape)
        .environment(\.surfaceTone, tone)
        .contentShape(shape)
    }

    private var mainLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            if isFeatured {
                MonoTag(text: MenuFeaturedService.tag, style: .ink)
                    .padding(.bottom, 2)
            }
            MenuTitleText(service.name, role: .displayS)
                .foregroundStyle(tone.primary)
            ServiceLengthAndPrice(
                duration: catalog.durationSummary(forService: service.id),
                price: catalog.priceSummary(forService: service.id)
            )
            Text(service.summary)
                .textRole(.caption)
                .foregroundStyle(tone.secondary)
                .lineLimit(2)
                .padding(.top, 2)
        }
    }
}

/// The length range in mono on the left and the price range on the right, on one line under the
/// name, so every card has the same shape whatever the name's length ("MILITARY HAIRCUT" and
/// "Included with cut" both fit at 375 pt). With big text the price moves under the length.
private struct ServiceLengthAndPrice: View {
    let duration: String
    let price: String

    @Environment(\.surfaceTone) private var tone

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                durationText
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.m)
                priceText
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                durationText
                    .fixedSize(horizontal: false, vertical: true)
                priceText
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var durationText: some View {
        Text(duration.menuKeepingUnits)
            .textRole(.monoNumber)
            .foregroundStyle(tone.secondary)
            .accessibilityLabel(duration.spokenRanges)
    }

    private var priceText: some View {
        Text(price)
            .textRole(.price)
            .foregroundStyle(tone.primary)
            .accessibilityLabel(price.spokenRanges)
    }
}
