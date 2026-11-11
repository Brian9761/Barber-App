import IzzyClipzKit
import SwiftUI

/// Opens a sale from Today's sales.
struct SaleLink: Hashable {
    let id: String
}

/// Today's sales, at the bottom of Take payment: time, client, barber, method and total, newest
/// first, voided ones struck through. A sale opens to its details, with Void sale.
struct TodaysSalesSection: View {
    let store: SalesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's sales")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let totals = store.totalsText {
                    Text(totals)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("salesTotal")
                }
            }
            if let error = store.refreshError {
                InlineMessage(text: "Couldn't refresh: \(error)")
            }
            switch store.loadState {
            case .idle:
                loading
            case .loading where store.sales.isEmpty:
                loading
            case .failed(let message):
                InlineMessage(text: message)
                Button("Try again") { Task { await store.refresh() } }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("retrySales")
            default:
                if store.sales.isEmpty {
                    Text("No sales yet today. Sales show up here as you check clients out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("salesEmpty")
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.sales) { sale in
                            NavigationLink(value: SaleLink(id: sale.id)) {
                                SaleRow(sale: sale, detail: store.rowDetail(for: sale))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sale-\(sale.customerName ?? "Walk-in")")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading today's sales…").foregroundStyle(.secondary)
        }
    }
}

/// One sale in the list: "$63" and "11 AM · Diego Sample · Carlos · Cash", struck through once
/// voided.
struct SaleRow: View {
    let sale: IzzyAPI.Sale
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(sale.totalLabel)
                        .font(.headline.monospacedDigit())
                        .strikethrough(sale.isVoided)
                    if sale.isVoided {
                        Badge(text: "Voided", color: .gray)
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .strikethrough(sale.isVoided)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: BusinessTheme.minimumTapSize)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        .opacity(sale.isVoided ? 0.7 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([sale.receiptLine, detail] + (sale.isVoided ? ["voided"] : [])).joined(separator: ", "))
    }
}

/// A sale's details: what was sold, by whom and how, and Void sale, which asks first (with an
/// optional reason, and for a card the reminder to refund it in the Stripe Dashboard).
struct SaleDetailView: View {
    let saleID: String
    let store: SalesStore
    @State private var asksToVoid = false
    @State private var reason = ""

    var body: some View {
        Group {
            if let sale = store.sale(withID: saleID) {
                details(sale)
            } else {
                ContentUnavailableView("Sale not found", systemImage: "receipt", description: Text("It's no longer in today's sales."))
            }
        }
        .navigationTitle("Sale")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "That didn't work",
            isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }

    private func details(_ sale: IzzyAPI.Sale) -> some View {
        let receipt = SaleReceipt(sale: sale)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(receipt.summary)
                        .font(.title3.bold())
                        .strikethrough(sale.isVoided)
                        .accessibilityIdentifier("saleSummary")
                    if sale.isVoided {
                        Badge(text: "Voided", color: .gray)
                            .accessibilityIdentifier("saleVoided")
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("When", value: store.shopTime.dayAndTime(sale.soldAt))
                LabeledContent("Client", value: sale.customerName ?? "Walk-in")
                if sale.appointmentId != nil {
                    LabeledContent("Appointment", value: "Checked out with this sale")
                }
                if sale.isVoided, let reason = sale.voidReason {
                    LabeledContent("Why it was voided", value: reason)
                }
            }
            Section("Items") {
                SaleLines(receipt: receipt)
            }
            if let message = store.voidMessages[sale.id] {
                Section {
                    InlineMessage(text: message, systemImage: "info.circle.fill", color: .blue)
                        .accessibilityIdentifier("voidMessage")
                }
            }
            if !sale.isVoided {
                Section {
                    Button(role: .destructive) {
                        reason = ""
                        asksToVoid = true
                    } label: {
                        HStack {
                            Label("Void sale", systemImage: "xmark.bin")
                            Spacer()
                            if store.voiding.contains(sale.id) { ProgressView() }
                        }
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                    }
                    .disabled(store.voiding.contains(sale.id))
                    .accessibilityIdentifier("voidSale")
                } footer: {
                    Text(sale.method == .card
                        ? "For a mistake: the sale stops counting. Voiding doesn't refund the card. Refund the card in your Stripe Dashboard."
                        : "For a mistake: the sale stops counting in your sales.")
                }
            }
        }
        .alert(SalesStore.voidQuestion(for: sale), isPresented: $asksToVoid) {
            TextField("Reason (optional)", text: $reason)
                .accessibilityIdentifier("voidReason")
            Button("Void sale", role: .destructive) {
                let why = reason
                Task { await store.void(sale, reason: why) }
            }
            .accessibilityIdentifier("confirmVoidSale")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(SalesStore.voidExplanation(for: sale))
        }
    }
}

/// A receipt's items, one per row, and the total.
struct SaleLines: View {
    let receipt: SaleReceipt

    var body: some View {
        ForEach(Array(receipt.lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                    if line.price != line.total {
                        Text(line.price)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(line.total)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
        HStack {
            Text("Total").font(.headline)
            Spacer()
            Text(Money.amount(receipt.totalCents))
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

/// The receipt on the success screen: "Sold $60 · Cash · Izzy", the client, and the items.
struct SaleReceiptCard: View {
    let receipt: SaleReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(receipt.summary)
                .font(.headline)
                .accessibilityIdentifier("saleReceiptLine")
            if let client = receipt.clientName {
                Text(client)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 8) {
                SaleLines(receipt: receipt)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saleReceipt")
    }
}
