import Foundation
import Observation

/// The shop's no-show policy for each booking choice, from the server (`GET /api/no-show-policy`):
/// whether a card is needed, the fee, the late-cancellation window, the policy the client agrees
/// to and the warning shown on Pick a day and time and on Review.
///
/// Shared by the booking steps, so Review already knows what the time step loaded. Kept in memory
/// only. When a request fails, the last answer stays (and `error` says why); with no answer at all,
/// the app books as if no card were needed and the server says if one is (`card_required`).
@MainActor
@Observable
final class NoShowPolicyStore {
    /// What's known about one booking choice.
    struct Entry: Equatable {
        /// The last answer, `nil` until one arrives.
        var policy: IzzyAPI.NoShowPolicy?
        /// Why the last request failed; `nil` once one works.
        var error: APIError?
        var loadedAt: Date?
        var isLoading = false

        /// An answer arrived, or the request failed: the app knows what it can do.
        var isSettled: Bool { policy != nil || error != nil }
    }

    /// How old an answer may get before a booking step asks again.
    static let maxAge: TimeInterval = 60

    private(set) var entries: [IzzyAPI.BookingTarget: Entry] = [:]

    @ObservationIgnored private let api: any ShopAPI
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: [IzzyAPI.BookingTarget: Task<Void, Never>] = [:]

    init(api: any ShopAPI, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    func entry(for target: IzzyAPI.BookingTarget) -> Entry {
        entries[target] ?? Entry()
    }

    /// The last policy the server gave for `target`.
    func policy(for target: IzzyAPI.BookingTarget) -> IzzyAPI.NoShowPolicy? {
        entries[target]?.policy
    }

    /// Asks the server unless there's an answer younger than `maxAge` seconds (`Self.maxAge` when
    /// `nil`). Two loads at once share one request.
    func load(_ target: IzzyAPI.BookingTarget, maxAge: TimeInterval? = nil) async {
        if let inFlight = inFlight[target] {
            await inFlight.value
            return
        }
        if let entry = entries[target], entry.policy != nil, let loadedAt = entry.loadedAt,
           now().timeIntervalSince(loadedAt) < (maxAge ?? Self.maxAge) {
            return
        }
        await fetch(target)
    }

    /// Asks the server again, after any request already on its way (whose answer may be from
    /// before a change): the booking was turned down because the policy changed or a card is needed.
    func reload(_ target: IzzyAPI.BookingTarget) async {
        if let inFlight = inFlight[target] {
            await inFlight.value
        }
        await fetch(target)
    }

    private func fetch(_ target: IzzyAPI.BookingTarget) async {
        let task = Task { await self.perform(target) }
        inFlight[target] = task
        await task.value
        // A reload may have started the next request already: that one is still on its way.
        if inFlight[target] == task { inFlight[target] = nil }
    }

    private func perform(_ target: IzzyAPI.BookingTarget) async {
        var entry = entry(for: target)
        entry.isLoading = true
        entries[target] = entry
        do {
            let policy = try await api.noShowPolicy(for: target)
            entry.policy = policy
            entry.error = nil
            entry.loadedAt = now()
        } catch where error.isCancellation {
            // Left as it was; the next load tries again.
        } catch {
            entry.error = error.asAPIError
        }
        entry.isLoading = false
        entries[target] = entry
    }
}
