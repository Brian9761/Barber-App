import Foundation
import Observation

/// The card saved for no-show protection, as this iPhone keeps it: the card token (the secret the
/// shop's server knows the card by) and what to show, "Visa •••• 4242" and "Expires 12/30".
///
/// The card number never reaches the app or the shop's server: the client types it on Stripe's
/// own page. Stripe keeps the card; the server keeps its brand, last 4 digits, expiry and Stripe's
/// ids under the token's SHA-256.
struct StoredCard: Codable, Hashable, CustomStringConvertible {
    let token: IzzyAPI.CardToken
    let card: IzzyAPI.SavedCard

    /// "Visa •••• 4242".
    var label: String { card.label }

    /// Leaves the token out, so it never ends up in a log.
    var description: String { "StoredCard(\(card.label), \(card.expiryLabel), token: <redacted>)" }
}

/// The client's card for no-show protection, kept on this iPhone (in the Keychain, and only on
/// this iPhone) so the next booking can use it straight away, like the remembered name and number.
///
/// With "Remember me" off the card is kept for this booking only, in memory, and forgotten once
/// it's booked; if the app closes first, the shop is asked to delete it the next time the app
/// opens (`cardsToDelete`), since nobody could use or remove it again. A card that has expired is
/// treated as no card; one that expires before an appointment's month can't hold that appointment
/// (the server's rule too).
@MainActor
@Observable
final class SavedCardStore {
    /// The Keychain item the card is kept under.
    static let account = "no-show-card"
    /// The Keychain item listing the keys of cards this iPhone holds only until the app closes (saved
    /// without "Remember me", or a remembered card whose "Remember me" was turned off on the details
    /// step): if the app closes before a booking settles them, nobody could use or remove those cards
    /// again, so the shop is asked to delete them the next time the app opens (`cardsToDelete`).
    static let pendingDeletionAccount = "no-show-cards-to-delete"

    /// The card last saved, expired or not: remembered, or kept for this booking only.
    private(set) var saved: StoredCard?
    /// Whether `saved` is kept in the Keychain for next time (otherwise only until the app closes).
    private(set) var isRemembered = false

    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date
    /// The Keychain couldn't be read yet (the iPhone hasn't been unlocked since it restarted): it's
    /// read again when the app becomes active.
    @ObservationIgnored private var needsReading = true

    init(secrets: SecretStore, timeZone: TimeZone = AppData.shop.timeZone, now: @escaping () -> Date = Date.init) {
        self.secrets = secrets
        self.timeZone = timeZone
        self.now = now
        readIfNeeded()
    }

    /// The card to show and book with: `nil` when there's none, or when it has expired.
    var current: StoredCard? {
        guard let saved, saved.card.isValid(at: now(), in: timeZone) else { return nil }
        return saved
    }

    /// The saved card, when it has expired: the app says so and asks for another one.
    var expired: StoredCard? {
        guard let saved, current == nil else { return nil }
        return saved
    }

    /// The card that can hold an appointment starting at `start`: good now, and through the
    /// appointment's month (in the shop's time zone), as the server checks at booking.
    func card(forAppointmentAt start: Date) -> StoredCard? {
        guard let current, current.card.isValid(at: start, in: timeZone) else { return nil }
        return current
    }

    /// Keeps `card` as the client's card, replacing the one before. Remembered in the Keychain
    /// when `remember`; otherwise only until the app closes (and any remembered card is dropped,
    /// so it doesn't come back next time).
    func save(_ card: StoredCard, remember: Bool) {
        // The card it replaces: whoever saves the new one asks the shop to delete it (`CardDeleter`).
        if let replaced = saved?.token, replaced != card.token { removePendingDeletion(replaced) }
        saved = card
        // The client's choice wins over whatever the Keychain held while it couldn't be read.
        needsReading = false
        write(remember: remember)
    }

    /// "Remember me on this iPhone" changed for the booking being made: the card on this iPhone is
    /// kept in the Keychain for next time, or only until it's booked (or the app closes).
    func setRemembered(_ remember: Bool) {
        guard saved != nil else {
            // Nothing to keep; and with "Remember me" off, nothing comes back from the Keychain later.
            if !remember {
                needsReading = false
                isRemembered = false
                try? secrets.removeSecret(for: Self.account)
            }
            return
        }
        guard remember != isRemembered else { return }
        write(remember: remember)
    }

    /// Drops the card from this iPhone ("Remember me" off after a booking, "Forget my details",
    /// "Remove card").
    func forget() {
        // Whoever forgets it asks the shop to delete it now (`CardDeleter`).
        if let token = saved?.token { removePendingDeletion(token) }
        saved = nil
        isRemembered = false
        needsReading = false
        try? secrets.removeSecret(for: Self.account)
    }

    /// Drops the card with `token`, if it's still the saved one (the shop's server no longer knows
    /// it). A card added since is kept.
    func forget(_ token: IzzyAPI.CardToken) {
        guard saved?.token == token else { return }
        forget()
    }

    /// Reads the remembered card from the Keychain, if that hasn't worked yet. A card saved since
    /// the app started is newer and stays.
    func readIfNeeded() {
        guard needsReading else { return }
        let text: String?
        do {
            text = try secrets.secret(for: Self.account)
        } catch {
            // Locked: try again when the app becomes active.
            return
        }
        needsReading = false
        guard let text, saved == nil else { return }
        if let card = try? IzzyAPI.makeDecoder().decode(StoredCard.self, from: Data(text.utf8)) {
            saved = card
            isRemembered = true
        } else {
            // Something this version can't read: no card, rather than a broken one.
            try? secrets.removeSecret(for: Self.account)
        }
    }

    // MARK: Cards to delete

    /// The keys of cards this iPhone let go of without a booking settling them (the app closed
    /// while a card was held only in memory), for the shop to delete: never the card still kept for
    /// the booking being made. Empty while the Keychain can't be read.
    func cardsToDelete() -> [IzzyAPI.CardToken] {
        pendingDeletions().filter { $0 != saved?.token }
    }

    /// The shop answered about the card with `token` (deleted, deleted once no booking needs it, or
    /// it had none): it's off the list.
    func deletionAnswered(for token: IzzyAPI.CardToken) {
        removePendingDeletion(token)
    }

    private func pendingDeletions() -> [IzzyAPI.CardToken] {
        guard let text = try? secrets.secret(for: Self.pendingDeletionAccount),
              let tokens = try? JSONDecoder().decode([IzzyAPI.CardToken].self, from: Data(text.utf8))
        else { return [] }
        return tokens
    }

    private func setPendingDeletions(_ tokens: [IzzyAPI.CardToken]) {
        if tokens.isEmpty {
            try? secrets.removeSecret(for: Self.pendingDeletionAccount)
        } else if let data = try? JSONEncoder().encode(tokens) {
            try? secrets.setSecret(String(decoding: data, as: UTF8.self), for: Self.pendingDeletionAccount)
        }
    }

    private func addPendingDeletion(_ token: IzzyAPI.CardToken) {
        let tokens = pendingDeletions()
        guard !tokens.contains(token) else { return }
        setPendingDeletions(tokens + [token])
    }

    private func removePendingDeletion(_ token: IzzyAPI.CardToken) {
        let tokens = pendingDeletions()
        guard tokens.contains(token) else { return }
        setPendingDeletions(tokens.filter { $0 != token })
    }

    /// Puts `saved` in the Keychain, or takes it out. A card that isn't in the Keychain is held only
    /// until the app closes, so it goes on the list of cards to delete if that happens first.
    private func write(remember: Bool) {
        if remember, let saved, let data = try? IzzyAPI.makeEncoder().encode(saved) {
            do {
                try secrets.setSecret(String(decoding: data, as: UTF8.self), for: Self.account)
                isRemembered = true
                removePendingDeletion(saved.token)
                return
            } catch {
                // The card still works until the app closes; an older one mustn't come back instead.
            }
        }
        isRemembered = false
        try? secrets.removeSecret(for: Self.account)
        if let saved { addPendingDeletion(saved.token) }
    }
}
