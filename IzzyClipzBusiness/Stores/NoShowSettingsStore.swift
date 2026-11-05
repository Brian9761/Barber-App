import Foundation
import IzzyClipzKit
import Observation

/// Settings → No-show protection: whether online bookings need a card on file, the fee (a share
/// of the service's price or a flat amount; the full price to start), whether late cancellations
/// can be charged too and from how long before the start, an example, and the words clients see.
///
/// Changes stay on screen (`draft`) until Save sends them to the server, which only gets the
/// fields the owner changed, so a change made on another iPhone meanwhile stays: a refresh (or a
/// save's answer) shows it in every field the owner didn't change. Each booking keeps the fee and
/// terms it was booked with: a change only affects new bookings.
@MainActor
@Observable
final class NoShowSettingsStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// What the server has, once loaded.
    private(set) var saved: IzzyAPI.NoShowSettings?
    /// What's on screen. A change to it puts away the last save's error: that error was about what
    /// was on screen then (a flat fee of $600 fixed to $25 no longer says "Pick a flat fee from $0.50
    /// to $500."), and Save says again what's wrong, if anything.
    var draft = NoShowSettingsDraft() {
        didSet {
            if draft != oldValue { saveError = nil }
        }
    }
    private(set) var loadState: LoadState = .idle
    /// The latest refresh failed while the settings are on screen.
    private(set) var refreshError: String?
    private(set) var isSaving = false
    /// Why the last save didn't work, in plain words, until what's on screen changes, the next
    /// save, or Cancel.
    private(set) var saveError: String?
    /// What the last save stored, to say "Saved" until something changes.
    private(set) var lastSaved: NoShowSettingsDraft?

    let catalog: Catalog
    @ObservationIgnored private let api: any OwnerAPI
    /// Bumped by every load and save, so a slow answer never replaces a newer one.
    @ObservationIgnored private var generation = 0

    /// The stepper's range and step for "% of the service" (the server takes 1–100).
    static let percentStepperRange: ClosedRange<Int> = 10...100
    static let percentStep = 5
    /// The late-cancellation windows to pick from (the server takes 30 minutes to 48 hours).
    static let windowChoices = [30, 60, 120, 180, 240, 360, 720, 1_440, 2_880]

    init(api: any OwnerAPI, catalog: Catalog) {
        self.api = api
        self.catalog = catalog
    }

    // MARK: Loading and saving

    /// Loads the settings. Changes on screen that aren't saved yet stay as they are, and every
    /// field the owner didn't change shows what the server has now (changed on another iPhone, say).
    func refresh() async {
        generation += 1
        let requested = generation
        if loadState != .loaded { loadState = .loading }
        do {
            let settings = try await api.noShowSettings()
            guard requested == generation else { return }
            let keepsChanges = hasChanges
            let startedFrom = saved.map(NoShowSettingsDraft.init)
            saved = settings
            if keepsChanges, let startedFrom {
                // Moved onto the server's settings, so Save sends only what the owner changed. A save
                // error was about those changes, which stay, so it stays too.
                let error = saveError
                draft = draft.rebased(from: startedFrom, onto: NoShowSettingsDraft(settings))
                saveError = error
            } else {
                draft = NoShowSettingsDraft(settings)
            }
            // Nothing on screen waits to be saved (the same change was made on another iPhone,
            // say), so no save error applies any more.
            if !hasChanges { saveError = nil }
            refreshError = nil
            loadState = .loaded
        } catch is CancellationError {
            if requested == generation, loadState == .loading { loadState = .idle }
        } catch {
            guard requested == generation else { return }
            let message = ErrorText.message(for: error)
            if loadState == .loaded {
                refreshError = message
            } else {
                loadState = .failed(message)
            }
        }
    }

    /// Whether what's on screen differs from what the server has.
    var hasChanges: Bool {
        guard let saved else { return false }
        return draft.normalized != NoShowSettingsDraft(saved)
    }

    /// What's wrong with what's on screen, if anything: Save explains it instead of sending it.
    var problem: String? { draft.problem }

    /// Sends what changed. `true` when the server has what's on screen (or nothing changed).
    @discardableResult
    func save() async -> Bool {
        guard !isSaving, let saved else { return false }
        saveError = nil
        if let problem = draft.problem {
            saveError = problem
            return false
        }
        let sent = draft
        guard let update = sent.update(from: saved) else {
            // Nothing the server would change (say, only a flat amount typed while the fee is a percentage).
            draft = NoShowSettingsDraft(saved)
            return true
        }
        isSaving = true
        defer { isSaving = false }
        // A load that started before this can't bring the old settings back...
        generation += 1
        do {
            let result = try await api.updateNoShowSettings(update)
            // ...nor one that started while saving: the server may have answered it before the change.
            generation += 1
            self.saved = result
            // What's on screen becomes what the server has now (with a change made on another iPhone
            // meanwhile), except the fields the owner changed while it saved.
            draft = draft.rebased(from: sent, onto: NoShowSettingsDraft(result))
            lastSaved = NoShowSettingsDraft(result)
            refreshError = nil
            loadState = .loaded
            return true
        } catch is CancellationError {
            // The change may or may not have reached the server; saving again sends the same fields.
            saveError = "Saving was interrupted. Try again."
            return false
        } catch {
            saveError = ErrorText.message(for: error)
            return false
        }
    }

    /// Puts back what the server has.
    func discardChanges() {
        if let saved { draft = NoShowSettingsDraft(saved) }
        saveError = nil
    }

    /// Says "Saved" after a save, until something changes on screen.
    var justSaved: Bool {
        guard let lastSaved, !hasChanges else { return false }
        return draft.normalized == lastSaved
    }

    // MARK: The fee

    var canIncreasePercent: Bool { draft.percent < Self.percentStepperRange.upperBound }
    var canDecreasePercent: Bool { draft.percent > Self.percentStepperRange.lowerBound }

    /// The stepper's +: the next step up (10, 15, … 100).
    func increasePercent() {
        guard canIncreasePercent else { return }
        let next = (draft.percent / Self.percentStep + 1) * Self.percentStep
        draft.percent = min(Self.percentStepperRange.upperBound, max(Self.percentStepperRange.lowerBound, next))
    }

    /// The stepper's −: the next step down, never under 10%.
    func decreasePercent() {
        guard canDecreasePercent else { return }
        let next = ((draft.percent - 1) / Self.percentStep) * Self.percentStep
        draft.percent = max(Self.percentStepperRange.lowerBound, next)
    }

    /// "100% of the service (the full price)", "50% of the service".
    var percentLabel: String {
        draft.percent == 100 ? "100% of the service (the full price)" : "\(draft.percent)% of the service"
    }

    // MARK: What the switches mean

    /// Under the No-show protection switch, while it's on.
    static let onFooter = "Clients add a card (or Apple Pay) when they book online. Nothing is charged then: you decide whether to charge a no-show or a late cancellation."
    /// While it's off. Each booking keeps the terms it was booked with (the server never reads
    /// today's settings to charge one), so a booking made with a card can still be charged.
    static let offFooter = "Off: new online bookings don't need a card. Bookings already made with a card keep their fee, and you can still charge it."

    /// Under the Fee picker.
    static let feeFooter = "The same fee for a no-show and a late cancellation. Each booking keeps the fee and late-cancellation window it was booked with, so a change only affects new bookings."

    /// Under the Late cancellations switch: "A client who cancels in the app less than 1 hour before
    /// the start can be charged the fee. Cancelling earlier is free, and there's never a fee when the
    /// shop cancels." Off, only for new bookings: those made before keep their window.
    var lateCancellationFooter: String {
        guard draft.lateCancelEnabled else {
            return "Off: new bookings can be cancelled in the app for free until the start, and only no-shows can be charged. "
                + "Bookings already made keep the window they were booked with."
        }
        let window = IzzyAPI.NoShowRule.windowLabel(minutes: draft.lateCancelWindowMinutes)
        return "A client who cancels in the app less than \(window) before the start can be charged the fee. "
            + "Cancelling earlier is free, and there's never a fee when the shop cancels."
    }

    /// The windows to pick from, with the one on screen (set elsewhere, say 90 minutes) among them.
    var windowChoices: [Int] {
        var choices = Self.windowChoices
        if !choices.contains(draft.lateCancelWindowMinutes) {
            choices.append(draft.lateCancelWindowMinutes)
            choices.sort()
        }
        return choices
    }

    // MARK: What it looks like

    /// The settings on screen, when they can be saved.
    var previewSettings: IzzyAPI.NoShowSettings? {
        draft.settings(keeping: saved ?? .default)
    }

    /// The menu items the example uses: the first barber's haircut (the owner's, $40), and the
    /// cheapest item with a price, since a flat fee is capped at a cheap service's price.
    var exampleItems: [(name: String, price: Price)] {
        var items: [(name: String, price: Price)] = []
        if let haircut = catalog.offerings.first(where: { $0.serviceID == "haircut" && $0.price.kind == .fixed && $0.price.cents > 0 }) {
            items.append((catalog.service(withID: haircut.serviceID)?.name ?? "Haircut", haircut.price))
        }
        let priced = catalog.offerings.filter { $0.price.kind == .fixed && $0.price.cents > 0 }
        if let cheapest = priced.min(by: { $0.price.cents < $1.price.cents }),
           !items.contains(where: { $0.price.cents == cheapest.price.cents }) {
            items.append((catalog.service(withID: cheapest.serviceID)?.name ?? cheapest.serviceID, cheapest.price))
        }
        return items
    }

    /// "A $40 haircut: $40", "A $16 seniors haircut: $16"; `[]` while what's on screen can't be saved.
    var examples: [String] {
        guard let settings = previewSettings else { return [] }
        return exampleItems.map { item in
            let price = Price.currencyString(cents: item.price.cents)
            let fee = IzzyAPI.NoShowRule.feeCents(for: item.price, settings: settings)
            let what = "\(Self.article(forDollars: item.price.cents / 100)) \(price) \(item.name.lowercased())"
            return "\(what): \(fee.map { Price.currencyString(cents: $0) } ?? "no fee (it would be under $0.50)")"
        }
    }

    /// "A" or "An", as "$8", "$11", "$18" and "$80" are said: "an eight-dollar…".
    static func article(forDollars dollars: Int) -> String {
        let vowelSound = dollars == 8 || dollars == 11 || dollars == 18 || (80...89).contains(dollars) || (800...899).contains(dollars)
        return vowelSound ? "An" : "A"
    }

    /// The fee clients are shown for the example haircut (the first example item), if it has one.
    private var exampleFeeCents: Int? {
        guard let settings = previewSettings, let item = exampleItems.first else { return nil }
        return IzzyAPI.NoShowRule.feeCents(for: item.price, settings: settings)
    }

    /// The notice clients see on "Pick a day and time" and on Review, for the example haircut, as
    /// the server words it ("Full Service Cancellation & No-Show Fee").
    var clientWarning: IzzyAPI.NoShowWarning? {
        guard let settings = previewSettings, let fee = exampleFeeCents else { return nil }
        return IzzyAPI.NoShowRule.warning(minFeeCents: fee, maxFeeCents: fee, settings: settings)
    }

    /// The policy clients agree to above "Book appointment" (and on Stripe's card page), for the
    /// example haircut, as the server words it.
    var clientPolicy: String? {
        guard let settings = previewSettings, let fee = exampleFeeCents else { return nil }
        return IzzyAPI.NoShowRule.policyText(minFeeCents: fee, maxFeeCents: fee, settings: settings)
    }

    /// What Stripe keeps of a fee charged to a card on file: its online card rate in the US, 2.9% + 30¢.
    static func stripeCostCents(ofFee cents: Int) -> Int {
        (cents * 29 + 500) / 1_000 + 30
    }

    /// Stripe's costs (US standard pricing, stripe.com/pricing), with the example haircut's fee when
    /// there is one. A dispute costs $15 that Stripe keeps either way; fighting it costs $15 more,
    /// which comes back only if the shop wins. Refunds are free, but Stripe keeps its fee.
    var costsText: String {
        var rate = "Each fee is a card payment at Stripe's online rate, 2.9% + 30¢ in the US"
        if let fee = exampleFeeCents {
            rate += " (about \(Price.currencyString(cents: Self.stripeCostCents(ofFee: fee))) of a \(Price.currencyString(cents: fee)) fee)"
        }
        return rate + ". If a client disputes a fee, Stripe charges $15, and $15 more if you fight it, which comes back if you win. "
            + "Refunds are made in the Stripe Dashboard, and Stripe keeps its fee on a refund."
    }

    /// The Settings row: "Off", or "On: the full service price for no-shows and cancellations
    /// less than 1 hour before". Always what the server has, not unsaved changes.
    var summary: String {
        guard let saved else {
            if case .failed = loadState { return "Couldn't load. Open to try again." }
            return "Loading…"
        }
        return Self.summary(of: saved)
    }

    static func summary(of settings: IzzyAPI.NoShowSettings) -> String {
        guard settings.enabled else { return "Off: clients book online without a card" }
        let fee: String
        switch settings.feeMode {
        case .percent: fee = settings.percent == 100 ? "the full service price" : "\(settings.percent)% of the service"
        case .flat: fee = "\(Price.currencyString(cents: settings.flatCents)) flat"
        }
        let cases = settings.lateCancelEnabled
            ? "no-shows and cancellations less than \(IzzyAPI.NoShowRule.windowLabel(minutes: settings.lateCancelWindowMinutes)) before"
            : "no-shows"
        return "On: \(fee) for \(cases)"
    }

    /// What Stripe's set-up on the server means for clients, when it changes things: no card is
    /// asked for without Stripe, and test keys turn real cards down on Stripe's card page.
    func stripeNote(for stripe: IzzyAPI.StripeStatus?) -> String? {
        guard let stripe else { return nil }
        if !stripe.configured {
            return "Stripe isn't set up on the server yet, so clients aren't asked for a card, even with this on."
        }
        if stripe.mode == .test, draft.enabled {
            return "Stripe is in test mode: its card page turns real cards down, so clients couldn't book online. Turn this on once the server has the live key."
        }
        return nil
    }
}

/// The No-show protection screen's fields, as they're edited.
struct NoShowSettingsDraft: Equatable {
    var enabled: Bool
    var feeMode: IzzyAPI.NoShowFeeMode
    var percent: Int
    /// The flat fee as typed: "20", "17.50".
    var flatText: String
    var lateCancelEnabled: Bool
    var lateCancelWindowMinutes: Int

    init(_ settings: IzzyAPI.NoShowSettings = .default) {
        enabled = settings.enabled
        feeMode = settings.feeMode
        percent = settings.percent
        flatText = Money.editable(settings.flatCents)
        lateCancelEnabled = settings.lateCancelEnabled
        lateCancelWindowMinutes = settings.lateCancelWindowMinutes
    }

    /// The flat fee in cents; `nil` when what's typed isn't an amount.
    var flatCents: Int? { Money.cents(from: flatText) }

    /// The same, with the flat fee written the usual way ("20.00" reads "20"), to compare.
    var normalized: NoShowSettingsDraft {
        var copy = self
        if let cents = flatCents { copy.flatText = Money.editable(cents) }
        return copy
    }

    /// What the server would turn down, in its words; `nil` when it can be saved. A flat amount
    /// only counts while the fee is a flat amount.
    var problem: String? {
        if !IzzyAPI.NoShowRule.percentRange.contains(percent) {
            return "Pick a percentage from 1% to 100%."
        }
        if feeMode == .flat {
            guard let cents = flatCents else { return "Enter the flat fee in dollars, like 20 or 17.50." }
            if !IzzyAPI.NoShowRule.flatCentsRange.contains(cents) {
                return "Pick a flat fee from \(Price.currencyString(cents: IzzyAPI.NoShowRule.flatCentsRange.lowerBound)) to \(Price.currencyString(cents: IzzyAPI.NoShowRule.flatCentsRange.upperBound))."
            }
        }
        if !IzzyAPI.NoShowRule.lateCancelWindowRange.contains(lateCancelWindowMinutes) {
            return "Pick a late-cancellation window from 30 minutes to 48 hours."
        }
        return nil
    }

    /// The settings this makes, over `saved`; `nil` while there's a problem. A flat amount that
    /// can't be read while the fee is a percentage keeps the saved one.
    func settings(keeping saved: IzzyAPI.NoShowSettings) -> IzzyAPI.NoShowSettings? {
        guard problem == nil else { return nil }
        var settings = saved
        settings.enabled = enabled
        settings.feeMode = feeMode
        settings.percent = percent
        if let cents = flatCents, IzzyAPI.NoShowRule.flatCentsRange.contains(cents) { settings.flatCents = cents }
        settings.lateCancelEnabled = lateCancelEnabled
        settings.lateCancelWindowMinutes = lateCancelWindowMinutes
        return settings
    }

    /// This draft moved onto newer settings from the server (`newer`): every field the owner changed
    /// from `base` (what they started from) keeps their value, and every other field takes the
    /// server's, which may have been changed on another iPhone. A flat amount counts as changed only
    /// when it's another amount ("20.00" for $20 isn't), or isn't an amount at all.
    func rebased(from base: NoShowSettingsDraft, onto newer: NoShowSettingsDraft) -> NoShowSettingsDraft {
        var result = newer
        if enabled != base.enabled { result.enabled = enabled }
        if feeMode != base.feeMode { result.feeMode = feeMode }
        if percent != base.percent { result.percent = percent }
        if normalized.flatText != base.normalized.flatText { result.flatText = flatText }
        if lateCancelEnabled != base.lateCancelEnabled { result.lateCancelEnabled = lateCancelEnabled }
        if lateCancelWindowMinutes != base.lateCancelWindowMinutes { result.lateCancelWindowMinutes = lateCancelWindowMinutes }
        return result
    }

    /// Only the fields that differ from `saved`; `nil` when nothing does (or there's a problem).
    func update(from saved: IzzyAPI.NoShowSettings) -> IzzyAPI.NoShowSettingsUpdate? {
        guard let settings = settings(keeping: saved) else { return nil }
        let update = IzzyAPI.NoShowSettingsUpdate(
            enabled: settings.enabled == saved.enabled ? nil : settings.enabled,
            feeMode: settings.feeMode == saved.feeMode ? nil : settings.feeMode,
            percent: settings.percent == saved.percent ? nil : settings.percent,
            flatCents: settings.flatCents == saved.flatCents ? nil : settings.flatCents,
            lateCancelEnabled: settings.lateCancelEnabled == saved.lateCancelEnabled ? nil : settings.lateCancelEnabled,
            lateCancelWindowMinutes: settings.lateCancelWindowMinutes == saved.lateCancelWindowMinutes ? nil : settings.lateCancelWindowMinutes
        )
        return update.isEmpty ? nil : update
    }
}
