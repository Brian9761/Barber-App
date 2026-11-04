import Foundation
import Observation

// No-show protection while booking: what Review needs (a card, the policy the client agrees to),
// adding a card through Stripe's page, and the words the app shows about it. The server decides
// everything (whether a card is needed, the fee, the window, the wording of the policy and the
// warning); this only puts it together. See server/README.md, "No-show protection".

/// What no-show protection asks of a booking on Review, from the policy on screen and the card on
/// this iPhone.
enum NoShowRequirement: Equatable {
    /// The first answer about the policy is on its way: Book waits a moment.
    case checking
    /// No card needed: protection is off, this item has no fee, or the policy couldn't be checked
    /// (then the server says if a card is needed, and the app asks for one).
    case notNeeded
    /// A card is needed and there's none that can hold this appointment. `unusable` is the saved
    /// card when it has expired or expires before the appointment's month.
    case needsCard(IzzyAPI.NoShowPolicy, unusable: StoredCard?)
    /// Ready to book: the card, and the policy the client agrees to by booking.
    case ready(IzzyAPI.NoShowPolicy, card: StoredCard)

    /// - Parameters:
    ///   - entry: what the app knows about the policy for this booking's service and barber.
    ///   - saved: the card on this iPhone, expired or not.
    ///   - usable: the card that can hold this appointment (`SavedCardStore.card(forAppointmentAt:)`).
    init(entry: NoShowPolicyStore.Entry, saved: StoredCard?, usable: StoredCard?) {
        guard let policy = entry.policy else {
            self = entry.isSettled ? .notNeeded : .checking
            return
        }
        // A policy to agree to comes with every "required" one; without it there's nothing to send.
        guard policy.required, policy.policyText != nil else {
            self = .notNeeded
            return
        }
        if let usable {
            self = .ready(policy, card: usable)
        } else {
            self = .needsCard(policy, unusable: saved)
        }
    }

    /// What Review shows and books with, for an appointment starting at `start`.
    @MainActor
    init(entry: NoShowPolicyStore.Entry, cards: SavedCardStore, start: Date) {
        self.init(entry: entry, saved: cards.saved, usable: cards.card(forAppointmentAt: start))
    }

    /// The policy that applies, when a card is part of the booking.
    var policy: IzzyAPI.NoShowPolicy? {
        switch self {
        case .needsCard(let policy, _), .ready(let policy, _): return policy
        case .checking, .notNeeded: return nil
        }
    }

    /// The card the booking goes with.
    var card: StoredCard? {
        if case .ready(_, let card) = self { return card }
        return nil
    }

    /// What the booking sends: the card's token and the policy exactly as shown.
    var agreement: IzzyAPI.NoShowAgreement? {
        guard case .ready(let policy, let card) = self, let text = policy.policyText else { return nil }
        return IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: text)
    }

    /// Book appointment stays off: a card is needed first, or the policy is still being checked.
    var blocksBooking: Bool {
        switch self {
        case .checking, .needsCard: return true
        case .notNeeded, .ready: return false
        }
    }

    /// Under a Book appointment button that waits: "Add a card first", or "Checking with the shop…".
    var bookButtonNote: String? {
        switch self {
        case .checking: return NoShowCopy.bookChecking
        case .needsCard: return NoShowCopy.bookNeedsCard
        case .notNeeded, .ready: return nil
        }
    }
}

/// The "Full Service Cancellation & No-Show Fee" notice on Pick a day and time and on Review: the
/// server's title and message, and for a picked time that starts less than the late-cancellation
/// window from now, "This time is less than 1 hour away, so cancelling it may be charged $40."
/// Only when protection applies to the booking.
struct NoShowWarningContent: Equatable {
    let title: String
    let message: String
    /// About the picked time, when cancelling it can't be free any more once it's booked.
    let notice: String?

    /// `nil` when no card is needed (protection off, no fee for this item, or not known yet).
    init?(policy: IzzyAPI.NoShowPolicy?, start: Date?, now: Date) {
        guard let policy, policy.required, let warning = policy.warning else { return nil }
        title = warning.title
        message = warning.message
        notice = start.flatMap { policy.lateCancelNotice(start: $0, now: now) }
    }

    /// What VoiceOver reads, in one go.
    var spoken: String {
        [title, message, notice].compactMap { $0 }.joined(separator: ". ")
    }
}

/// When a picked time comes inside the late-cancellation window while the client looks at it, so
/// Pick a day and time and Review show "This time is less than 1 hour away…" from that moment.
///
/// A once-a-minute timeline isn't enough: its moments are the starts of minutes, and a time on the
/// hour or half hour comes inside a window of whole minutes exactly at the start of one (1:30 PM is
/// an hour away at 12:30:00, which is still free). The note would then be a whole minute late, and
/// a client booking at 12:30:40 would never see it.
struct LateCancelNoticeTimer: Equatable {
    let start: Date?
    /// The window, when the note can show at all: the booking needs a card and late cancellations
    /// are on.
    let windowMinutes: Int?

    init(policy: IzzyAPI.NoShowPolicy?, start: Date?) {
        self.start = start
        windowMinutes = policy?.required == true ? policy?.lateCancelWindowMinutes : nil
    }

    /// How long after the window starts the screen looks again: by then the time is inside it.
    static let margin: TimeInterval = 0.25

    /// How long to wait before the note shows, or `nil` when it already shows, or never will.
    func wait(now: Date) -> TimeInterval? {
        guard let start, let windowMinutes else { return nil }
        let free = start.addingTimeInterval(-Double(windowMinutes) * 60).timeIntervalSince(now)
        // Exactly the window away is still free: the note waits for the moment after.
        return free >= 0 ? free + Self.margin : nil
    }
}

/// Adds a card on Review: Stripe's page (a Checkout Session the shop's server makes in setup mode,
/// so nothing is charged), then the shop's server keeps it under a new card token, and this iPhone
/// keeps the token and "Visa •••• 4242" (`SavedCardStore`).
///
/// If Stripe saved the card but the shop's server didn't answer (offline, say), Try again finishes
/// saving that same card without the card page: the server answers a repeat with the same card.
@MainActor
@Observable
final class CardSetup {
    enum Phase: Equatable {
        case idle
        /// Asking the shop's server for Stripe's page.
        case starting
        /// Stripe's page is open.
        case onCardPage
        /// Asking the shop's server to keep the card.
        case saving
    }

    /// A card Stripe saved that the shop's server hasn't confirmed keeping.
    private struct Unfinished: Equatable {
        let token: IzzyAPI.CardToken
        let sessionId: String
    }

    private(set) var phase: Phase = .idle
    /// Why the last try didn't add a card, in words for the client. `nil` when it worked, or when
    /// the client closed the card page.
    private(set) var failure: String?
    private var unfinished: Unfinished?

    @ObservationIgnored private let api: any ShopAPI
    @ObservationIgnored private let saver: any CardSaver
    @ObservationIgnored private let cards: SavedCardStore
    @ObservationIgnored private let policies: NoShowPolicyStore?

    init(api: any ShopAPI, saver: any CardSaver, cards: SavedCardStore, policies: NoShowPolicyStore? = nil) {
        self.api = api
        self.saver = saver
        self.cards = cards
        self.policies = policies
    }

    var isWorking: Bool { phase != .idle }

    /// Stripe has the card and only the shop's server's answer is missing: Try again finishes it.
    var canFinishSaving: Bool { unfinished != nil }

    /// When the card page didn't come back as it should.
    static let pageFailedMessage = "The card wasn't added. Try again."
    static let notWorkingMessage = "Adding a card isn't working right now. Try again later, or call the shop."
    static let unfinishedMessage = "Your card is saved with Stripe, but we couldn't reach the shop to finish. Try again."

    /// Adds a card for booking `target`, kept for next time when `remember`. Returns it, or `nil`
    /// with `failure` set (or not, when the client closed the card page). A second call while one
    /// runs does nothing.
    func addCard(for target: IzzyAPI.BookingTarget, remember: Bool) async -> StoredCard? {
        guard phase == .idle else { return nil }
        failure = nil
        defer { phase = .idle }

        let attempt: Unfinished
        if let unfinished {
            attempt = unfinished
        } else {
            let token = IzzyAPI.CardToken.generate()
            phase = .starting
            let checkout: IzzyAPI.CardCheckout
            do {
                checkout = try await api.startCardCheckout(for: target, token: token)
            } catch where error.isCancellation {
                return nil
            } catch {
                let apiError = error.asAPIError
                failure = Self.message(for: apiError)
                if Self.policyMayHaveChanged(apiError) {
                    // No card needed any more, or Stripe isn't set up: the policy says what's true now.
                    await policies?.reload(target)
                }
                return nil
            }

            phase = .onCardPage
            let result: IzzyAPI.CardCheckoutResult
            do {
                result = try await saver.collectCard(on: checkout)
            } catch where error.isCancellation {
                return nil
            } catch {
                failure = Self.pageFailedMessage
                return nil
            }
            switch result {
            case .cancelled:
                return nil
            case .failed:
                failure = Self.pageFailedMessage
                return nil
            case .saved:
                // The session this phone started; the server checks it was made for this token.
                attempt = Unfinished(token: token, sessionId: checkout.sessionId)
            }
        }

        phase = .saving
        do {
            let card = try await api.saveCard(sessionId: attempt.sessionId, token: attempt.token)
            unfinished = nil
            let stored = StoredCard(token: attempt.token, card: card)
            cards.save(stored, remember: remember)
            return stored
        } catch where error.isCancellation {
            unfinished = attempt
            return nil
        } catch {
            let apiError = error.asAPIError
            if apiError.isRetryable {
                unfinished = attempt
                failure = Self.unfinishedMessage(for: apiError)
            } else {
                unfinished = nil
                failure = Self.message(for: apiError)
            }
            return nil
        }
    }

    func clearFailure() {
        failure = nil
    }

    /// What the client is told when the shop's server turned the card down or couldn't be reached.
    static func message(for error: APIError) -> String {
        if case .notConfigured = error { return notWorkingMessage }
        return error.userMessage
    }

    /// Stripe saved the card, but the shop's server didn't answer: nothing is lost.
    static func unfinishedMessage(for error: APIError) -> String {
        if case .rateLimited(let message) = error, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return unfinishedMessage
    }

    /// The server turned the card page down because of something the policy says: the item doesn't
    /// need a card any more (a 400), or Stripe isn't set up (a 503).
    static func policyMayHaveChanged(_ error: APIError) -> Bool {
        switch error {
        case .notConfigured: return true
        case .server(let code, _, _): return code == IzzyAPI.ErrorCode.invalidRequest
        default: return false
        }
    }
}

/// What the app says about no-show protection: on Review, on the appointment cards and on "You're
/// booked". The policy and the warning themselves are the server's words.
enum NoShowCopy {
    /// Over the card section on Review.
    static let sectionTitle = "Card on file"
    static let sectionSubtitle = "Needed to book. You won't be charged now."
    static let addCardButton = "Add a card"
    static let changeCardButton = "Change"
    static let tryAgainButton = "Try again"
    static let stripePageNote = "You'll add it on Stripe's secure page. Your card number never reaches this app or the shop."
    /// Over the policy text on Review: booking is agreeing to it.
    static let agreeLabel = "By booking, you agree to this:"
    /// Under a Book appointment button that waits for a card.
    static let bookNeedsCard = "Add a card first"
    /// Under a Book appointment button while the policy is checked.
    static let bookChecking = "Checking with the shop…"
    /// The card page is open, or the card is being saved.
    static let addingCard = "Adding your card…"
    /// What VoiceOver says once a card is added: "Visa ending in 4242 added."
    static func cardAdded(_ card: StoredCard) -> String { "\(spokenCard(card.card.cardOnFile)) added." }

    /// Why the saved card can't hold this booking: "Your Visa •••• 4242 has expired. Add another
    /// card." or "Your Visa •••• 4242 expires before this appointment. Add another card."
    static func unusableCardNote(_ card: StoredCard, now: Date, timeZone: TimeZone) -> String {
        unusableCardNote(card, naming: card.label, now: now, timeZone: timeZone)
    }

    /// `unusableCardNote` as VoiceOver says it: "Your Visa ending in 4242 has expired. Add another card."
    static func spokenUnusableCardNote(_ card: StoredCard, now: Date, timeZone: TimeZone) -> String {
        unusableCardNote(card, naming: spokenCard(card.card.cardOnFile), now: now, timeZone: timeZone)
    }

    private static func unusableCardNote(_ card: StoredCard, naming name: String, now: Date, timeZone: TimeZone) -> String {
        if !card.card.isValid(at: now, in: timeZone) {
            return "Your \(name) has expired. Add another card."
        }
        return "Your \(name) expires before this appointment. Add another card."
    }

    /// "Card on file for no-shows", or "… and late cancellations" when the booking's policy has them.
    static func cardOnFileLabel(_ fee: IzzyAPI.NoShowFee?) -> String {
        fee?.lateCancelWindowMinutes == nil ? "Card on file for no-shows" : "Card on file for no-shows and late cancellations"
    }

    /// "Card on file for no-shows: Visa •••• 4242" on an appointment that has one.
    static func cardOnFileLine(_ appointment: IzzyAPI.Appointment) -> String? {
        guard let card = appointment.card else { return nil }
        return "\(cardOnFileLabel(appointment.noShowFee)): \(card.label)"
    }

    /// "Visa ending in 4242": what VoiceOver says for "Visa •••• 4242" (it would read each dot).
    static func spokenCard(_ card: IzzyAPI.CardOnFile) -> String {
        "\(card.brandName) ending in \(card.last4)"
    }

    /// `cardOnFileLine` as VoiceOver says it: "Card on file for no-shows: Visa ending in 4242".
    static func spokenCardOnFileLine(_ appointment: IzzyAPI.Appointment) -> String? {
        guard let card = appointment.card else { return nil }
        return "\(cardOnFileLabel(appointment.noShowFee)): \(spokenCard(card))"
    }

    /// "No-show fee charged: $20", or "Late cancellation fee charged: $40", once Stripe charged it.
    static func feeChargedLine(_ appointment: IzzyAPI.Appointment) -> String? {
        guard appointment.card != nil, let fee = appointment.noShowFee, fee.isCharged else { return nil }
        return "\(fee.title) charged: \(fee.amountLabel)"
    }

    /// Under the card on "You're booked": "Nothing is charged now. If you don't come, or cancel less
    /// than 1 hour before, the shop may charge $45."
    static func bookedCardDetail(_ appointment: IzzyAPI.Appointment) -> String? {
        guard appointment.card != nil, let fee = appointment.noShowFee else { return nil }
        if let window = fee.lateCancelWindowMinutes {
            let before = IzzyAPI.NoShowRule.windowLabel(minutes: window)
            return "Nothing is charged now. If you don't come, or cancel less than \(before) before, the shop may charge \(fee.amountLabel)."
        }
        return "Nothing is charged now. If you don't come, the shop may charge \(fee.amountLabel)."
    }

    /// Under "Remind me the day before and an hour before" on "You're booked", for a booking whose
    /// late cancellations may be charged.
    static let remindersNote = "Reminders also say until when you can cancel for free."

    /// Under "Remember me on this iPhone" on the details step.
    static func rememberNote(cardNeeded: Bool) -> String {
        cardNeeded ? "Your name and number fill in next time, and your card stays saved." : "Your name and number fill in next time."
    }
}
