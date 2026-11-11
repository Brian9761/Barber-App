import IzzyClipzKit
import SwiftUI

/// "+ Service": the services of the barber who's selling, with that barber's prices. A barber who
/// hasn't been picked yet is picked here first.
struct ServicePickerSheet: View {
    let checkout: CheckoutModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Sold by", selection: Binding(
                        get: { checkout.ticket.barberId ?? "" },
                        set: { if !$0.isEmpty { checkout.chooseBarber($0) } }
                    )) {
                        if checkout.ticket.barberId == nil {
                            Text("Pick a barber").tag("")
                        }
                        ForEach(checkout.catalog.barbers) { barber in
                            Text(barber.name).tag(barber.id)
                        }
                    }
                    .accessibilityIdentifier("servicePickerBarber")
                } footer: {
                    Text("Each barber's own prices. You can change a price on the ticket.")
                }
                if let barberId = checkout.ticket.barberId {
                    Section(checkout.barberName.map { "\($0)'s services" } ?? "Services") {
                        ForEach(checkout.catalog.offerings(forBarber: barberId)) { offering in
                            let name = checkout.catalog.service(withID: offering.serviceID)?.name ?? offering.serviceID
                            Button {
                                checkout.ticket.addService(id: offering.serviceID, name: name, price: offering.price)
                                checkout.validationMessage = nil
                                dismiss()
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    Text(offering.price.label)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .frame(minHeight: BusinessTheme.minimumTapSize)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("pickService-\(name)")
                        }
                    }
                } else {
                    Section {
                        Text("Pick who's selling to see their services and prices.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add a service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelPicker")
                }
            }
        }
    }
}

/// "+ Product": the shop's products with their photos and prices (hidden ones too: they can still
/// be sold at the counter). A product without a price asks for one first.
struct ProductPickerSheet: View {
    let checkout: CheckoutModel
    let products: ProductsStore
    @Environment(\.dismiss) private var dismiss
    @State private var needsPrice: IzzyAPI.Product?

    var body: some View {
        NavigationStack {
            List {
                switch products.loadState {
                case .failed(let message) where products.products.isEmpty:
                    ContentUnavailableView {
                        Label("Couldn't load the products", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await products.refresh() } }
                            .buttonStyle(.borderedProminent)
                    }
                default:
                    if products.products.isEmpty {
                        if products.loadState == .loaded {
                            ContentUnavailableView(
                                "No products yet",
                                systemImage: "bag",
                                description: Text("Add the shop's products in Settings → Products, then sell them here.")
                            )
                        } else {
                            HStack {
                                Spacer()
                                ProgressView("Loading products…")
                                Spacer()
                            }
                        }
                    } else {
                        Section {
                            ForEach(products.products) { product in
                                Button {
                                    pick(product)
                                } label: {
                                    HStack(spacing: 12) {
                                        ProductThumbnail(url: product.imageUrl, localData: product.imageUrl.flatMap { products.uploadedPhotos[$0] })
                                            .frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(product.name)
                                                .foregroundStyle(.primary)
                                            if !product.visible {
                                                Text("Not shown in the app")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Text(product.priceCents.map(Money.amount) ?? "Enter a price")
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .frame(minHeight: BusinessTheme.minimumTapSize)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("pickProduct-\(product.name)")
                            }
                        } footer: {
                            Text("Tap a product again on the ticket's + Product to add another, or use its quantity.")
                        }
                    }
                }
            }
            .navigationTitle("Add a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelPicker")
                }
            }
            .navigationDestination(item: $needsPrice) { product in
                AmountEntryView(purpose: .productPrice(product), checkout: checkout) { dismiss() }
            }
            .task { await products.refresh() }
        }
    }

    private func pick(_ product: IzzyAPI.Product) {
        guard let price = product.priceCents else {
            needsPrice = product
            return
        }
        checkout.ticket.addProduct(product, unitCents: price)
        checkout.validationMessage = nil
        dismiss()
    }
}

/// The keypad, for "+ Amount" (an amount named "Other", or a name the owner types), a new price for
/// an item on the ticket, or the price of a product that has none.
struct AmountEntryView: View {
    enum Purpose: Equatable {
        case newAmount
        case price(itemID: Int)
        case productPrice(IzzyAPI.Product)
    }

    let purpose: Purpose
    let checkout: CheckoutModel
    let onDone: () -> Void
    @State private var entry = AmountEntry()
    @State private var name = ""
    @State private var problem: String?
    @State private var started = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if purpose == .newAmount {
                    TextField("Name (optional): Tip, Gift card…", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("amountName")
                }
                Text(Money.amount(entry.cents))
                    .font(.system(size: amountSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Amount")
                    .accessibilityValue(Money.spoken(entry.cents))
                    .accessibilityIdentifier("amountEntryValue")
                AmountKeypad(entry: $entry)
                if let problem {
                    InlineMessage(text: problem, systemImage: "exclamationmark.octagon.fill", color: .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("amountProblem")
                }
                Button(saveTitle, action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("saveAmount")
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A product's price is asked inside the product list, whose back button goes back to it.
            if !asksProductPrice {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelAmount")
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if case .price(let id) = purpose, let item = checkout.ticket.item(withID: id) {
                entry = AmountEntry(cents: item.unitCents)
            }
        }
    }

    private var asksProductPrice: Bool {
        if case .productPrice = purpose { return true }
        return false
    }

    private var title: String {
        switch purpose {
        case .newAmount: return "Add an amount"
        case .price(let id): return checkout.ticket.item(withID: id).map { "Price of \($0.name)" } ?? "Price"
        case .productPrice(let product): return "Price of \(product.name)"
        }
    }

    private var explanation: String {
        switch purpose {
        case .newAmount: return "Anything else on the ticket: a tip, a gift card, an extra. It's called Other unless you name it."
        case .price: return "The price of one. Type it like a cash register: 4, 5, 0, 0 is $45.00."
        case .productPrice: return "This product has no price yet. Type what the client pays for one."
        }
    }

    private var saveTitle: String {
        switch purpose {
        case .newAmount: return "Add \(Money.amount(entry.cents))"
        case .price: return "Save price"
        case .productPrice(let product): return "Add \(product.name)"
        }
    }

    private func save() {
        let cents = entry.cents
        guard cents <= IzzyAPI.NewSaleItem.unitCentsRange.upperBound else {
            problem = "That's more than $10,000. Check the amount."
            return
        }
        switch purpose {
        case .newAmount:
            guard cents > 0 else {
                problem = "Enter an amount."
                return
            }
            checkout.ticket.addAmount(cents, name: name)
        case .price(let id):
            checkout.ticket.setPrice(cents, of: id)
        case .productPrice(let product):
            guard cents > 0 else {
                problem = "Enter the price."
                return
            }
            checkout.ticket.addProduct(product, unitCents: cents)
        }
        checkout.validationMessage = nil
        onDone()
    }
}
