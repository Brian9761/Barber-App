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

            TeamView()
                .tabItem { Label("Team", systemImage: Symbol.team) }
                .tag(AppTab.team)

            VisitView()
                .tabItem { Label("Visit", systemImage: Symbol.visit) }
                .tag(AppTab.visit)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .booking(let request):
                BookingSheet(request: request)
            case .reminders:
                ReminderSettingsView()
            }
        }
    }
}
