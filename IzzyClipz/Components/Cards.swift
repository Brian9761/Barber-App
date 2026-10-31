import SwiftUI

// MARK: - Ratings

/// Five stars, with halves. Never red: ink on bone, bone on ink (from the surface tone), unless a
/// color is given.
struct RatingStars: View {
    let average: Double
    var size: CGFloat = 12
    var color: Color?

    @Environment(\.surfaceTone) private var tone

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(forStar: index))
                    .font(.system(size: size, weight: .bold))
            }
        }
        .foregroundStyle(color ?? tone.primary)
        .accessibilityHidden(true)
    }

    private func symbol(forStar index: Int) -> String {
        let remaining = average - Double(index)
        if remaining >= 0.75 { return Symbol.starFilled }
        if remaining >= 0.25 { return Symbol.starHalf }
        return Symbol.starEmpty
    }
}

// MARK: - Notes

/// "Walk-ins welcome" with today's hours.
struct WalkInCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Symbol.walkIn)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.bone)
                .frame(width: 44, height: 44)
                .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Walk-ins welcome")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text("No appointment? Stop by during open hours. Booking ahead saves you the wait.")
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.everyMinute) { context in
                    Text(AppData.clock.todayLabel(at: context.date))
                        .textRole(.detail)
                        .foregroundStyle(Theme.bone)
                }
                .padding(.top, 2)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// A note with an icon on an ink card, for explaining a step. `electric` for information,
/// `caution` for a warning.
struct InfoCallout: View {
    let title: String
    let message: String
    var symbol: String = Symbol.info
    var tint: Color = Theme.electric

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .textRole(.callout)
                    .foregroundStyle(Theme.bone)
                Text(message)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty states

/// `ContentUnavailableView` in Street Drip: a bone symbol on an `ink4` tile, a title, a
/// line of body text and the actions (a bone "Call (442) 341-3053" is the usual one). For a link to
/// a service or barber that no longer exists, or a list with nothing in it.
///
///     EmptyStateView(title: "Barber not found", symbol: Symbol.team,
///                    message: "They may have left the team. The shop can help.") {
///         CallButton { Text("Call \(AppData.shop.phone.display)") }
///             .buttonStyle(.secondary)
///     }
struct EmptyStateView<Actions: View>: View {
    let title: String
    let symbol: String
    var message: String?
    let actions: Actions

    init(title: String, symbol: String, message: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                    .frame(width: 64, height: 64)
                    .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .textRole(.displayM)
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.center)
            }
        } description: {
            if let message {
                Text(message)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
            }
        } actions: {
            actions
        }
        .background(Theme.ink)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, symbol: String, message: String? = nil) {
        self.init(title: title, symbol: symbol, message: message) { EmptyView() }
    }
}
