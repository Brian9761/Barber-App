import XCTest
@testable import IzzyClipz

/// Asking the shop to delete a saved card ("Remove card", "Forget my details", and after a booking
/// made without Remember me), what Your details says about it, and the in-memory server answering
/// like the real one.
@MainActor
final class CardDeleterTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private let token = IzzyAPI.CardToken.generate()
    private let deleted = IzzyAPI.CardDeletion(status: .deleted, message: "Your saved card is deleted. It can't be charged any more.")
    private let scheduled = IzzyAPI.CardDeletion(status: .scheduled, message: "Your card will be deleted as soon as your appointments no longer need it.")

    func testTheShopsAnswer() async {
        api.deleteCardHandler = { [deleted] _ in deleted }
        let now = await CardDeleter.delete(token, api: api)
        XCTAssertEqual(now, .answered(deleted))
        api.deleteCardHandler = { [scheduled] _ in scheduled }
        let later = await CardDeleter.delete(token, api: api)
        XCTAssertEqual(later, .answered(scheduled))
        XCTAssertEqual(api.cardDeletions, [token, token])
    }

    /// No card under that key at the shop (a 404): nothing to delete there.
    func testNoCardAtTheShop() async {
        api.deleteCardHandler = { _ in throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that card.", status: 404) }
        let result = await CardDeleter.delete(token, api: api)
        XCTAssertEqual(result, .nothingToDelete)
        XCTAssertEqual(api.cardDeletions.count, 1)
    }

    /// The connection drops: asked once more, which works.
    func testAskedOnceMoreWhenTheConnectionDrops() async {
        var calls = 0
        api.deleteCardHandler = { [deleted] _ in
            calls += 1
            if calls == 1 { throw APIError.offline }
            return deleted
        }
        let result = await CardDeleter.delete(token, api: api)
        XCTAssertEqual(result, .answered(deleted))
        XCTAssertEqual(api.cardDeletions.count, 2)
    }

    /// Offline twice, or another problem: it failed, and the client is told to call. Other problems
    /// aren't tried again.
    func testItFailsWhenTheShopCantBeReached() async {
        api.deleteCardHandler = { _ in throw APIError.offline }
        let offline = await CardDeleter.delete(token, api: api)
        XCTAssertEqual(offline, .failed)
        XCTAssertEqual(api.cardDeletions.count, 2)

        for problem: APIError in [.rateLimited(message: "Too many tries."), .server(code: "server_error", message: "", status: 500), .notConfigured(APIError.Feature.stripe)] {
            let other = ScriptedShopAPI()
            other.deleteCardHandler = { _ in throw problem }
            let result = await CardDeleter.delete(token, api: other)
            XCTAssertEqual(result, .failed, "\(problem)")
            XCTAssertEqual(other.cardDeletions.count, 1, "\(problem)")
        }
    }

    /// What Your details says: the shop's own words, or what to do when it couldn't be reached.
    func testWhatYourDetailsSays() {
        XCTAssertEqual(CardRemovalState.asking.message, "Asking the shop to delete your saved card…")
        XCTAssertEqual(CardRemovalState.finished(.answered(deleted)).message, "Your saved card is deleted. It can't be charged any more.")
        XCTAssertEqual(
            CardRemovalState.finished(.answered(scheduled)).message,
            "Your card will be deleted as soon as your appointments no longer need it."
        )
        // An answer without words gets the server's usual ones.
        XCTAssertEqual(CardRemovalState.finished(.answered(IzzyAPI.CardDeletion(status: .deleted, message: " "))).message, CardRemovalState.deletedMessage)
        XCTAssertEqual(CardRemovalState.finished(.answered(IzzyAPI.CardDeletion(status: .scheduled, message: ""))).message, CardRemovalState.scheduledMessage)
        XCTAssertEqual(CardRemovalState.finished(.nothingToDelete).message, "Your card is removed from this iPhone.")
        let failed = CardRemovalState.finished(.failed)
        XCTAssertEqual(
            failed.message,
            "Your card is removed from this iPhone, but we couldn't reach the shop to delete it there. To have it deleted, call the shop at (442) 341-3053."
        )
        XCTAssertTrue(failed.offersCall)
        XCTAssertFalse(CardRemovalState.finished(.answered(deleted)).offersCall)
        XCTAssertFalse(CardRemovalState.asking.offersCall)
    }
}

/// The in-memory server deletes a card the client removes now, or once no booking needs it, as the
/// real one does, and a removed card can't book again.
@MainActor
final class FakeShopAPICardDeletionTests: XCTestCase {
    private let carlos = IzzyAPI.BookingTarget.offering(id: TestData.carlosHaircutID)

    /// A card saved on the "card page" under a new token.
    private func saveCard(on fake: FakeShopAPI) async throws -> IzzyAPI.CardToken {
        let token = IzzyAPI.CardToken.generate()
        let checkout = try await fake.startCardCheckout(for: carlos, token: token)
        fake.completeCardCheckout(sessionId: checkout.sessionId, card: fake.sampleCard)
        _ = try await fake.saveCard(sessionId: checkout.sessionId, token: token)
        return token
    }

    /// Books Carlos's first open time tomorrow with the card, or throws what the server said.
    private func book(on fake: FakeShopAPI, with token: IzzyAPI.CardToken, slot: Int = 0) async throws -> IzzyAPI.BookingConfirmation {
        let tomorrow = TestData.calendarDay(2026, 10, 29)
        let open = try await fake.availability(IzzyAPI.AvailabilityQuery(target: carlos, from: tomorrow, days: 1)).slots(on: tomorrow)
        let start = try XCTUnwrap(open.dropFirst(slot).first?.start)
        let request = IzzyAPI.NewAppointment(
            target: carlos, start: start, customer: IzzyAPI.NewCustomer(name: "Alex", phone: "+14425550123"), note: nil,
            noShow: IzzyAPI.NoShowAgreement(cardToken: token, policyText: NoShowTestData.carlosPolicyText)
        )
        return try await fake.book(request, token: .generate())
    }

    func testAnUnknownCardIsANotFound() async {
        let fake = NoShowTestData.fake()
        do {
            _ = try await fake.deleteCard(token: .generate())
            XCTFail("No card under that token")
        } catch {
            XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that card.", status: 404))
        }
    }

    /// No booking needs it: deleted at once, and asking again answers the same.
    func testAnUnusedCardIsDeletedAtOnce() async throws {
        let fake = NoShowTestData.fake()
        let token = try await saveCard(on: fake)
        let first = try await fake.deleteCard(token: token)
        XCTAssertEqual(first, IzzyAPI.CardDeletion(status: .deleted, message: CardRemovalState.deletedMessage))
        let again = try await fake.deleteCard(token: token)
        XCTAssertEqual(again.status, .deleted)
        XCTAssertEqual(fake.cardRemoval(for: token)?.deleted, true)
    }

    /// An upcoming booking still needs it: it's deleted once none does, and it can't book again
    /// meanwhile. Once that booking is cancelled in time (free), nothing needs it: asking again deletes it.
    func testACardABookingStillNeedsIsScheduled() async throws {
        let fake = NoShowTestData.fake()
        let token = try await saveCard(on: fake)
        let booked = try await book(on: fake, with: token)
        let first = try await fake.deleteCard(token: token)
        XCTAssertEqual(first, IzzyAPI.CardDeletion(status: .scheduled, message: CardRemovalState.scheduledMessage))
        XCTAssertEqual(fake.cardRemoval(for: token)?.requested, true)
        XCTAssertEqual(fake.cardRemoval(for: token)?.deleted, false)

        do {
            _ = try await book(on: fake, with: token, slot: 3)
            XCTFail("A removed card can't book again")
        } catch {
            XCTAssertEqual(error as? APIError, .cardRequired(message: "We couldn't find your saved card. Add it again."))
        }

        // Tomorrow's booking, cancelled today: well before the hour, so it's free and needs no card.
        let cancelled = try await fake.cancelAppointment(id: booked.appointment.id, manageToken: booked.manageToken)
        XCTAssertEqual(cancelled.status, .cancelled)
        let then = try await fake.deleteCard(token: token)
        XCTAssertEqual(then.status, .deleted)
        XCTAssertEqual(fake.cardRemoval(for: token)?.deleted, true)
    }
}
