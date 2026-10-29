import SwiftUI

/// Everyone on the team, pushed from Home ("Meet everyone"). Home's stack
/// shows the barber pages, so this screen has no stack of its own.
struct TeamView: View {
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every barber sets their own menu and prices. Tap one to see theirs and book with them.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(catalog.barbers) { barber in
                    TeamBarberLink(barber: barber, isFavorite: favorites.isFavorite(barber.id))
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("The Team")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// A barber's card, opening their page.
private struct TeamBarberLink: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        NavigationLink(value: barber) {
            TeamBarberCard(barber: barber, isFavorite: isFavorite)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(TeamBarberCard.accessibilityText(for: barber, isFavorite: isFavorite))
        .accessibilityHint("Opens their profile")
        .accessibilityIdentifier("barber-\(barber.id)")
    }
}

private struct TeamBarberCard: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BarberAvatar(barber: barber, size: 64)
            details
                // Take the whole row so the chips wrap only when they have to.
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .card()
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(barber.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite {
                    Image(systemName: Symbol.favoriteFilled)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .accessibilityHidden(true)
                }
            }
            Text(barber.title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let rating = barber.rating {
                RatingLine(rating: rating, source: "Squire")
            }
            if let haircut = TeamBarberCard.haircutPrice(for: barber) {
                Text("Haircut \(haircut)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowingChips(items: barber.specialties)
                .padding(.top, 2)
        }
    }

    /// "$35", or "$35–$40" for a barber with more than one haircut on their menu.
    /// `nil` when they don't offer haircuts.
    static func haircutPrice(for barber: Barber) -> String? {
        let prices = AppData.catalog.offerings(forBarber: barber.id)
            .filter { $0.serviceID == "haircut" }
            .map(\.price)
        guard !prices.isEmpty else { return nil }
        return Price.summary(of: prices)
    }

    static func accessibilityText(for barber: Barber, isFavorite: Bool) -> String {
        var parts = [barber.name + (isFavorite ? ", your barber" : ""), barber.title]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5, \(rating.countLabel) on Squire")
        }
        if let haircut = haircutPrice(for: barber) {
            parts.append("haircut \(haircut.replacingOccurrences(of: "–", with: " to "))")
        }
        if !barber.specialties.isEmpty {
            parts.append(barber.specialties.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}
