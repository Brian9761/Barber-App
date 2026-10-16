import SwiftUI

struct TeamView: View {
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(catalog.barbers) { barber in
                        NavigationLink(value: barber) {
                            BarberCard(barber: barber, isFavorite: favorites.isFavorite(barber.id))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(BarberCard.accessibilityText(for: barber, isFavorite: favorites.isFavorite(barber.id)))
                        .accessibilityIdentifier("barber-\(barber.id)")
                    }
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("The Team")
            .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0) }
            .navigationDestination(for: Service.self) { ServiceDetailView(service: $0) }
        }
    }
}

private struct BarberCard: View {
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BarberAvatar(barber: barber, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(barber.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    if isFavorite {
                        Image(systemName: Symbol.favoriteFilled)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }
                Text(barber.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let rating = barber.rating {
                    RatingLine(rating: rating)
                }
                if let price = BarberCard.haircutPrice(for: barber) {
                    Text("Haircut \(price.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.red)
                }
                FlowingChips(items: barber.specialties)
                    .padding(.top, 2)
            }
            // Take the whole row so the chips wrap only when they have to.
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: Symbol.chevron)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .contentShape(Rectangle())
    }

    static func haircutPrice(for barber: Barber) -> Price? {
        AppData.catalog.lowestPrice(forService: "haircut", barber: barber.id)
    }

    static func accessibilityText(for barber: Barber, isFavorite: Bool) -> String {
        var parts = [barber.name + (isFavorite ? ", your barber" : ""), barber.title]
        if let rating = barber.rating {
            parts.append("rated \(rating.averageLabel) out of 5, \(rating.countLabel)")
        }
        if let price = haircutPrice(for: barber) {
            parts.append("haircut \(price.label)")
        }
        parts.append(barber.specialties.joined(separator: ", "))
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
