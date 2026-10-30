import SwiftUI

/// The crew, pushed from Home ("All 5 barbers"). Home's stack shows the barber pages, so this
/// screen has no stack of its own. One full-width row per barber, in team order. No red here.
struct TeamView: View {
    @Environment(Favorites.self) private var favorites
    /// Whether the title in the content has scrolled up under the navigation bar.
    @State private var titleIsUnderBar = false
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ScreenHeader(kicker: "\(catalog.barbers.count) barbers", title: "The crew")
                        .menuTitleScrolledUnderBar($titleIsUnderBar)
                    Text("Every barber sets their own menu and prices.")
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: Theme.Space.m) {
                    ForEach(catalog.barbers) { barber in
                        TeamBarberLink(barber: barber, isFavorite: favorites.isFavorite(barber.id))
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .menuNavigationTitle("The crew", showsInBar: titleIsUnderBar)
        .screenBackground()
    }
}

/// A barber's row, opening their page.
private struct TeamBarberLink: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        NavigationLink(value: barber) {
            TeamBarberRow(barber: barber, isFavorite: isFavorite)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(TeamBarberRow.accessibilityText(for: barber, isFavorite: isFavorite))
        .accessibilityHint("Opens their profile")
        .accessibilityIdentifier("barber-\(barber.id)")
    }
}

/// An `ink3` row: the 72 pt monogram, the name, their title, their Squire rating if they have one
/// and their haircut price, all in mono, and a chevron. At accessibility text sizes the monogram
/// moves above the text so the name keeps the full width.
private struct TeamBarberRow: View {
    let barber: Barber
    let isFavorite: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            mainLayout {
                MonogramTile(barber: barber, side: 72)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MenuChevron()
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var mainLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(barber.name)
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite {
                    Image(systemName: Symbol.favoriteFilled)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                        .accessibilityHidden(true)
                }
            }
            Text(barber.title)
                .textRole(.monoTag)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            if let rating = barber.rating {
                RatingLine(rating: rating)
            }
            if let haircut = Self.haircutLine(for: barber) {
                Text(haircut)
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Haircut $45", or "Haircut from $35" for a barber with more than one haircut price on their
    /// menu. `nil` when they don't offer haircuts.
    static func haircutLine(for barber: Barber) -> String? {
        let prices = AppData.catalog.offerings(forBarber: barber.id)
            .filter { $0.serviceID == "haircut" }
            .map(\.price)
        guard let lowest = prices.min() else { return nil }
        let hasRange = Set(prices.map(\.cents)).count > 1 || lowest.kind == .startingAt
        return hasRange ? "Haircut from \(Price.currencyString(cents: lowest.cents))" : "Haircut \(lowest.label)"
    }

    static func accessibilityText(for barber: Barber, isFavorite: Bool) -> String {
        var parts = [barber.name + (isFavorite ? ", your barber" : ""), barber.title]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5, \(rating.countLabel) on Squire")
        }
        if let haircut = haircutLine(for: barber) {
            parts.append(haircut)
        }
        return parts.joined(separator: ", ")
    }
}
