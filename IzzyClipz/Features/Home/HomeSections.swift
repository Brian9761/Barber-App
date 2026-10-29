import SwiftUI

// The sections of the Home tab, top to bottom. Names start with "Home" so
// they can't clash with other screens' views.

// MARK: - Hero

/// Full-bleed photo under a royal blue to navy wash, with the shop's logo,
/// where it is, and whether it's open right now.
struct HomeHero: View {
    /// Height of the status and navigation bars the hero runs under.
    let topInset: CGFloat

    private let shop = AppData.shop

    var body: some View {
        VStack(spacing: 14) {
            LogoBadge(height: 112)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(shop.fullName)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 6) {
                Text("BARBERSHOP · \(shop.address.city.uppercased()), \(shop.address.state)")
                    .font(.caption.weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .accessibilityLabel("Barbershop in \(shop.address.city), \(shop.address.state)")
                Text(shop.tagline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            LiveStatusPill(onDark: true)
        }
        .padding(.horizontal, Theme.gutter)
        // Clear the bars when large text makes the hero grow.
        .padding(.top, topInset + 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 440, alignment: .bottom)
        .background { HomeHeroBackdrop() }
        .overlay(alignment: .bottom) {
            StripeBand(stripeWidth: 10)
                .frame(height: 8)
        }
        // Navy, not the light page, shows when pulling down past the top.
        .background(alignment: .top) {
            Theme.blueDeep
                .frame(height: 600)
                .offset(y: -600)
                .accessibilityHidden(true)
        }
    }
}

private struct HomeHeroBackdrop: View {
    var body: some View {
        ZStack {
            FillImage(name: Asset.hero)
            LinearGradient(
                stops: [
                    .init(color: Theme.blueDeep.opacity(0.78), location: 0),
                    .init(color: Theme.blue.opacity(0.45), location: 0.32),
                    .init(color: Theme.blueDeep.opacity(0.88), location: 0.68),
                    .init(color: Theme.blueDeep, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            StripeTexture(opacity: 0.06)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Book, quick actions, next appointment, favorite barber

/// The main call to action, contact shortcuts, the next saved appointment
/// and the client's barber.
struct HomeActions: View {
    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    @Environment(AppointmentStore.self) private var appointments

    var body: some View {
        let upcoming = appointments.upcoming
        let favorite = favorites.barber
        // Re-checked every minute, so an appointment that's over drops off.
        TimelineView(.everyMinute) { context in
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    bookButton
                    QuickActions()
                }
                if let next = upcoming.first(where: { $0.isUpcoming(at: context.date) }) {
                    UpcomingAppointmentCard(appointment: next)
                        // A new card when the next one changes, so an open
                        // "Remove?" can't carry over to another appointment.
                        .id(next.id)
                }
                if let favorite {
                    HomeFavoriteBarberCard(barber: favorite)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private var bookButton: some View {
        Button {
            router.startBooking()
        } label: {
            Label("Book an Appointment", systemImage: Symbol.book)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier("homeBookButton")
    }
}

/// "Your barber", with their profile one tap away and a quick way to book them.
struct HomeFavoriteBarberCard: View {
    let barber: Barber
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: Symbol.favoriteFilled)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.red)
                    .accessibilityHidden(true)
                // UI tests look for this exact text.
                Text("Your barber")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    profileLink
                    Spacer(minLength: 8)
                    bookButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    profileLink
                    bookButton
                }
            }
        }
        .card()
    }

    private var profileLink: some View {
        NavigationLink(value: barber) {
            HStack(spacing: 14) {
                BarberAvatar(barber: barber, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(barber.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(barber.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(barber.name), \(barber.title)")
        .accessibilityHint("Opens their profile")
    }

    private var bookButton: some View {
        Button {
            router.startBooking(barberID: barber.id)
        } label: {
            // Padded so the capsule is a comfortable 44 points tall.
            Text("Book")
                .padding(.horizontal, 6)
                .frame(minHeight: 28)
        }
        .buttonStyle(.compact)
        .accessibilityLabel("Book with \(barber.name)")
    }
}

// MARK: - Popular services

struct HomePopularSection: View {
    @Environment(AppRouter.self) private var router
    private let services = AppData.catalog.popularServices

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Popular") {
                Button("All services") {
                    router.selectedTab = .services
                }
                .accessibilityHint("Opens the Services tab")
                .accessibilityIdentifier("allServicesButton")
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(services) { service in
                        NavigationLink(value: service) {
                            HomePopularCard(service: service)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                        .accessibilityHint("Shows what's included and who offers it")
                        .accessibilityIdentifier("popular-\(service.id)")
                    }
                }
                .scrollTargetLayout()
                // Every card as tall as the tallest one.
                .fixedSize(horizontal: false, vertical: true)
            }
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // Lets the cards' shadows show past the carousel's edges.
            .scrollClipDisabled()
        }
    }
}

/// A white card with the service's icon, name, price in red and length.
struct HomePopularCard: View {
    let service: Service
    /// Wider with larger text, so names don't break mid-word.
    @ScaledMetric(relativeTo: .headline) private var width: CGFloat = 164

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ServiceIcon(symbol: service.symbol, size: 46)
                .padding(.bottom, 8)
            Spacer(minLength: 0)
            Text(service.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppData.catalog.priceSummary(forService: service.id))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppData.catalog.durationSummary(forService: service.id))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: min(width, 300), alignment: .leading)
        .frame(minHeight: 184, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.shadow, radius: 12, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Bravo

/// The shop's Bravo partnership. Opens the Shop tab.
struct HomeBravoBanner: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let sponsor = AppData.products.sponsor
    private let imageName = AppData.products.featured.first?.imageName

    var body: some View {
        Button {
            router.selectedTab = .shop
        } label: {
            card
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the Shop tab")
        .accessibilityIdentifier("bravoBanner")
    }

    private var card: some View {
        // Side by side, or stacked when the text is very large.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            productTile
            copy
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blueDeep.opacity(0.25), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    @ViewBuilder private var productTile: some View {
        if let imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(8)
                .frame(width: 100, height: 100)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
                .accessibilityHidden(true)
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Symbol.partner)
                    .font(.caption.weight(.bold))
                // Wraps on narrow screens and at large text sizes rather than
                // cutting off the partner's name.
                Text("PROUD \(sponsor.name.uppercased()) PARTNER")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.white.opacity(0.9))
            Text(sponsor.fullName)
                .font(.display(.title2))
                .foregroundStyle(Color.white)
            Text("The gels, clay and pomade we trust in the chair.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            shopCapsule
                .padding(.top, 4)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shopCapsule: some View {
        HStack(spacing: 6) {
            Text("Shop \(sponsor.name)")
            Image(systemName: Symbol.chevron)
                .font(.caption.weight(.heavy))
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Theme.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white, in: Capsule())
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.blueDeep, Theme.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            StripeTexture(opacity: 0.07)
        }
    }

    private var accessibilityText: String {
        "Proud \(sponsor.name) partner. \(sponsor.fullName): the gels, clay and pomade we trust in the chair. Shop \(sponsor.name)"
    }
}

// MARK: - The team

struct HomeTeamSection: View {
    @Environment(Favorites.self) private var favorites
    private let barbers = AppData.catalog.barbers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("The Team") {
                NavigationLink("Meet everyone", value: HomeRoute.team)
                    .accessibilityIdentifier("meetTeamButton")
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(barbers) { barber in
                        NavigationLink(value: barber) {
                            HomeTeamMember(barber: barber, isFavorite: favorites.isFavorite(barber.id))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(accessibilityText(for: barber))
                        .accessibilityHint("Opens their profile")
                        .accessibilityIdentifier("homeBarber-\(barber.id)")
                    }
                }
            }
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollClipDisabled()
        }
    }

    private func accessibilityText(for barber: Barber) -> String {
        let base = "\(barber.name), \(barber.title)"
        return favorites.isFavorite(barber.id) ? "\(base), your barber" : base
    }
}

/// A barber's avatar and name, with a heart on the client's favorite.
struct HomeTeamMember: View {
    let barber: Barber
    let isFavorite: Bool
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 84

    var body: some View {
        VStack(spacing: 8) {
            BarberAvatar(barber: barber, size: 68)
                .overlay(alignment: .bottomTrailing) {
                    if isFavorite {
                        favoriteBadge
                    }
                }
            Text(barber.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: min(width, 160))
        .contentShape(Rectangle())
    }

    private var favoriteBadge: some View {
        Image(systemName: Symbol.favoriteFilled)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(Theme.red, in: Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

// MARK: - Fresh cuts

struct HomeFreshCutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Fresh Cuts") {
                NavigationLink("See all", value: HomeRoute.gallery)
                    .accessibilityLabel("See all photos")
                    .accessibilityIdentifier("seeAllPhotos")
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GalleryPhoto.allCases) { photo in
                        NavigationLink(value: HomeRoute.gallery) {
                            FillImage(name: photo.assetName)
                                .frame(width: 150, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: Theme.shadow, radius: 10, y: 4)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(photo.caption)
                        .accessibilityHint("Opens the gallery")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

// MARK: - Reviews

struct HomeReviewsSection: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Reviews") {
                NavigationLink("See all", value: HomeRoute.reviews)
                    .accessibilityLabel("See all reviews")
                    .accessibilityIdentifier("seeAllReviews")
            }

            RatingSummary(ratings: shop.ratings, onOpen: { sourced in
                if let url = sourced.url {
                    router.openWeb(url)
                }
            })

            ForEach(Array(shop.reviews.prefix(2))) { review in
                ReviewCard(review: review)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}
