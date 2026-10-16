import SwiftUI

struct BarberDetailView: View {
    let barber: Barber

    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    private var reviews: [Review] {
        AppData.shop.reviews.filter { $0.barberID == barber.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                Button {
                    router.book(.barber(barber.id))
                } label: {
                    Label("Book with \(barber.name)", systemImage: Symbol.book)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("bookBarberButton")

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Specialties")
                    FlowingChips(items: barber.specialties)
                }

                menu

                if !reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("What clients say")
                        ForEach(reviews) { ReviewCard(review: $0) }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(barber.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let isFavorite = favorites.isFavorite(barber.id)
                Button {
                    favorites.toggle(barber.id)
                } label: {
                    Image(systemName: isFavorite ? Symbol.favoriteFilled : Symbol.favorite)
                        .foregroundStyle(isFavorite ? Theme.red : .white)
                }
                .accessibilityLabel(isFavorite ? "Remove \(barber.name) as your barber" : "Make \(barber.name) your barber")
                .accessibilityIdentifier("favoriteButton")
                .sensoryFeedback(.selection, trigger: isFavorite)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                BarberAvatar(barber: barber, size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(barber.name.uppercased())
                        .font(.display(.largeTitle))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text(barber.title)
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                    if barber.listedName != barber.name {
                        Text("Listed as \(barber.listedName) on Squire")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let rating = barber.rating {
                        RatingLine(rating: rating, source: "Squire")
                    }
                }
            }
            Text(barber.bio)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("\(barber.name)'s menu")
            ForEach(catalog.offerings(forBarber: barber.id)) { offering in
                if let service = catalog.service(withID: offering.serviceID) {
                    Button {
                        router.book(.offering(offering))
                    } label: {
                        BarberMenuRow(service: service, offering: offering)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(BarberMenuRow.accessibilityText(service: service, offering: offering))
                    .accessibilityHint("Opens booking")
                    .accessibilityIdentifier("barberMenu-\(offering.id)")
                }
            }
        }
    }
}

private struct BarberMenuRow: View {
    let service: Service
    let offering: Offering

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(offering.durationLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let note = offering.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(offering.price.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                Text("Book")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.red)
            }
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    static func accessibilityText(service: Service, offering: Offering) -> String {
        var parts = [service.name, offering.price.label, DurationText.spoken(minutes: offering.durationMinutes)]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
