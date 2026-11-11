import Foundation

/// What the shop's server said when asked to delete a saved card (`DELETE /api/cards`).
enum CardRemoval: Equatable {
    /// Its answer: deleted now, or as soon as no booking needs the card (`status`), in its words.
    case answered(IzzyAPI.CardDeletion)
    /// It has no card under that key (a 404): there was nothing to delete there.
    case nothingToDelete
    /// It couldn't be reached, or answered with a problem: the client should call to have it removed.
    case failed
}

/// Asks the shop's server to delete a saved card whenever this iPhone lets go of the card's key for
/// good: "Remove card" and "Forget my details" in Your details, right after a booking made without
/// "Remember me", and when another card takes its place. The key exists only on this iPhone, so
/// once it's forgotten nobody could use or remove the card again; the server deletes it at Stripe
/// now, or as soon as no booking needs it (it answers "scheduled": a card saved without Remember me
/// is kept only while that booking can still be charged).
///
/// The key is forgotten on this iPhone whatever the answer (the callers forget it first): a network
/// problem never keeps it.
enum CardDeleter {
    /// Asks once more when the connection drops; never throws.
    static func delete(_ token: IzzyAPI.CardToken, api: any ShopAPI) async -> CardRemoval {
        for attempt in 0..<2 {
            do {
                return .answered(try await api.deleteCard(token: token))
            } catch {
                switch error.asAPIError {
                case .server(let code, _, let status) where code == IzzyAPI.ErrorCode.notFound || status == 404:
                    return .nothingToDelete
                case .offline where attempt == 0:
                    continue
                default:
                    return .failed
                }
            }
        }
        return .failed
    }
}

/// While the shop is asked to delete the card, or what it answered: for Your details to say.
enum CardRemovalState: Equatable {
    case asking
    case finished(CardRemoval)

    /// "Asking the shop to delete your saved card…", then the shop's own words ("Your saved card is
    /// deleted. It can't be charged any more." or "Your card will be deleted as soon as your
    /// appointments no longer need it."), or what to do when it couldn't be reached.
    var message: String {
        switch self {
        case .asking:
            return "Asking the shop to delete your saved card…"
        case .finished(.answered(let deletion)):
            let words = deletion.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { return words }
            return deletion.status == .deleted ? Self.deletedMessage : Self.scheduledMessage
        case .finished(.nothingToDelete):
            return "Your card is removed from this iPhone."
        case .finished(.failed):
            return "Your card is removed from this iPhone, but we couldn't reach the shop to delete it there. "
                + "To have it deleted, call the shop at \(AppData.shop.phone.display)."
        }
    }

    /// The shop couldn't be reached: Your details offers to call.
    var offersCall: Bool { self == .finished(.failed) }

    /// The server's words for each answer (`server/src/cards.ts`), for an answer without them.
    static let deletedMessage = "Your saved card is deleted. It can't be charged any more."
    static let scheduledMessage = "Your card will be deleted as soon as your appointments no longer need it."
}
