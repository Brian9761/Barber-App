import IzzyClipzKit
import SwiftUI

/// Server and Stripe status, Tap to Pay setup and "How to Tap", the owner
/// key, sign out, and the app's version.
struct SettingsView: View {
    let workspace: Workspace
    let model: AppModel
    @State private var showsReplaceKey = false
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            List {
                serverSection
                stripeSection
                tapToPaySection
                keySection
                Section {
                    Button("Sign out", role: .destructive) { confirmsSignOut = true }
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("signOut")
                } footer: {
                    Text("Signing out removes the owner key from this iPhone.")
                }
                Section {
                    LabeledContent("Version", value: Self.version)
                        .accessibilityIdentifier("appVersion")
                }
            }
            .navigationTitle("Settings")
            .refreshable {
                await workspace.refreshStatus()
                await workspace.refreshHealth()
            }
            .task { await workspace.refreshHealth() }
            .sheet(isPresented: $showsReplaceKey) {
                ReplaceKeyView(model: model)
            }
            .confirmationDialog("Sign out of Izzy Clipz Business?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
                .accessibilityIdentifier("confirmSignOut")
                Button("Stay signed in", role: .cancel) {}
            } message: {
                Text("You'll need the owner key to sign in again.")
            }
        }
    }

    // MARK: Sections

    private var serverSection: some View {
        Section {
            LabeledContent("Address", value: workspace.environment.serverDescription)
            if let health = workspace.health {
                LabeledContent("Status") {
                    Label("Online", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .accessibilityIdentifier("serverStatus")
                LabeledContent("Server version", value: health.version)
            } else if let error = workspace.healthError {
                InlineMessage(text: error)
                    .accessibilityIdentifier("serverStatus")
            } else {
                LabeledContent("Status") { ProgressView() }
            }
            Button("Check again") {
                Task {
                    await workspace.refreshHealth()
                    await workspace.refreshStatus()
                }
            }
            .frame(minHeight: BusinessTheme.minimumTapSize)
        } header: {
            Text("Server")
        }
    }

    private var stripeSection: some View {
        Section {
            if let stripe = workspace.ownerStatus?.stripe {
                LabeledContent("Card payments", value: stripe.configured ? "Set up" : "Not set up")
                    .accessibilityIdentifier("stripeConfigured")
                if stripe.configured {
                    LabeledContent("Mode", value: stripe.mode == .live ? "Live: real money" : stripe.mode == .test ? "Test mode: no real money" : "Unknown")
                        .accessibilityIdentifier("stripeMode")
                    LabeledContent("Terminal location", value: stripe.locationId ?? "Missing")
                        .accessibilityIdentifier("stripeLocation")
                }
            } else if let error = workspace.statusError {
                InlineMessage(text: error)
            } else {
                LabeledContent("Card payments") { ProgressView() }
            }
        } header: {
            Text("Stripe")
        } footer: {
            Text(stripeFooter)
        }
    }

    private var stripeFooter: String {
        guard let stripe = workspace.ownerStatus?.stripe else { return "" }
        if !stripe.configured {
            return "To take cards, add the shop's Stripe secret key (STRIPE_SECRET_KEY) and Terminal location (STRIPE_TERMINAL_LOCATION_ID) to the server's settings."
        }
        if stripe.locationId == nil {
            return "Create a Terminal location with the shop's address in the Stripe Dashboard and add its ID (tml_…) to the server as STRIPE_TERMINAL_LOCATION_ID."
        }
        if stripe.mode == .test {
            return "Stripe test keys: only Stripe test cards work and no money moves. Switch the server to the live key to take real payments."
        }
        return "Payments go to the shop's Stripe account."
    }

    private var tapToPaySection: some View {
        Section {
            LabeledContent("This iPhone", value: tapToPayStatus)
                .accessibilityIdentifier("tapToPayStatus")
            if case .preparing(let progress) = workspace.checkout.currentTerminal.state {
                ReaderProgress(progress: progress)
            }
            Button {
                Task { await workspace.setUpTapToPay() }
            } label: {
                HStack {
                    Label("Set up Tap to Pay on iPhone", systemImage: "wave.3.right.circle")
                    Spacer()
                    if workspace.isSettingUpTapToPay { ProgressView() }
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .disabled(workspace.isSettingUpTapToPay)
            .accessibilityIdentifier("settingsSetUpTapToPay")
            if let error = workspace.tapToPaySetupError {
                InlineMessage(text: error)
                    .accessibilityIdentifier("tapToPaySetupError")
            }
            Button {
                Task { await workspace.showHowToTap() }
            } label: {
                Label("How to Tap", systemImage: "hand.tap")
                    .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .accessibilityIdentifier("howToTap")
        } header: {
            Text("Tap to Pay on iPhone")
        } footer: {
            Text("Needs an iPhone XS or later with the latest iOS, a passcode, and location turned on for this app. The first setup asks the shop's owner to accept Apple's terms.")
        }
    }

    private var tapToPayStatus: String {
        let checkout = workspace.checkout
        switch checkout.mode {
        case .checking: return "Checking…"
        case .unavailable(let issue): return issue.title
        case .practice(.deviceUnsupported): return "Not supported (test mode only)"
        case .practice(.chosen): return "Test mode"
        case .sampleServer: return "Test mode (sample server)"
        case .live:
            switch checkout.currentTerminal.state {
            case .ready, .collecting, .processing: return "Ready"
            case .preparing: return "Getting ready…"
            case .reconnecting: return "Reconnecting…"
            case .unavailable(let issue): return issue.title
            case .idle: return workspace.hasSetUpTapToPay ? "Set up" : "Not set up yet"
            }
        }
    }

    private var keySection: some View {
        Section {
            LabeledContent("Owner key", value: Self.masked(workspace.ownerKey))
                .accessibilityLabel("Owner key ending in \(String(workspace.ownerKey.suffix(4)))")
            Button("Replace owner key") { showsReplaceKey = true }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("replaceKey")
        } header: {
            Text("Owner key")
        } footer: {
            Text(workspace.keySaveError ?? "Kept in this iPhone's keychain. If the key changes on the server, replace it here.")
        }
    }

    /// "••••••••7f3a".
    static func masked(_ key: String) -> String {
        String(repeating: "•", count: 8) + key.suffix(4)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Paste a new owner key; it's checked with the server before it replaces
/// the saved one.
private struct ReplaceKeyView: View {
    let model: AppModel
    @State private var key = ""
    @State private var error: String?
    @State private var isChecking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New owner key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("newOwnerKey")
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first { key = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                } footer: {
                    Text("The current key stays until the new one is confirmed by the server.")
                }
                if let error {
                    Section {
                        InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                    }
                }
            }
            .navigationTitle("Replace owner key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isChecking = true
                            Task {
                                error = await model.replaceKey(with: key)
                                isChecking = false
                                if error == nil { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }
}
