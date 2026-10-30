import SwiftUI

/// The Home tab: the drop page. The shop's work up top, the way to book right under it, then the
/// client's next appointment, the quick ways to reach the shop, the menu's favorites, the crew,
/// what clients say, Instagram and Bravo.
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.homePath) {
            HomeScreen()
                .navigationDestination(for: Service.self) { ServiceDetailView(service: $0).barberPolePushRide() }
                .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0).barberPolePushRide() }
                .navigationDestination(for: HomeRoute.self) { route in
                    Group {
                        switch route {
                        case .gallery: GalleryView()
                        case .team: TeamView()
                        case .reviews: ReviewsView()
                        }
                    }
                    .barberPolePushRide()
                }
        }
    }
}

/// The scrolling page under a pinned header. Home has no back button to keep, so its navigation bar
/// is hidden and the shop's own header (mascot, wordmark, reminders bell) takes its place. Every
/// screen pushed from here shows the native bar again, with its back button and swipe-back.
private struct HomeScreen: View {
    private static let top = "homeTop"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // The whole screen's height, bars and home indicator included: the hero is sized from
            // it so a 375 × 667 iPhone SE still shows the Book button and a ticket above the tab bar.
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ScrollViewReader { scroller in
                ScrollView {
                    HomeContent(heroHeight: HomeHero.height(forScreenHeight: screenHeight))
                        .id(Self.top)
                }
                .onTabReselect {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        scroller.scrollTo(Self.top, anchor: .top)
                    }
                }
            }
            // Content scrolls up under the header, which is frosted ink.
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeHeader()
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Everything on Home, top to bottom (art direction §1.2): hero, Book, the next appointment, quick
/// actions, popular services, the crew, reviews, Instagram, Bravo.
private struct HomeContent: View {
    let heroHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
                HomeHero(height: heroHeight)
                HomeBookSection()
                QuickActions()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.xxs)

            VStack(alignment: .leading, spacing: Theme.Space.section) {
                HomePopularSection()
                HomeCrewSection()
                VStack(spacing: 0) {
                    HomeReviewsCard()
                    // Room for the logo sticker that pokes out above the Instagram card.
                    InstagramCard()
                        .padding(.top, 28)
                    HomeBravoCard()
                        .padding(.top, Theme.Space.cardGap)
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, Theme.Space.section)
            .padding(.bottom, Theme.Space.xxl)
        }
    }
}

// MARK: - Header

/// The mascot sticker, "IZZY CLIPZ" and where the shop is, with the reminders bell on the right.
/// Pinned over the content in frosted ink (solid ink2 with Reduce Transparency). It stops growing
/// at xxLarge text so it never eats the screen; the bell shows the large content viewer above that.
private struct HomeHeader: View {
    private let shop = AppData.shop

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            MascotSticker(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Wordmark()
                Text("Barbershop · \(shop.address.city), \(shop.address.state)")
                    .textRole(.monoTag)
                    .foregroundStyle(Theme.smoke)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(shop.name), barbershop in \(shop.address.city), \(shop.address.state)")
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            HomeRemindersButton()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.Space.xxs)
        .padding(.bottom, Theme.Space.s)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background {
            InkMaterial(shape: Rectangle(), tint: 0.9)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// The bell: cut reminder settings. A 44 pt ink3 circle (it's in the content, not a toolbar).
private struct HomeRemindersButton: View {
    @Environment(AppRouter.self) private var router
    @Environment(ReminderStore.self) private var reminders

    var body: some View {
        Button {
            router.showReminders()
        } label: {
            Image(systemName: reminders.isEnabled ? Symbol.remindersOn : Symbol.reminders)
        }
        .buttonStyle(.icon)
        .accessibilityLabel("Cut reminders")
        .accessibilityValue(reminders.isEnabled ? "On" : "Off")
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("remindersButton")
    }
}
