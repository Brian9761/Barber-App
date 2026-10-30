import SwiftUI

/// What clients say: the shop's score on each review site as bone tiles, every quoted review on a
/// bone card with an honest byline, and the screen's one red, "Leave a review on Google".
///
/// Pushed from Home and from the Visit tab, so it has no navigation stack of its own, and it pushes
/// nothing itself (the two stacks know different screens).
struct ReviewsView: View {
    @Environment(AppRouter.self) private var router
    @State private var titleIsUnderBar = false
    @State private var isScrolled = false
    private let shop = AppData.shop

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        ScreenHeader(kicker: Self.kicker(for: shop.ratings), title: "Reviews")
                            .pageScrolledUnderBar($titleIsUnderBar)
                        scores
                    }
                    reviews
                    ReviewsYourTurnSection(
                        onLeaveReview: { router.openOutside(shop.googleReviewURL) },
                        onReadMore: { router.openOutside(shop.googleMapsURL) }
                    )
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xxl)
                .pageScrolled($isScrolled)
            }
        }
        .coordinateSpace(.named(PageBar.space))
        .screenBackground()
        .pageBar(title: "Reviews", showsTitle: titleIsUnderBar, isScrolled: isScrolled)
    }

    /// The score tiles, side by side (stacked from xxLarge text). Each opens its site.
    private var scores: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            RatingSummary(ratings: shop.ratings, onOpen: { sourced in
                if let url = sourced.url {
                    router.openWeb(url)
                }
            })
            if shop.ratings.contains(where: { $0.url != nil }) {
                Text("Tap a score to read the reviews on that site.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var reviews: some View {
        if !shop.reviews.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                SectionHeader("What clients say")
                ForEach(shop.reviews) { review in
                    ReviewCard(review: review)
                }
                if !reviewSources.isEmpty {
                    Text("Each one is quoted from a review a client left on \(ReviewsView.joined(reviewSources, conjunction: "or")).")
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The sites the quoted reviews come from, in the order they first appear.
    private var reviewSources: [String] {
        var sources: [String] = []
        for review in shop.reviews where !sources.contains(review.source) {
            sources.append(review.source)
        }
        return sources
    }

    /// "174 reviews on Squire and Google": every review the scores are based on, and where.
    static func kicker(for ratings: [SourcedRating]) -> String {
        let total = ratings.reduce(0) { $0 + $1.rating.count }
        let count = total == 1 ? "1 review" : "\(total) reviews"
        return "\(count) on \(joined(ratings.map(\.source), conjunction: "and"))"
    }

    /// "Squire", "Squire or Yelp", "Squire, Yelp, or Google".
    static func joined(_ items: [String], conjunction: String) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) \(conjunction) \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), \(conjunction) \(items[items.count - 1])"
        }
    }
}

/// An invitation to review the shop on Google (the screen's red), or read more there.
private struct ReviewsYourTurnSection: View {
    let onLeaveReview: () -> Void
    let onReadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                SectionHeader("Your turn")
                Text("Had a good cut? A few words on Google mean a lot to the team.")
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onLeaveReview) {
                Text("Leave a review on Google")
            }
            .buttonStyle(.primary(trailingSymbol: Symbol.external))
            .accessibilityHint("Opens Google's review form")
            .accessibilityIdentifier("leaveReviewButton")

            Button(action: onReadMore) {
                HStack(spacing: 5) {
                    Text("Read more on Google")
                    Image(systemName: Symbol.external)
                        .font(.system(size: 12, weight: .heavy))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.textLink)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Opens the shop's Google Maps page")
            .accessibilityIdentifier("readGoogleReviewsButton")
        }
    }
}
