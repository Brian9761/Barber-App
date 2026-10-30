import SwiftUI

/// One service: what it is, what's included, and who does it at what price.
/// Every way to book leads into the in-app calendar.
struct ServiceDetailView: View {
    let service: Service

    @Environment(AppRouter.self) private var router
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ServiceDetailHeader(service: service)
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

    @ViewBuilder private var includes: some View {
        if !service.includes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("What's included")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(service.includes, id: \.self) { item in
                        IncludedItem(text: item)
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
                firstAvailableButton(option)
            }
            ForEach(sortedOfferings) { offering in
                if let barber = catalog.barber(withID: offering.barberID) {
                    offeringButton(offering, barber: barber)
                }
            }
            Text("Next, you'll pick a day and time. Squire confirms the real opening when you book.")
                .font(.footnote)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func firstAvailableButton(_ option: FirstAvailableOption) -> some View {
        Button {
            router.startBooking(choice: .firstAvailable(option))
        } label: {
            FirstAvailableRow(option: option)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(FirstAvailableRow.accessibilityText(for: option))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("bookFirstAvailable")
    }

    private func offeringButton(_ offering: Offering, barber: Barber) -> some View {
        let isFavorite = favorites.isFavorite(barber.id)
        return Button {
            router.startBooking(choice: .offering(offering))
        } label: {
            OfferingRow(offering: offering, barber: barber, isFavorite: isFavorite, actionLabel: "Book")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(OfferingRow.accessibilityText(offering: offering, barber: barber, isFavorite: isFavorite))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("book-\(offering.id)")
    }

    /// The client's favorite barber first, then cheapest first.
    private var sortedOfferings: [Offering] {
        let offerings = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return offerings }
        return offerings.filter { $0.barberID == favorite } + offerings.filter { $0.barberID != favorite }
    }
}

/// Icon, category, name, summary, and the price and length ranges.
private struct ServiceDetailHeader: View {
    let service: Service
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServiceIcon(symbol: service.symbol, size: 68)
            titles
            Text(service.summary)
                .font(.body)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            chips
        }
        .card(padding: 20)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(service.category.title)
            Text(service.name.uppercased())
                .textRole(.displayL)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(service.name)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            if !priceSummary.isEmpty {
                DetailChip(text: priceSummary, symbol: nil, isPrice: true)
                    .accessibilityLabel("Price \(spokenPrice)")
            }
            if !durationSummary.isEmpty {
                DetailChip(text: durationSummary, symbol: Symbol.clock, isPrice: false)
                    .accessibilityLabel("Takes \(spokenDuration)")
            }
        }
    }

    private var priceSummary: String {
        catalog.priceSummary(forService: service.id)
    }

    private var durationSummary: String {
        catalog.durationSummary(forService: service.id)
    }

    /// "$35 to $60", so VoiceOver doesn't skip the dash.
    private var spokenPrice: String {
        priceSummary.replacingOccurrences(of: "–", with: " to ")
    }

    /// "45 minutes to 1 hour".
    private var spokenDuration: String {
        let minutes = catalog.offerings(forService: service.id).map(\.durationMinutes)
        guard let shortest = minutes.min(), let longest = minutes.max() else { return durationSummary }
        if shortest == longest { return DurationText.spoken(minutes: shortest) }
        return "\(DurationText.spoken(minutes: shortest)) to \(DurationText.spoken(minutes: longest))"
    }
}

/// A bold capsule: bone for the price, ink for the rest. (The screen's red is its Book button.)
private struct DetailChip: View {
    let text: String
    let symbol: String?
    let isPrice: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(isPrice ? Theme.ink : Theme.bone)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(isPrice ? Theme.bone : Theme.ink4))
        .accessibilityElement(children: .combine)
    }
}

/// A checkmarked line in "What's included".
private struct IncludedItem: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: Symbol.included)
                .foregroundStyle(Theme.electric)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
