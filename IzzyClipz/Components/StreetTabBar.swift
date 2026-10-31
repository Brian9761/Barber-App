import SwiftUI

extension AppTab {
    /// Left to right, as the tab bar shows them. The tab sweep's direction comes from this order.
    static let barOrder: [AppTab] = [.home, .services, .book, .shop, .visit]

    /// The button's label, and what VoiceOver reads.
    var barTitle: String {
        switch self {
        case .home: return "Home"
        case .services: return "Services"
        case .book: return "Book"
        case .shop: return "Shop"
        case .visit: return "Visit"
        }
    }

    /// The UI tests' handle on the tab button.
    var barIdentifier: String {
        switch self {
        case .home: return "tab.home"
        case .services: return "tab.services"
        case .book: return "tab.book"
        case .shop: return "tab.shop"
        case .visit: return "tab.visit"
        }
    }

    /// The filled variant when selected, where SF Symbols has one.
    func barSymbol(isSelected: Bool) -> String {
        switch self {
        case .home: return isSelected ? Symbol.homeSelected : Symbol.home
        case .services: return Symbol.services
        case .book: return Symbol.book
        case .shop: return isSelected ? Symbol.shopSelected : Symbol.shop
        case .visit: return Symbol.visit
        }
    }
}

/// The floating "sneaker sole" tab bar (spec §6): a bone capsule over a fade, a raised red Book
/// button in the middle, and the mini barber pole standing over the selected tab.
///
/// - The Book button is the one red that's on every screen. When Book is the selected tab it
///   settles into the bar (a 40 pt circle), freeing the space above the bar for the booking flow's
///   sticky Continue bar.
/// - Tapping the selected tab again calls `onReselect` (pop that tab to its root) and plays no sweep.
/// - A light haptic on every tab change, including ones the app makes (Book an appointment).
/// - Labels stop growing at xLarge; above that, a long press shows the large content viewer.
/// - VoiceOver: one button per tab, "Home" … "Visit", with the selected trait on the current one.
/// - It ignores the keyboard: it stays at the bottom of the screen, under the keyboard.
///
/// Every tab root reserves `contentReserve(for:safeAreaBottom:)` at the bottom, so content and
/// sticky bars clear the bar.
struct StreetTabBar: View {
    @Binding var selection: AppTab
    /// The screen's bottom safe-area inset (the home indicator), without the keyboard.
    var safeAreaBottom: CGFloat
    /// The selected tab's button was tapped again.
    var onReselect: (AppTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Metrics

    static let barHeight: CGFloat = 64
    static let sideInset: CGFloat = 16
    /// The raised Book button, ring included, and how far its top stands above the bar.
    static let raisedDiameter: CGFloat = 62
    static let raisedLift: CGFloat = 34
    /// The Book button when Book is the selected tab: inside the bar, 4 pt from its top.
    static let settledDiameter: CGFloat = 40
    static let settledTop: CGFloat = 4
    /// Where the icons start inside the bar (the mini pole reaches 11 pt in, just above them).
    static let iconTop: CGFloat = 10
    /// The room above the "BOOK" label, so it clears the settled button (and sits a little lower
    /// than the other labels, as the button above it is bigger).
    static let bookLabelOffset: CGFloat = 33
    /// The mini pole's top above the bar's top edge (it reaches 11 pt into the bar).
    static let indicatorRise: CGFloat = 19

    /// The gap between the bar and the bottom of the screen: just inside the home indicator, or
    /// 12 pt on iPhones with a Home button.
    static func bottomGap(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom > 0 ? max(safeAreaBottom - 2, 12) : 12
    }

    /// How much a tab root adds to its bottom safe area so its content and sticky bars sit above
    /// the floating bar: 8 pt clear of the raised Book button on most tabs, and 3 pt clear of the
    /// mini pole on Book, where the button has settled into the bar (on a 390 × 844 iPhone, the
    /// Continue bar's bottom lands 22 pt above the bar, as in the pole spec).
    static func contentReserve(for tab: AppTab, safeAreaBottom: CGFloat) -> CGFloat {
        let barTop = bottomGap(safeAreaBottom: safeAreaBottom) + barHeight
        let above = tab == .book ? indicatorRise + 3 : raisedLift + 8
        return max(0, barTop + above - safeAreaBottom)
    }

    // MARK: Body

    var body: some View {
        let gap = Self.bottomGap(safeAreaBottom: safeAreaBottom)
        ZStack(alignment: .bottom) {
            // Content fades out before it reaches the bar.
            Theme.tabScrim
                .frame(height: gap + Self.barHeight + 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            bar
                .padding(.horizontal, Self.sideInset)
                .padding(.bottom, gap)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.barOrder, id: \.self) { tab in
                item(for: tab)
            }
        }
        .frame(height: Self.barHeight)
        .background { sole }
        // Drawn after the items, so the pole stands in front of the Book button as it passes.
        .overlay(alignment: .top) {
            PoleTabIndicator(selectedIndex: AppTab.barOrder.firstIndex(of: selection) ?? 0, count: AppTab.barOrder.count)
                .offset(y: -Self.indicatorRise)
        }
        .accessibilityElement(children: .contain)
        // VoiceOver reads each button as a tab ("Services, tab, 2 of 5"), as on a system tab bar.
        .accessibilityAddTraits(.isTabBar)
    }

    /// The bone capsule, with a slightly darker 2 pt edge along the bottom like a sneaker's sole.
    private var sole: some View {
        Capsule()
            .fill(Theme.bone2)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Theme.bone)
                    .padding(.bottom, 2)
            }
            .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
    }

    private func item(for tab: AppTab) -> some View {
        let isSelected = tab == selection
        let symbol = tab.barSymbol(isSelected: isSelected)
        return Button {
            if isSelected {
                onReselect(tab)
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                if tab == .book {
                    // The round button sits here (see the overlay); its label always reads as active.
                    Color.clear
                        .frame(width: 26, height: Self.bookLabelOffset)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: isSelected ? .bold : .medium))
                        .frame(height: 26)
                }
                Text(tab.barTitle)
                    .textRole(.tabLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected || tab == .book ? Theme.ink : Theme.smokeDark)
            .padding(.top, Self.iconTop)
            .frame(maxWidth: .infinity, minHeight: Self.barHeight, alignment: .top)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if tab == .book {
                    BookDisc(isSettled: isSelected)
                        .animation(reduceMotion ? nil : PoleTabIndicator.spring, value: isSelected)
                }
            }
        }
        .buttonStyle(TabItemButtonStyle())
        .accessibilityLabel(tab.barTitle)
        .accessibilityHint(tab == .book ? "Book an appointment" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.barIdentifier)
        .accessibilityShowsLargeContentViewer {
            Label(tab.barTitle, systemImage: symbol)
        }
    }
}

/// The red Book button: raised above the bar with a bone ring and a red glow, or settled into the
/// bar when Book is the selected tab.
private struct BookDisc: View {
    let isSettled: Bool

    var body: some View {
        let ring: CGFloat = isSettled ? 0 : 4
        let diameter = isSettled ? StreetTabBar.settledDiameter : StreetTabBar.raisedDiameter
        Image(systemName: Symbol.book)
            .font(.system(size: isSettled ? 18 : 26, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: diameter - 2 * ring, height: diameter - 2 * ring)
            .background(Theme.dripRed, in: Circle())
            .padding(ring)
            .background(Theme.bone, in: Circle())
            .shadow(color: Theme.dripRed.opacity(isSettled ? 0 : 0.55), radius: 9, y: 10)
            .offset(y: isSettled ? StreetTabBar.settledTop : -StreetTabBar.raisedLift)
            .accessibilityHidden(true)
    }
}

/// No dimming or scaling: the selection change itself is the feedback.
private struct TabItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Re-selecting a tab

private struct TabReselectionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Goes up by one each time the tab this view lives in is tapped while it's already selected.
    /// Read it through `onTabReselect(perform:)`.
    var tabReselection: Int {
        get { self[TabReselectionKey.self] }
        set { self[TabReselectionKey.self] = newValue }
    }
}

private struct TabReselectModifier: ViewModifier {
    let action: () -> Void
    @Environment(\.tabReselection) private var reselection

    func body(content: Content) -> some View {
        content.onChange(of: reselection) {
            action()
        }
    }
}

extension View {
    /// Runs `action` when the tab this view lives in is tapped again while selected: pop the tab's
    /// own navigation path to its root, or scroll back to the top.
    ///
    ///     NavigationStack(path: $path) { … }
    ///         .onTabReselect { path = NavigationPath() }
    func onTabReselect(perform action: @escaping () -> Void) -> some View {
        modifier(TabReselectModifier(action: action))
    }
}

// MARK: - Room for the floating bar

private struct TabBarReserveKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much room the floating tab bar takes over the bottom of this tab's screens, beyond the
    /// home indicator's inset. Zero in sheets and while the keyboard is up.
    var tabBarReserve: CGFloat {
        get { self[TabBarReserveKey.self] }
        set { self[TabBarReserveKey.self] = newValue }
    }
}

private struct TabScreenModifier: ViewModifier {
    @Environment(\.tabBarReserve) private var reserve
    @Environment(\.isSelectedTab) private var isSelectedTab

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, reserve)
            .accessibilityHidden(!isSelectedTab)
    }
}

extension View {
    /// Makes this screen behave as part of its tab: its scrolling content and sticky bottom bars stay
    /// clear of the floating tab bar, and while another tab is selected, VoiceOver (and UI tests)
    /// can't reach it.
    ///
    /// Apply it to a tab's first screen and to every screen it pushes, inside the `NavigationStack`.
    /// Each pushed screen is hosted on its own, so neither padding nor `accessibilityHidden` added
    /// outside the stack reaches it: on iOS 26 Continue and the other pinned bars ended up behind the
    /// tab bar, and every hidden tab stayed in the accessibility tree.
    func tabScreen() -> some View {
        modifier(TabScreenModifier())
    }
}
