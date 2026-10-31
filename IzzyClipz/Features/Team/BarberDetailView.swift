import SwiftUI

/// A barber's page: their monogram band with the favorite button, who they are, their own menu at
/// their prices, and what clients say about them. Menu rows go straight to the calendar with that
/// service; the red "Book with …" bar (the screen's one red) goes to picking one of their services.
struct BarberDetailView: View {
    let barber: Barber

    @Environment(AppRouter.self) private var router
    /// Whether the name in the content has scrolled up under the navigation bar.
    @State private var nameIsUnderBar = false

    private var reviews: [Review] {
        AppData.shop.reviews.filter { $0.barberID == barber.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    BarberBand(barber: barber)
                    BarberNameBlock(barber: barber)
                        .menuTitleScrolledUnderBar($nameIsUnderBar)
                }
                if let url = barber.instagramURL, let handle = barber.instagramHandle {
                    BarberInstagramRow(barberName: barber.name, handle: handle, url: url)
                }
                BarberAbout(barber: barber)
                BarberMenuSection(barber: barber)
                reviewsSection
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .menuNavigationTitle(barber.name, showsInBar: nameIsUnderBar)
        .screenBackground()
        .stickyBottomBar {
            Button {
                router.startBooking(barberID: barber.id)
            } label: {
                Text("Book with \(barber.name)")
            }
            .buttonStyle(.primary)
            .accessibilityHint("Next, pick one of their services")
            .accessibilityIdentifier("bookBarberButton")
        }
    }

    @ViewBuilder private var reviewsSection: some View {
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("What clients say")
                ForEach(reviews) { review in
                    ReviewCard(review: review)
                }
            }
        }
    }
}

// MARK: - Band and name

/// The barber's monogram as a full-width band, 140 pt tall (the owner's carries the "OWNER" tag),
/// with the favorite button on its corner.
private struct BarberBand: View {
    let barber: Barber

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .overlay {
                GeometryReader { proxy in
                    MonogramTile(barber: barber, size: proxy.size, cornerRadius: Theme.Radius.hero)
                        // The band is decoration with a fixed height: its "OWNER" tag stops growing
                        // before it would cover the letters. The kicker under it says it too.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                BarberFavoriteButton(barber: barber)
                    .padding(Theme.Space.l)
            }
    }
}

/// Their title in mono, the name in Display XL, then how Squire lists them and their Squire rating
/// (nothing for barbers without one: never "0 reviews").
private struct BarberNameBlock: View {
    let barber: Barber

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Kicker(barber.title)
                .accessibilityLabel(barber.title.menuSpokenList)
            MenuTitleText(barber.name, role: .displayXL)
                .foregroundStyle(Theme.bone)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                if barber.listedName != barber.name {
                    Text("Listed as \(barber.listedName) on Squire")
                        .textRole(.label)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let rating = barber.rating {
                    RatingLine(rating: rating, source: "Squire")
                }
            }
        }
    }
}

/// A 44 pt bone circle with an ink heart, filled when this is the client's barber. The favorite
/// shows on Home and first wherever the client picks a barber.
private struct BarberFavoriteButton: View {
    let barber: Barber
    @Environment(Favorites.self) private var favorites

    private var isFavorite: Bool {
        favorites.isFavorite(barber.id)
    }

    var body: some View {
        Button {
            favorites.toggle(barber.id)
        } label: {
            Image(systemName: isFavorite ? Symbol.favoriteFilled : Symbol.favorite)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: Theme.minimumTapSize, height: Theme.minimumTapSize)
                .background(Theme.bone, in: Circle())
                // Keeps the circle's edge visible on the bone tiles too.
                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.16)))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(isFavorite ? "Remove favorite" : "Favorite")
        .accessibilityHint(
            isFavorite
                ? "\(barber.name) stops being your barber"
                : "Makes \(barber.name) your barber, shown first when you book"
        )
        .accessibilityIdentifier("favoriteButton")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

// MARK: - Instagram

/// The barber's own Instagram account, opened outside the app (Instagram's app if it's installed).
/// One tap target.
private struct BarberInstagramRow: View {
    let barberName: String
    let handle: String
    let url: URL

    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 44

    /// Shown as written: handles can contain underscores, which Markdown would eat.
    private var handleText: String { "@" + handle }

    var body: some View {
        Button {
            router.openOutside(url)
        } label: {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: Symbol.instagram)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: min(iconSide, 60), height: min(iconSide, 60))
                    .background(Theme.bone, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("\(barberName) on Instagram")
                    Text(verbatim: handleText)
                        .textRole(.displayS)
                        .foregroundStyle(Theme.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: Symbol.external)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.bone)
            }
            .card()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(barberName) on Instagram, \(handleText)")
        .accessibilityHint("Opens Instagram")
        .accessibilityIdentifier("barberInstagram")
    }
}

// MARK: - About

/// The bio, then the specialties as one mono line (they aren't tappable, so they aren't chips).
private struct BarberAbout: View {
    let barber: Barber

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Kicker("About")
                    .accessibilityAddTraits(.isHeader)
                Text(barber.bio)
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !barber.specialties.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Kicker("Specialties")
                        .accessibilityAddTraits(.isHeader)
                    specialties
                        .textRole(.detail)
                        .foregroundStyle(Theme.bone)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(barber.specialties.joined(separator: ", "))
                }
            }
        }
    }

    /// One line joined with " · ", or one specialty per line at accessibility text sizes, where
    /// "COLOR & LIGHTENER" alone is wider than the screen and has to wrap.
    @ViewBuilder private var specialties: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(barber.specialties, id: \.self) { specialty in
                    Text(specialty)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(specialtiesLine)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "COLOR & LIGHTENER · PERMS · …", breaking only after a "·", never inside a specialty.
    private var specialtiesLine: String {
        barber.specialties
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }
}

// MARK: - Menu

/// Everything the barber offers at their own prices, each row going straight to the calendar.
private struct BarberMenuSection: View {
    let barber: Barber
    @Environment(AppRouter.self) private var router
    private let catalog = AppData.catalog

    var body: some View {
        let offerings = catalog.offerings(forBarber: barber.id)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("\(barber.name)'s menu")
            ForEach(offerings) { offering in
                if let service = catalog.service(withID: offering.serviceID) {
                    row(service: service, offering: offering)
                }
            }
            if offerings.isEmpty {
                InfoCallout(
                    title: "Nothing to book online yet",
                    message: "\(barber.name) has no services on Squire right now. Call the shop at \(AppData.shop.phone.display)."
                )
            }
        }
    }

    private func row(service: Service, offering: Offering) -> some View {
        Button {
            router.startBooking(fromBarberMenu: offering)
        } label: {
            BarberMenuRow(service: service, offering: offering)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(BarberMenuRow.accessibilityText(service: service, offering: offering))
        .accessibilityHint("Books with \(barber.name). Next, pick a day and time")
        .accessibilityIdentifier("barberMenu-\(offering.id)")
    }
}

/// An `ink3` row: the service and the barber's price, their length in mono, their note, a chevron.
private struct BarberMenuRow: View {
    let service: Service
    let offering: Offering

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                MenuNamePriceLine(name: service.name, price: offering.price.label)
                Text(offering.durationLabel)
                    .textRole(.detail)
                    .foregroundStyle(Theme.smoke)
                if let note = offering.note {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MenuChevron()
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    static func accessibilityText(service: Service, offering: Offering) -> String {
        var parts = [service.name, offering.price.label, DurationText.spoken(minutes: offering.durationMinutes)]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
