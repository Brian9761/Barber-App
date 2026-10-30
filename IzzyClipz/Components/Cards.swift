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

/// "★ 5.0 · 92 REVIEWS ON SQUIRE" in mono: a barber's rating in a row or on their profile.
struct RatingLine: View {
    let rating: Rating
    var source: String?

    @Environment(\.surfaceTone) private var tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: Symbol.starFilled)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tone.primary)
            Text(line)
                .textRole(.monoNumber)
                .foregroundStyle(tone.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var line: String {
        let base = "\(rating.averageLabel) · \(rating.countLabel)"
        guard let source else { return base }
        return "\(base) on \(source)"
    }

    private var accessibilityText: String {
        let base = "Rated \(rating.averageLabel) out of 5, \(rating.countLabel)"
        guard let source else { return base }
        return "\(base) on \(source)"
    }
}

/// One review site's score on a bone tile: "5.0" big, ink stars, "115 ON SQUIRE ↗".
struct ScoreTile: View {
    let sourced: SourcedRating
    /// Shows the ↗ that says tapping opens the site.
    var showsLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(sourced.rating.averageLabel)
                .textRole(.displayXL)
                .lineLimit(1)
            RatingStars(average: sourced.rating.average, size: 13)
            HStack(spacing: 4) {
                Text("\(sourced.rating.count) on \(sourced.source)")
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.smokeDark)
                if showsLink {
                    Image(systemName: Symbol.external)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .boneCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(sourced.rating.averageLabel) out of 5 from \(sourced.rating.countLabel) on \(sourced.source)")
    }
}

/// The shop's score on each review site, side by side, stacked from xxLarge text.
struct RatingSummary: View {
    let ratings: [SourcedRating]
    /// Called with a rating whose site should open, if it has a link.
    var onOpen: ((SourcedRating) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.l))
        layout {
            ForEach(ratings, id: \.source) { sourced in
                if let onOpen, sourced.url != nil {
                    Button {
                        onOpen(sourced)
                    } label: {
                        ScoreTile(sourced: sourced, showsLink: true)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens \(sourced.source)")
                } else {
                    ScoreTile(sourced: sourced)
                }
            }
        }
    }
}

// MARK: - Reviews

/// A client's review on a bone card: ink stars, an ink quote mark, their words in Archivo SemiBold
/// and a mono byline ("ALEX N. · SQUIRE · ON CARLOS"). Quoted as written, never edited.
struct ReviewCard: View {
    let review: Review
    /// Cut the text off after this many lines (Home shows 3), or `nil` for all of it.
    var lineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                RatingStars(average: Double(review.stars), size: 13)
                Spacer()
                Image(systemName: Symbol.quote)
                    .font(.title3.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(review.text)
                .textRole(.quote)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)
            Text(byline)
                .textRole(.monoTag)
                .foregroundStyle(Theme.smokeDark)
        }
        .boneCard(padding: Theme.Space.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var barberName: String? {
        review.barberID.flatMap { AppData.catalog.barber(withID: $0)?.name }
    }

    private var byline: String {
        [review.author, review.source, review.date, barberName.map { "on \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var accessibilityText: String {
        let about = barberName.map { ", about \($0)" } ?? ""
        return "\(review.stars) star review by \(review.author) on \(review.source)\(about): \(review.text)"
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
                        .textRole(.monoNumber)
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

/// `ContentUnavailableView` in Street Drip: a bone symbol on an `ink4` tile, a Display M title, a
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
