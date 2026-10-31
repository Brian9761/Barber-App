import SwiftUI

/// The five tabs in the system tab bar, and every sheet the app presents.
///
/// A plain `TabView`: the system bar at the bottom (dark, the selected tab in red), no animation
/// between tabs, and the standard behavior when a tab is tapped again. Each tab owns its
/// `NavigationStack`, so it keeps its pushed screens and scroll position while another tab is
/// showing. Sheets present above everything, one at a time, through the router.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BagStore.self) private var bag

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabRoot(tab)
                    // Bone, not red, for back buttons and plain buttons: red is each screen's main action.
                    .tint(Theme.bone)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .tag(tab)
            }
        }
        // The selected tab in red; the system draws the rest of the bar.
        .tint(Theme.dripRed)
        .background(Theme.ink.ignoresSafeArea())
        .sheet(item: $router.sheet, onDismiss: { router.sheetDidDismiss() }) { sheet in
            sheetContent(sheet)
                .tint(Theme.bone)
                .presentationBackground(Theme.ink2)
        }
        // Asked once Bravo's checkout closes: the app can't see whether the order went through.
        .alert("Did you finish checking out?", isPresented: $router.asksAboutCheckout) {
            Button("Yes, empty my bag") {
                router.answerCheckoutPrompt(finished: true, bag: bag)
            }
            Button("Not yet", role: .cancel) {
                router.answerCheckoutPrompt(finished: false, bag: bag)
            }
        } message: {
            Text("The app can't tell whether your order went through on bravohairgel.com.")
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
        case .bag:
            BagView()
        case .checkout(let url):
            WebSheet(url: url)
        }
    }
}

extension AppTab: CaseIterable {
    /// Left to right, as the tab bar shows them.
    static let allCases: [AppTab] = [.home, .services, .book, .shop, .visit]

    /// The tab's label in the bar, and what VoiceOver (and the UI tests) read.
    var title: String {
        switch self {
        case .home: return "Home"
        case .services: return "Services"
        case .book: return "Book"
        case .shop: return "Shop"
        case .visit: return "Visit"
        }
    }

    var symbol: String {
        switch self {
        case .home: return Symbol.home
        case .services: return Symbol.services
        case .book: return Symbol.book
        case .shop: return Symbol.shop
        case .visit: return Symbol.visit
        }
    }
}
