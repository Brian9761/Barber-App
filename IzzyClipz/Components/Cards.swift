import SwiftUI

/// A quoted client review.
struct ReviewCard: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RatingStars(average: Double(review.stars), size: 13)
                Spacer()
                Image(systemName: Symbol.quote)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.red.opacity(0.85))
                    .accessibilityHidden(true)
            }
            Text(review.text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(byline)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(review.stars) star review by \(review.author) on \(review.source): \(review.text)")
    }

    private var byline: String {
        [review.author, review.source, review.date].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The shop's rating on each review site, side by side.
struct RatingSummary: View {
    let ratings: [SourcedRating]
    /// Called with a rating whose site should open, if it has a link.
    var onOpen: ((SourcedRating) -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tiles }
            VStack(spacing: 12) { tiles }
        }
    }

    @ViewBuilder private var tiles: some View {
        ForEach(ratings, id: \.source) { sourced in
            if let onOpen, sourced.url != nil {
                Button {
                    onOpen(sourced)
                } label: {
                    RatingTile(sourced: sourced, showsLink: true)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens \(sourced.source)")
            } else {
                RatingTile(sourced: sourced, showsLink: false)
            }
        }
    }
}

private struct RatingTile: View {
    let sourced: SourcedRating
    let showsLink: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(sourced.rating.averageLabel)
                    .font(.system(size: min(numberSize, 72), weight: .black).width(.condensed))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if showsLink {
                    Image(systemName: Symbol.external)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.blue)
                        .accessibilityHidden(true)
                }
            }
            RatingStars(average: sourced.rating.average, size: 13)
            // The site over the count: short lines keep two tiles side by side.
            VStack(alignment: .leading, spacing: 1) {
                Text(sourced.source)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(sourced.rating.countLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(sourced.rating.averageLabel) out of 5 from \(sourced.rating.countLabel) on \(sourced.source)")
    }
}

/// "Walk-ins welcome" with today's hours.
struct WalkInCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Symbol.walkIn)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 44, height: 44)
                .background(Theme.tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Walk-ins welcome")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("No appointment? Stop by during open hours. Booking ahead saves you the wait.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.everyMinute) { context in
                    Text(AppData.clock.todayLabel(at: context.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                }
                .padding(.top, 2)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// A light blue note with an icon, for explaining a step.
struct InfoCallout: View {
    let title: String
    let message: String
    var symbol: String = Symbol.info

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.blue.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}
