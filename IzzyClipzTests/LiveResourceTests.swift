import XCTest
@testable import IzzyClipz

/// The products and reviews: loaded live, kept in memory, refreshed on pull.
@MainActor
final class LiveResourceTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private var now = TestData.now

    private func makeProducts() -> ProductsStore {
        ProductsStore(now: { [unowned self] in self.now }) { [api] in try await api.products() }
    }

    private func makeReviews() -> ReviewsStore {
        ReviewsStore(now: { [unowned self] in self.now }) { [api] in try await api.reviews() }
    }

    private let product = IzzyAPI.Product(id: "p1", name: "Pomade", description: "Matte", priceCents: 1800)

    func testLoadsOnceUntilItGetsOld() async {
        api.productsHandler = { [product] in [product] }
        let store = makeProducts()
        XCTAssertNil(store.value)
        await store.load(maxAge: 300)
        XCTAssertEqual(store.value, [product])
        XCTAssertNil(store.error)
        XCTAssertEqual(store.loadedAt, now)

        await store.load(maxAge: 300)
        XCTAssertEqual(api.productRequests, 1, "Fresh enough: not asked again")
        now = now.addingTimeInterval(301)
        await store.load(maxAge: 300)
        XCTAssertEqual(api.productRequests, 2)
        await store.refresh()
        XCTAssertEqual(api.productRequests, 3, "Pull to refresh always asks")
    }

    func testAFailedFirstLoadShowsTheError() async {
        api.productsHandler = { throw APIError.offline }
        let store = makeProducts()
        await store.load(maxAge: 300)
        XCTAssertNil(store.value)
        XCTAssertEqual(store.error, .offline)
        XCTAssertFalse(store.isLoading)

        api.productsHandler = { [] }
        await store.refresh()
        XCTAssertEqual(store.value, [])
        XCTAssertNil(store.error)
    }

    /// A failed refresh keeps what was on screen.
    func testAFailedRefreshKeepsTheLastAnswer() async {
        api.productsHandler = { [product] in [product] }
        let store = makeProducts()
        await store.refresh()
        api.productsHandler = { throw APIError.server(code: IzzyAPI.ErrorCode.serverError, message: "", status: 500) }
        await store.refresh()
        XCTAssertEqual(store.value, [product])
        XCTAssertNotNil(store.error)
    }

    func testTwoRefreshesAtOnceShareOneRequest() async {
        api.productsHandler = { [product] in [product] }
        let store = makeProducts()
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        XCTAssertEqual(api.productRequests, 1)
    }

    func testReviewsAreNeverCombined() async {
        let google = IzzyAPI.ReviewSource(available: true, rating: 4.8, count: 40, url: AppData.shop.googleMapsURL)
        let yelp = IzzyAPI.ReviewSource(available: true, rating: 3.5, count: 4, url: ReviewLinks.yelpPage)
        api.reviewsHandler = { IzzyAPI.ReviewsResponse(google: google, yelp: yelp) }
        let store = makeReviews()
        await store.load(maxAge: 60)
        XCTAssertEqual(store.value?.google.summary?.averageLabel, "4.8")
        XCTAssertEqual(store.value?.yelp.summary?.averageLabel, "3.5")
    }

    private nonisolated static func reviewsResponse(googleAvailable: Bool) -> IzzyAPI.ReviewsResponse {
        IzzyAPI.ReviewsResponse(
            google: googleAvailable
                ? IzzyAPI.ReviewSource(available: true, rating: 4.8, count: 40, url: AppData.shop.googleMapsURL)
                : IzzyAPI.ReviewSource(available: false, url: AppData.shop.googleMapsURL),
            yelp: IzzyAPI.ReviewSource(available: false, url: ReviewLinks.yelpPage)
        )
    }

    /// Opening Reviews and pulling it down ask the server at most every 5 minutes: each answer
    /// from Google counts against the server's daily limit, which every client shares.
    func testReviewsAskAtMostEveryFiveMinutesEvenWhenPulledDown() async {
        api.reviewsHandler = { Self.reviewsResponse(googleAvailable: true) }
        let store = makeReviews()
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 1)
        XCTAssertEqual(store.maxAge, 5 * 60)

        for _ in 0..<10 {
            await store.loadIfOld()
        }
        XCTAssertEqual(api.reviewRequests, 1, "Pulling down again and again within 5 minutes doesn't ask again")
        now = now.addingTimeInterval(5 * 60 - 1)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 1)
        now = now.addingTimeInterval(2)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 2, "Older than 5 minutes: asked again")
    }

    /// While Google's reviews can't be shown, the client can try again a minute later; once they
    /// show, it's every 5 minutes again.
    func testUnavailableGoogleReviewsAreAskedForAgainAfterAMinute() async {
        var googleAvailable = false
        api.reviewsHandler = { Self.reviewsResponse(googleAvailable: googleAvailable) }
        let store = makeReviews()
        await store.loadIfOld()
        XCTAssertEqual(store.maxAge, 60)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 1, "Not again within the minute")

        googleAvailable = true
        now = now.addingTimeInterval(61)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 2)
        XCTAssertEqual(store.value?.google.available, true)
        XCTAssertEqual(store.maxAge, 5 * 60)
        now = now.addingTimeInterval(61)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 2, "Back to every 5 minutes")
    }

    /// Nothing loaded yet (offline, say): opening or pulling down always tries again.
    func testReviewsThatNeverLoadedAreAskedForOnEveryPull() async {
        api.reviewsHandler = { throw APIError.offline }
        let store = makeReviews()
        await store.loadIfOld()
        XCTAssertEqual(store.error, .offline)
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 2)

        api.reviewsHandler = { Self.reviewsResponse(googleAvailable: true) }
        await store.loadIfOld()
        XCTAssertEqual(api.reviewRequests, 3)
        XCTAssertNil(store.error)
        XCTAssertNotNil(store.value)
    }

    func testUnavailableGoogleHasNoRatingToShow() async {
        api.reviewsHandler = {
            IzzyAPI.ReviewsResponse(
                google: IzzyAPI.ReviewSource(available: false, rating: 4.8, count: 40, url: AppData.shop.googleMapsURL),
                yelp: IzzyAPI.ReviewSource(available: false, url: ReviewLinks.yelpPage)
            )
        }
        let store = makeReviews()
        await store.load(maxAge: 60)
        XCTAssertNil(store.value?.google.summary, "The Reviews screen says Google's reviews can't be shown, with no rating")
    }
}
