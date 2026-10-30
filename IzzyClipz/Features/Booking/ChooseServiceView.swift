import SwiftUI

/// Step 2 when the barber was picked first (from Home or their profile):
/// everything they offer, with their own prices and lengths.
struct ChooseServiceView: View {
    let barber: Barber
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    StepHeader(
                        step: 2,
                        of: 4,
                        stepName: "Service",
                        title: "Pick a service",
                        subtitle: "Everything \(barber.name) offers, with their prices and lengths."
                    )
                    ChooseServiceBarberCard(barber: barber, isFavorite: favorites.isFavorite(barber.id))
                }

                if sections.isEmpty {
                    InfoCallout(
                        title: "Nothing to book here yet",
                        message: "\(barber.name) has no services on the booking menu right now. Call the shop at \(AppData.shop.phone.display) to set something up."
                    )
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(section.category.title)
                            ForEach(section.offerings) { offering in
                                ChooseServiceOfferingLink(offering: offering, service: catalog.service(withID: offering.serviceID))
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(barber.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The barber's offerings, grouped by menu category, in menu order.
    private var sections: [ChooseServiceSection] {
        let offerings = catalog.offerings(forBarber: barber.id)
        return catalog.categories.compactMap { category -> ChooseServiceSection? in
            let matching = offerings.filter { catalog.service(withID: $0.serviceID)?.category == category }
            return matching.isEmpty ? nil : ChooseServiceSection(category: category, offerings: matching)
        }
    }
}

private struct ChooseServiceSection: Identifiable {
    let category: ServiceCategory
    let offerings: [Offering]

    var id: String { category.id }
}

/// The barber this booking is with: avatar, name, title and rating.
private struct ChooseServiceBarberCard: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 16) {
            MonogramTile(barber: barber, side: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(barber.name)
                        .textRole(.displayS)
                        .foregroundStyle(Theme.bone)
                    if isFavorite {
                        Image(systemName: Symbol.favoriteFilled)
                            .font(.subheadline)
                            .foregroundStyle(Theme.bone)
                            .accessibilityHidden(true)
                    }
                }
                Text(barber.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
                if let rating = barber.rating {
                    RatingLine(rating: rating, source: "Squire")
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Booking with \(barber.name)" + (isFavorite ? ", your barber" : ""), barber.title]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5, \(rating.countLabel) on Squire")
        }
        return parts.joined(separator: ", ")
    }
}

/// One of the barber's services: icon, name, length and their price.
private struct ChooseServiceOfferingLink: View {
    let offering: Offering
    let service: Service?

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.offering(offering))) {
            HStack(alignment: .top, spacing: 14) {
                ServiceIcon(symbol: service?.symbol ?? Symbol.services, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(serviceName)
                        .font(.headline)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(offering.durationLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.smoke)
                    if let note = offering.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.smoke)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Text(offering.price.label)
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.trailing)
                Image(systemName: Symbol.chevron)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.smoke)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            .card(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("barberService-\(offering.id)")
    }

    private var serviceName: String {
        service?.name ?? "Appointment"
    }

    private var accessibilityText: String {
        var parts = [serviceName, offering.price.label, DurationText.spoken(minutes: offering.durationMinutes)]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
