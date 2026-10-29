import SwiftUI

/// The Home tab: the shop at a glance, and the quickest ways to book.
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.homePath) {
            HomeScreen()
                .navigationDestination(for: Service.self) { ServiceDetailView(service: $0) }
                .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0) }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .gallery: GalleryView()
                    case .team: TeamView()
                    case .reviews: ReviewsView()
                    }
                }
        }
    }
}

/// The scrolling page, with the hero photo running under the status and
/// navigation bars.
private struct HomeScreen: View {
    static let scrollSpace = "homeScroll"

    var body: some View {
        GeometryReader { outer in
            // The hero runs under the status and navigation bars, so the system
            // can't tell when content scrolls beneath them. This reads how tall
            // those bars are so the scrim below can cover them.
            let barHeight = outer.safeAreaInsets.top
            ScrollView {
                HomeContent(topInset: barHeight)
                    .overlay(alignment: .top) {
                        BarScrim(height: barHeight, scrollSpace: HomeScreen.scrollSpace)
                    }
            }
            .coordinateSpace(.named(HomeScreen.scrollSpace))
            .ignoresSafeArea(.container, edges: .top)
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RemindersButton()
            }
        }
        // A transparent bar in the dark scheme, so the status bar and the bell
        // read white over the navy hero and the navy scrim.
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.clear, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Everything on Home, top to bottom.
private struct HomeContent: View {
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HomeHero(topInset: topInset)

            VStack(alignment: .leading, spacing: 32) {
                HomeActions()
                HomePopularSection()
                HomeBravoBanner()
                    .padding(.horizontal, Theme.gutter)
                HomeTeamSection()
                HomeFreshCutsSection()
                HomeReviewsSection()
                WalkInCard()
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 24)
            // Room for the last card to clear the tab bar.
            .padding(.bottom, 40)
        }
    }
}

/// The bell in the top corner: cut reminder settings.
private struct RemindersButton: View {
    @Environment(AppRouter.self) private var router
    @Environment(ReminderStore.self) private var reminders

    var body: some View {
        Button {
            router.showReminders()
        } label: {
            // A plain white bell reads on the navy hero and scrim. No circle of
            // its own: newer iOS versions draw one around toolbar buttons.
            Image(systemName: reminders.isEnabled ? Symbol.remindersOn : Symbol.reminders)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Cut reminders")
        .accessibilityValue(stateText)
        .accessibilityIdentifier("remindersButton")
    }

    private var stateText: String {
        reminders.isEnabled ? "On" : "Off"
    }
}

/// Fades in behind the status and navigation bars as content scrolls under them.
///
/// Sits at the top of the scrolling content and is pushed down by exactly how
/// far the content has scrolled, so it stays pinned to the top of the screen.
/// Everything is derived from geometry while drawing; no state is updated.
private struct BarScrim: View {
    let height: CGFloat
    let scrollSpace: String

    var body: some View {
        GeometryReader { proxy in
            let scrolled = max(0, -proxy.frame(in: .named(scrollSpace)).minY)
            LinearGradient(
                stops: [
                    .init(color: Theme.blueDeep, location: 0),
                    .init(color: Theme.blueDeep.opacity(0.92), location: 0.75),
                    .init(color: Theme.blueDeep.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height + 16)
            .opacity(min(1, scrolled / 200))
            .offset(y: scrolled)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
