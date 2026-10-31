import SwiftUI

// The sections of the Home tab, top to bottom. Names start with "Home" so they can't clash with
// other screens' views.

// MARK: - Hero

/// The shop's six cuts as a photo pager you swipe through (no autoplay), with the open status on
/// top and "FRESH / OUT THE CHAIR." over an ink band at the bottom. Each photo's real caption and a
/// "3 / 6" counter sit under it, on the canvas. Tapping a photo, or the ↗ button, opens the Gallery.
///
/// Text sits only on the band, which is 82% ink under the type (bone on it is 10:1 or better over
/// any photo); the faces stay clear above it.
struct HomeHero: View {
    /// The pager's minimum height: it grows with the headline at large text sizes.
    let height: CGFloat

    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The photo on screen, kept in step with the pager.
    @State private var page: GalleryPhoto? = HomeHero.photos.first

    /// The cuts, the textured crop first (it's the strongest opener). The storefront isn't here:
    /// it's on the Directions tile and the Visit tab.
    static let photos: [GalleryPhoto] = [.texturedCrop, .curls, .blueColor, .fullBeard, .fadeAndBeard, .classicBeard]

    /// `min(282, 0.32 × screen height)`: 213 pt on a 667 pt iPhone SE, 270 on an 844 pt iPhone,
    /// 282 from 882 pt up.
    static func height(forScreenHeight screenHeight: CGFloat) -> CGFloat {
        min(282, (screenHeight * 0.32).rounded())
    }

    var body: some View {
        let current = page ?? Self.photos[0]
        let index = Self.photos.firstIndex(of: current) ?? 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            card
            caption(for: current, index: index)
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveStatusPill(isOverPhoto: true)
                // One line on the photo: the longest status ("Closed · opens 10 AM tomorrow") still
                // fits at xxxLarge. VoiceOver reads it in full.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(Theme.Space.l)
                // Swipes that start on the pill still turn the page.
                .allowsHitTesting(false)
            Spacer(minLength: Theme.Space.xxl)
            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                headline
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                galleryButton
            }
            .padding(.leading, Theme.Space.xl)
            .padding(.trailing, 14)
            .padding(.bottom, 14)
            .background(alignment: .top) { band }
        }
        // `idealHeight` too: inside the vertical scroll view nothing proposes a height, and without
        // it the spacer wouldn't push the headline down to the bottom of the photo.
        .frame(maxWidth: .infinity, minHeight: height, idealHeight: height, alignment: .topLeading)
        .background { pager }
        .background(Theme.ink3)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }

    /// The one drip word on Home, in bone (red stays for the Book button), over the hero line.
    private var headline: some View {
        // Rubik Wet Paint's drips hang 16 pt below its baseline, inside its own line box; pulling
        // the next line up by a point leaves the 2–4 pt gap the spec asks for.
        VStack(alignment: .leading, spacing: -1) {
            Text("Fresh")
                .textRole(.displayXL)
            Text("Out the chair.")
                .textRole(.displayL)
        }
        .foregroundStyle(Theme.bone)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: false, vertical: true)
        // A slogan, not information: VoiceOver gets the photos and the status instead.
        .accessibilityHidden(true)
    }

    /// 82% ink behind the headline, fading in over the 40 pt above it.
    private var band: some View {
        let fade: CGFloat = 40
        return VStack(spacing: 0) {
            LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Theme.ink.opacity(0.82)
        }
        .padding(.top, -fade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var galleryButton: some View {
        NavigationLink(value: HomeRoute.gallery) {
            Image(systemName: Symbol.external)
        }
        .buttonStyle(IconButtonStyle(fill: Theme.bone, foreground: Theme.ink))
        .accessibilityLabel("See all photos")
        .accessibilityHint("Opens the gallery")
        .accessibilityIdentifier("seeAllPhotos")
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.photos, id: \.self) { photo in
                    FillImage(name: photo.assetName, anchor: photo.heroAnchor)
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: openGallery)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        // One adjustable element for VoiceOver: swipe up or down for the next photo, double-tap
        // for the gallery.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fresh cuts")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turnPage(by: 1)
            case .decrement: turnPage(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction(.default, openGallery)
        .accessibilityHint("Opens the gallery")
        .accessibilityIdentifier("homeHeroPhotos")
    }

    /// "Textured crop with a fade" on the left, "1 / 6" on the right.
    private func caption(for photo: GalleryPhoto, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
            Text(photo.caption)
                .textRole(.label)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\(index + 1) / \(Self.photos.count)")
                .textRole(.detail)
                .foregroundStyle(Theme.bone)
                .fixedSize()
        }
        .padding(.horizontal, Theme.Space.xxs)
        // The pager reads the same thing as its value.
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private var accessibilityValue: String {
        let current = page ?? Self.photos[0]
        let index = Self.photos.firstIndex(of: current) ?? 0
        return "Photo \(index + 1) of \(Self.photos.count), \(current.caption)"
    }

    private func turnPage(by step: Int) {
        let index = Self.photos.firstIndex(of: page ?? Self.photos[0]) ?? 0
        let next = min(max(index + step, 0), Self.photos.count - 1)
        guard next != index else { return }
        withAnimation(reduceMotion ? nil : .snappy) {
            page = Self.photos[next]
        }
    }

    private func openGallery() {
        router.homePath.append(HomeRoute.gallery)
    }
}

private extension GalleryPhoto {
    /// Where to crop each portrait photo for the landscape hero, so the head and the fade line sit
    /// in the clear top half, above the headline's band. Measured on each photo: the textured crop's
    /// head is near the top of the frame, the lined-up beard's much lower.
    var heroAnchor: UnitPoint {
        let y: CGFloat
        switch self {
        case .texturedCrop: y = 0.1
        case .curls: y = 0.27
        case .blueColor: y = 0.35
        case .fullBeard: y = 0.45
        case .fadeAndBeard: y = 0.41
        case .classicBeard: y = 0.30
        }
        return UnitPoint(x: 0.5, y: y)
    }
}

// MARK: - Book, and the next appointment

/// The screen's one red thing, "BOOK AN APPOINTMENT" with the logo's drips, then either the next
/// saved appointment as a ticket or, with nothing booked, a mono line about walk-ins (not another
/// booking card: the button above already does that job).
struct HomeBookSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments

    var body: some View {
        let upcoming = appointments.upcoming
        // Re-checked every minute, so an appointment that's over drops off.
        TimelineView(.everyMinute) { context in
            // The next one that's on, or one the shop cancelled, so the client hears about it.
            let next = upcoming.first { $0.isUpcoming(at: context.date) && ($0.status == .booked || $0.isCancelledByShop) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                bookButton
                if let next {
                    AppointmentCard(appointment: next, isNext: true)
                        // A new card when the next one changes, so an open "Cancel?" can't carry
                        // over to another appointment.
                        .id(next.id)
                } else {
                    walkInLine(at: context.date)
                }
            }
        }
    }

    private var bookButton: some View {
        Button {
            router.startBooking()
        } label: {
            Text("Book an appointment")
        }
        .buttonStyle(.primary(drips: true))
        .accessibilityIdentifier("homeBookButton")
    }

    /// "WALK-INS WELCOME · TODAY 10 AM – 7 PM", from the shop's highlights and regular hours.
    private func walkInLine(at date: Date) -> some View {
        let hours = AppData.clock.todayLabel(at: date)
        let walkIns = AppData.shop.highlights.first { $0.localizedCaseInsensitiveContains("walk-in") }
        let parts = [walkIns, hours].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .textRole(.label)
            .foregroundStyle(Theme.smoke)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Space.xxs)
            .accessibilityLabel(parts.map(\.spokenRanges).joined(separator: ". "))
            .accessibilityIdentifier("homeWalkIns")
    }
}

// MARK: - Popular services

/// The menu's popular services in a row you swipe: icon, name, price range and length. Tapping one
/// opens its page (what's included, who offers it at what price); a chevron, not a "+", because
/// booking isn't a cart.
struct HomePopularSection: View {
    @Environment(AppRouter.self) private var router
    private let services = AppData.catalog.popularServices

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionHeader("Popular") {
                Button {
                    router.selectedTab = .services
                } label: {
                    HomeLinkLabel(title: "All services")
                }
                .accessibilityHint("Opens the Services tab")
                .accessibilityIdentifier("allServicesButton")
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
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
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// An ink card with the service's icon, name, price and length. VIP, "the works in one
/// appointment", is the bone one, as on the Services tab.
struct HomePopularCard: View {
    let service: Service
    /// Wider with larger text, so names don't break mid-word.
    @ScaledMetric(relativeTo: .title3) private var width: CGFloat = 168

    private var isTheWorks: Bool { service.id == "vip" }

    var body: some View {
        let primary = isTheWorks ? Theme.ink : Theme.bone
        let secondary = isTheWorks ? Theme.smokeDark : Theme.smoke
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: service.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(primary)
                    .frame(width: 48, height: 48)
                    .background(isTheWorks ? Theme.bone2 : Theme.ink4,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail * 0.86, style: .continuous))
                Spacer(minLength: Theme.Space.s)
                Image(systemName: Symbol.chevron)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(secondary)
                    .padding(.top, Theme.Space.xxs)
            }
            .accessibilityHidden(true)
            Spacer(minLength: Theme.Space.l)
            Text(service.name)
                .textRole(.displayS)
                .foregroundStyle(primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            PriceText(AppData.catalog.priceSummary(forService: service.id))
                .foregroundStyle(primary)
                .padding(.top, 2)
            Text(AppData.catalog.durationSummary(forService: service.id))
                .textRole(.detail)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(Theme.Space.xl)
        .frame(width: min(width, 300), alignment: .leading)
        .frame(minHeight: 172, maxHeight: .infinity, alignment: .topLeading)
        .background(isTheWorks ? Theme.bone : Theme.ink3, in: shape)
        .contentShape(shape)
    }
}

// MARK: - The crew

/// "THE CREW": the client's barber first, on their own card with a Book button, then everyone else
/// in a row you swipe. Each opens the barber's profile.
struct HomeCrewSection: View {
    @Environment(Favorites.self) private var favorites
    private let barbers = AppData.catalog.barbers

    var body: some View {
        let favorite = favorites.barber
        let crew = barbers.filter { $0.id != favorite?.id }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionHeader("The crew") {
                NavigationLink(value: HomeRoute.team) {
                    HomeLinkLabel(title: "All \(barbers.count) barbers")
                }
                .accessibilityHint("Opens the team")
                .accessibilityIdentifier("meetTeamButton")
            }
            .padding(.horizontal, Theme.gutter)

            if let favorite {
                HomeFavoriteBarberCard(barber: favorite)
                    .padding(.horizontal, Theme.gutter)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(crew) { barber in
                        NavigationLink(value: barber) {
                            HomeCrewCard(barber: barber)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(HomeCrewCard.accessibilityText(for: barber))
                        .accessibilityHint("Opens their profile")
                        .accessibilityIdentifier("homeBarber-\(barber.id)")
                    }
                }
                .scrollTargetLayout()
                // Every card as tall as the tallest one.
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// A barber's card in the crew row: their monogram tile on top, then the name and their title.
struct HomeCrewCard: View {
    let barber: Barber
    /// About 2.9 cards show on a 390 pt screen, so the row clearly scrolls. Wider with larger text.
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 116

    var body: some View {
        // Wide enough at the largest sizes for "Flowxbori" on one line.
        let cardWidth = min(width, 260)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            MonogramTile(barber: barber, size: CGSize(width: cardWidth, height: 66), cornerRadius: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(barber.name)
                    .textRole(.callout)
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HomeBarberMeta(barber: barber)
            }
            .padding(.horizontal, 11)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
        }
        .frame(width: cardWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.ink3)
        .clipShape(shape)
        .contentShape(shape)
    }

    /// "Izzy, Owner, Barber".
    static func accessibilityText(for barber: Barber) -> String {
        [barber.name, barber.title.replacingOccurrences(of: " · ", with: ", ")].joined(separator: ", ")
    }
}

/// The barber's title, "Owner · Barber".
private struct HomeBarberMeta: View {
    let barber: Barber
    @Environment(\.surfaceTone) private var tone

    var body: some View {
        Text(barber.title)
            .textRole(.label)
            .foregroundStyle(tone.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "YOUR BARBER": the client's favorite, with their profile one tap away and a quick way to book
/// them (straight to their own menu).
struct HomeFavoriteBarberCard: View {
    let barber: Barber
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: Symbol.favoriteFilled)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.bone)
                    .accessibilityHidden(true)
                Text("Your barber")
                    .textRole(.label)
                    .foregroundStyle(Theme.smoke)
                    // UI tests look for this exact text; the role sets it in capitals.
                    .accessibilityLabel("Your barber")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.l) {
                    profileLink
                    Spacer(minLength: Theme.Space.s)
                    bookButton
                }
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    profileLink
                    bookButton
                }
            }
        }
        .card()
    }

    private var profileLink: some View {
        // The tile over the name at accessibility sizes, so a long name keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.m))
            : AnyLayout(HStackLayout(spacing: 14))
        return NavigationLink(value: barber) {
            layout {
                MonogramTile(barber: barber, side: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(barber.name)
                        .textRole(.displayS)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    HomeBarberMeta(barber: barber)
                }
                .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(HomeCrewCard.accessibilityText(for: barber)), your barber")
        .accessibilityHint("Opens their profile")
        .accessibilityIdentifier("homeBarber-\(barber.id)")
    }

    private var bookButton: some View {
        Button {
            router.startBooking(barberID: barber.id)
        } label: {
            Text("Book")
        }
        .buttonStyle(.compact)
        .accessibilityLabel("Book with \(barber.name)")
        .accessibilityIdentifier("homeFavoriteBook")
    }
}

/// A section header's trailing link: "All 5 barbers ›".
private struct HomeLinkLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: Symbol.chevron)
                .font(.system(size: 12, weight: .bold))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reviews

/// What clients say: Google's live rating and count, with Google Maps' attribution, opening the
/// Reviews screen. Until Google's numbers arrive (or when they can't be shown), it's a plain link,
/// "See what clients say". Google and Yelp are never added up into one rating.
struct HomeReviewsCard: View {
    @Environment(ReviewsStore.self) private var reviews

    var body: some View {
        NavigationLink(value: HomeRoute.reviews) {
            Group {
                if let summary = reviews.value?.google.summary {
                    rated(summary)
                } else {
                    link
                }
            }
            .card(padding: Theme.Space.xl)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the reviews")
        .accessibilityIdentifier("homeReviews")
        .task {
            // Google's numbers are asked for live and never stored; once per half hour at most.
            await reviews.load(maxAge: 30 * 60)
        }
    }

    private func rated(_ summary: Rating) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("What clients say")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Spacer(minLength: Theme.Space.s)
                MenuChevron()
            }
            ReviewScore(rating: summary, site: "Google")
                .accessibilityIdentifier("homeGoogleRating")
            GoogleMapsAttribution(lead: "From")
        }
        .accessibilityElement(children: .combine)
    }

    private var link: some View {
        HStack(spacing: Theme.Space.l) {
            Image(systemName: Symbol.reviews)
                .font(.title3)
                .foregroundStyle(Theme.bone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("See what clients say")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text("Reviews on Google and Yelp")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
            }
            Spacer(minLength: Theme.Space.s)
            MenuChevron()
        }
        .accessibilityElement(children: .combine)
    }
}
