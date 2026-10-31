import SwiftUI

/// The five tabs in a `PoleTabContainer`, the floating Street Drip tab bar over them, and every
/// sheet the app presents.
///
/// Each tab root stays alive (its scroll position and navigation path survive a tab switch) and
/// reserves room at the bottom for the floating bar. Sheets present above everything, one at a
/// time, through the router.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BagStore.self) private var bag
    /// How many times each tab has been tapped again while selected, for `onTabReselect`.
    @State private var reselections: [AppTab: Int] = [:]
    /// The home indicator's inset (without the keyboard), which places the floating bar.
    @State private var bottomInset: CGFloat = 0
    /// The bar steps aside while typing (the Services search), rather than riding on the keyboard.
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var router = router

        PoleTabContainer(tabs: AppTab.barOrder, selection: $router.selectedTab) { tab in
            tabRoot(tab)
                // Bone, not red, for back buttons and plain buttons: red is each screen's main action.
                .tint(Theme.bone)
                // Applied inside each tab's NavigationStack by `tabScreen()`.
                .environment(\.tabBarReserve, isKeyboardVisible ? 0 : StreetTabBar.contentReserve(for: tab, safeAreaBottom: bottomInset))
                .environment(\.tabReselection, reselections[tab, default: 0])
        }
        .overlay(alignment: .bottom) {
            // Gone, not just transparent, while typing: a see-through bar stayed in the
            // accessibility tree.
            if !isKeyboardVisible {
                StreetTabBar(selection: $router.selectedTab, safeAreaBottom: bottomInset) { tab in
                    reselect(tab)
                }
                // The overlay ends where the safe area does, above the home indicator, and
                // `ignoresSafeArea` doesn't reach past it (on iOS 26 the bar sat 34 pt too high). Moving
                // the bar down by the measured inset puts it, and the scrim under it, on the screen's edge.
                .offset(y: bottomInset)
            }
        }
        // Only a keyboard over the tabs moves the bar. One in a sheet (Squire's or Bravo's pages,
        // the calendar editor) leaves the bar and the five tab layouts alone under it.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            if router.sheet == nil {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        // Every tab stays alive, so a text field on one keeps the keyboard when another is
        // selected, and with the bar hidden there would be no way back. A switch the app makes
        // while the client types (a notification tap that opens Book) ends the typing first.
        .onChange(of: router.selectedTab) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
