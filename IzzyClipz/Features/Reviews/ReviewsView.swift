import SwiftUI

/// What clients say: the shop's rating on each review site, every quoted
/// review, and links to read more or leave one on Google.
///
/// Pushed from Home and from the Visit tab, so it has no navigation stack of
/// its own, and it pushes nothing itself (the two stacks know different screens).
struct ReviewsView: View {
    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ratings
                reviews
                ReviewsYourTurnSection(
                    onLeaveReview: { router.openOutside(shop.googleReviewURL) },
                    onReadMore: { router.openOutside(shop.googleMapsURL) }
                )
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            // Room for the last button to clear the tab bar.
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.large)
    }

    private var ratings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ratings")
            RatingSummary(ratings: shop.ratings, onOpen: { sourced in
                if let url = sourced.url {
                    router.openWeb(url)
                }
            })
            if shop.ratings.contains(where: { $0.url != nil }) {
                Text("Tap a rating to read the reviews on that site.")
                    .font(.footnote)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var reviews: some View {
        if !shop.reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("What clients say")
                ForEach(shop.reviews) { review in
                    ReviewCard(review: review)
                }
                if !reviewSources.isEmpty {
                    InfoCallout(
                        title: "Real reviews",
                        message: "Each one is quoted from a review a client left on \(ReviewsView.joined(reviewSources, conjunction: "or")).",
                        symbol: Symbol.reviews
                    )
                    .padding(.top, 4)
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

/// An invitation to review the shop on Google, or read more there.
private struct ReviewsYourTurnSection: View {
    let onLeaveReview: () -> Void
    let onReadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your turn")
            Text("Had a good cut? A few words on Google mean a lot to the team.")
                .font(.subheadline)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onLeaveReview) {
                Text("Leave a review on Google")
            }
            .buttonStyle(.primary(trailingSymbol: Symbol.external))
            .accessibilityHint("Opens Google's review form")
            .accessibilityIdentifier("leaveReviewButton")

            Button(action: onReadMore) {
                Label("Read more on Google", systemImage: Symbol.external)
            }
            .buttonStyle(.tertiary)
            .accessibilityHint("Opens the shop's Google Maps page")
            .accessibilityIdentifier("readGoogleReviewsButton")
        }
    }
}
