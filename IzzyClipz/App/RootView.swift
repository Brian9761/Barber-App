import SwiftUI

/// The five tabs in a `PoleTabContainer`, the floating Street Drip tab bar over them, and every
/// sheet the app presents.
///
/// Each tab root stays alive (its scroll position and navigation path survive a tab switch) and
/// reserves room at the bottom for the floating bar. Sheets present above everything, one at a
/// time, through the router.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    /// How many times each tab has been tapped again while selected, for `onTabReselect`.
    @State private var reselections: [AppTab: Int] = [:]
    /// The home indicator's inset (without the keyboard), which places the floating bar.
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        @Bindable var router = router

        PoleTabContainer(tabs: AppTab.barOrder, selection: $router.selectedTab) { tab in
            tabRoot(tab)
                // Bone, not red, for back buttons and plain buttons: red is each screen's main action.
                .tint(Theme.bone)
                .safeAreaPadding(.bottom, StreetTabBar.contentReserve(for: tab, safeAreaBottom: bottomInset))
                .environment(\.tabReselection, reselections[tab, default: 0])
        }
        .overlay(alignment: .bottom) {
            StreetTabBar(selection: $router.selectedTab, safeAreaBottom: bottomInset) { tab in
                reselect(tab)
            }
            // Pinned to the bottom of the screen, under the keyboard when one is up.
            .ignoresSafeArea(edges: .bottom)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bottomInset = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, inset in
                        bottomInset = inset
                    }
            }
            .ignoresSafeArea(.keyboard)
        }
        .background(Theme.ink.ignoresSafeArea())
        .sheet(item: $router.sheet, onDismiss: { router.sheetDidDismiss() }) { sheet in
            sheetContent(sheet)
                .tint(Theme.bone)
                .presentationBackground(Theme.ink2)
        }
    }

    @ViewBuilder private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .services: ServicesView()
        case .book: BookView()
        case .shop: ShopView()
        case .visit: VisitView()
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .squire(let handoff):
            WebSheet(url: handoff.url)
        case .confirmBooking(let plan):
            ConfirmBookingSheet(plan: plan)
        case .web(let url):
            WebSheet(url: url)
        case .reminders:
            ReminderSettingsView()
        case .addToCalendar(let appointment):
            AddToCalendarSheet(appointment: appointment)
        }
    }

    /// The selected tab tapped again: back to its first screen. Home and Book keep their paths in
    /// the router; the other tabs pop their own through `onTabReselect`.
    private func reselect(_ tab: AppTab) {
        switch tab {
        case .home:
            router.homePath = NavigationPath()
        case .book:
            router.bookingPath = []
        case .services, .shop, .visit:
            break
        }
        reselections[tab, default: 0] += 1
    }
}
