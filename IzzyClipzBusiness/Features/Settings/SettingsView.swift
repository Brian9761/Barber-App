import IzzyClipzKit
import SwiftUI

/// The shop's products, server and Stripe status, no-show protection, Tap to Pay setup and "How
/// to Tap", the owner key, the legal pages, sign out, and the app's version.
struct SettingsView: View {
    let workspace: Workspace
    let model: AppModel
    @State private var showsReplaceKey = false
    @State private var confirmsSignOut = false
    /// The legal page open in the in-app browser, if any.
    @State private var legalPage: Website.LegalPage?

    var body: some View {
        NavigationStack {
            List {
                if DemoMode.isOn {
                    Section {
                        InlineMessage(text: DemoMode.notice, systemImage: "info.circle.fill", color: .blue)
                            .accessibilityIdentifier("demoNotice")
                    }
                }
                shopSection
                StripeConnectionSection(workspace: workspace)
                noShowSection
                tapToPaySection
                serverSection
                keySection
                legalSection
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
                await workspace.noShow.refresh()
                await workspace.stripeConnection.refresh()
            }
            .task {
                async let health: Void = workspace.refreshHealth()
                async let noShow: Void = workspace.noShow.refresh()
                async let stripe: Void = workspace.stripeConnection.refresh()
                _ = await (health, noShow, stripe)
            }
            .sheet(isPresented: $showsReplaceKey) {
                ReplaceKeyView(model: model)
            }
            .sheet(item: $legalPage) { page in
                WebPageSheet(url: page.url(on: workspace.environment.websiteURL))
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

    /// The shop's own products (they used to have a tab of their own).
    private var shopSection: some View {
        Section {
            NavigationLink {
                ProductsView(store: workspace.products, allowsTestPhoto: workspace.environment.usesSampleServer)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Products")
                        Text("What clients see in the Izzy Clipz app, with photos and prices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bag")
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("productsLink")
        } header: {
            Text("Shop")
        }
    }

    /// The website's Privacy Policy, Terms of Service, Cancellation & No-Show Policy and
    /// Accessibility pages, in the in-app browser.
    private var legalSection: some View {
        Section {
            ForEach(Website.LegalPage.allCases) { page in
                Button {
                    legalPage = page
                } label: {
                    HStack {
                        Text(page.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the page on the shop's website.")
                .accessibilityIdentifier(page.identifier)
            }
        } header: {
            Text("Legal")
        } footer: {
            Text("The shop's policies, on its website: what clients agree to when they book, and how their details are used.")
        }
    }

    private var serverSection: some View {
        Section {
            LabeledContent("Address", value: workspace.environment.serverDescription)
            if let health = workspace.health {
                // A plain row: a Label inside LabeledContent made the row three times as tall.
                HStack(spacing: 6) {
                    Text("Status")
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Online")
                        .foregroundStyle(.green)
                }
                // One element, "Status, Online".
                .accessibilityElement(children: .combine)
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

    private var noShowSection: some View {
        Section {
            NavigationLink {
                NoShowSettingsView(store: workspace.noShow, stripe: workspace.ownerStatus?.stripe)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No-show protection")
                    Text(workspace.noShow.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("noShowSettingsLink")
        } header: {
            Text("Bookings")
        } footer: {
            Text("A card on file for online bookings, and the fee for no-shows and late cancellations.")
        }
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
