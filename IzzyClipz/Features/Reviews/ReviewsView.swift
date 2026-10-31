import SwiftUI

/// What clients say, live from Google (and Yelp when the shop's server has it), each in its own
/// section with its own attribution, never mixed and never added up into one rating. Then the
/// screen's one red, "Leave a review on Google".
///
/// Google's terms shape this screen: nothing from Google is stored (the reviews are asked for
/// when the screen opens and kept in memory only), the section says "Reviews from Google Maps",
/// each review credits its author and links to itself on Google Maps, and the order is Google's
/// own ("most relevant").
///
/// Pushed from Home and from the Visit tab, so it has no navigation stack of its own.
struct ReviewsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ReviewsStore.self) private var reviews
    private let shop = AppData.shop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                Text("What clients say about \(shop.name) on Google and Yelp, as they wrote it.")
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                googleSection
                yelpSection
                ReviewsYourTurnSection(onLeaveReview: { router.openOutside(shop.googleReviewURL) })
                GoogleTermsNotice()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await reviews.refresh()
        }
        .task {
            await reviews.load(maxAge: 5 * 60)
        }
    }

    // MARK: Google

    @ViewBuilder private var googleSection: some View {
        if let google = reviews.value?.google {
            if google.available {
                GoogleReviewsSection(source: google)
            } else {
                ReviewsUnavailableCard(
                    title: "Google reviews can't be shown right now",
                    message: "Read them on Google Maps instead.",
                    buttonTitle: "See our reviews on Google Maps",
                    url: google.url,
                    identifier: "googleReviewsUnavailable"
                )
            }
        } else if let error = reviews.error {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ErrorStateView(
                    title: "Couldn't load the reviews",
                    message: error.userMessage,
                    onRetry: { Task { await reviews.refresh() } },
                    isRetrying: reviews.isLoading
                )
                .accessibilityIdentifier("reviewsError")
                Button {
                    router.openOutside(shop.googleMapsURL)
                } label: {
                    Label("See our reviews on Google Maps", systemImage: Symbol.external)
                }
                .buttonStyle(.tertiary)
                .accessibilityIdentifier("seeAllGoogleReviews")
            }
        } else {
            LoadingStateView(text: "Loading reviews from Google…")
                .accessibilityIdentifier("reviewsLoading")
        }
    }

    // MARK: Yelp

    @ViewBuilder private var yelpSection: some View {
        let yelp = reviews.value?.yelp
        if let yelp, yelp.available {
            YelpReviewsSection(source: yelp)
        } else {
            Button {
                router.openOutside(yelp?.url ?? ReviewLinks.yelpPage)
            } label: {
                Label("Read our reviews on Yelp", systemImage: Symbol.external)
            }
            .buttonStyle(.tertiary)
            .accessibilityHint("Opens the shop's Yelp page")
            .accessibilityIdentifier("yelpReviewsButton")
        }
    }
}

// MARK: - Google

/// Google's rating, count and up to five reviews, in one container with "Reviews from Google Maps"
/// at the top, so it's clearly Google's and separate from anything else on the screen.
private struct GoogleReviewsSection: View {
    let source: IzzyAPI.ReviewSource
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            GoogleMapsAttribution()

            if let summary = source.summary {
                ReviewScore(rating: summary, site: "Google")
                    .accessibilityIdentifier("googleRating")
            }

            if !source.reviews.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Most relevant on Google")
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                        .accessibilityAddTraits(.isHeader)
                    Text("Up to five reviews that Google picks, in Google's order.")
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("googleOrderNotice")

                ForEach(Array(source.reviews.enumerated()), id: \.offset) { _, review in
                    ThirdPartyReviewRow(review: review, linkTitle: "View on Google Maps", site: "Google Maps")
                    if review != source.reviews.last {
                        SummaryDivider()
                    }
                }
            }

            Button {
                router.openOutside(source.url)
            } label: {
                Label("See all reviews on Google Maps", systemImage: Symbol.external)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("seeAllGoogleReviews")

            Text("Reviews aren't verified by Google, but Google checks for and removes fake content when it's identified.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("googleReviews")
    }
}

/// "Reviews from Google Maps", as Google's attribution rules ask: the system font at regular
/// weight, 14 pt, white, on one line, never recapitalized.
struct GoogleMapsAttribution: View {
    var lead = "Reviews from"

    var body: some View {
        Text("\(lead) Google Maps")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("googleAttribution")
    }
}

// MARK: - Yelp

/// Yelp's rating, count and excerpts, in their own container with Yelp's name on it, each excerpt
/// linking to the full review on Yelp.
private struct YelpReviewsSection: View {
    let source: IzzyAPI.ReviewSource
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("Reviews from Yelp")
                .textRole(.headline)
                .foregroundStyle(Theme.bone)
                .accessibilityAddTraits(.isHeader)

            if let summary = source.summary {
                ReviewScore(rating: summary, site: "Yelp")
                    .accessibilityIdentifier("yelpRating")
            }

            ForEach(Array(source.reviews.enumerated()), id: \.offset) { _, review in
                ThirdPartyReviewRow(review: review, linkTitle: "Read more on Yelp", site: "Yelp")
                if review != source.reviews.last {
                    SummaryDivider()
                }
            }

            Button {
                router.openOutside(source.url)
            } label: {
                Label("Read our reviews on Yelp", systemImage: Symbol.external)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("yelpReviewsButton")
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yelpReviews")
    }
}

// MARK: - Shared

/// One site's score: "4.9", stars, "61 reviews on Google".
struct ReviewScore: View {
    let rating: Rating
    let site: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            Text(rating.averageLabel)
                .textRole(.priceL)
                .foregroundStyle(Theme.bone)
            VStack(alignment: .leading, spacing: 3) {
                RatingStars(average: rating.average, size: 14)
                Text("\(rating.countLabel) on \(site)")
                    .textRole(.detail)
                    .foregroundStyle(Theme.smoke)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating.averageLabel) out of 5 from \(rating.countLabel) on \(site)")
    }
}

/// A review as the site published it: the author's photo and name (linking to their profile when
/// there is one), the stars, when, the words, and a link to the review itself.
private struct ThirdPartyReviewRow: View {
    let review: IzzyAPI.Review
    let linkTitle: String
    let site: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                ReviewAuthorPhoto(url: review.authorPhotoUrl, name: review.author)
                VStack(alignment: .leading, spacing: 2) {
                    if let profile = review.authorUrl {
                        Button {
                            router.openOutside(profile)
                        } label: {
                            Text(review.author)
                                .textRole(.headline)
                                .foregroundStyle(Theme.bone)
                                .underline()
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens \(review.author)'s profile on \(site)")
                    } else {
                        Text(review.author)
                            .textRole(.headline)
                            .foregroundStyle(Theme.bone)
                    }
                    HStack(spacing: Theme.Space.s) {
                        RatingStars(average: Double(review.rating), size: 11)
                        if let when = review.relativeTime {
                            Text(when)
                                .textRole(.caption)
                                .foregroundStyle(Theme.smoke)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([ "\(review.rating) stars", review.relativeTime ].compactMap { $0 }.joined(separator: ", "))
                }
            }
            if !review.text.isEmpty {
                Text(review.text)
                    .textRole(.quote)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = review.url {
                Button {
                    router.openOutside(url)
                } label: {
                    Label(linkTitle, systemImage: Symbol.external)
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.textLink(color: Theme.electric))
                .accessibilityLabel("\(linkTitle): \(review.author)'s review")
                .accessibilityIdentifier("reviewLink")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thirdPartyReview")
    }
}

/// The author's photo from the site, or their initial while it loads or when there's none.
private struct ReviewAuthorPhoto: View {
    let url: URL?
    let name: String

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .textRole(.headline)
            .foregroundStyle(Theme.bone)
            .frame(width: 40, height: 40)
            .background(Theme.ink4)
    }
}

/// When a site's reviews can't be shown: why, and a button to read them on the site.
private struct ReviewsUnavailableCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let url: URL
    let identifier: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button {
                router.openOutside(url)
            } label: {
                Label(buttonTitle, systemImage: Symbol.external)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("seeAllGoogleReviews")
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// An invitation to review the shop on Google: the screen's red.
private struct ReviewsYourTurnSection: View {
    let onLeaveReview: () -> Void

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
        }
    }
}

/// Google's terms ask apps that show Google Maps content to say so, with its terms and privacy
/// policy.
private struct GoogleTermsNotice: View {
    @Environment(AppRouter.self) private var router

    static let termsURL = URL(string: "https://maps.google.com/help/terms_maps/")!
    static let privacyURL = URL(string: "https://policies.google.com/privacy")!

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("This app shows content from Google Maps. Using it is subject to Google's terms and privacy policy.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xl) { links }
                VStack(alignment: .leading, spacing: 0) { links }
            }
        }
    }

    @ViewBuilder private var links: some View {
        Button("Google Maps terms") { router.openOutside(Self.termsURL) }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityIdentifier("googleTermsLink")
        Button("Google privacy policy") { router.openOutside(Self.privacyURL) }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityIdentifier("googlePrivacyLink")
    }
}
