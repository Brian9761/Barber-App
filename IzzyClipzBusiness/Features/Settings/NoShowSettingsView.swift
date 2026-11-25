import IzzyClipzKit
import SwiftUI

/// Settings → No-show protection: on or off, the fee (a share of the service or a flat amount),
/// late cancellations and their window, an example, and the notice and policy clients see.
/// Changes are saved to the server with Save; Cancel puts back what's saved.
struct NoShowSettingsView: View {
    @Bindable var store: NoShowSettingsStore
    let stripe: IzzyAPI.StripeStatus?
    @State private var confirmsDiscard = false
    /// The flat fee's field: its decimal pad has no return key, so Done above it closes it.
    @FocusState private var flatAmountFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle("No-show protection")
            .navigationBarTitleDisplayMode(.inline)
            // With changes on screen, Back would lose them: Cancel asks first.
            .navigationBarBackButtonHidden(store.hasChanges)
            .toolbar {
                if store.hasChanges {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { confirmsDiscard = true }
                            .disabled(store.isSaving)
                            .accessibilityIdentifier("cancelNoShowSettings")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaving {
                        ProgressView()
                            .accessibilityLabel("Saving")
                    } else {
                        Button("Save") {
                            flatAmountFocused = false
                            Task { await store.save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!store.hasChanges)
                        .accessibilityIdentifier("saveNoShowSettings")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { flatAmountFocused = false }
                        .accessibilityIdentifier("flatAmountDone")
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) {
                    store.discardChanges()
                    dismiss()
                }
                .accessibilityIdentifier("confirmDiscardNoShowSettings")
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("The no-show protection settings stay as they were saved.")
            }
            .task { await store.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if store.saved == nil {
            switch store.loadState {
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load the settings", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await store.refresh() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("retryNoShowSettings")
                }
            case .idle, .loading, .loaded:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            protectionSection
            feeSection
            lateCancellationSection
            if store.draft.enabled {
                exampleSection
                clientsSection
            }
            if let error = store.saveError {
                Section {
                    InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                        .accessibilityIdentifier("noShowSaveError")
                }
            } else if store.justSaved {
                Section {
                    Label("Saved. New bookings use these settings.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        // One message, as InlineMessage is: not the checkmark and the words apart.
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("noShowSaved")
                }
            }
            costsSection
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
    }

    // MARK: Sections

    private var protectionSection: some View {
        Section {
            Toggle("No-show protection", isOn: $store.draft.enabled)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("noShowEnabled")
            if let note = store.stripeNote(for: stripe) {
                InlineMessage(text: note)
                    .accessibilityIdentifier("noShowStripeNote")
            }
            if let refreshError = store.refreshError {
                InlineMessage(text: "Couldn't refresh: \(refreshError)")
            }
        } footer: {
            Text(store.draft.enabled ? NoShowSettingsStore.onFooter : NoShowSettingsStore.offFooter)
        }
    }

    private var feeSection: some View {
        Section {
            Picker("Fee", selection: $store.draft.feeMode) {
                Text("% of the service").tag(IzzyAPI.NoShowFeeMode.percent)
                Text("Flat amount").tag(IzzyAPI.NoShowFeeMode.flat)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: BusinessTheme.minimumTapSize)
            .accessibilityIdentifier("noShowFeeMode")
            switch store.draft.feeMode {
            case .percent:
                Stepper {
                    Text(store.percentLabel)
                        .monospacedDigit()
                } onIncrement: {
                    store.increasePercent()
                } onDecrement: {
                    store.decreasePercent()
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityValue("\(store.draft.percent) percent")
                .accessibilityIdentifier("noShowPercent")
            case .flat:
                HStack {
                    Text("$").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Amount", text: $store.draft.flatText)
                        .keyboardType(.decimalPad)
                        .focused($flatAmountFocused)
                        .accessibilityLabel("Flat fee in dollars")
                        .accessibilityIdentifier("noShowFlatAmount")
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            if Self.problemIsARow, let problem = store.problem {
                problemMessage(problem)
            }
        } header: {
            Text("Fee")
        } footer: {
            if Self.problemIsARow {
                Text(NoShowSettingsStore.feeFooter)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let problem = store.problem {
                        // As prominent as the row it stands in for: the footer's own text is small and gray.
                        problemMessage(problem)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    Text(NoShowSettingsStore.feeFooter)
                }
            }
        }
    }

    /// What Save would be turned down for, in the server's words: "Pick a flat fee from $0.50 to $500."
    private func problemMessage(_ problem: String) -> some View {
        InlineMessage(text: problem, systemImage: "exclamationmark.octagon.fill", color: .red)
            .accessibilityIdentifier("noShowSettingsProblem")
    }

    /// Whether the fee's problem is a row under the flat fee's field (iOS 26) or the first line of the
    /// Fee section's footer, also right under the field (iOS 18). On iOS 18.6 the row appearing under
    /// the focused field moved the form up 125 points, with the keyboard still up: an owner deleting
    /// $20 to type $600 saw the field go up under the navigation bar as the problem appeared, and typed
    /// $600 into a field they couldn't see. A change in the footer adds no row next to the field. The
    /// owner app's UI test checks after every key that the field is still between the navigation bar
    /// and the keyboard.
    private static var problemIsARow: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private var lateCancellationSection: some View {
        Section {
            Toggle("Charge late cancellations", isOn: $store.draft.lateCancelEnabled)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("noShowLateCancel")
            if store.draft.lateCancelEnabled {
                Picker("Cancelling less than", selection: $store.draft.lateCancelWindowMinutes) {
                    ForEach(store.windowChoices, id: \.self) { minutes in
                        Text("\(IzzyAPI.NoShowRule.windowLabel(minutes: minutes)) before").tag(minutes)
                    }
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("noShowWindow")
            }
        } header: {
            Text("Late cancellations")
        } footer: {
            Text(store.lateCancellationFooter)
        }
    }

    private var exampleSection: some View {
        Section {
            if store.examples.isEmpty {
                Text("Fix the fee above to see an example.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.examples, id: \.self) { line in
                    Text(line)
                        .monospacedDigit()
                        .accessibilityIdentifier("noShowExample")
                }
            }
        } header: {
            Text("Example")
        } footer: {
            if let note = store.capNote {
                // The cap: never more than the service's price (the Cancellation & No-Show Policy's promise).
                Text(note)
                    .accessibilityIdentifier("noShowCapNote")
            }
        }
    }

    @ViewBuilder
    private var clientsSection: some View {
        if let warning = store.clientWarning, let policy = store.clientPolicy {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(warning.title).font(.headline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BusinessTheme.caution)
                    }
                    Text(warning.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("noShowClientWarning")
                Text(policy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("noShowClientPolicy")
            } header: {
                Text("What clients see")
            } footer: {
                Text("For the example haircut. The notice shows while clients pick a day and time and on Review; they agree to the policy below it before booking.")
            }
        }
    }

    private var costsSection: some View {
        Section("Stripe's costs") {
            Text(store.costsText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("noShowCosts")
        }
    }
}
