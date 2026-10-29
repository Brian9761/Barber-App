import SwiftUI

/// A barber's page: who they are, what they offer at which price, and what
/// clients say. Booking from here starts the in-app calendar with them chosen.
struct BarberDetailView: View {
    let barber: Barber

    @Environment(AppRouter.self) private var router

    private var reviews: [Review] {
        AppData.shop.reviews.filter { $0.barberID == barber.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                BarberHeroCard(barber: barber)
                bookButton
                about
                specialties
                BarberMenuSection(barber: barber)
                reviewsSection
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(barber.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bookButton: some View {
        Button {
            router.startBooking(barberID: barber.id)
        } label: {
            Label("Book with \(barber.name)", systemImage: Symbol.book)
        }
        .buttonStyle(.primary)
        .accessibilityHint("Next, pick one of their services")
        .accessibilityIdentifier("bookBarberButton")
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("About")
            VStack(alignment: .leading, spacing: 14) {
                Text(barber.bio)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = barber.instagramURL, let handle = barber.instagramHandle {
                    Divider()
                    BarberInstagramLink(barberName: barber.name, handle: handle, url: url)
                }
            }
            .card()
        }
    }

    @ViewBuilder private var specialties: some View {
        if !barber.specialties.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Specialties")
                FlowingChips(items: barber.specialties)
                    .card()
            }
        }
    }

    @ViewBuilder private var reviewsSection: some View {
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("What clients say")
                ForEach(reviews) { review in
                    ReviewCard(review: review)
                }
            }
        }
    }
}

// MARK: - Header

/// Big avatar, name, title, rating and the favorite toggle on royal blue.
private struct BarberHeroCard: View {
    let barber: Barber

    var body: some View {
        VStack(spacing: 14) {
            BarberAvatar(barber: barber, size: 104)
            names
            if let rating = barber.rating {
                RatingLine(rating: rating, source: "Squire")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }
            BarberFavoriteButton(barber: barber)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background {
            ZStack {
                Theme.heroGradient
                StripeTexture(opacity: 0.07)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blueDeep.opacity(0.22), radius: 16, y: 8)
    }

    private var names: some View {
        VStack(spacing: 4) {
            Text(barber.name.uppercased())
                .font(.display(.largeTitle))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(barber.name)
                .accessibilityAddTraits(.isHeader)
            Text(barber.title)
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if barber.listedName != barber.name {
                Text("Listed as \(barber.listedName) on Squire")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Favorite" / "Remove favorite", with a heart. The favorite barber shows
/// on Home and first wherever the client picks a barber.
private struct BarberFavoriteButton: View {
    let barber: Barber
    @Environment(Favorites.self) private var favorites

    private var isFavorite: Bool {
        favorites.isFavorite(barber.id)
    }

    private var title: String {
        isFavorite ? "Remove favorite" : "Favorite"
    }

    private var symbol: String {
        isFavorite ? Symbol.favoriteFilled : Symbol.favorite
    }

    private var hint: String {
        isFavorite
            ? "\(barber.name) stops being your barber"
            : "Makes \(barber.name) your barber, shown first when you book"
    }

    var body: some View {
        Button {
            favorites.toggle(barber.id)
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isFavorite ? Theme.red : Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Capsule().fill(isFavorite ? Color.white : Color.white.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isFavorite ? 0 : 0.35)))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityHint(hint)
        .accessibilityIdentifier("favoriteButton")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

/// The barber's own Instagram account.
private struct BarberInstagramLink: View {
    let barberName: String
    let handle: String
    let url: URL
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    /// Read as written: handles can contain underscores, which Markdown would eat.
    private var handleText: String { "@" + handle }

    private var accessibilityText: String { "\(barberName) on Instagram, \(handleText)" }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: Symbol.instagram)
                    .font(.body.weight(.semibold))
                    // The glyph stops growing with the circle, so it stays inside.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(Theme.blue)
                    .frame(width: min(iconSize, 56), height: min(iconSize, 56))
                    .background(Theme.tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: handleText)
                        .font(.headline)
                        .foregroundStyle(Theme.blue)
                    Text("\(barberName) on Instagram")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: Symbol.external)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.blue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens Instagram")
        .accessibilityIdentifier("barberInstagram")
    }
}

// MARK: - Menu

/// Everything the barber offers, each row starting a booking with them.
private struct BarberMenuSection: View {
    let barber: Barber
    @Environment(AppRouter.self) private var router
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("\(barber.name)'s menu")
            ForEach(catalog.offerings(forBarber: barber.id)) { offering in
                if let service = catalog.service(withID: offering.serviceID) {
                    row(service: service, offering: offering)
                }
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

private struct BarberMenuRow: View {
    let service: Service
    let offering: Offering
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(offering.durationLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let note = offering.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if stacksPrice {
                    // Beside the button if they fit on one line, otherwise over it.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            price
                            bookCapsule
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            price
                            bookCapsule
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            if !stacksPrice {
                VStack(alignment: .trailing, spacing: 6) {
                    price
                        .multilineTextAlignment(.trailing)
                    bookCapsule
                }
            }
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    /// At the largest text sizes the price moves under the name, so neither
    /// has to break mid-word.
    private var stacksPrice: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var price: some View {
        Text(offering.price.label)
            .font(.headline)
            .foregroundStyle(Theme.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bookCapsule: some View {
        Text("Book")
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.red, in: Capsule())
    }

    static func accessibilityText(service: Service, offering: Offering) -> String {
        var parts = [service.name, offering.price.label, DurationText.spoken(minutes: offering.durationMinutes)]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
