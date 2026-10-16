import SwiftUI

/// Destinations pushed from Home that aren't a service or a barber.
enum HomeRoute: Hashable {
    case gallery
}

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    @Environment(ReminderStore.self) private var reminders

    private let catalog = AppData.catalog
    private let shop = AppData.shop

    var body: some View {
        NavigationStack {
            GeometryReader { outer in
                // The hero photo runs under the status and navigation bars, so the
                // system can't tell when content scrolls beneath them. This reads
                // how tall those bars are so the scrim below can cover them.
                let barHeight = outer.safeAreaInsets.top
                ScrollView {
                    content
                        .overlay(alignment: .top) {
                            BarScrim(height: barHeight, scrollSpace: Self.scrollSpace)
                        }
                }
                .coordinateSpace(.named(Self.scrollSpace))
                .ignoresSafeArea(.container, edges: .top)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.showReminders()
                    } label: {
                        Image(systemName: reminders.isEnabled ? Symbol.remindersOn : Symbol.reminders)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Cut reminders")
                    .accessibilityIdentifier("remindersButton")
                }
            }
            .navigationDestination(for: Service.self) { ServiceDetailView(service: $0) }
            .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0) }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .gallery: GalleryView()
                }
            }
        }
    }

    private static let scrollSpace = "homeScroll"

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            HomeHero()

            VStack(spacing: 12) {
                Button {
                    router.startBooking()
                } label: {
                    Label("Book an Appointment", systemImage: Symbol.book)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("homeBookButton")

                QuickActions()
            }
            .padding(.horizontal, Theme.gutter)

            if let barber = favorites.barber {
                FavoriteBarberCard(barber: barber)
                    .padding(.horizontal, Theme.gutter)
            }

            popularServices
            team
            gallery
            reviews

            WalkInCard()
                .padding(.horizontal, Theme.gutter)
        }
        .padding(.bottom, 32)
    }

    private var popularServices: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Popular") {
                Button("All services") { router.selectedTab = .services }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(catalog.popularServices) { service in
                        NavigationLink(value: service) {
                            PopularServiceCard(service: service)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                        .accessibilityIdentifier("popular-\(service.id)")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var team: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("The Team") {
                Button("Meet everyone") { router.selectedTab = .team }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(catalog.barbers) { barber in
                        NavigationLink(value: barber) {
                            VStack(spacing: 10) {
                                BarberAvatar(barber: barber, size: 72)
                                Text(barber.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: 92)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(barber.name), \(barber.title)")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Fresh Cuts") {
                NavigationLink("See all", value: HomeRoute.gallery)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("seeAllPhotos")
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GalleryPhoto.allCases) { photo in
                        NavigationLink(value: HomeRoute.gallery) {
                            Image(photo.assetName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityLabel(photo.caption)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Reviews")
                .padding(.horizontal, Theme.gutter)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(shop.rating.averageLabel)
                        .font(.system(size: 44, weight: .black).width(.condensed))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        RatingStars(average: shop.rating.average, size: 14)
                        Text("\(shop.rating.countLabel) on \(shop.ratingSource)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rated \(shop.rating.averageLabel) out of 5 from \(shop.rating.countLabel) on \(shop.ratingSource)")

                ForEach(shop.reviews) { review in
                    ReviewCard(review: review)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
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
                    .init(color: Theme.background, location: 0),
                    .init(color: Theme.background.opacity(0.92), location: 0.75),
                    .init(color: Theme.background.opacity(0), location: 1),
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

/// Full-bleed photo with the wordmark and live open/closed status.
private struct HomeHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FillImage(name: Asset.hero)
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: Theme.background.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: Theme.background.opacity(0.75), location: 0.7),
                    .init(color: Theme.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text("BARBERSHOP · \(AppData.shop.address.city.uppercased()), \(AppData.shop.address.state)")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
                Wordmark()
                Text(AppData.shop.tagline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                LiveStatusPill()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .frame(height: 440)
    }
}

private struct PopularServiceCard: View {
    let service: Service

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ServiceIcon(symbol: service.symbol)
            Spacer(minLength: 0)
            Text(service.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(AppData.catalog.priceSummary(forService: service.id))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.red)
            Text(AppData.catalog.durationSummary(forService: service.id))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        // Grows taller instead of clipping at large text sizes.
        .frame(width: 160, alignment: .topLeading)
        .frame(minHeight: 180, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

private struct FavoriteBarberCard: View {
    let barber: Barber
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 14) {
            BarberAvatar(barber: barber, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your barber")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(barber.name)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Button("Book") {
                router.book(.barber(barber.id))
            }
            .buttonStyle(.compact)
            .accessibilityLabel("Book with \(barber.name)")
        }
        .card()
    }
}

struct ReviewCard: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RatingStars(average: Double(review.stars))
                Spacer()
                Image(systemName: Symbol.quote)
                    .foregroundStyle(Theme.red)
                    .accessibilityHidden(true)
            }
            Text(review.text)
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(review.author) · \(review.source)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(review.stars) star review by \(review.author): \(review.text)")
    }
}

struct WalkInCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Symbol.walkIn)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Walk-ins welcome")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("No appointment? Stop by during open hours. Booking ahead saves you the wait.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
