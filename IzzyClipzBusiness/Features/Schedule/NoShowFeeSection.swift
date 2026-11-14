import IzzyClipzKit
import SwiftUI

/// An appointment's card on file and its fee (a no-show or a late cancellation): what the client
/// agreed to when booking, what happened to the fee, and Charge (which asks first), Charge again
/// after a decline, or Check again when Stripe hasn't answered. Nothing for an appointment
/// without a card on file.
struct NoShowFeeSection: View {
    let appointment: IzzyAPI.Appointment
    let now: Date
    let store: ScheduleStore
    @State private var confirmation: FeePanel.Confirmation?

    var body: some View {
        if let panel = FeePanel(appointment: appointment, now: now, shopTime: store.shopTime) {
            Section {
                LabeledContent("Card", value: panel.cardLabel)
                    .accessibilityIdentifier("detailCard")
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Fee agreed at booking", value: panel.feeLabel)
                    Text(panel.agreement)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detailFee")
                status(panel.status)
                if let error = store.feeError(for: appointment) {
                    InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                        .accessibilityIdentifier("feeError")
                }
                if let action = panel.action {
                    actionButton(action)
                }
            } header: {
                Text("Card on file")
            } footer: {
                if let footer = panel.footer { Text(footer) }
            }
        }
    }

    @ViewBuilder
    private func status(_ status: FeePanel.Status) -> some View {
        switch status {
        case .notCharged(let note):
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feeStatus")
            }
        case .charged(let title, let detail):
            outcome(symbol: "checkmark.circle.fill", tint: .green, title: title, detail: detail)
        case .declined(let reason):
            outcome(symbol: "xmark.octagon.fill", tint: .red, title: "Declined", detail: reason)
        case .needsClient(let message):
            outcome(symbol: "person.crop.circle.badge.exclamationmark", tint: .orange, title: "The card needs the client to approve it", detail: message)
        case .pending(let message):
            outcome(symbol: "hourglass", tint: .orange, title: "Not confirmed yet", detail: message)
        }
    }

    private func outcome(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feeStatus")
    }

    private func actionButton(_ action: FeePanel.Action) -> some View {
        let isCharging = store.chargingFee.contains(appointment.id)
        // Not while the status is changing either (Reopen, say): the server decides the fee by it.
        let isUpdating = store.updating.contains(appointment.id)
        return Button {
            if let confirmation = action.confirmation {
                self.confirmation = confirmation
            } else {
                Task { await store.chargeFee(for: appointment) }
            }
        } label: {
            HStack {
                Label(action.title, systemImage: action.checksAgain ? "arrow.clockwise" : "creditcard")
                Spacer(minLength: 8)
                if isCharging {
                    ProgressView()
                        .accessibilityLabel(action.checksAgain ? "Checking" : "Charging")
                }
            }
            .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .disabled(isCharging || isUpdating)
        .accessibilityIdentifier("chargeFee")
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { confirmation in
            Button(confirmation.button) {
                Task { await store.chargeFee(for: appointment) }
            }
            .accessibilityIdentifier("confirmChargeFee")
            Button("Don't charge", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}
