import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: Symbol.home) }
                .tag(AppTab.home)

            ServicesView()
                .tabItem { Label("Services", systemImage: Symbol.services) }
                .tag(AppTab.services)

            BookView()
                .tabItem { Label("Book", systemImage: Symbol.book) }
                .tag(AppTab.book)

            ShopView()
                .tabItem { Label("Shop", systemImage: Symbol.shop) }
                .tag(AppTab.shop)

            VisitView()
                .tabItem { Label("Visit", systemImage: Symbol.visit) }
                .tag(AppTab.visit)
        }
        .sheet(item: $router.sheet, onDismiss: router.sheetDidDismiss) { sheet in
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
    }
}
