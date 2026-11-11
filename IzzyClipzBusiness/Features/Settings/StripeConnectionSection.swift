import IzzyClipzKit
import SwiftUI

/// Settings → Card payments (Stripe): the "login window" that connects the shop's own Stripe
/// account. The status row says where it stands ("Connected" with a green check and the business
/// name, "Not connected", "Finish setting up"…), the main button opens Stripe's own window
/// (Connect Stripe, or Finish setting up), and once an account is connected there's Open Stripe
/// Dashboard and Disconnect Stripe (which asks first).
///
/// On a server from before Stripe Connect, it shows what `GET /api/owner/me` says, as before.
struct StripeConnectionSection: View {
    let workspace: Workspace
    @State private var confirmsDisconnect = false
    @Environment(\.openURL) private var openURL

    private var store: StripeConnectionStore { workspace.stripeConnection }

    var body: some View {
        Section {
            if store.loadState == .notOnThisServer {
                serverStatusRows
            } else if let display = store.display {
                statusRows(display)
            } else if case .failed(let message) = store.loadState {
                InlineMessage(text: message)
                    .accessibilityIdentifier("stripeLoadError")
                Button("Try again") { Task { await store.refresh() } }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("retryStripe")
            } else {
                LabeledContent("Card payments") { ProgressView() }
                    .accessibilityIdentifier("stripeLoading")
            }
        } header: {
            Text("Card payments (Stripe)")
        } footer: {
            Text(footer)
        }
    }

    // MARK: The shop's Stripe account

    @ViewBuilder
    private func statusRows(_ display: StripeStatusDisplay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: display.symbol)
                .font(.title2)
                .foregroundStyle(display.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.title)
                    .font(.headline)
                if let name = display.businessName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.spoken)
        .accessibilityIdentifier("stripeStatus")

        Text(display.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("stripeMessage")

        if let result = store.result {
            InlineMessage(
                text: result.message,
                systemImage: result.isGoodNews ? "checkmark.circle.fill" : "info.circle.fill",
                color: result.isGoodNews ? .green : .blue
            )
            .accessibilityIdentifier("stripeResult")
        }
        if let error = store.actionError {
            InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                .accessibilityIdentifier("stripeActionError")
        }

        if let title = display.buttonTitle {
            Button {
                Task { await store.connect() }
            } label: {
                HStack(spacing: 8) {
                    if store.isConnecting {
                        ProgressView().tint(.white)
                    }
                    Text(store.isConnecting ? "Opening Stripe…" : title)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isConnecting || store.isDisconnecting)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .accessibilityHint("Opens Stripe, where you sign in or sign up and finish setting up.")
            .accessibilityIdentifier("connectStripe")
        }

        if let stripe = workspace.ownerStatus?.stripe, stripe.configured {
            modeRows(stripe)
        }

        if display.showsDashboard {
            Button {
                openURL(display.dashboardURL)
            } label: {
                Label("Open Stripe Dashboard", systemImage: "safari")
                    .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .accessibilityHint("Opens Stripe in Safari: payments, payouts and refunds.")
            .accessibilityIdentifier("openStripeDashboard")
        }
        if display.canDisconnect {
            Button(role: .destructive) {
                confirmsDisconnect = true
            } label: {
                HStack {
                    Label("Disconnect Stripe", systemImage: "xmark.circle")
                    Spacer()
                    if store.isDisconnecting { ProgressView() }
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .disabled(store.isConnecting || store.isDisconnecting)
            .accessibilityIdentifier("disconnectStripe")
            .confirmationDialog(StripeConnectionStore.disconnectQuestion, isPresented: $confirmsDisconnect, titleVisibility: .visible) {
                Button("Disconnect Stripe", role: .destructive) {
                    Task { await store.disconnect() }
                }
                .accessibilityIdentifier("confirmDisconnectStripe")
                Button("Keep it connected", role: .cancel) {}
            } message: {
                Text(StripeConnectionStore.disconnectExplanation)
            }
        }
    }

    /// Live or test keys, and the Terminal location Tap to Pay connects to.
    @ViewBuilder
    private func modeRows(_ stripe: IzzyAPI.StripeStatus) -> some View {
        LabeledContent("Mode", value: stripe.mode == .live ? "Live: real money" : stripe.mode == .test ? "Test mode: no real money" : "Unknown")
            .accessibilityIdentifier("stripeMode")
        LabeledContent("Terminal location", value: stripe.locationId ?? "Missing")
            .accessibilityIdentifier("stripeLocation")
    }

    // MARK: A server from before Stripe Connect

    @ViewBuilder
    private var serverStatusRows: some View {
        if let stripe = workspace.ownerStatus?.stripe {
            LabeledContent("Card payments", value: stripe.configured ? "Set up" : "Not set up")
                .accessibilityIdentifier("stripeConfigured")
            if stripe.configured {
                modeRows(stripe)
            }
        } else if let error = workspace.statusError {
            InlineMessage(text: error)
        } else {
            LabeledContent("Card payments") { ProgressView() }
        }
    }

    // MARK: Footer

    private var footer: String {
        var lines: [String] = []
        let usesTheServersKey = store.loadState == .notOnThisServer || store.connection?.mode == .off
        if usesTheServersKey, let hint = Self.serverSetupHint(workspace.ownerStatus?.stripe) {
            lines.append(hint)
        } else {
            lines.append("Payments go straight to your own Stripe account. Stripe charges its fees there.")
            if workspace.ownerStatus?.stripe.configured == true, workspace.ownerStatus?.stripe.mode == .test {
                lines.append("Stripe test mode: only Stripe test cards work and no money moves.")
            }
        }
        if DemoMode.isOn { lines.append(DemoMode.stripeNotice) }
        return lines.joined(separator: "\n\n")
    }

    /// What to set on the server when it takes card payments with its own Stripe key.
    static func serverSetupHint(_ stripe: IzzyAPI.StripeStatus?) -> String? {
        guard let stripe else { return nil }
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
}

extension StripeStatusDisplay.Tone {
    var color: Color {
        switch self {
        case .good: return .green
        case .waiting: return BusinessTheme.caution
        case .problem: return .red
        case .neutral: return .secondary
        }
    }
}
