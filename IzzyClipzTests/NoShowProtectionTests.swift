import Foundation
import XCTest
@testable import IzzyClipz

// No-show protection in the customer app: the card kept on this iPhone, the policy for each
// booking choice, what Review asks for, adding a card, booking with it, the warnings, cancelling
// inside the late-cancellation window, and the in-memory server answering like the real one.

/// A card page whose answers each test scripts.
@MainActor
final class ScriptedCardSaver: CardSaver {
    /// Answered in order; `.saved` for the checkout's own session once they run out.
    var results: [IzzyAPI.CardCheckoutResult] = []
    var error: Error?
    private(set) var shown: [IzzyAPI.CardCheckout] = []

    func collectCard(on checkout: IzzyAPI.CardCheckout) async throws -> IzzyAPI.CardCheckoutResult {
        shown.append(checkout)
        // The page stays open a moment, like the real one, so a second tap can come in meanwhile.
        await Task.yield()
        if let error { throw error }
        return results.isEmpty ? .saved(sessionId: checkout.sessionId) : results.removeFirst()
    }
}

/// What the shop's server says when protection is on with its starting settings (the full service
/// price, cancelling less than 1 hour before or not coming), for Carlos's $45 haircut.
enum NoShowTestData {
    static let carlosPolicyText = "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $45 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free."
    static let carlosWarning = IzzyAPI.NoShowWarning(
        title: "Full Service Cancellation & No-Show Fee",
        message: "Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($45). Cancelling in the app more than 1 hour before is free."
    )
    static let carlosPolicy = IzzyAPI.NoShowPolicy(
        required: true, minFeeCents: 4_500, maxFeeCents: 4_500, policyText: carlosPolicyText,
        lateCancelWindowMinutes: 60, warning: carlosWarning
    )
    static let lateCancelWarning = "Cancelling now, less than 1 hour before your appointment, may be charged $45, the full service price."

    static func card(expMonth: Int = 12, expYear: Int = 2029, last4: String = "4242") -> IzzyAPI.SavedCard {
        IzzyAPI.SavedCard(brand: "visa", last4: last4, expMonth: expMonth, expYear: expYear)
    }

    static func stored(_ card: IzzyAPI.SavedCard = card()) -> StoredCard {
        StoredCard(token: .generate(), card: card)
    }

    /// Carlos's haircut with a card on file, booked under the starting policy.
    static func appointment(start: Date, fee: IzzyAPI.NoShowFee? = nil) -> IzzyAPI.Appointment {
        var appointment = TestData.appointment(start: start)
        appointment.card = IzzyAPI.CardOnFile(brand: "visa", last4: "4242")
        appointment.noShowFee = fee ?? IzzyAPI.NoShowFee(amountCents: 4_500, fullPrice: true, lateCancelWindowMinutes: 60)
        return appointment
    }

    /// The in-memory server with no delay, protection on (or off) with the server's starting settings.
    @MainActor
    static func fake(protection: Bool = true, configure: (inout FakeShopAPI.Options) -> Void = { _ in }) -> FakeShopAPI {
        var options = FakeShopAPI.Options()
        options.latency = .zero
        options.noShowSettings.enabled = protection
        configure(&options)
        return FakeShopAPI(options: options, now: TestData.now)
    }
}

// MARK: - The card on this iPhone

@MainActor
final class SavedCardStoreTests: XCTestCase {
    private let keychain = InMemorySecretStore()
    private var now = TestData.now
    private let zone = AppData.shop.timeZone

    private func makeStore() -> SavedCardStore {
        SavedCardStore(secrets: keychain, timeZone: zone, now: { [unowned self] in self.now })
    }

    func testRemembersTheCardInTheKeychainForNextTime() throws {
        let store = makeStore()
        XCTAssertNil(store.saved)
        let card = NoShowTestData.stored()
        store.save(card, remember: true)
        XCTAssertEqual(store.current, card)
        XCTAssertTrue(store.isRemembered)
        let item = try XCTUnwrap(keychain.secrets[SavedCardStore.account])
        XCTAssertTrue(item.contains(card.token.rawValue), "The token is in the Keychain, with the card")
        XCTAssertTrue(item.contains("4242"))

        // The app opened again: the same card, straight away.
        let reopened = makeStore()
        XCTAssertEqual(reopened.current, card)
        XCTAssertTrue(reopened.isRemembered)
    }

    /// "Remember me" off: the card holds this booking, and is gone when the app opens again. A card
    /// remembered before doesn't come back instead.
    func testWithoutRememberMeTheCardIsKeptOnlyForNow() {
        let store = makeStore()
        store.save(NoShowTestData.stored(), remember: true)
        let forNow = NoShowTestData.stored(NoShowTestData.card(last4: "1881"))
        store.save(forNow, remember: false)
        XCTAssertEqual(store.current, forNow)
        XCTAssertFalse(store.isRemembered)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])
        XCTAssertNil(makeStore().saved)
    }

    /// Changing "Remember me" for the booking being made keeps or drops the card from the Keychain;
    /// the card itself stays for this booking.
    func testRememberMeCanChangeWhileBooking() {
        let store = makeStore()
        let card = NoShowTestData.stored()
        store.save(card, remember: true)
        store.setRemembered(false)
        XCTAssertEqual(store.current, card, "Still holds this booking")
        XCTAssertNil(keychain.secrets[SavedCardStore.account])
        store.setRemembered(true)
        XCTAssertNotNil(keychain.secrets[SavedCardStore.account])
        XCTAssertEqual(makeStore().current, card)
    }

    /// A card is good through the last day of its expiry month, in the shop's time zone. An expired
    /// one counts as no card; one that expires before an appointment's month can't hold it.
    func testAnExpiredCardCountsAsNone() throws {
        // Now is October 28, 2026.
        let store = makeStore()
        let october = NoShowTestData.stored(NoShowTestData.card(expMonth: 10, expYear: 2026))
        store.save(october, remember: true)
        XCTAssertEqual(store.current, october, "Good through October 31")
        XCTAssertNil(store.expired)
        XCTAssertEqual(store.card(forAppointmentAt: TestData.friday), october, "Friday is still October")
        let november = try XCTUnwrap(AppData.bookingCalendar.date(on: TestData.calendarDay(2026, 11, 2).calendarDay, at: TimeOfDay(hour: 10)))
        XCTAssertNil(store.card(forAppointmentAt: november), "It expires before a November appointment")

        now = try XCTUnwrap(AppData.bookingCalendar.date(on: TestData.calendarDay(2026, 11, 1).calendarDay, at: TimeOfDay(hour: 9)))
        XCTAssertNil(store.current)
        XCTAssertEqual(store.expired, october, "Kept, so the app can say it expired")
        XCTAssertNil(store.card(forAppointmentAt: november))
    }

    /// 10 PM on October 31 in Oceanside is already November in UTC: still October for the card.
    func testTheShopsDayDecidesTheMonth() throws {
        now = try XCTUnwrap(AppData.bookingCalendar.date(on: TestData.calendarDay(2026, 10, 31).calendarDay, at: TimeOfDay(hour: 22)))
        XCTAssertEqual(LocalDate(containing: now, in: TimeZone(identifier: "UTC")!).month, 11)
        let store = makeStore()
        store.save(NoShowTestData.stored(NoShowTestData.card(expMonth: 10, expYear: 2026)), remember: false)
        XCTAssertNotNil(store.current)
    }

    func testForgetting() {
        let store = makeStore()
        let card = NoShowTestData.stored()
        store.save(card, remember: true)
        // Another card's token (a card replaced since): nothing happens.
        store.forget(IzzyAPI.CardToken.generate())
        XCTAssertEqual(store.saved, card)
        store.forget(card.token)
        XCTAssertNil(store.saved)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])

        store.save(card, remember: true)
        store.forget()
        XCTAssertNil(store.saved)
        XCTAssertFalse(store.isRemembered)
        XCTAssertNil(makeStore().saved)
    }

    /// Before the first unlock the Keychain can't be read: it's read when the app becomes active.
    func testALockedKeychainIsReadLater() {
        let card = NoShowTestData.stored()
        makeStore().save(card, remember: true)
        keychain.failsReads = true
        let store = makeStore()
        XCTAssertNil(store.saved)
        store.readIfNeeded()
        XCTAssertNil(store.saved)
        keychain.failsReads = false
        store.readIfNeeded()
        XCTAssertEqual(store.saved, card)
    }

    /// A card saved while the Keychain was locked is the newer one and stays.
    func testACardSavedWhileLockedWins() {
        makeStore().save(NoShowTestData.stored(), remember: true)
        keychain.failsReads = true
        let store = makeStore()
        let newer = NoShowTestData.stored(NoShowTestData.card(last4: "0005"))
        store.save(newer, remember: true)
        keychain.failsReads = false
        store.readIfNeeded()
        XCTAssertEqual(store.saved, newer)
        XCTAssertEqual(makeStore().saved, newer)
    }

    func testSomethingUnreadableInTheKeychainIsDropped() throws {
        try keychain.setSecret("not a card", for: SavedCardStore.account)
        let store = makeStore()
        XCTAssertNil(store.saved)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])
    }

    /// The Keychain won't take it: the card still holds this booking, and an older card doesn't
    /// come back next time instead.
    func testAKeychainThatWontTakeTheCard() {
        let store = makeStore()
        store.save(NoShowTestData.stored(), remember: true)
        keychain.failsWrites = true
        let newer = NoShowTestData.stored(NoShowTestData.card(last4: "0005"))
        store.save(newer, remember: true)
        XCTAssertEqual(store.current, newer)
        XCTAssertFalse(store.isRemembered)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])
    }

    func testTheTokenNeverShowsInADescription() {
        let card = NoShowTestData.stored()
        XCTAssertFalse(String(describing: card).contains(card.token.rawValue))
        XCTAssertTrue(String(describing: card).contains("Visa •••• 4242"))
    }
}

// MARK: - The policy for each booking choice

@MainActor
final class NoShowPolicyStoreTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private var now = TestData.now
    private let carlos = IzzyAPI.BookingTarget.offering(id: TestData.carlosHaircutID)

    private func makeStore() -> NoShowPolicyStore {
        NoShowPolicyStore(api: api, now: { [unowned self] in self.now })
    }

    func testAsksOnceAMinute() async {
        api.noShowPolicyHandler = { _ in NoShowTestData.carlosPolicy }
        let store = makeStore()
        XCTAssertFalse(store.entry(for: carlos).isSettled)
        await store.load(carlos)
        await store.load(carlos)
        XCTAssertEqual(api.noShowPolicyRequests, [carlos])
        XCTAssertEqual(store.policy(for: carlos), NoShowTestData.carlosPolicy)
        XCTAssertTrue(store.entry(for: carlos).isSettled)
        XCTAssertFalse(store.entry(for: carlos).isLoading)

        now = now.addingTimeInterval(NoShowPolicyStore.maxAge + 1)
        await store.load(carlos)
        XCTAssertEqual(api.noShowPolicyRequests.count, 2, "Older than a minute: asked again")
        await store.reload(carlos)
        XCTAssertEqual(api.noShowPolicyRequests.count, 3, "Reload always asks")
    }

    func testEachChoiceHasItsOwnPolicy() async {
        let any = IzzyAPI.BookingTarget.anyBarber(serviceId: "haircut")
        api.noShowPolicyHandler = { target in target == any ? .notRequired : NoShowTestData.carlosPolicy }
        let store = makeStore()
        await store.load(carlos)
        await store.load(any)
        XCTAssertEqual(store.policy(for: carlos), NoShowTestData.carlosPolicy)
        XCTAssertEqual(store.policy(for: any), .notRequired)
    }

    func testTwoLoadsAtOnceShareOneRequest() async {
        api.noShowPolicyHandler = { _ in NoShowTestData.carlosPolicy }
        let store = makeStore()
        async let first: Void = store.load(carlos)
        async let second: Void = store.load(carlos)
        _ = await (first, second)
        XCTAssertEqual(api.noShowPolicyRequests.count, 1)
    }

    /// A failed request keeps the last answer (and says why); with no answer at all it's settled
    /// anyway, so booking isn't stuck waiting.
    func testAFailureKeepsTheLastAnswer() async {
        api.noShowPolicyHandler = { _ in throw APIError.offline }
        let store = makeStore()
        await store.load(carlos)
        XCTAssertNil(store.policy(for: carlos))
        XCTAssertEqual(store.entry(for: carlos).error, .offline)
        XCTAssertTrue(store.entry(for: carlos).isSettled)

        api.noShowPolicyHandler = { _ in NoShowTestData.carlosPolicy }
        await store.load(carlos)
        XCTAssertEqual(store.policy(for: carlos), NoShowTestData.carlosPolicy, "Asked again: no answer yet")
        XCTAssertNil(store.entry(for: carlos).error)

        api.noShowPolicyHandler = { _ in throw APIError.offline }
        await store.reload(carlos)
        XCTAssertEqual(store.policy(for: carlos), NoShowTestData.carlosPolicy)
        XCTAssertEqual(store.entry(for: carlos).error, .offline)
    }
}

// MARK: - What Review asks for

@MainActor
final class NoShowRequirementTests: XCTestCase {
    private func entry(_ policy: IzzyAPI.NoShowPolicy?, error: APIError? = nil) -> NoShowPolicyStore.Entry {
        NoShowPolicyStore.Entry(policy: policy, error: error, loadedAt: TestData.now)
    }

    func testWaitsForTheFirstAnswer() {
        let requirement = NoShowRequirement(entry: NoShowPolicyStore.Entry(), saved: nil, usable: nil)
        XCTAssertEqual(requirement, .checking)
        XCTAssertTrue(requirement.blocksBooking)
        XCTAssertEqual(requirement.bookButtonNote, "Checking with the shop…")
        XCTAssertNil(requirement.policy)
    }

    /// No card needed, or the policy couldn't be checked: book as before (the server says if a card
    /// is needed after all).
    func testBooksWithoutACardWhenNoneIsNeeded() {
        let card = NoShowTestData.stored()
        for requirement in [
            NoShowRequirement(entry: entry(.notRequired), saved: card, usable: card),
            NoShowRequirement(entry: entry(nil, error: .offline), saved: nil, usable: nil),
            // "Required" without a policy to agree to can't be sent.
            NoShowRequirement(entry: entry(IzzyAPI.NoShowPolicy(required: true, minFeeCents: 4_500, maxFeeCents: 4_500)), saved: nil, usable: nil),
        ] {
            XCTAssertEqual(requirement, .notNeeded)
            XCTAssertFalse(requirement.blocksBooking)
            XCTAssertNil(requirement.agreement)
            XCTAssertNil(requirement.policy)
            XCTAssertNil(requirement.bookButtonNote)
        }
    }

    func testBookWaitsForACard() {
        let none = NoShowRequirement(entry: entry(NoShowTestData.carlosPolicy), saved: nil, usable: nil)
        XCTAssertEqual(none, .needsCard(NoShowTestData.carlosPolicy, unusable: nil))
        XCTAssertTrue(none.blocksBooking)
        XCTAssertEqual(none.bookButtonNote, "Add a card first")
        XCTAssertEqual(none.policy, NoShowTestData.carlosPolicy)
        XCTAssertNil(none.agreement)

        // The card on this iPhone can't hold this appointment: it says so.
        let expired = NoShowTestData.stored(NoShowTestData.card(expMonth: 1, expYear: 2026))
        XCTAssertEqual(
            NoShowRequirement(entry: entry(NoShowTestData.carlosPolicy), saved: expired, usable: nil),
            .needsCard(NoShowTestData.carlosPolicy, unusable: expired)
        )
    }

    /// Ready: the booking sends the card's token and the policy exactly as the server gave it.
    func testBooksWithTheCardAndThePolicyAsShown() {
        let card = NoShowTestData.stored()
        let ready = NoShowRequirement(entry: entry(NoShowTestData.carlosPolicy), saved: card, usable: card)
        XCTAssertEqual(ready, .ready(NoShowTestData.carlosPolicy, card: card))
        XCTAssertFalse(ready.blocksBooking)
        XCTAssertEqual(ready.card, card)
        XCTAssertEqual(ready.agreement, IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
    }

    /// From the stores: the card has to be good through the appointment's month.
    func testUsesTheCardThatCanHoldTheAppointment() throws {
        let cards = SavedCardStore(secrets: InMemorySecretStore(), now: { TestData.now })
        let october = NoShowTestData.stored(NoShowTestData.card(expMonth: 10, expYear: 2026))
        cards.save(october, remember: false)
        let entry = entry(NoShowTestData.carlosPolicy)
        XCTAssertEqual(NoShowRequirement(entry: entry, cards: cards, start: TestData.friday), .ready(NoShowTestData.carlosPolicy, card: october))
        let december = try XCTUnwrap(AppData.bookingCalendar.date(on: TestData.calendarDay(2026, 12, 3).calendarDay, at: TimeOfDay(hour: 11)))
        XCTAssertEqual(NoShowRequirement(entry: entry, cards: cards, start: december), .needsCard(NoShowTestData.carlosPolicy, unusable: october))
    }
}

// MARK: - The warning while booking

final class NoShowWarningContentTests: XCTestCase {
    func testOnlyWhenTheBookingNeedsACard() {
        XCTAssertNil(NoShowWarningContent(policy: nil, start: nil, now: TestData.now))
        XCTAssertNil(NoShowWarningContent(policy: .notRequired, start: nil, now: TestData.now))
        // From a server without a warning: nothing to show here (Review still has the policy).
        var withoutWarning = NoShowTestData.carlosPolicy
        withoutWarning.warning = nil
        XCTAssertNil(NoShowWarningContent(policy: withoutWarning, start: nil, now: TestData.now))
    }

    func testTheServersWords() throws {
        let content = try XCTUnwrap(NoShowWarningContent(policy: NoShowTestData.carlosPolicy, start: nil, now: TestData.now))
        XCTAssertEqual(content.title, "Full Service Cancellation & No-Show Fee")
        XCTAssertEqual(content.message, NoShowTestData.carlosWarning.message)
        XCTAssertNil(content.notice)
        XCTAssertEqual(content.spoken, "Full Service Cancellation & No-Show Fee. \(NoShowTestData.carlosWarning.message)")
    }

    /// A time less than the window away can't be cancelled for free once it's booked: it says so.
    /// An hour or more away is free to cancel until an hour before.
    func testAPickedTimeInsideTheWindowSaysCancellingMayBeCharged() throws {
        let soon = try XCTUnwrap(NoShowWarningContent(policy: NoShowTestData.carlosPolicy, start: TestData.now.addingTimeInterval(45 * 60), now: TestData.now))
        XCTAssertEqual(soon.notice, "This time is less than 1 hour away, so cancelling it may be charged $45.")
        XCTAssertTrue(soon.spoken.hasSuffix("This time is less than 1 hour away, so cancelling it may be charged $45."))
        let inAnHour = try XCTUnwrap(NoShowWarningContent(policy: NoShowTestData.carlosPolicy, start: TestData.now.addingTimeInterval(60 * 60), now: TestData.now))
        XCTAssertNil(inAnHour.notice, "Exactly an hour away: still free until an hour before")

        // Late cancellations off: only no-shows can be charged, so a soon time says nothing more.
        var noLateCancel = NoShowTestData.carlosPolicy
        noLateCancel.lateCancelWindowMinutes = nil
        XCTAssertNil(NoShowWarningContent(policy: noLateCancel, start: TestData.now.addingTimeInterval(45 * 60), now: TestData.now)?.notice)
    }
}

// MARK: - Adding a card

@MainActor
final class CardSetupTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private let saver = ScriptedCardSaver()
    private let keychain = InMemorySecretStore()
    private lazy var cards = SavedCardStore(secrets: keychain, now: { TestData.now })
    private lazy var policies = NoShowPolicyStore(api: api, now: { TestData.now })
    private let carlos = IzzyAPI.BookingTarget.offering(id: TestData.carlosHaircutID)

    private func makeSetup() -> CardSetup {
        CardSetup(api: api, saver: saver, cards: cards, policies: policies)
    }

    private func checkout(_ id: String) -> IzzyAPI.CardCheckout {
        IzzyAPI.CardCheckout(url: URL(string: "https://checkout.stripe.com/c/pay/\(id)")!, sessionId: id)
    }

    /// Stripe's page with a new token, then the server keeps the card from that session under the
    /// same token, and this iPhone keeps both.
    func testAddsACardThroughStripesPage() async throws {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        api.saveCardHandler = { _, _ in NoShowTestData.card() }
        let setup = makeSetup()
        let addedResult = await setup.addCard(for: carlos, remember: true)
        let added = try XCTUnwrap(addedResult)
        XCTAssertEqual(api.cardCheckouts.map(\.target), [carlos])
        XCTAssertEqual(saver.shown.map(\.sessionId), ["cs_test_a1"])
        XCTAssertEqual(api.cardSaves.map(\.sessionId), ["cs_test_a1"])
        let token = try XCTUnwrap(api.cardCheckouts.first?.token)
        XCTAssertEqual(api.cardSaves.first?.token, token, "Saved under the token the page was opened with")
        XCTAssertEqual(added, StoredCard(token: token, card: NoShowTestData.card()))
        XCTAssertEqual(cards.current, added)
        XCTAssertTrue(cards.isRemembered)
        XCTAssertNil(setup.failure)
        XCTAssertFalse(setup.isWorking)
        XCTAssertEqual(setup.phase, .idle)
    }

    func testANewTokenForEachCard() async throws {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a\(api.cardCheckouts.count)") }
        api.saveCardHandler = { _, _ in NoShowTestData.card() }
        let setup = makeSetup()
        _ = await setup.addCard(for: carlos, remember: false)
        _ = await setup.addCard(for: carlos, remember: false)
        XCTAssertEqual(Set(api.cardCheckouts.map(\.token)).count, 2)
        XCTAssertFalse(cards.isRemembered, "Remember me off: only for this booking")
        XCTAssertNil(keychain.secrets[SavedCardStore.account])
    }

    /// The client closed Stripe's page: nothing is added and nothing goes wrong.
    func testClosingTheCardPageAddsNothing() async {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        saver.results = [.cancelled]
        let setup = makeSetup()
        let added = await setup.addCard(for: carlos, remember: true)
        XCTAssertNil(added)
        XCTAssertNil(setup.failure)
        XCTAssertTrue(api.cardSaves.isEmpty)
        XCTAssertNil(cards.saved)
    }

    func testAPageThatDidntComeBackRightSaysToTryAgain() async {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        saver.results = [.failed]
        let setup = makeSetup()
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, "The card wasn't added. Try again.")
        XCTAssertFalse(setup.canFinishSaving)
        XCTAssertTrue(api.cardSaves.isEmpty)

        saver.results = []
        saver.error = APIError.offline
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, "The card wasn't added. Try again.")
        setup.clearFailure()
        XCTAssertNil(setup.failure)
    }

    /// Stripe has the card but the shop's server didn't answer: Try again finishes saving that same
    /// card, without the card page.
    func testTryAgainFinishesACardStripeAlreadyHas() async throws {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        api.saveCardHandler = { _, _ in throw APIError.offline }
        let setup = makeSetup()
        let lost = await setup.addCard(for: carlos, remember: true)
        XCTAssertNil(lost)
        XCTAssertEqual(setup.failure, "Your card is saved with Stripe, but we couldn't reach the shop to finish. Try again.")
        XCTAssertTrue(setup.canFinishSaving)

        api.saveCardHandler = { _, _ in NoShowTestData.card() }
        let addedResult = await setup.addCard(for: carlos, remember: true)
        let added = try XCTUnwrap(addedResult)
        XCTAssertEqual(api.cardCheckouts.count, 1, "No second card page")
        XCTAssertEqual(saver.shown.count, 1)
        XCTAssertEqual(api.cardSaves.map(\.sessionId), ["cs_test_a1", "cs_test_a1"])
        XCTAssertEqual(api.cardSaves[0].token, api.cardSaves[1].token)
        XCTAssertEqual(added.token, api.cardSaves[1].token)
        XCTAssertFalse(setup.canFinishSaving)
        XCTAssertNil(setup.failure)
    }

    func testTooManyTriesSaysWhatTheServerSays() async {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        let limit = "Too many tries to add a card from this network. Try again in an hour, or call the shop."
        api.saveCardHandler = { _, _ in throw APIError.rateLimited(message: limit) }
        let setup = makeSetup()
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, limit)
        XCTAssertTrue(setup.canFinishSaving)
    }

    /// The server turned the card down (expired, say): its words, and the next try opens a new page.
    func testATurnedDownCardSaysWhy() async {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a\(api.cardCheckouts.count)") }
        api.saveCardHandler = { _, _ in
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That card has expired. Add another card.", status: 400)
        }
        let setup = makeSetup()
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, "That card has expired. Add another card.")
        XCTAssertFalse(setup.canFinishSaving)
        XCTAssertNil(cards.saved)
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(api.cardCheckouts.count, 2)
    }

    /// The server says the booking doesn't need a card (the owner just turned protection off), or
    /// Stripe isn't set up: the policy is asked again, so Review shows what's true now.
    func testNoCardNeededAnyMoreAsksForThePolicyAgain() async {
        api.startCardCheckoutHandler = { _, _ in
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "This booking doesn't need a card. Go ahead and book.", status: 400)
        }
        let setup = makeSetup()
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, "This booking doesn't need a card. Go ahead and book.")
        XCTAssertEqual(api.noShowPolicyRequests, [carlos])
        XCTAssertEqual(policies.policy(for: carlos), .notRequired)

        api.startCardCheckoutHandler = { _, _ in throw APIError.notConfigured(APIError.Feature.stripe) }
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, "Adding a card isn't working right now. Try again later, or call the shop.")
        XCTAssertEqual(api.noShowPolicyRequests.count, 2)

        api.startCardCheckoutHandler = { _, _ in throw APIError.offline }
        _ = await setup.addCard(for: carlos, remember: true)
        XCTAssertEqual(setup.failure, APIError.offline.userMessage)
        XCTAssertEqual(api.noShowPolicyRequests.count, 2, "Offline says nothing about the policy")
        XCTAssertTrue(saver.shown.isEmpty)
    }

    func testOneAtATime() async {
        api.startCardCheckoutHandler = { [unowned self] _, _ in checkout("cs_test_a1") }
        api.saveCardHandler = { _, _ in NoShowTestData.card() }
        let setup = makeSetup()
        async let first = setup.addCard(for: carlos, remember: true)
        async let second = setup.addCard(for: carlos, remember: true)
        let results = await [first, second]
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        XCTAssertEqual(api.cardCheckouts.count, 1)
    }

    /// Against the in-memory server and the UI tests' card page: Stripe's test card, saved.
    func testWithTheInMemoryServerAndTheTestCardPage() async throws {
        let fake = NoShowTestData.fake()
        let page = FakeCardSaver(api: fake)
        let setup = CardSetup(api: fake, saver: page, cards: cards)
        let addedResult = await setup.addCard(for: carlos, remember: true)
        let added = try XCTUnwrap(addedResult)
        XCTAssertEqual(added.label, "Visa •••• 4242")
        XCTAssertEqual(added.card, fake.sampleCard)
        XCTAssertEqual(page.pagesShown, 1)
    }

    /// The UI tests' card page: closed once, or failing once, with launch arguments.
    func testTheTestCardPageCanCloseOrFailOnce() async throws {
        let fake = NoShowTestData.fake()
        let closes = FakeCardSaver(api: fake, options: FakeCardSaver.Options(arguments: ["-fakeCardCancel"]))
        let setup = CardSetup(api: fake, saver: closes, cards: cards)
        let closed = await setup.addCard(for: carlos, remember: true)
        XCTAssertNil(closed)
        XCTAssertNil(setup.failure)
        let then = await setup.addCard(for: carlos, remember: true)
        XCTAssertNotNil(then, "Only the first time")

        cards.forget()
        let fails = FakeCardSaver(api: fake, options: FakeCardSaver.Options(arguments: ["-fakeCardFail"]))
        let failing = CardSetup(api: fake, saver: fails, cards: cards)
        let failed = await failing.addCard(for: carlos, remember: true)
        XCTAssertNil(failed)
        XCTAssertEqual(failing.failure, "The card wasn't added. Try again.")
        let retried = await failing.addCard(for: carlos, remember: true)
        XCTAssertNotNil(retried)
        XCTAssertEqual(FakeCardSaver.Options(arguments: []), FakeCardSaver.Options())
    }
}

// MARK: - Booking with the card

@MainActor
final class NoShowBookingTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private let tokens = InMemorySecretStore()
    private let keychain = InMemorySecretStore()
    private let defaults = TestData.defaults()
    private lazy var cards = SavedCardStore(secrets: keychain, now: { TestData.now })
    private lazy var policies = NoShowPolicyStore(api: api, now: { TestData.now })
    private let carlos = IzzyAPI.BookingTarget.offering(id: TestData.carlosHaircutID)

    private func makeAppointments(api: (any ShopAPI)? = nil) -> AppointmentStore {
        AppointmentStore(api: api ?? self.api, tokens: tokens, scheduler: FakeNotificationScheduler(), defaults: defaults, calendar: AppData.bookingCalendar, now: { TestData.now })
    }

    private func makeSubmitter(api: (any ShopAPI)? = nil, appointments: AppointmentStore? = nil) -> BookingSubmitter {
        BookingSubmitter(api: api ?? self.api, appointments: appointments ?? makeAppointments(api: api), cards: cards, policies: policies)
    }

    private func draft(start: Date = TestData.friday, remember: Bool = true, choice: BookingChoice? = nil) throws -> BookingDraft {
        let offering = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        return BookingDraft(
            plan: BookingPlan(choice: choice ?? .offering(offering), start: start),
            customer: CustomerDetails(name: "Alex", phone: "(442) 555-0123"),
            note: "",
            remember: remember
        )
    }

    func testSendsTheCardAndThePolicyAsShown() async throws {
        api.bookHandler = { _ in TestData.confirmation() }
        let card = NoShowTestData.stored()
        let agreement = IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText)
        let saved = await makeSubmitter().book(try draft(), noShow: agreement)
        XCTAssertNotNil(saved)
        XCTAssertEqual(api.bookings.first?.noShow, agreement)
    }

    /// Booking without protection sends no card, as before.
    func testWithoutProtectionNoCardIsSent() async throws {
        api.bookHandler = { _ in TestData.confirmation() }
        _ = await makeSubmitter().book(try draft())
        XCTAssertNil(api.bookings.first?.noShow)
    }

    /// The card isn't part of "the same booking": a retry with another card (or none) still sends
    /// the same manage token, so a booking that went through is found, not made twice.
    func testTheCardIsntPartOfTheSameBooking() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        let appointments = makeAppointments()
        let first = IzzyAPI.NoShowAgreement(cardToken: .generate(), policyText: NoShowTestData.carlosPolicyText)
        let second = IzzyAPI.NoShowAgreement(cardToken: .generate(), policyText: "Another policy")
        _ = await makeSubmitter(appointments: appointments).book(try draft(), noShow: first)
        _ = await makeSubmitter(appointments: appointments).book(try draft(), noShow: second)
        _ = await makeSubmitter(appointments: appointments).book(try draft())
        XCTAssertEqual(Set(api.bookingTokens).count, 1)
    }

    /// The server needs a card after all (the policy couldn't be checked, say): the policy is asked
    /// again so Review shows the card section, and the client is told to add one.
    func testACardNeededAfterAllShowsThePolicy() async throws {
        api.bookHandler = { _ in throw APIError.cardRequired(message: "Add a card to book this time. You won't be charged now.") }
        api.noShowPolicyHandler = { _ in NoShowTestData.carlosPolicy }
        let submitter = makeSubmitter()
        let saved = await submitter.book(try draft())
        XCTAssertNil(saved)
        XCTAssertEqual(submitter.failure, .cardNeeded("Add a card to book this time. You won't be charged now."))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
        XCTAssertEqual(submitter.failure?.title, "Not booked yet")
        XCTAssertEqual(policies.policy(for: carlos), NoShowTestData.carlosPolicy)
    }

    /// A card the server doesn't know (it was saved in test mode, say) is dropped from this iPhone,
    /// so Review asks for another. A card added since is kept.
    func testAnUnknownCardIsDropped() async throws {
        let card = NoShowTestData.stored()
        cards.save(card, remember: true)
        api.bookHandler = { _ in throw APIError.cardRequired(message: "We couldn't find your saved card. Add it again.") }
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft(), noShow: IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
        XCTAssertEqual(submitter.failure, .cardNeeded("We couldn't find your saved card. Add it again."))
        XCTAssertNil(cards.saved)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])

        let newer = NoShowTestData.stored()
        cards.save(newer, remember: true)
        _ = await submitter.book(try draft(), noShow: IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
        XCTAssertEqual(cards.saved, newer)
    }

    /// The owner changed the fee meanwhile: the new policy is loaded for Review to show, and the
    /// card stays.
    func testAChangedPolicyIsLoadedAgain() async throws {
        let card = NoShowTestData.stored()
        cards.save(card, remember: true)
        var changed = NoShowTestData.carlosPolicy
        changed.policyText = "A new policy."
        api.noShowPolicyHandler = { _ in changed }
        api.bookHandler = { _ in throw APIError.policyChanged(message: "The no-show policy for this booking just changed. Check it and book again.") }
        let submitter = makeSubmitter()
        _ = await submitter.book(try draft(), noShow: IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
        XCTAssertEqual(submitter.failure, .policyChanged("The no-show policy for this booking just changed. Check it and book again."))
        XCTAssertFalse(submitter.failure?.canRetry ?? true)
        XCTAssertEqual(policies.policy(for: carlos), changed)
        XCTAssertEqual(cards.saved, card)
    }

    func testOtherFailuresLeaveTheCardAndThePolicyAlone() async throws {
        let card = NoShowTestData.stored()
        cards.save(card, remember: true)
        api.bookHandler = { _ in throw APIError.slotTaken }
        _ = await makeSubmitter().book(try draft(), noShow: IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
        XCTAssertEqual(cards.saved, card)
        XCTAssertTrue(api.noShowPolicyRequests.isEmpty)
    }

    /// "Remember me" off: the card is forgotten once it's booked, like the name and number. On, it's
    /// kept for next time.
    func testRememberMeOffForgetsTheCardOnceBooked() async throws {
        api.bookHandler = { _ in TestData.confirmation() }
        let card = NoShowTestData.stored()
        cards.save(card, remember: false)
        let agreement = IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText)
        _ = await makeSubmitter().book(try draft(remember: false), noShow: agreement)
        XCTAssertNil(cards.saved)
        XCTAssertNil(keychain.secrets[SavedCardStore.account])

        cards.save(card, remember: true)
        api.bookHandler = { _ in TestData.confirmation(id: "6c9f3d2f-4e5b-4f70-9bac-1d2e3f4a5b6c", token: "token-2") }
        _ = await makeSubmitter().book(try draft(start: TestData.friday.addingTimeInterval(3600)), noShow: agreement)
        XCTAssertEqual(cards.saved, card)
        XCTAssertTrue(cards.isRemembered)
    }

    /// Not booked: the card stays for the next try, whatever "Remember me" says.
    func testAFailedBookingKeepsTheCardForTheNextTry() async throws {
        api.bookHandler = { _ in throw APIError.offline }
        let card = NoShowTestData.stored()
        cards.save(card, remember: false)
        _ = await makeSubmitter().book(try draft(remember: false), noShow: IzzyAPI.NoShowAgreement(cardToken: card.token, policyText: NoShowTestData.carlosPolicyText))
        XCTAssertEqual(cards.saved, card)
    }

    /// The whole thing against the in-memory server: the policy, a card from the test card page,
    /// the booking with its card on file and fee, and the next booking with the same card.
    func testBookingWithACardOnTheInMemoryServer() async throws {
        let fake = NoShowTestData.fake()
        let fakePolicies = NoShowPolicyStore(api: fake, now: { TestData.now })
        let appointments = makeAppointments(api: fake)
        let submitter = BookingSubmitter(api: fake, appointments: appointments, cards: cards, policies: fakePolicies)
        let tomorrow = TestData.calendarDay(2026, 10, 29)
        let open = try await fake.availability(IzzyAPI.AvailabilityQuery(target: carlos, from: tomorrow, days: 1)).slots(on: tomorrow)
        let start = try XCTUnwrap(open.first?.start)
        let booking = try draft(start: start)

        await fakePolicies.load(carlos)
        var requirement = NoShowRequirement(entry: fakePolicies.entry(for: carlos), cards: cards, start: start)
        XCTAssertEqual(requirement, .needsCard(NoShowTestData.carlosPolicy, unusable: nil), "Book waits for a card")
        // Booking anyway (an older app) is turned down.
        _ = await submitter.book(booking)
        XCTAssertEqual(submitter.failure, .cardNeeded("Add a card to book this time. You won't be charged now."))

        let addedResult = await CardSetup(api: fake, saver: FakeCardSaver(api: fake), cards: cards).addCard(for: carlos, remember: true)
        let added = try XCTUnwrap(addedResult)
        requirement = NoShowRequirement(entry: fakePolicies.entry(for: carlos), cards: cards, start: start)
        XCTAssertEqual(requirement, .ready(NoShowTestData.carlosPolicy, card: added))
        let savedResult = await submitter.book(booking, noShow: requirement.agreement)
        let saved = try XCTUnwrap(savedResult)
        XCTAssertEqual(saved.snapshot.card, IzzyAPI.CardOnFile(brand: "visa", last4: "4242"))
        XCTAssertEqual(saved.snapshot.noShowFee, IzzyAPI.NoShowFee(amountCents: 4_500, fullPrice: true, lateCancelWindowMinutes: 60))
        XCTAssertEqual(NoShowCopy.cardOnFileLine(saved.snapshot), "Card on file for no-shows and late cancellations: Visa •••• 4242")

        // The next booking uses the same card straight away.
        let later = try XCTUnwrap(open.last?.start)
        let next = NoShowRequirement(entry: fakePolicies.entry(for: carlos), cards: cards, start: later)
        XCTAssertEqual(next.card, added)
        let againResult = await submitter.book(try draft(start: later), noShow: next.agreement)
        let again = try XCTUnwrap(againResult)
        XCTAssertEqual(again.snapshot.card?.last4, "4242")
        XCTAssertEqual(fake.bookingsMade, 2)
    }
}

// MARK: - Cancelling inside the window

@MainActor
final class AppointmentCancellingTests: XCTestCase {
    private let api = ScriptedShopAPI()
    private let calendar = AppData.bookingCalendar
    private var now = TestData.now

    private func makeStore(holding appointment: IzzyAPI.Appointment) -> AppointmentStore {
        let store = AppointmentStore(
            api: api, tokens: InMemorySecretStore(), scheduler: FakeNotificationScheduler(), defaults: TestData.defaults(),
            calendar: calendar, now: { [unowned self] in self.now }
        )
        store.add(IzzyAPI.BookingConfirmation(appointment: appointment, manageToken: "t1"), remind: false)
        return store
    }

    private func makeFlow(_ store: AppointmentStore, id: String = TestData.appointment().id) -> AppointmentCancelling {
        AppointmentCancelling(appointmentID: id, store: store, calendar: calendar, now: { [unowned self] in self.now }, pauseBeforeAskingAgain: .zero)
    }

    private func cancelled(_ id: String) -> IzzyAPI.Appointment {
        TestData.appointment(id: id, status: .cancelled, cancelledBy: .customer)
    }

    func testWithoutACardItAsksAsBefore() async throws {
        let store = makeStore(holding: TestData.appointment())
        api.cancelHandler = { [unowned self] id, _ in cancelled(id) }
        let flow = makeFlow(store)
        flow.ask()
        let question = try XCTUnwrap(flow.question)
        XCTAssertEqual(question.message, "Haircut with Carlos, \(calendar.dateTimeLabel(for: TestData.friday)). The shop sees it right away.")
        XCTAssertFalse(question.warnsOfFee)
        let outcome = await flow.confirm(question)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(api.cancellations.map(\.acceptLateCancelFee), [false])
        XCTAssertNil(flow.question)
        XCTAssertFalse(flow.isCancelling)
        XCTAssertEqual(store.appointment(withID: TestData.appointment().id)?.status, .cancelled)
    }

    /// With a card on file, more than an hour ahead: free, and it says so.
    func testOutsideTheWindowItSaysCancellingIsFree() async throws {
        let store = makeStore(holding: NoShowTestData.appointment(start: TestData.friday))
        let flow = makeFlow(store)
        flow.ask()
        XCTAssertEqual(
            flow.question,
            CancelQuestion(message: "Haircut with Carlos, \(calendar.dateTimeLabel(for: TestData.friday)). The shop sees it right away. Cancelling now is free.", warnsOfFee: false)
        )
        flow.dismissQuestion()
        XCTAssertNil(flow.question)
    }

    /// Less than an hour before: the warning first, and a yes agrees to the fee.
    func testInsideTheWindowItWarnsFirst() async throws {
        let start = TestData.now.addingTimeInterval(30 * 60)
        let store = makeStore(holding: NoShowTestData.appointment(start: start))
        api.cancelHandler = { [unowned self] id, _ in cancelled(id) }
        let flow = makeFlow(store)
        flow.ask()
        let question = try XCTUnwrap(flow.question)
        XCTAssertEqual(question.message, "\(NoShowTestData.lateCancelWarning) Haircut with Carlos, \(calendar.dateTimeLabel(for: start)).")
        XCTAssertTrue(question.warnsOfFee)
        XCTAssertEqual(CancelQuestion.confirmButton, "Cancel appointment")
        XCTAssertEqual(CancelQuestion.keepButton, "Keep appointment")
        let outcome = await flow.confirm(question)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(api.cancellations.map(\.acceptLateCancelFee), [true])
    }

    /// The question is worked out when it's asked: the same booking an hour and a half ahead is free,
    /// then half an hour ahead it warns.
    func testTheQuestionIsWorkedOutWhenAsked() throws {
        let start = TestData.now.addingTimeInterval(90 * 60)
        let store = makeStore(holding: NoShowTestData.appointment(start: start))
        let flow = makeFlow(store)
        flow.ask()
        XCTAssertEqual(flow.question?.warnsOfFee, false)
        now = now.addingTimeInterval(60 * 60)
        flow.ask()
        XCTAssertEqual(flow.question?.warnsOfFee, true)
    }

    /// The phone thought it was free, but by the server's clock it's inside the window: nothing
    /// changed, and the client is asked again with the server's warning. Only that yes agrees.
    func testWhenTheServerSaysItsLateItAsksAgain() async throws {
        let start = TestData.now.addingTimeInterval(61 * 60)
        let store = makeStore(holding: NoShowTestData.appointment(start: start))
        let warning = NoShowTestData.lateCancelWarning
        api.cancelHandler = { [unowned self] id, _ in
            guard api.cancellations.last?.acceptLateCancelFee == true else { throw APIError.lateCancelFee(message: warning) }
            return cancelled(id)
        }
        let flow = makeFlow(store)
        flow.ask()
        let free = try XCTUnwrap(flow.question)
        XCTAssertFalse(free.warnsOfFee)
        let first = await flow.confirm(free)
        XCTAssertEqual(first, .askedAgain)
        let again = try XCTUnwrap(flow.question)
        XCTAssertEqual(again.message, "\(warning) Haircut with Carlos, \(calendar.dateTimeLabel(for: start)).")
        XCTAssertTrue(again.warnsOfFee)
        XCTAssertNil(flow.error)
        XCTAssertEqual(store.appointment(withID: TestData.appointment().id)?.status, .booked, "Nothing changed yet")

        let second = await flow.confirm(again)
        XCTAssertEqual(second, .cancelled)
        XCTAssertEqual(api.cancellations.map(\.acceptLateCancelFee), [false, true])
        XCTAssertEqual(store.appointment(withID: TestData.appointment().id)?.status, .cancelled)
    }

    /// The client said no to the second question: nothing is cancelled.
    func testKeepingItAfterTheWarningCancelsNothing() async throws {
        let start = TestData.now.addingTimeInterval(61 * 60)
        let store = makeStore(holding: NoShowTestData.appointment(start: start))
        api.cancelHandler = { _, _ in throw APIError.lateCancelFee(message: NoShowTestData.lateCancelWarning) }
        let flow = makeFlow(store)
        flow.ask()
        _ = await flow.confirm(try XCTUnwrap(flow.question))
        flow.dismissQuestion()
        XCTAssertNil(flow.question)
        XCTAssertEqual(api.cancellations.count, 1)
        XCTAssertEqual(store.appointment(withID: TestData.appointment().id)?.status, .booked)
    }

    func testAFailureSaysWhy() async throws {
        let store = makeStore(holding: TestData.appointment())
        api.cancelHandler = { _, _ in throw APIError.offline }
        let flow = makeFlow(store)
        flow.ask()
        let outcome = await flow.confirm(try XCTUnwrap(flow.question))
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(flow.error, APIError.offline.userMessage)
        flow.clearError()
        XCTAssertNil(flow.error)

        // A server that asks again after a yes: an error, never a loop of questions.
        api.cancelHandler = { _, _ in throw APIError.lateCancelFee(message: NoShowTestData.lateCancelWarning) }
        let afterYes = await flow.confirm(CancelQuestion(message: "Warned", warnsOfFee: true))
        XCTAssertEqual(afterYes, .failed)
        XCTAssertEqual(flow.error, NoShowTestData.lateCancelWarning)
        XCTAssertNil(flow.question)
    }

    func testAnAppointmentThatIsntThereAsksNothing() async {
        let store = makeStore(holding: TestData.appointment())
        let flow = makeFlow(store, id: "00000000-0000-4000-8000-000000000000")
        flow.ask()
        XCTAssertNil(flow.question)
        let outcome = await flow.confirm(CancelQuestion(message: "", warnsOfFee: false))
        XCTAssertEqual(outcome, .ignored)
        XCTAssertTrue(api.cancellations.isEmpty)
    }

    /// The UI tests' booking that starts soon with a card on file: cancelling it now warns first.
    func testTheSeededBookingStartingSoonWarns() throws {
        let fake = NoShowTestData.fake(protection: false)
        let seeded = try XCTUnwrap(fake.seedBookingStartingSoonWithCard())
        XCTAssertEqual(seeded.appointment.card, IzzyAPI.CardOnFile(brand: "visa", last4: "4242"))
        XCTAssertEqual(seeded.appointment.noShowFee?.amountCents, 4_500)
        XCTAssertEqual(seeded.appointment.lateCancelWarning(at: TestData.now), NoShowTestData.lateCancelWarning)
    }
}

// MARK: - The words

final class NoShowCopyTests: XCTestCase {
    func testTheCardOnAnAppointment() {
        var appointment = NoShowTestData.appointment(start: TestData.friday)
        XCTAssertEqual(NoShowCopy.cardOnFileLine(appointment), "Card on file for no-shows and late cancellations: Visa •••• 4242")
        XCTAssertNil(NoShowCopy.feeChargedLine(appointment))
        XCTAssertEqual(
            NoShowCopy.bookedCardDetail(appointment),
            "Nothing is charged now. If you don't come, or cancel less than 1 hour before, the shop may charge $45."
        )

        // A policy without late cancellations.
        appointment.noShowFee = IzzyAPI.NoShowFee(amountCents: 2_000)
        XCTAssertEqual(NoShowCopy.cardOnFileLine(appointment), "Card on file for no-shows: Visa •••• 4242")
        XCTAssertEqual(NoShowCopy.bookedCardDetail(appointment), "Nothing is charged now. If you don't come, the shop may charge $20.")

        // VoiceOver hears "ending in", not each dot.
        XCTAssertEqual(NoShowCopy.spokenCard(IzzyAPI.CardOnFile(brand: "amex", last4: "0005")), "American Express ending in 0005")
        XCTAssertEqual(NoShowCopy.spokenCardOnFileLine(appointment), "Card on file for no-shows: Visa ending in 4242")

        // No card on file: nothing to say.
        let plain = TestData.appointment()
        XCTAssertNil(NoShowCopy.cardOnFileLine(plain))
        XCTAssertNil(NoShowCopy.feeChargedLine(plain))
        XCTAssertNil(NoShowCopy.bookedCardDetail(plain))
        XCTAssertNil(NoShowCopy.spokenCardOnFileLine(plain))
    }

    /// Only a fee Stripe charged is said to be charged.
    func testAChargedFee() {
        var appointment = NoShowTestData.appointment(start: TestData.monday)
        for status in [IzzyAPI.NoShowFeeStatus.none, .pending, .declined, .needsAction] {
            appointment.noShowFee = IzzyAPI.NoShowFee(amountCents: 4_500, status: status, reason: .noShow)
            XCTAssertNil(NoShowCopy.feeChargedLine(appointment), "\(status)")
        }
        appointment.noShowFee = IzzyAPI.NoShowFee(amountCents: 4_500, status: .charged, reason: .noShow)
        XCTAssertEqual(NoShowCopy.feeChargedLine(appointment), "No-show fee charged: $45")
        appointment.noShowFee = IzzyAPI.NoShowFee(amountCents: 4_500, status: .charged, reason: .lateCancel)
        XCTAssertEqual(NoShowCopy.feeChargedLine(appointment), "Late cancellation fee charged: $45")
    }

    func testACardThatCantHoldTheBooking() {
        let expired = NoShowTestData.stored(NoShowTestData.card(expMonth: 9, expYear: 2026))
        XCTAssertEqual(NoShowCopy.unusableCardNote(expired, now: TestData.now, timeZone: AppData.shop.timeZone), "Your Visa •••• 4242 has expired. Add another card.")
        let october = NoShowTestData.stored(NoShowTestData.card(expMonth: 10, expYear: 2026))
        XCTAssertEqual(NoShowCopy.unusableCardNote(october, now: TestData.now, timeZone: AppData.shop.timeZone), "Your Visa •••• 4242 expires before this appointment. Add another card.")
        XCTAssertEqual(NoShowCopy.cardAdded(october), "Visa •••• 4242 added.")
    }

    func testRememberMe() {
        XCTAssertEqual(NoShowCopy.rememberNote(cardNeeded: false), "Your name and number fill in next time.")
        XCTAssertEqual(NoShowCopy.rememberNote(cardNeeded: true), "Your name and number fill in next time, and your card stays saved.")
    }
}

// MARK: - The in-memory server, with protection on

/// `FakeShopAPI` with `-fakeNoShowProtection` answers like the shop's server with Stripe set up and
/// protection on at its starting settings.
@MainActor
final class FakeShopAPINoShowTests: XCTestCase {
    private let carlos = IzzyAPI.BookingTarget.offering(id: TestData.carlosHaircutID)
    private let tomorrow = TestData.calendarDay(2026, 10, 29)

    private func customer(_ phone: String = "4425550123") -> IzzyAPI.NewCustomer {
        IzzyAPI.NewCustomer(name: "Test", phone: phone)
    }

    private func firstStart(_ fake: FakeShopAPI, _ target: IzzyAPI.BookingTarget, day: LocalDate? = nil) async throws -> Date {
        let date = day ?? tomorrow
        let open = try await fake.availability(IzzyAPI.AvailabilityQuery(target: target, from: date, days: 1)).slots(on: date)
        return try XCTUnwrap(open.first?.start)
    }

    /// Saves a card the way the app does: the card page, then the server keeps it under `token`.
    private func saveCard(_ fake: FakeShopAPI, _ card: IzzyAPI.SavedCard? = nil, token: IzzyAPI.CardToken = .generate()) async throws -> IzzyAPI.CardToken {
        let checkout = try await fake.startCardCheckout(for: carlos, token: token)
        fake.completeCardCheckout(sessionId: checkout.sessionId, card: card ?? fake.sampleCard)
        _ = try await fake.saveCard(sessionId: checkout.sessionId, token: token)
        return token
    }

    func testTheLaunchArgumentsTurnItOn() {
        XCTAssertFalse(FakeShopAPI.Options(arguments: []).noShowSettings.enabled, "Off, as the server starts")
        let on = FakeShopAPI.Options(arguments: ["-fakeNoShowProtection"]).noShowSettings
        XCTAssertEqual(on, IzzyAPI.NoShowSettings(enabled: true))
        let noLate = FakeShopAPI.Options(arguments: ["-fakeNoShowProtection", "-fakeNoLateCancel"]).noShowSettings
        XCTAssertEqual(noLate, IzzyAPI.NoShowSettings(enabled: true, lateCancelEnabled: false))
    }

    /// The policy, the window and the warning, as the server words them for Carlos's $45 haircut.
    func testThePolicyForOneBarber() async throws {
        let policy = try await NoShowTestData.fake().noShowPolicy(for: carlos)
        XCTAssertEqual(policy, NoShowTestData.carlosPolicy)
    }

    /// The server's own answer for "any barber" Haircut & Beard (server/test/fixtures/contract/no-show-policy.json).
    func testAnyBarberGivesTheRangeOfTheirFees() async throws {
        let fixture = #"{"required":true,"minFeeCents":5500,"maxFeeCents":6000,"policyText":"No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $55–$60 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free.","lateCancelWindowMinutes":60,"warning":{"title":"Full Service Cancellation & No-Show Fee","message":"Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($55–$60). Cancelling in the app more than 1 hour before is free."}}"#
        let server = try IzzyAPI.makeDecoder().decode(IzzyAPI.NoShowPolicy.self, from: Data(fixture.utf8))
        let policy = try await NoShowTestData.fake().noShowPolicy(for: .anyBarber(serviceId: "haircut-and-beard"))
        XCTAssertEqual(policy, server)
        XCTAssertEqual(policy.feeLabel, "$55–$60")
    }

    /// Items included with a cut have no fee, so no card (server/test/fixtures/contract/no-show-policy-not-required.json).
    func testAnItemWithoutAFeeNeedsNoCard() async throws {
        let lineUp = try XCTUnwrap(AppData.catalog.offerings.first { $0.price.kind == .includedWithCut })
        let fake = NoShowTestData.fake()
        let policy = try await fake.noShowPolicy(for: .offering(lineUp))
        XCTAssertEqual(policy, .notRequired)
        do {
            _ = try await fake.startCardCheckout(for: .offering(lineUp), token: .generate())
            XCTFail("No card page for a booking that needs no card")
        } catch {
            XCTAssertEqual(error as? APIError, .server(code: IzzyAPI.ErrorCode.invalidRequest, message: "This booking doesn't need a card. Go ahead and book.", status: 400))
        }
    }

    func testLateCancellationsOff() async throws {
        let policy = try await NoShowTestData.fake { $0.noShowSettings.lateCancelEnabled = false }.noShowPolicy(for: carlos)
        XCTAssertNil(policy.lateCancelWindowMinutes)
        XCTAssertEqual(policy.policyText, "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $45 (100% of the service) to this card. Cancelling in the app before your appointment is free.")
        XCTAssertEqual(policy.warning, IzzyAPI.NoShowWarning(title: "No-Show Fee", message: "Not showing up is charged the full service price ($45). Cancelling in the app before your appointment is free."))
    }

    /// Booking needs a usable card and today's policy, checked in the server's order, with its words.
    func testBookingNeedsAUsableCardAndTodaysPolicy() async throws {
        let fake = NoShowTestData.fake()
        let start = try await firstStart(fake, carlos)
        func book(_ agreement: IzzyAPI.NoShowAgreement?) async -> APIError? {
            do {
                _ = try await fake.book(IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: agreement), token: .generate())
                return nil
            } catch {
                return error as? APIError
            }
        }
        let text = NoShowTestData.carlosPolicyText
        let noCard = await book(nil)
        XCTAssertEqual(noCard, .cardRequired(message: "Add a card to book this time. You won't be charged now."))
        let unknown = await book(IzzyAPI.NoShowAgreement(cardToken: .generate(), policyText: text))
        XCTAssertEqual(unknown, .cardRequired(message: "We couldn't find your saved card. Add it again."))
        let october = try await saveCard(fake, NoShowTestData.card(expMonth: 10, expYear: 2026))
        let nextMonth = try await firstStart(fake, carlos, day: TestData.calendarDay(2026, 11, 3))
        do {
            _ = try await fake.book(IzzyAPI.NewAppointment(target: carlos, start: nextMonth, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: october, policyText: text)), token: .generate())
            XCTFail("The card expires before the appointment")
        } catch {
            XCTAssertEqual(error as? APIError, .cardRequired(message: "That card expires before your appointment. Add another card."))
        }
        let good = try await saveCard(fake)
        let oldPolicy = await book(IzzyAPI.NoShowAgreement(cardToken: good, policyText: "An older policy."))
        XCTAssertEqual(oldPolicy, .policyChanged(message: "The no-show policy for this booking just changed. Check it and book again."))
        XCTAssertEqual(fake.bookingsMade, 0)

        let confirmation = try await fake.book(
            IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: good, policyText: text)),
            token: .generate()
        )
        let appointment = confirmation.appointment
        XCTAssertEqual(appointment.card, IzzyAPI.CardOnFile(brand: "visa", last4: "4242"))
        XCTAssertEqual(appointment.noShowFee, IzzyAPI.NoShowFee(amountCents: 4_500, fullPrice: true, lateCancelWindowMinutes: 60))
        XCTAssertNil(appointment.noShowFee?.reason, "Booked: no fee applies yet")
        let found = try await fake.appointment(id: appointment.id, manageToken: confirmation.manageToken)
        XCTAssertEqual(found, appointment)
    }

    /// The time rules come first, as on the server: a time that's too soon says so even without a card.
    func testTheTimeRulesComeFirst() async throws {
        let fake = NoShowTestData.fake()
        do {
            _ = try await fake.book(IzzyAPI.NewAppointment(target: carlos, start: TestData.now.addingTimeInterval(10 * 60), customer: customer()), token: .generate())
            XCTFail("Too soon")
        } catch {
            XCTAssertEqual(error as? APIError, .tooSoon)
        }
    }

    /// A retry with the same manage token is answered before the card is checked: the card isn't
    /// part of "the same booking".
    func testARetryIsAnsweredBeforeTheCard() async throws {
        let fake = NoShowTestData.fake { $0.loseBookingResponseOnce = true }
        let start = try await firstStart(fake, carlos)
        let card = try await saveCard(fake)
        let manageToken = IzzyAPI.ManageToken.generate()
        let request = IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: NoShowTestData.carlosPolicyText))
        do {
            _ = try await fake.book(request, token: manageToken)
            XCTFail("The answer is lost")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        var withoutCard = request
        withoutCard.noShow = nil
        let retried = try await fake.book(withoutCard, token: manageToken)
        XCTAssertEqual(retried.appointment.card?.last4, "4242", "The booking that went through, with its card")
        XCTAssertEqual(fake.bookingsMade, 1)
    }

    /// "Any barber" stores the fee of the barber it lands with.
    func testAnyBarberKeepsTheFeeOfTheBarberItLandsWith() async throws {
        let fake = NoShowTestData.fake()
        let target = IzzyAPI.BookingTarget.anyBarber(serviceId: "haircut-and-beard")
        let policy = try await fake.noShowPolicy(for: target)
        let start = try await firstStart(fake, target)
        let card = try await saveCard(fake)
        let booked = try await fake.book(
            IzzyAPI.NewAppointment(target: target, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: try XCTUnwrap(policy.policyText))),
            token: .generate()
        )
        let offering = try XCTUnwrap(AppData.catalog.offering(withID: booked.appointment.offeringId))
        XCTAssertEqual(booked.appointment.noShowFee?.amountCents, offering.price.cents)
        XCTAssertEqual(booked.appointment.noShowFee?.fullPrice, true)
    }

    /// The owner changes the fee in the Business app: the policy changes, and a booking sent with
    /// the old one is turned down.
    func testTheOwnerChangingTheFee() async throws {
        let fake = NoShowTestData.fake()
        let before = try await fake.noShowPolicy(for: carlos)
        var settings = fake.noShowSettings
        settings.feeMode = .flat
        settings.flatCents = 2_000
        fake.noShowSettings = settings
        let after = try await fake.noShowPolicy(for: carlos)
        XCTAssertNotEqual(after.policyText, before.policyText)
        XCTAssertEqual(after.minFeeCents, 2_000)
        XCTAssertEqual(after.warning?.title, "Late Cancellation & No-Show Fee")
        let card = try await saveCard(fake)
        let start = try await firstStart(fake, carlos)
        do {
            _ = try await fake.book(IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: try XCTUnwrap(before.policyText))), token: .generate())
            XCTFail("The policy changed")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, IzzyAPI.ErrorCode.policyChanged)
        }
        let booked = try await fake.book(
            IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: try XCTUnwrap(after.policyText))),
            token: .generate()
        )
        XCTAssertEqual(booked.appointment.noShowFee?.amountCents, 2_000)
        XCTAssertEqual(booked.appointment.noShowFee?.fullPrice, false)

        // Turned off: no card needed, and a card sent anyway is ignored.
        settings.enabled = false
        fake.noShowSettings = settings
        let off = try await fake.noShowPolicy(for: carlos)
        XCTAssertEqual(off, .notRequired)
    }

    /// Saving a card, as the server checks it: only the phone that started the session (it has the
    /// token), only once Stripe's page is done, the same card again after a lost answer, one card per
    /// token, and never an expired card.
    func testSavingACard() async throws {
        let fake = NoShowTestData.fake()
        let token = IzzyAPI.CardToken.generate()
        let checkout = try await fake.startCardCheckout(for: carlos, token: token)
        XCTAssertTrue(checkout.sessionId.hasPrefix("cs_test_"))
        XCTAssertEqual(checkout.url.host, "checkout.stripe.com")
        func save(_ sessionId: String, _ token: IzzyAPI.CardToken) async -> Result<IzzyAPI.SavedCard, APIError> {
            do {
                return .success(try await fake.saveCard(sessionId: sessionId, token: token))
            } catch {
                return .failure(error as? APIError ?? .offline)
            }
        }
        let notDone = await save(checkout.sessionId, token)
        XCTAssertEqual(notDone, .failure(.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "The card wasn't added. Add it again.", status: 400)))
        fake.completeCardCheckout(sessionId: checkout.sessionId, card: fake.sampleCard)
        let someoneElse = await save(checkout.sessionId, .generate())
        XCTAssertEqual(someoneElse, .failure(.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that card. Add it again.", status: 404)))
        let notASession = await save("pi_123", token)
        XCTAssertEqual(notASession, .failure(.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That isn't a Stripe Checkout session id.", status: 400)))
        let saved = await save(checkout.sessionId, token)
        XCTAssertEqual(saved, .success(fake.sampleCard))
        let again = await save(checkout.sessionId, token)
        XCTAssertEqual(again, .success(fake.sampleCard), "After a lost answer: the same card")

        let other = try await fake.startCardCheckout(for: carlos, token: .generate())
        fake.completeCardCheckout(sessionId: other.sessionId, card: fake.sampleCard)
        let reused = await save(other.sessionId, token)
        XCTAssertEqual(reused, .failure(.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That card token was already used for another card.", status: 400)))

        let expiredToken = IzzyAPI.CardToken.generate()
        let expiredCheckout = try await fake.startCardCheckout(for: carlos, token: expiredToken)
        fake.completeCardCheckout(sessionId: expiredCheckout.sessionId, card: NoShowTestData.card(expMonth: 9, expYear: 2026))
        let expired = await save(expiredCheckout.sessionId, expiredToken)
        XCTAssertEqual(expired, .failure(.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That card has expired. Add another card.", status: 400)))
    }

    /// Offline is offline for no-show protection too.
    func testOffline() async {
        let fake = NoShowTestData.fake { $0.offline = true }
        do {
            _ = try await fake.noShowPolicy(for: carlos)
            XCTFail("Offline")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
    }

    /// Cancelling a booking it made with a card more than an hour ahead: free, and the time it was
    /// cancelled is kept (the fake's cancellations inside the window are tested in FakeShopAPITests).
    func testCancellingABookingItMadeWithACard() async throws {
        let fake = NoShowTestData.fake()
        let start = try await firstStart(fake, carlos)
        let card = try await saveCard(fake)
        let booked = try await fake.book(
            IzzyAPI.NewAppointment(target: carlos, start: start, customer: customer(), noShow: IzzyAPI.NoShowAgreement(cardToken: card, policyText: NoShowTestData.carlosPolicyText)),
            token: .generate()
        )
        // Tomorrow is more than an hour away: free.
        let cancelled = try await fake.cancelAppointment(id: booked.appointment.id, manageToken: booked.manageToken)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.noShowFee?.customerCancelledAt, TestData.now)
        XCTAssertNil(cancelled.noShowFee?.reason)
    }
}
