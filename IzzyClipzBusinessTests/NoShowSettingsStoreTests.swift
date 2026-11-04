import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Settings → No-show protection: loading, editing (the fee as a percentage or a flat amount, late
/// cancellations and their window), what clients see, and saving only what changed, with the
/// server's answers and errors.
@MainActor
final class NoShowSettingsStoreTests: XCTestCase {
    private var harness: Harness!
    private var api: ScriptedAPI!

    override func setUp() async throws {
        harness = Harness()
        api = ScriptedAPI(base: harness.api)
    }

    private func makeStore() -> NoShowSettingsStore {
        NoShowSettingsStore(api: api, catalog: .izzyClipz)
    }

    private func loadedStore() async -> NoShowSettingsStore {
        let store = makeStore()
        await store.refresh()
        return store
    }

    // MARK: Loading

    func testLoadsTheServersSettingsOffAtTheFullPrice() async {
        let store = makeStore()
        XCTAssertEqual(store.summary, "Loading…")
        XCTAssertFalse(store.hasChanges, "nothing to save before it's loaded")
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.saved, .default)
        XCTAssertEqual(store.draft, NoShowSettingsDraft(.default))
        XCTAssertEqual(store.draft.flatText, "20")
        XCTAssertFalse(store.draft.enabled)
        XCTAssertEqual(store.draft.feeMode, .percent)
        XCTAssertEqual(store.draft.percent, 100)
        XCTAssertTrue(store.draft.lateCancelEnabled)
        XCTAssertEqual(store.draft.lateCancelWindowMinutes, 60)
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.summary, "Off: clients book online without a card")
        XCTAssertEqual(harness.server.calls.last, "noShowSettings")
    }

    func testAFirstLoadThatFailsSaysSoAndALaterOneKeepsWhatsShown() async {
        harness.server.options.offline = true
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.loadState, .failed(APIError.offline.userMessage))
        XCTAssertNil(store.saved)
        XCTAssertEqual(store.summary, "Couldn't load. Open to try again.")
        harness.server.options.offline = false
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded)
        harness.server.options.offline = true
        await store.refresh()
        XCTAssertEqual(store.loadState, .loaded, "the settings stay on screen")
        XCTAssertEqual(store.refreshError, APIError.offline.userMessage)
        harness.server.options.offline = false
        await store.refresh()
        XCTAssertNil(store.refreshError)
    }

    func testARefreshKeepsChangesOnScreenButPicksUpTheServersOtherwise() async throws {
        let store = await loadedStore()
        // Changed on another iPhone.
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 120))
        await store.refresh()
        XCTAssertEqual(store.draft.lateCancelWindowMinutes, 120, "no changes on screen: the server's settings show")
        store.draft.enabled = true
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(percent: 80))
        await store.refresh()
        XCTAssertTrue(store.draft.enabled, "the owner's change stays")
        XCTAssertEqual(store.draft.percent, 100, "what's on screen isn't replaced while it has changes")
        XCTAssertEqual(store.saved?.percent, 80)
        XCTAssertTrue(store.hasChanges)
    }

    func testASlowLoadNeverReplacesWhatASaveStored() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        api.noShowSettingsHandler = { [base = api.base] in
            let old = try await base.noShowSettings()
            await gate.wait()
            return old
        }
        let slow = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        store.draft.enabled = true
        let saved = await store.save()
        XCTAssertTrue(saved)
        await gate.open()
        await slow.value
        XCTAssertEqual(store.saved?.enabled, true, "the older answer was dropped")
        XCTAssertTrue(store.draft.enabled)
    }

    func testALoadThatStartedWhileSavingNeverReplacesWhatTheSaveStored() async throws {
        let store = await loadedStore()
        let saveGate = AsyncGate()
        let loadGate = AsyncGate()
        api.updateNoShowSettingsHandler = { [base = api.base] update in
            await saveGate.wait()
            return try await base.updateNoShowSettings(update)
        }
        store.draft.enabled = true
        let saving = Task { await store.save() }
        try await Task.sleep(for: .milliseconds(50))
        // A pull to refresh while saving, which the server answers before it takes the change.
        let before = try await api.base.noShowSettings()
        api.noShowSettingsHandler = {
            await loadGate.wait()
            return before
        }
        let loading = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        await saveGate.open()
        let saved = await saving.value
        XCTAssertTrue(saved)
        await loadGate.open()
        await loading.value
        XCTAssertEqual(store.saved?.enabled, true, "the older answer was dropped")
        XCTAssertTrue(store.draft.enabled)
        XCTAssertFalse(store.hasChanges, "nothing left to save")
        XCTAssertTrue(store.justSaved)
    }

    // MARK: Editing

    func testChangesAreChangesOnlyWhenTheyDifferFromTheServers() async {
        let store = await loadedStore()
        store.draft.flatText = "20.00"
        XCTAssertFalse(store.hasChanges, "$20.00 is the saved $20")
        store.draft.flatText = "20.5"
        XCTAssertTrue(store.hasChanges)
        store.draft.flatText = "20"
        store.draft.enabled = true
        XCTAssertTrue(store.hasChanges)
        store.draft.enabled = false
        XCTAssertFalse(store.hasChanges)
    }

    func testThePercentageStepsBy5From10To100() async throws {
        let store = await loadedStore()
        XCTAssertEqual(store.percentLabel, "100% of the service (the full price)")
        XCTAssertFalse(store.canIncreasePercent)
        store.increasePercent()
        XCTAssertEqual(store.draft.percent, 100)
        store.decreasePercent()
        XCTAssertEqual(store.draft.percent, 95)
        XCTAssertEqual(store.percentLabel, "95% of the service")
        for _ in 0..<20 { store.decreasePercent() }
        XCTAssertEqual(store.draft.percent, 10, "never under 10% with the stepper")
        XCTAssertFalse(store.canDecreasePercent)
        store.increasePercent()
        XCTAssertEqual(store.draft.percent, 15)
        // Set elsewhere (the server takes 1–100): the stepper goes to the next step.
        store.draft.percent = 12
        store.decreasePercent()
        XCTAssertEqual(store.draft.percent, 10)
        store.draft.percent = 12
        store.increasePercent()
        XCTAssertEqual(store.draft.percent, 15)
        store.draft.percent = 7
        XCTAssertFalse(store.canDecreasePercent)
        store.increasePercent()
        XCTAssertEqual(store.draft.percent, 10)
        store.draft.percent = 97
        store.increasePercent()
        XCTAssertEqual(store.draft.percent, 100)
    }

    func testAFlatAmountMustBeAnAmountTheServerTakes() async {
        let store = await loadedStore()
        store.draft.feeMode = .flat
        XCTAssertNil(store.problem, "$20 to start")
        for (typed, problem) in [
            ("", "Enter the flat fee in dollars, like 20 or 17.50."),
            ("abc", "Enter the flat fee in dollars, like 20 or 17.50."),
            ("12.345", "Enter the flat fee in dollars, like 20 or 17.50."),
            ("0.49", "Pick a flat fee from $0.50 to $500."),
            ("500.01", "Pick a flat fee from $0.50 to $500."),
            ("0.50", nil),
            ("$25", nil),
            ("500", nil),
        ] as [(String, String?)] {
            store.draft.flatText = typed
            XCTAssertEqual(store.problem, problem, typed)
        }
        // An amount that can't be read only matters while the fee is a flat amount.
        store.draft.flatText = "abc"
        store.draft.feeMode = .percent
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.draft.settings(keeping: .default)?.flatCents, 2_000, "the saved amount is kept")
    }

    func testTheWindowChoicesIncludeOneSetElsewhere() async throws {
        let store = await loadedStore()
        XCTAssertEqual(store.windowChoices, [30, 60, 120, 180, 240, 360, 720, 1_440, 2_880])
        XCTAssertEqual(store.windowChoices.map { IzzyAPI.NoShowRule.windowLabel(minutes: $0) }, [
            "30 minutes", "1 hour", "2 hours", "3 hours", "4 hours", "6 hours", "12 hours", "24 hours", "48 hours",
        ])
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 90))
        await store.refresh()
        XCTAssertEqual(store.windowChoices, [30, 60, 90, 120, 180, 240, 360, 720, 1_440, 2_880])
        store.draft.lateCancelWindowMinutes = 20
        XCTAssertEqual(store.problem, "Pick a late-cancellation window from 30 minutes to 48 hours.")
    }

    // MARK: What it looks like

    func testTheExampleAndWhatClientsSeeAtTheFullPrice() async {
        let store = await loadedStore()
        store.draft.enabled = true
        XCTAssertEqual(store.exampleItems.map(\.name), ["Haircut", "Hot Lather Shave"], "the owner's haircut and the cheapest item")
        XCTAssertEqual(store.examples, ["A $40 haircut: $40", "A $5 hot lather shave: $5"])
        XCTAssertEqual(store.clientWarning, IzzyAPI.NoShowWarning(
            title: "Full Service Cancellation & No-Show Fee",
            message: "Cancelling less than 1 hour before your appointment, or not showing up, is charged the full service price ($40). Cancelling in the app more than 1 hour before is free."
        ))
        XCTAssertEqual(
            store.clientPolicy,
            "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $40 (100% of the service) to this card. Cancelling in the app more than 1 hour before is free."
        )
        XCTAssertEqual(
            store.costsText,
            "Each fee is a card payment at Stripe's online rate, 2.9% + 30¢ in the US (about $1.46 of a $40 fee). "
                + "If a client disputes a fee, Stripe charges $15, and $15 more if you fight it, which comes back if you win. "
                + "Refunds are made in the Stripe Dashboard, and Stripe keeps its fee on a refund."
        )
    }

    func testTheExampleFollowsWhatsOnScreenBeforeItsSaved() async {
        let store = await loadedStore()
        store.draft.enabled = true
        store.draft.percent = 50
        XCTAssertEqual(store.examples, ["A $40 haircut: $20", "A $5 hot lather shave: $2.50"])
        XCTAssertEqual(store.clientWarning?.title, "Late Cancellation & No-Show Fee")
        XCTAssertEqual(
            store.clientWarning?.message,
            "Cancelling less than 1 hour before your appointment, or not showing up, is charged $20 (50% of the service). Cancelling in the app more than 1 hour before is free."
        )
        store.draft.feeMode = .flat
        store.draft.flatText = "25"
        XCTAssertEqual(store.examples, ["A $40 haircut: $25", "A $5 hot lather shave: $25"], "a flat fee can be more than a cheap service")
        XCTAssertEqual(store.clientPolicy?.contains("may charge $25 to this card"), true)
        store.draft.lateCancelWindowMinutes = 120
        store.draft.lateCancelEnabled = false
        XCTAssertEqual(store.clientWarning, IzzyAPI.NoShowWarning(
            title: "No-Show Fee", message: "Not showing up is charged $25. Cancelling in the app before your appointment is free."
        ))
        XCTAssertEqual(
            store.clientPolicy,
            "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $25 to this card. Cancelling in the app before your appointment is free."
        )
        store.draft.lateCancelEnabled = true
        XCTAssertEqual(store.clientWarning?.message.contains("less than 2 hours before"), true)
        // Something that can't be saved has no preview.
        store.draft.flatText = "abc"
        XCTAssertEqual(store.examples, [])
        XCTAssertNil(store.clientWarning)
        XCTAssertNil(store.clientPolicy)
        XCTAssertTrue(store.costsText.hasPrefix("Each fee is a card payment at Stripe's online rate, 2.9% + 30¢ in the US. "))
    }

    func testAFeeUnderFiftyCentsIsNoFee() async {
        let store = await loadedStore()
        store.draft.percent = 9
        XCTAssertEqual(store.examples, ["A $40 haircut: $3.60", "A $5 hot lather shave: no fee (it would be under $0.50)"])
    }

    func testTheArticleIsTheOneTheAmountIsSaidWith() {
        for dollars in [8, 11, 18, 80, 85, 89, 800, 899] {
            XCTAssertEqual(NoShowSettingsStore.article(forDollars: dollars), "An", "$\(dollars)")
        }
        for dollars in [1, 5, 16, 35, 40, 79, 90, 100, 180, 500] {
            XCTAssertEqual(NoShowSettingsStore.article(forDollars: dollars), "A", "$\(dollars)")
        }
    }

    func testStripesCostOfAFee() {
        XCTAssertEqual(NoShowSettingsStore.stripeCostCents(ofFee: 4_000), 146, "2.9% of $40 is $1.16, plus 30¢")
        XCTAssertEqual(NoShowSettingsStore.stripeCostCents(ofFee: 3_500), 132)
        XCTAssertEqual(NoShowSettingsStore.stripeCostCents(ofFee: 2_000), 88)
        XCTAssertEqual(NoShowSettingsStore.stripeCostCents(ofFee: 50), 31)
    }

    func testTheSettingsRowSaysWhatTheServerHas() {
        var settings = IzzyAPI.NoShowSettings.default
        XCTAssertEqual(NoShowSettingsStore.summary(of: settings), "Off: clients book online without a card")
        settings.enabled = true
        XCTAssertEqual(NoShowSettingsStore.summary(of: settings), "On: the full service price for no-shows and cancellations less than 1 hour before")
        settings.percent = 50
        settings.lateCancelWindowMinutes = 120
        XCTAssertEqual(NoShowSettingsStore.summary(of: settings), "On: 50% of the service for no-shows and cancellations less than 2 hours before")
        settings.feeMode = .flat
        settings.flatCents = 2_550
        settings.lateCancelEnabled = false
        XCTAssertEqual(NoShowSettingsStore.summary(of: settings), "On: $25.50 flat for no-shows")
    }

    func testWhatStripesSetUpMeansForClients() async {
        let store = await loadedStore()
        XCTAssertNil(store.stripeNote(for: nil), "not known yet")
        XCTAssertEqual(
            store.stripeNote(for: IzzyAPI.StripeStatus(configured: false)),
            "Stripe isn't set up on the server yet, so clients aren't asked for a card, even with this on."
        )
        let test = IzzyAPI.StripeStatus(configured: true, mode: .test, locationId: "tml_x")
        XCTAssertNil(store.stripeNote(for: test), "off: test keys change nothing for clients")
        store.draft.enabled = true
        XCTAssertEqual(
            store.stripeNote(for: test),
            "Stripe is in test mode: its card page turns real cards down, so clients couldn't book online. Turn this on once the server has the live key."
        )
        XCTAssertNil(store.stripeNote(for: IzzyAPI.StripeStatus(configured: true, mode: .live, locationId: "tml_x")))
    }

    // MARK: Saving

    func testSavingSendsOnlyWhatChanged() async throws {
        let store = await loadedStore()
        store.draft.enabled = true
        store.decreasePercent()
        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(api.noShowUpdates, [IzzyAPI.NoShowSettingsUpdate(enabled: true, percent: 95)])
        XCTAssertEqual(harness.server.noShowSettings, IzzyAPI.NoShowSettings(enabled: true, percent: 95))
        XCTAssertEqual(store.saved, harness.server.noShowSettings)
        XCTAssertFalse(store.hasChanges)
        XCTAssertTrue(store.justSaved)
        XCTAssertNil(store.saveError)
        XCTAssertEqual(store.summary, "On: 95% of the service for no-shows and cancellations less than 1 hour before")
        store.increasePercent()
        XCTAssertFalse(store.justSaved, "a new change on screen")
    }

    func testSavingAFlatFeeAndNoLateCancellations() async throws {
        let store = await loadedStore()
        store.draft.feeMode = .flat
        store.draft.flatText = "25.5"
        store.draft.lateCancelEnabled = false
        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(api.noShowUpdates, [IzzyAPI.NoShowSettingsUpdate(feeMode: .flat, flatCents: 2_550, lateCancelEnabled: false)])
        XCTAssertEqual(store.draft.flatText, "25.50", "written back the usual way")
        let reread = try await harness.api.noShowSettings()
        XCTAssertEqual(reread, IzzyAPI.NoShowSettings(feeMode: .flat, flatCents: 2_550, lateCancelEnabled: false))
    }

    func testAChangeMadeOnAnotherIPhoneMeanwhileStays() async throws {
        let store = await loadedStore()
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(lateCancelWindowMinutes: 180))
        store.draft.percent = 50
        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(api.noShowUpdates, [IzzyAPI.NoShowSettingsUpdate(percent: 50)])
        XCTAssertEqual(harness.server.noShowSettings.lateCancelWindowMinutes, 180)
        XCTAssertEqual(store.draft.lateCancelWindowMinutes, 180, "the server's answer shows both changes")
        XCTAssertEqual(store.draft.percent, 50)
    }

    func testSomethingTheServerWouldTurnDownIsExplainedAndNotSent() async {
        let store = await loadedStore()
        store.draft.feeMode = .flat
        store.draft.flatText = "600"
        let saved = await store.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(store.saveError, "Pick a flat fee from $0.50 to $500.")
        XCTAssertTrue(api.noShowUpdates.isEmpty)
        XCTAssertTrue(store.hasChanges, "what's on screen stays, to fix it")
        store.discardChanges()
        XCTAssertNil(store.saveError)
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.draft.flatText, "20")
    }

    func testASaveErrorGoesOnceWhatsOnScreenChanges() async {
        let store = await loadedStore()
        store.draft.feeMode = .flat
        store.draft.flatText = "600"
        let refused = await store.save()
        XCTAssertFalse(refused)
        XCTAssertEqual(store.saveError, "Pick a flat fee from $0.50 to $500.")
        // Fixed: the old error goes as soon as the amount changes, before Save.
        store.draft.flatText = "25"
        XCTAssertNil(store.saveError)
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.examples.first, "A $40 haircut: $25")
        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertTrue(store.justSaved, "Saved can show")

        // The same for the server's answer: a change on screen puts it away...
        store.draft.lateCancelEnabled = false
        harness.server.options.offline = true
        let offline = await store.save()
        XCTAssertFalse(offline)
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
        // ...but not a field set to what it already shows.
        store.draft.lateCancelEnabled = false
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
        store.draft.lateCancelWindowMinutes = 120
        XCTAssertNil(store.saveError)
        // Save says again what's wrong, while it still is.
        let again = await store.save()
        XCTAssertFalse(again)
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
        XCTAssertTrue(store.hasChanges, "what's on screen stays, to save later")
    }

    func testASaveErrorGoesWhenARefreshLeavesNothingToSave() async throws {
        let store = await loadedStore()
        store.draft.enabled = true
        harness.server.options.offline = true
        _ = await store.save()
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
        harness.server.options.offline = false
        // Turned on from another iPhone meanwhile: what's on screen is what the server has.
        _ = try await harness.api.updateNoShowSettings(IzzyAPI.NoShowSettingsUpdate(enabled: true))
        await store.refresh()
        XCTAssertFalse(store.hasChanges)
        XCTAssertNil(store.saveError)

        // Changes that still aren't saved keep it through a refresh.
        store.draft.percent = 50
        harness.server.options.offline = true
        _ = await store.save()
        harness.server.options.offline = false
        await store.refresh()
        XCTAssertTrue(store.hasChanges)
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
    }

    func testWhatTheSwitchesMean() async {
        let store = await loadedStore()
        XCTAssertEqual(
            NoShowSettingsStore.onFooter,
            "Clients add a card (or Apple Pay) when they book online. Nothing is charged then: you decide whether to charge a no-show or a late cancellation."
        )
        // Off only changes new bookings: the server charges each booking by the terms it was made with.
        XCTAssertEqual(
            NoShowSettingsStore.offFooter,
            "Off: new online bookings don't need a card. Bookings already made with a card keep their fee, and you can still charge it."
        )
        XCTAssertEqual(
            NoShowSettingsStore.feeFooter,
            "The same fee for a no-show and a late cancellation. Each booking keeps the fee and late-cancellation window it was booked with, so a change only affects new bookings."
        )
        XCTAssertEqual(
            store.lateCancellationFooter,
            "A client who cancels in the app less than 1 hour before the start can be charged the fee. Cancelling earlier is free, and there's never a fee when the shop cancels."
        )
        store.draft.lateCancelWindowMinutes = 1_440
        XCTAssertTrue(store.lateCancellationFooter.hasPrefix("A client who cancels in the app less than 24 hours before the start"))
        store.draft.lateCancelEnabled = false
        XCTAssertEqual(
            store.lateCancellationFooter,
            "Off: new bookings can be cancelled in the app for free until the start, and only no-shows can be charged. Bookings already made keep the window they were booked with."
        )
    }

    func testTheSampleDayWithCardsOnFileStartsWithProtectionOn() async {
        var options = FakeServer.Options()
        options.upcomingWithCard = true
        let sample = Harness(options: options)
        let store = NoShowSettingsStore(api: sample.api, catalog: .izzyClipz)
        await store.refresh()
        XCTAssertEqual(store.saved?.enabled, true, "those clients booked with it on")
        XCTAssertEqual(store.summary, "On: the full service price for no-shows and cancellations less than 1 hour before")
        XCTAssertEqual(store.saved, IzzyAPI.NoShowSettings(enabled: true), "the rest as the server starts")
    }

    func testAnAmountTypedForAFeeNotInUseIsntSent() async {
        let store = await loadedStore()
        store.draft.feeMode = .flat
        store.draft.flatText = "abc"
        store.draft.feeMode = .percent
        XCTAssertTrue(store.hasChanges)
        let saved = await store.save()
        XCTAssertTrue(saved, "nothing the server would change")
        XCTAssertTrue(api.noShowUpdates.isEmpty)
        XCTAssertEqual(store.draft, NoShowSettingsDraft(.default))
    }

    func testASaveThatDoesntGoThroughKeepsTheChangesAndSaysWhy() async {
        let store = await loadedStore()
        store.draft.enabled = true
        harness.server.options.offline = true
        let offline = await store.save()
        XCTAssertFalse(offline)
        XCTAssertEqual(store.saveError, APIError.offline.userMessage)
        XCTAssertTrue(store.draft.enabled)
        XCTAssertTrue(store.hasChanges)
        XCTAssertFalse(store.justSaved)
        XCTAssertFalse(harness.server.noShowSettings.enabled)

        harness.server.options.offline = false
        api.updateNoShowSettingsHandler = { _ in
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Pick a percentage from 1% to 100%.", status: 400)
        }
        let refused = await store.save()
        XCTAssertFalse(refused)
        XCTAssertEqual(store.saveError, "Pick a percentage from 1% to 100%.", "the server's own words")

        api.updateNoShowSettingsHandler = nil
        let saved = await store.save()
        XCTAssertTrue(saved)
        XCTAssertNil(store.saveError)
        XCTAssertTrue(store.justSaved)
        XCTAssertTrue(harness.server.noShowSettings.enabled)
    }

    func testOneSaveAtATime() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        api.updateNoShowSettingsHandler = { [base = api.base] update in
            await gate.wait()
            return try await base.updateNoShowSettings(update)
        }
        store.draft.enabled = true
        let first = Task { await store.save() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.isSaving)
        let second = await store.save()
        XCTAssertFalse(second, "ignored while the first is saving")
        await gate.open()
        let firstSaved = await first.value
        XCTAssertTrue(firstSaved)
        XCTAssertFalse(store.isSaving)
        XCTAssertEqual(api.noShowUpdates.count, 1)
    }

    func testAChangeMadeWhileSavingStaysOnScreen() async throws {
        let store = await loadedStore()
        let gate = AsyncGate()
        api.updateNoShowSettingsHandler = { [base = api.base] update in
            await gate.wait()
            return try await base.updateNoShowSettings(update)
        }
        store.draft.enabled = true
        let saving = Task { await store.save() }
        try await Task.sleep(for: .milliseconds(50))
        store.draft.percent = 60
        await gate.open()
        _ = await saving.value
        XCTAssertTrue(store.draft.enabled)
        XCTAssertEqual(store.draft.percent, 60, "not replaced by the server's answer")
        XCTAssertTrue(store.hasChanges, "60% still has to be saved")
        XCTAssertFalse(store.justSaved)
    }

    func testTheWorkspaceHasTheSettingsForTheSignedInKey() async {
        let environment = AppEnvironment.sample()
        let workspace = Workspace(environment: environment, ownerKey: FakeServer.ownerKey, status: nil)
        await workspace.noShow.refresh()
        XCTAssertEqual(workspace.noShow.saved, .default)
        let wrongKey = Workspace(environment: environment, ownerKey: "wrong", status: nil)
        await wrongKey.noShow.refresh()
        XCTAssertEqual(wrongKey.noShow.loadState, .failed(APIError.unauthorized.userMessage))
    }
}
