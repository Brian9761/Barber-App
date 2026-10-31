import Foundation
import Observation

/// Something the app loads from the shop's server and shows as it is right now: the products,
/// the reviews.
///
/// It's kept in memory only, never saved (Google's terms don't allow storing its reviews, and
/// products change). While a refresh runs, the last answer stays on screen; if a refresh fails, the
/// last answer stays too and `error` says why. Two refreshes at once share one request.
@MainActor
@Observable
final class LiveResource<Value> {
    /// The last answer, `nil` until the first one arrives.
    private(set) var value: Value?
    /// Why the last attempt failed, `nil` once one succeeds.
    private(set) var error: APIError?
    private(set) var isLoading = false
    /// When `value` arrived.
    private(set) var loadedAt: Date?

    @ObservationIgnored private let fetch: @MainActor () async throws -> Value
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init, fetch: @escaping @MainActor () async throws -> Value) {
        self.fetch = fetch
        self.now = now
    }

    /// Loads if there's nothing yet, or if what's there is older than `maxAge` seconds.
    func load(maxAge: TimeInterval) async {
        if let loadedAt, value != nil, now().timeIntervalSince(loadedAt) < maxAge { return }
        await refresh()
    }

    /// Asks the server again.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.perform() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func perform() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetch()
            value = fresh
            error = nil
            loadedAt = now()
        } catch where error.isCancellation {
            // Left as it was; the next load tries again.
        } catch {
            self.error = error.asAPIError
        }
    }
}

/// The shop's products for the Shop tab.
typealias ProductsStore = LiveResource<[IzzyAPI.Product]>

/// Google's (and Yelp's) rating and reviews, for the Reviews screen only: it asks when it opens (at
/// most every 5 minutes), and Home never does, because each Google answer counts against the
/// server's daily limit.
typealias ReviewsStore = LiveResource<IzzyAPI.ReviewsResponse>
