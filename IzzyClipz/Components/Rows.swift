import SwiftUI

/// A service's SF Symbol in bone on an `ink4` tile. Photos never stand in for a service: none of
/// the bundled photos shows a shave, a facial or a perm, so every service gets its symbol.
struct ServiceIcon: View {
    let symbol: String
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(Theme.bone)
            .frame(width: size, height: size)
            .background(Theme.ink4, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A service on the menu: icon, name, length and price range, and a chevron.
struct ServiceRow: View {
    let service: Service
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppData.catalog.durationSummary(forService: service.id))
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.smoke)
                // At the largest text sizes the price moves under the name,
                // so neither has to break mid-word.
                if dynamicTypeSize.isAccessibilitySize {
                    price
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                price
            }
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.smoke)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    private var price: some View {
        PriceText(AppData.catalog.priceSummary(forService: service.id))
            .foregroundStyle(Theme.bone)
    }

    static func accessibilityText(for service: Service) -> String {
        "\(service.name), \(AppData.catalog.priceSummary(forService: service.id)), \(AppData.catalog.durationSummary(forService: service.id))"
            .spokenRanges
    }
}

/// "First available": book with whichever barber is free first. Squire picks; the app doesn't
/// know who's free.
struct FirstAvailableRow: View {
    let option: FirstAvailableOption
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            monograms
            VStack(alignment: .leading, spacing: 3) {
                Text("First available")
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                Text("Squire picks whoever's free")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                Text(option.durationLabel)
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.smoke)
                if dynamicTypeSize.isAccessibilitySize {
                    price
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                price
            }
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.smoke)
                .accessibilityHidden(true)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    /// The barbers it covers, overlapping.
    private var monograms: some View {
        let barbers = option.barberIDs.compactMap { AppData.catalog.barber(withID: $0) }
        return HStack(spacing: -12) {
            ForEach(barbers.prefix(3)) { barber in
                MonogramTile(barber: barber, side: 32, cornerRadius: 9)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.ink3, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    private var price: some View {
        PriceText(option.priceLabel)
            .foregroundStyle(Theme.bone)
    }

    static func accessibilityText(for option: FirstAvailableOption) -> String {
        "First available barber, any of \(option.barberIDs.count), \(option.priceLabel), \(option.durationLabel)"
            .spokenRanges
    }
}

/// One barber's version of a service, with their price and length.
struct OfferingRow: View {
    let offering: Offering
    let barber: Barber
    var isFavorite = false
    /// What tapping does, e.g. "Book" or "Select".
    var actionLabel = "Book"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MonogramTile(barber: barber, side: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(barber.name)
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    if isFavorite {
                        Image(systemName: Symbol.favoriteFilled)
                            .font(.caption)
                            .foregroundStyle(Theme.bone)
                            .accessibilityHidden(true)
                    }
                }
                Text(offering.durationLabel)
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.smoke)
                if let note = offering.note {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // At the largest text sizes the price moves under the name,
                // so neither has to break mid-word.
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 10) {
                        price
                        action
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 6) {
                    price
                    action
                }
            }
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    private var price: some View {
        PriceText(offering.price.label)
            .foregroundStyle(Theme.bone)
    }

    private var action: some View {
        HStack(spacing: 3) {
            Text(actionLabel)
                .textRole(.monoTag)
            Image(systemName: Symbol.chevron)
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(Theme.smoke)
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
