import SwiftUI

/// A service on the menu: icon, name, length and price range.
struct ServiceRow: View {
    let service: Service

    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(AppData.catalog.durationSummary(forService: service.id))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(AppData.catalog.priceSummary(forService: service.id))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.red)
                .multilineTextAlignment(.trailing)
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    static func accessibilityText(for service: Service) -> String {
        "\(service.name), \(AppData.catalog.priceSummary(forService: service.id)), \(AppData.catalog.durationSummary(forService: service.id))"
    }
}

/// "First available": book with whichever barber is free first.
struct FirstAvailableRow: View {
    let option: FirstAvailableOption

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Symbol.firstAvailable)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.redGradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("First available")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Any of \(option.barberIDs.count) barbers · \(option.durationLabel)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(option.priceLabel)
                .font(.headline)
                .foregroundStyle(Theme.red)
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityHidden(true)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    static func accessibilityText(for option: FirstAvailableOption) -> String {
        "First available barber, any of \(option.barberIDs.count), \(option.priceLabel), \(option.durationLabel)"
    }
}

/// One barber's version of a service, with their price and length.
struct OfferingRow: View {
    let offering: Offering
    let barber: Barber
    var isFavorite = false
    /// What tapping does, e.g. "Book" or "Select".
    var actionLabel = "Book"

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BarberAvatar(barber: barber, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(barber.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
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
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                Text(actionLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.red, in: Capsule())
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

/// Chips that wrap onto as many lines as they need.
struct FlowingChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { Chip(text: $0) }
        }
    }
}

/// Lays out children left to right, wrapping to a new line when out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            let needed = current.indices.isEmpty ? width : current.width + spacing + width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? width : current.width + spacing + width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
