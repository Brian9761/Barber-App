import SwiftUI

/// The bag sheet: what's in the client's Bravo bag, the subtotal, how far it
/// is from Bravo's free shipping, and "Check out on Bravo".
///
/// Plain SwiftUI on purpose, with no theme tokens, so the bag works end to
/// end while the Shop's Street Drip styling is built; that restyle replaces it.
struct BagView: View {
    @Environment(BagStore.self) private var bag
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bag.isEmpty {
                    emptyBag
                } else {
                    contents
                }
            }
            .navigationTitle("Your bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("bagDoneButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("bagSheet")
    }

    private var contents: some View {
        List {
            Section {
                ForEach(bag.lines) { line in
                    BagLineRow(line: line)
                }
                .onDelete { offsets in
                    let lines = bag.lines
                    for index in offsets where lines.indices.contains(index) {
                        bag.remove(lines[index].product)
                    }
                }
            } header: {
                Text(bag.count == 1 ? "1 item" : "\(bag.count) items")
            }

            Section {
                LabeledContent("Subtotal", value: bag.subtotal.label)
                    .accessibilityIdentifier("bagSubtotal")
                BagShippingMeter()
            } footer: {
                Text("Payment and shipping happen on bravohairgel.com, where Bravo shows the final total with shipping and tax.")
            }

            Section {
                Button("Check out on Bravo") {
                    if let url = bag.checkoutURL {
                        router.checkOut(url)
                    }
                }
                .bold()
                .disabled(bag.checkoutURL == nil)
                .accessibilityIdentifier("bagCheckoutButton")
            }
        }
    }

    private var emptyBag: some View {
        ContentUnavailableView {
            Label("Your bag is empty", systemImage: "bag")
        } description: {
            Text("Bravo gels, clay and pomade, shipped by Bravo.")
        } actions: {
            Button("Browse the shop") {
                router.closeSheet()
                router.selectedTab = .shop
            }
            .accessibilityIdentifier("bagBrowseShopButton")
        }
    }
}

/// A product in the bag, with its quantity stepper and a remove button.
private struct BagLineRow: View {
    @Environment(BagStore.self) private var bag
    let line: BagStore.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.product.name)
                        .font(.headline)
                    if let size = line.product.size {
                        Text(size)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if line.isSoldOut {
                        Text("Sold out at Bravo, so it's left out of checkout")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer()
                Text(line.total.label)
                    .font(.headline)
                    .monospacedDigit()
            }
            Stepper(value: quantity, in: quantityRange) {
                Text("Quantity: \(line.quantity)")
            }
            .accessibilityIdentifier("bagStepper-\(line.product.id)")
            Button("Remove", role: .destructive) {
                bag.remove(line.product)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(line.product.name)")
            .accessibilityIdentifier("bagRemove-\(line.product.id)")
        }
        .padding(.vertical, 4)
    }

    /// A sold-out product can go down but not up.
    private var quantityRange: ClosedRange<Int> {
        let range = BagStore.quantityRange
        return line.isSoldOut ? range.lowerBound...max(range.lowerBound, line.quantity) : range
    }

    private var quantity: Binding<Int> {
        Binding(
            get: { line.quantity },
            set: { bag.setQuantity($0, of: line.product) }
        )
    }
}

/// How far the subtotal is from Bravo's free U.S. shipping.
private struct BagShippingMeter: View {
    @Environment(BagStore.self) private var bag

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: bag.freeShippingProgress)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bagShippingMeter")
    }

    private var text: String {
        let threshold = bag.freeShippingThreshold.label
        if bag.reachesFreeShipping {
            return "Free U.S. shipping at checkout (\(threshold)+)"
        }
        return "\(bag.amountToFreeShipping.label) away from Bravo's free U.S. shipping (\(threshold)+)"
    }
}
