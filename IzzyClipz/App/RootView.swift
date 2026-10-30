import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BagStore.self) private var bag

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
        .sheet(item: $router.sheet, onDismiss: { router.sheetDidDismiss() }) { sheet in
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
}
