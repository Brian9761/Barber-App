import SwiftUI

/// Step 2 when the service was picked first: who does it. "Any barber" comes first when several
/// barbers share the service, then one row per barber's version of it, with their own price and
/// length (Flowxbori has two haircuts, so he's listed twice), the client's favorite at the top.
/// Tapping a row goes straight to the times.
struct ChooseBarberView: View {
    let service: Service
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
                BookingStepHeader(step: 2, title: "Pick a barber", subtitle: summary)
                    .padding(.bottom, Theme.Space.s)

                if let option = catalog.firstAvailableOption(forService: service.id) {
                    ChooseAnyBarberLink(option: option)
                    BookingSectionLabel(title: "Or pick your barber")
                        .padding(.top, Theme.Space.s)
                }

                ForEach(offerings) { offering in
                    if let barber = catalog.barber(withID: offering.barberID) {
                        ChooseBarberOfferingLink(
                            offering: offering,
                            barber: barber,
                            isFavorite: favorites.isFavorite(barber.id),
                            showsLength: offeringsByBarber[barber.id, default: 0] > 1
                        )
                    }
                }

                if let onlyBarber {
                    Text("Only \(onlyBarber.name) offers \(service.name).")
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .bookingStepChrome(title: service.name)
    }

    /// "Haircut · $35–$45 · 45 min – 1 hr".
    private var summary: String {
        [service.name, catalog.priceSummary(forService: service.id), catalog.durationSummary(forService: service.id)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The client's favorite barber first, then cheapest first.
    private var offerings: [Offering] {
        let all = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return all }
        return all.filter { $0.barberID == favorite } + all.filter { $0.barberID != favorite }
    }

    /// How many versions of the service each barber has.
    private var offeringsByBarber: [String: Int] {
        Dictionary(grouping: catalog.offerings(forService: service.id), by: \.barberID).mapValues(\.count)
    }

    /// The one barber who offers this service, when only one does ("Only Izzy offers VIP.").
    private var onlyBarber: Barber? {
        let barbers = catalog.barbers(offering: service.id)
        return barbers.count == 1 ? barbers.first : nil
    }
}

/// Book with whoever is free first among the barbers who share the service's main item. The shop
/// assigns the barber when the time is booked.
private struct ChooseAnyBarberLink: View {
    let option: FirstAvailableOption

    private var names: String {
        BookingFlowCopy.list(option.barberIDs.compactMap { AppData.catalog.barber(withID: $0)?.name })
    }

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.anyBarber(option))) {
            ChooseBarberRow(name: "Any barber", isFavorite: false, price: option.priceLabel, duration: option.durationLabel) {
                ServiceIcon(symbol: Symbol.firstAvailable, size: 56)
            } detail: {
                Text("Whoever is free first: \(names)")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Any barber, whoever is free first: \(names), \(option.priceLabel.spokenRanges), \(option.durationLabel.spokenRanges)")
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("chooseAnyBarber")
    }
}

/// One barber's version of the service.
private struct ChooseBarberOfferingLink: View {
    let offering: Offering
    let barber: Barber
    let isFavorite: Bool
    /// Names the length too, for a barber with two versions of the service.
    let showsLength: Bool

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.offering(offering))) {
            ChooseBarberRow(
                name: showsLength ? "\(barber.name), \(offering.durationLabel)" : barber.name,
                isFavorite: isFavorite,
                price: offering.price.label,
                duration: offering.durationLabel,
                note: offering.note
            ) {
                MonogramTile(barber: barber, side: 56)
            } detail: {
                Text(barber.title)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("choose-\(offering.id)")
    }

    private var accessibilityText: String {
        var parts = [barber.name + (isFavorite ? ", your barber" : ""), barber.title.menuSpokenList]
        parts.append(offering.price.label.spokenRanges)
        parts.append(DurationText.spoken(minutes: offering.durationMinutes))
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

/// A row on step 2: a 56 pt tile, the name with a line under it, the price and length on the
/// right and a chevron. When the name and price can't share a line (big text, a long price like
/// "Included with cut"), the price moves under the name. A barber's note runs full width below.
struct ChooseBarberRow<Leading: View, Detail: View>: View {
    let name: String
    let isFavorite: Bool
    let price: String
    let duration: String
    let note: String?
    let leading: Leading
    let detail: Detail

    init(
        name: String,
        isFavorite: Bool,
        price: String,
        duration: String,
        note: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder detail: () -> Detail
    ) {
        self.name = name
        self.isFavorite = isFavorite
        self.price = price
        self.duration = duration
        self.note = note
        self.leading = leading()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 14) {
                leading
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.m) {
                        nameBlock
                        Spacer(minLength: Theme.Space.s)
                        priceBlock(isStacked: false)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        nameBlock
                        priceBlock(isStacked: true)
                    }
                }
                Image(systemName: Symbol.chevron)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.smoke)
                    .accessibilityHidden(true)
            }
            if let note {
                Text(note)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Theme.Space.cardPadding)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                Text(name)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite {
                    Image(systemName: Symbol.favoriteFilled)
                        .font(.caption)
                        .foregroundStyle(Theme.bone)
                        .accessibilityHidden(true)
                }
            }
            detail
        }
    }

    private func priceBlock(isStacked: Bool) -> some View {
        VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
            Text(price)
                .textRole(.price)
                .foregroundStyle(Theme.bone)
                .lineLimit(isStacked ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(isStacked ? .leading : .trailing)
            Text(duration)
                .textRole(.detail)
                .foregroundStyle(Theme.smoke)
        }
    }
}
