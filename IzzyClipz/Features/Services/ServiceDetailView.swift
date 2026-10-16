import SwiftUI

struct ServiceDetailView: View {
    let service: Service

    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                includes
                bookingOptions
                WalkInCard()
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 60)
            Text(service.name.uppercased())
                .font(.display(.largeTitle))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Chip(text: catalog.priceSummary(forService: service.id))
                Chip(text: catalog.durationSummary(forService: service.id))
            }
            Text(service.summary)
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var includes: some View {
        if !service.includes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("What's included")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(service.includes, id: \.self) { item in
                        Label {
                            Text(item).foregroundStyle(.white)
                        } icon: {
                            Image(systemName: Symbol.included).foregroundStyle(Theme.red)
                        }
                    }
                }
                .card()
            }
        }
    }

    private var bookingOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Book with")

            if let option = catalog.firstAvailableOption(forService: service.id) {
                Button {
                    router.book(.firstAvailable(option))
                } label: {
                    FirstAvailableRow(option: option)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(FirstAvailableRow.accessibilityText(for: option))
                .accessibilityHint("Opens booking")
                .accessibilityIdentifier("bookFirstAvailable")
            }

            ForEach(sortedOfferings) { offering in
                if let barber = catalog.barber(withID: offering.barberID) {
                    let isFavorite = favorites.isFavorite(barber.id)
                    Button {
                        router.book(.offering(offering))
                    } label: {
                        OfferingRow(offering: offering, barber: barber, isFavorite: isFavorite)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(OfferingRow.accessibilityText(offering: offering, barber: barber, isFavorite: isFavorite))
                    .accessibilityHint("Opens booking")
                    .accessibilityIdentifier("book-\(offering.id)")
                }
            }
        }
    }

    /// The client's favorite barber first, then cheapest first.
    private var sortedOfferings: [Offering] {
        let offerings = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return offerings }
        return offerings.filter { $0.barberID == favorite } + offerings.filter { $0.barberID != favorite }
    }
}

struct FirstAvailableRow: View {
    let option: FirstAvailableOption

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Symbol.firstAvailable)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.red, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("First available")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Any of \(option.barberIDs.count) barbers · \(option.durationLabel)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(option.priceLabel)
                .font(.headline)
                .foregroundStyle(.white)
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    static func accessibilityText(for option: FirstAvailableOption) -> String {
        "First available barber, any of \(option.barberIDs.count), \(option.priceLabel), \(option.durationLabel)"
    }
}

struct OfferingRow: View {
    let offering: Offering
    let barber: Barber
    var isFavorite = false
    /// "Book" opens booking straight away; "Select" moves on to the next step.
    var actionLabel = "Book"

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BarberAvatar(barber: barber, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(barber.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if isFavorite {
                        Image(systemName: Symbol.favoriteFilled)
                            .font(.caption)
                            .foregroundStyle(Theme.red)
                            .accessibilityHidden(true)
                    }
                }
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
                Text(actionLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.red)
            }
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    static func accessibilityText(offering: Offering, barber: Barber, isFavorite: Bool, verb: String = "Book with") -> String {
        var parts = [
            "\(verb) \(barber.name)" + (isFavorite ? ", your barber" : ""),
            offering.price.label,
            DurationText.spoken(minutes: offering.durationMinutes),
        ]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
