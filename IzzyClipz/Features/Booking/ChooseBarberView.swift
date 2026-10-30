import SwiftUI

/// Step 2 when the service was picked first: who does it, one barber per row with their own price
/// and length (a Haircut runs $35–$45 and 45 min–1 hr depending on the barber). "First available"
/// comes first when several barbers share the service, then each barber who offers it, the
/// client's favorite at the top. Tapping a row goes straight to the calendar. No red here.
struct ChooseBarberView: View {
    let service: Service
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    BookingStepTitle(step: 2, name: "Barber", title: "Pick your barber")
                    Text(summary)
                        .textRole(.monoNumber)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(summary.spokenRanges)
                }
                .padding(.bottom, Theme.Space.s)

                if let option = catalog.firstAvailableOption(forService: service.id) {
                    ChooseBarberFirstAvailableLink(option: option)
                    BookingSectionLabel(title: "Or choose your barber")
                        .padding(.top, Theme.Space.s)
                }

                ForEach(offerings) { offering in
                    if let barber = catalog.barber(withID: offering.barberID) {
                        ChooseBarberOfferingLink(
                            offering: offering,
                            barber: barber,
                            isFavorite: favorites.isFavorite(barber.id)
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
        .bookingStepChrome(step: 2, name: "Barber", title: service.name)
    }

    /// "Haircut · $35–$45 · 45 min – 1 hr" (set in capitals).
    private var summary: String {
        [
            service.name,
            catalog.priceSummary(forService: service.id),
            catalog.durationSummary(forService: service.id),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// The client's favorite barber first, then cheapest first.
    private var offerings: [Offering] {
        let all = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return all }
        return all.filter { $0.barberID == favorite } + all.filter { $0.barberID != favorite }
    }

    /// The one barber who offers this service, when only one does ("Only Izzy offers VIP.").
    private var onlyBarber: Barber? {
        let barbers = catalog.barbers(offering: service.id)
        return barbers.count == 1 ? barbers.first : nil
    }
}

/// Book the service with whoever is free first. The app doesn't know who that is: Squire picks.
private struct ChooseBarberFirstAvailableLink: View {
    let option: FirstAvailableOption

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.firstAvailable(option))) {
            ChooseBarberRow(
                name: "First available",
                isFavorite: false,
                price: option.priceLabel,
                duration: option.durationLabel
            ) {
                ChooseBarberStackedMonograms(barberIDs: option.barberIDs)
            } detail: {
                Text("Squire picks whoever's free")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("chooseFirstAvailable")
    }

    private var accessibilityText: String {
        let names = option.barberIDs.compactMap { AppData.catalog.barber(withID: $0)?.name }
        return [
            "First available barber",
            "Squire picks whoever's free" + (names.isEmpty ? "" : ": \(ListFormatter.localizedString(byJoining: names))"),
            option.priceLabel.spokenRanges,
            option.durationLabel.spokenRanges,
        ].joined(separator: ", ")
    }
}

/// One barber's version of the service.
private struct ChooseBarberOfferingLink: View {
    let offering: Offering
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.offering(offering))) {
            ChooseBarberRow(
                name: barber.name,
                isFavorite: isFavorite,
                price: offering.price.label,
                duration: offering.durationLabel,
                note: offering.note
            ) {
                MonogramTile(barber: barber, side: 56)
            } detail: {
                if let rating = barber.rating {
                    RatingLine(rating: rating)
                } else {
                    // Cristian and Julian have no published rating: "BARBER", never "0 reviews".
                    Text(barber.title)
                        .textRole(.monoNumber)
                        .foregroundStyle(Theme.smoke)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("choose-\(offering.id)")
    }

    private var accessibilityText: String {
        var parts = ["\(barber.name)" + (isFavorite ? ", your barber" : "")]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5 from \(rating.countLabel)")
        } else {
            parts.append(barber.title)
        }
        parts.append(offering.price.label.spokenRanges)
        parts.append(DurationText.spoken(minutes: offering.durationMinutes))
        if let note = offering.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

/// A row on step 2: a 56 pt tile, the name with a line under it, the price and length on the
/// right and a chevron. When the name and price can't share a line (big text, a long price like
/// "Included with cut"), the price moves under the name. A barber's note runs full width below.
private struct ChooseBarberRow<Leading: View, Detail: View>: View {
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

    /// Beside the name it stays on one line; under it, a long price ("Included with cut") wraps.
    private func priceBlock(isStacked: Bool) -> some View {
        VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
            Text(price)
                .textRole(.price)
                .foregroundStyle(Theme.bone)
                .lineLimit(isStacked ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(isStacked ? .leading : .trailing)
            Text(duration)
                .textRole(.monoNumber)
                .foregroundStyle(Theme.smoke)
        }
    }
}

/// The barbers "first available" covers: up to three 32 pt monograms fanned across a 56 pt square,
/// so the row lines up with the barber rows under it.
private struct ChooseBarberStackedMonograms: View {
    let barberIDs: [String]

    private static let side: CGFloat = 32
    private static let box: CGFloat = 56

    var body: some View {
        let barbers = Array(barberIDs.compactMap { AppData.catalog.barber(withID: $0) }.prefix(3))
        // Spread corner to corner; a single tile sits in the middle.
        let travel = Self.box - Self.side
        let step = barbers.count > 1 ? travel / CGFloat(barbers.count - 1) : 0
        let start = barbers.count > 1 ? 0 : travel / 2
        ZStack(alignment: .topLeading) {
            ForEach(Array(barbers.enumerated()), id: \.element.id) { index, barber in
                let offset = start + CGFloat(index) * step
                MonogramTile(barber: barber, side: Self.side, cornerRadius: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.ink3, lineWidth: 2)
                    )
                    .offset(x: offset, y: offset)
            }
        }
        .frame(width: Self.box, height: Self.box, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
