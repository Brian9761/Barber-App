import SwiftUI

/// Step 2 when the barber was picked first (from Home, the Services tab or their profile): the
/// barber shows as step 1, done, then everything they offer with their own prices and lengths.
/// Tapping a service goes straight to the calendar. No red here.
struct ChooseServiceView: View {
    let barber: Barber
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                ChooseServiceBarberCard(barber: barber, isFavorite: favorites.isFavorite(barber.id))

                BookingStepTitle(
                    step: 2,
                    name: "Service",
                    title: "Pick a service",
                    subtitle: "Everything \(barber.name) offers, with their own prices and lengths."
                )

                if sections.isEmpty {
                    InfoCallout(
                        title: "Nothing to book here yet",
                        message: "\(barber.name) has no services on the booking menu right now. Call the shop at \(AppData.shop.phone.display) to set something up."
                    )
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            BookingSectionLabel(title: section.category.title, symbol: section.category.symbol)
                            ForEach(section.offerings) { offering in
                                ChooseServiceOfferingLink(offering: offering, service: catalog.service(withID: offering.serviceID))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .bookingStepChrome(step: 2, name: "Service", title: barber.name)
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

/// Step 1, already done: the barber this booking is with.
private struct ChooseServiceBarberCard: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 14) {
            MonogramTile(barber: barber, side: 56)
            VStack(alignment: .leading, spacing: 3) {
                MonoTag(text: "Barber", style: .bone, symbol: Symbol.checkmark)
                HStack(spacing: Theme.Space.xs) {
                    Text(barber.name)
                        .textRole(.displayS)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    if isFavorite {
                        Image(systemName: Symbol.favoriteFilled)
                            .font(.subheadline)
                            .foregroundStyle(Theme.bone)
                            .accessibilityHidden(true)
                    }
                }
                if let rating = barber.rating {
                    RatingLine(rating: rating, source: "Squire")
                } else {
                    Text(barber.title)
                        .textRole(.monoNumber)
                        .foregroundStyle(Theme.smoke)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.cardPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Barber picked: \(barber.name)" + (isFavorite ? ", your barber" : "")]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5 from \(rating.countLabel) on Squire")
        } else {
            parts.append(barber.title)
        }
        return parts.joined(separator: ", ")
    }
}

/// One of the barber's services: its symbol, name, length, the barber's note and their price.
private struct ChooseServiceOfferingLink: View {
    let offering: Offering
    let service: Service?

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.offering(offering))) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: 14) {
                    ServiceIcon(symbol: service?.symbol ?? Symbol.services, size: 48)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Space.m) {
                            nameBlock
                            Spacer(minLength: Theme.Space.s)
                            price(isStacked: false)
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            nameBlock
                            price(isStacked: true)
                        }
                    }
                    Image(systemName: Symbol.chevron)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.smoke)
                        .accessibilityHidden(true)
                }
                if let note = offering.note {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: Theme.Space.cardPadding)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("barberService-\(offering.id)")
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(serviceName)
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Text(offering.durationLabel)
                .textRole(.monoNumber)
                .foregroundStyle(Theme.smoke)
        }
    }

    /// Beside the name it stays on one line; under it, a long price ("Included with cut") wraps.
    private func price(isStacked: Bool) -> some View {
        Text(offering.price.label)
            .textRole(.price)
            .foregroundStyle(Theme.bone)
            .lineLimit(isStacked ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(isStacked ? .leading : .trailing)
    }

    private var serviceName: String {
        service?.name ?? "Appointment"
    }

    private var accessibilityText: String {
        var parts = [serviceName, offering.price.label.spokenRanges, DurationText.spoken(minutes: offering.durationMinutes)]
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
