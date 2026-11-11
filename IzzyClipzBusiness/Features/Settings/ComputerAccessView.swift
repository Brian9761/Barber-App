import IzzyClipzKit
import SwiftUI

/// Settings → Use on a computer: how to sign in to the website's Business area with a code, the
/// code itself (big, "483 920", counting down), and the computers signed in, each with Sign out,
/// plus Sign out all computers (which asks first).
struct ComputerAccessView: View {
    let store: ComputerAccessStore
    @State private var confirmsSignOutAll = false
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 52

    var body: some View {
        List {
            Section {
                Text("See your schedule, sales and analytics on a computer.")
                    .accessibilityIdentifier("computerIntro")
            }
            codeSection
            computersSection
            if !store.sessions.isEmpty {
                Section {
                    Button(role: .destructive) {
                        confirmsSignOutAll = true
                    } label: {
                        HStack {
                            Text("Sign out all computers")
                            Spacer()
                            if store.isSigningOutAll { ProgressView() }
                        }
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                    }
                    .disabled(store.isSigningOutAll)
                    .accessibilityIdentifier("signOutAllComputers")
                    .confirmationDialog(ComputerAccessStore.signOutAllQuestion, isPresented: $confirmsSignOutAll, titleVisibility: .visible) {
                        Button("Sign out all computers", role: .destructive) {
                            Task { await store.signOutAll() }
                        }
                        .accessibilityIdentifier("confirmSignOutAllComputers")
                        Button("Keep them signed in", role: .cancel) {}
                    } message: {
                        Text(ComputerAccessStore.signOutAllExplanation)
                    }
                }
            }
        }
        .navigationTitle("Use on a computer")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshSessions() }
        .task {
            async let code: Void = store.showCodeIfNeeded()
            async let computers: Void = store.refreshSessions()
            _ = await (code, computers)
        }
        .alert(
            "That didn't work",
            isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }

    // MARK: The code

    private var codeSection: some View {
        Section {
            step(1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On your computer, go to")
                    Text(store.siteAddress)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("computerSite")
                }
            }
            step(2) {
                Text("Type this code")
            }
            // Read the clock every second, so "Expires in" counts down.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                codeBlock(now: store.clock())
            }
            Button {
                Task { await store.makeCode() }
            } label: {
                HStack {
                    Label("Get a new code", systemImage: "arrow.clockwise")
                    Spacer()
                    if store.isMakingCode && store.code != nil { ProgressView() }
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .disabled(store.isMakingCode)
            .accessibilityIdentifier("newComputerCode")
        } header: {
            Text("Sign in with a code")
        } footer: {
            Text(codeFooter)
        }
    }

    @ViewBuilder
    private func codeBlock(now: Date) -> some View {
        VStack(spacing: 8) {
            if let code = store.code {
                let runOut = store.codeHasRunOut(at: now)
                Text(code.grouped)
                    .font(.system(size: codeSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(runOut ? .secondary : .primary)
                    .strikethrough(runOut)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Code \(store.spokenCode ?? code.code)")
                    .accessibilityIdentifier("computerCode")
                if let countdown = store.countdownText(at: now) {
                    Text(countdown)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(runOut ? BusinessTheme.caution : .secondary)
                        .accessibilityIdentifier("computerCodeExpiry")
                }
            } else if store.isMakingCode {
                ProgressView("Getting a code…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            if let error = store.codeError {
                InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("computerCodeError")
            }
        }
        .padding(.vertical, 8)
    }

    private var codeFooter: String {
        var text = "A code works once, for 10 minutes. The computer then stays signed in for 30 days, until you sign it out."
        if DemoMode.isOn {
            text += "\n\nDemo version: on the demo website, tap Open the Business demo. No code is needed."
        }
        return text
    }

    /// "1", "2": a numbered step.
    private func step<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number).")
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(BusinessTheme.red)
                .accessibilityHidden(true)
            content()
        }
    }

    // MARK: Computers signed in

    @ViewBuilder
    private var computersSection: some View {
        Section {
            switch store.sessionsState {
            case .idle:
                loadingRow
            case .loading where store.sessions.isEmpty:
                loadingRow
            case .failed(let message):
                InlineMessage(text: message)
                Button("Try again") { Task { await store.refreshSessions() } }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("retryComputers")
            default:
                if store.sessions.isEmpty {
                    Text("No computers are signed in. Sign in on the website with a code, and the computer shows here.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("computersEmpty")
                } else {
                    ForEach(store.sessions) { session in
                        computerRow(session)
                    }
                }
            }
        } header: {
            Text("Computers signed in")
        } footer: {
            if !store.sessions.isEmpty {
                Text("Signing a computer out takes it back to the website's sign-in page.")
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView("Loading…")
            Spacer()
        }
    }

    private func computerRow(_ session: IzzyAPI.ComputerSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.body.weight(.semibold))
                Text(store.lastUsedText(for: session))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("computer-\(session.name)")
            Spacer(minLength: 8)
            if store.signingOut.contains(session.id) {
                ProgressView()
            } else {
                Button("Sign out") {
                    Task { await store.signOut(session) }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .disabled(store.isSigningOutAll)
                .accessibilityLabel("Sign out \(session.name)")
                .accessibilityIdentifier("signOutComputer-\(session.name)")
            }
        }
    }
}
