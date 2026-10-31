import SwiftUI

/// One Bravo product, pushed from the Shop tab.
///
/// Top to bottom: the photo on a big white tile ("SOLD OUT" on its corner when Bravo is out of it),
/// "BRAVO · HAIR GELS", the name in Display L, a size control for the gels that come in 4 oz and
/// 16 oz, the price from bravohairgel.com with the quantity stepper beside it, Bravo's summary and
/// highlights, the shipping row, and "See it on bravohairgel.com ↗". The red "ADD TO BAG · $17.99"
/// bar (this screen's one red) sits above the tab bar; after adding it reads "IN YOUR BAG ✓" for
/// 1.2 s with a success haptic. Sold out, the bar is a disabled "SOLD OUT AT BRAVO".
struct ProductDetailView: View {
    let product: Product

    @Environment(AppRouter.self) private var router
    @Environment(BravoStore.self) private var bravo
    @Environment(BagStore.self) private var bag
    /// The size picked on this page; `nil` until one is, which means `product`.
    @State private var selectedID: String?
    @State private var quantity = 1
    @State private var justAdded = false
    @State private var addCount = 0

    private let catalog = AppData.products

    /// Every size of the item, smallest first: [4 oz, 16 oz] for the blue and white gels.
    private var sizes: [Product] { catalog.sizes(of: product) }

    /// The size on screen.
    private var selected: Product {
        sizes.first { $0.id == selectedID } ?? product
    }

    private var price: Price { bravo.price(for: selected) }
    private var isSoldOut: Bool { bravo.isSoldOut(selected) }

    /// How many more of the selected size the bag takes: up to 10 of a product, 10 products in all,
    /// none while it's sold out.
    private var room: Int {
        guard bag.canAdd(selected) else { return 0 }
        return BagStore.quantityRange.upperBound - bag.quantity(of: selected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                photo
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    titles
                    sizeControl
                    priceRow
                    if isSoldOut {
                        soldOutNote
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    Text(selected.summary)
                        .textRole(.body)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    ProductHighlights(highlights: selected.highlights)
                }
                shippingRow
                storeLinks
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .navigationTitle(selected.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShopToolbarBagButton(identifier: "productBagButton")
            }
        }
        .stickyBottomBar {
            addToBagButton
        }
        .sensoryFeedback(.success, trigger: addCount)
        .task(id: addCount) {
            guard addCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                justAdded = false
            } catch {
                // Added again: the newer task resets it.
            }
        }
        .onChange(of: room) { _, room in
            quantity = min(quantity, max(1, room))
        }
        .onDisappear { justAdded = false }
    }

    // MARK: Photo and titles

    private var photo: some View {
        ProductPhoto(product: selected, cornerRadius: Theme.Radius.hero, inset: 20, aspectRatio: 358 / 300)
            .overlay(alignment: .topLeading) {
                if isSoldOut {
                    ProductSoldOutBadge()
                        .padding(14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo of \(BravoShopCopy.name(of: selected))")
            .accessibilityAddTraits(.isImage)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Kicker("\(catalog.sponsor.name) · \(selected.category.title)")
            Text(selected.name)
                .textRole(.displayL)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// 4 oz / 16 oz chips for an item that comes in several sizes, or just the size ("3 PACK").
    @ViewBuilder private var sizeControl: some View {
        if sizes.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Kicker("Size")
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        sizeChips
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        sizeChips
                    }
                }
            }
        } else if let size = selected.size {
            Text(size)
                .textRole(.detail)
                .foregroundStyle(Theme.smoke)
        }
    }

    private var sizeChips: some View {
        ForEach(sizes) { size in
            let isSelected = size.id == selected.id
            let soldOut = bravo.isSoldOut(size)
            Button {
                selectedID = size.id
            } label: {
                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: Symbol.checkmark)
                            .font(.system(size: 11, weight: .heavy))
                            .accessibilityHidden(true)
                    }
                    Text(sizeChipText(size, soldOut: soldOut))
                        .lineLimit(1)
                }
            }
            .buttonStyle(ChipButtonStyle(isSelected: isSelected))
            .accessibilityLabel("\(size.size ?? size.name) size, \(soldOut ? "sold out" : bravo.price(for: size).label)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("productSize-\(size.id)")
        }
    }

    private func sizeChipText(_ size: Product, soldOut: Bool) -> String {
        let label = size.size ?? size.name
        return soldOut ? "\(label) · Sold out" : "\(label) · \(bravo.price(for: size).label)"
    }

    // MARK: Price and quantity

    /// The price and "PRICE FROM BRAVOHAIRGEL.COM", with the quantity stepper beside them (under
    /// them when they don't fit on one line).
    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                priceBlock
                Spacer(minLength: 0)
                stepper
            }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                priceBlock
                stepper
            }
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(price.label)
                .textRole(.priceL)
                .foregroundStyle(Theme.bone)
                .lineLimit(1)
            Text("Price from \(BravoShopCopy.storeHost)")
                .textRole(.label)
                .foregroundStyle(Theme.smoke)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(price.label), price from \(BravoShopCopy.storeHost)")
    }

    @ViewBuilder private var stepper: some View {
        if !isSoldOut {
            ShopQuantityStepper(value: $quantity, range: 1...max(1, room), label: "Quantity")
                .disabled(room == 0)
                .accessibilityIdentifier("productQuantity")
        }
    }

    private var soldOutNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: Symbol.warning)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text("\(catalog.sponsor.name)'s store shows this as sold out right now.")
                .textRole(.body)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Shipping and links

    /// "Free shipping on U.S. orders $64+", sold and shipped by Bravo, on an ink card.
    private var shippingRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            Image(systemName: Symbol.shipping)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.bone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(catalog.sponsor.shippingNote)
                    .textRole(.callout)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sold and shipped by \(catalog.sponsor.name)")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }

    /// The product and the whole store on bravohairgel.com, then where the prices come from.
    private var storeLinks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.openWeb(catalog.url(for: selected))
            } label: {
                linkLabel("See it on \(BravoShopCopy.storeHost)")
            }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityHint("Opens \(BravoShopCopy.name(of: selected)) on \(BravoShopCopy.storeHost)")
            .accessibilityIdentifier("buyProductButton")

            Button {
                router.openWeb(catalog.storeURL)
            } label: {
                linkLabel("Shop all \(catalog.sponsor.name) products")
            }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityHint("Opens \(BravoShopCopy.storeHost)")
            .accessibilityIdentifier("productShopAllBravo")

            Text(BravoShopCopy.finePrint)
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.s)
        }
    }

    private func linkLabel(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: Symbol.external)
                .font(.system(size: 13, weight: .bold))
                .accessibilityHidden(true)
        }
    }

    // MARK: Add to bag

    private var addToBagButton: some View {
        Button(action: addToBag) {
            Text(addTitle)
        }
        .buttonStyle(.primary(trailingSymbol: addSymbol))
        .disabled(room == 0 && !justAdded)
        .accessibilityLabel(addAccessibilityLabel)
        .accessibilityIdentifier("addToBagButton")
    }

    private var total: Price {
        Price(cents: price.cents * quantity)
    }

    /// "Add to bag · $17.99", "In your bag", "Sold out at Bravo", or why the bag can't take more.
    private var addTitle: String {
        if justAdded { return "In your bag" }
        if isSoldOut { return "Sold out at \(catalog.sponsor.name)" }
        if room == 0 { return "Bag limit reached" }
        return "Add to bag · \(total.label)"
    }

    private var addSymbol: String? {
        if justAdded { return Symbol.checkmark }
        return room == 0 ? nil : Symbol.add
    }

    private var addAccessibilityLabel: String {
        let name = BravoShopCopy.name(of: selected)
        if justAdded { return "In your bag: \(name)" }
        if isSoldOut { return "\(name) is sold out at \(catalog.sponsor.name)" }
        if room == 0 {
            return bag.quantity(of: selected) > 0
                ? "Bag limit reached: \(bag.quantity(of: selected)) \(name) in your bag"
                : "Bag limit reached: your bag holds \(Bag.maxLines) different products"
        }
        let what = quantity > 1 ? "\(quantity) \(name)" : name
        return "Add \(what) to bag, \(total.label)"
    }

    private func addToBag() {
        // The bar reads "In your bag" for a moment; a second tap then would add the same again.
        guard !justAdded else { return }
        let amount = min(quantity, room)
        guard amount > 0, bag.add(selected, quantity: amount) else { return }
        ShopBagFeedback.announceAdded(selected, quantity: amount)
        addCount += 1
        justAdded = true
        quantity = 1
    }
}

/// The product's selling points, from Bravo's description, each after a 6 pt bone square.
private struct ProductHighlights: View {
    let highlights: [String]

    var body: some View {
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Highlights")
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { item in
                        ProductHighlightRow(text: item.element)
                    }
                }
            }
        }
    }
}

/// A highlight with a 6 pt bone square for a bullet.
private struct ProductHighlightRow: View {
    let text: String

    /// How far above the text's baseline the bullet's centre sits: about half the x-height.
    @ScaledMetric(relativeTo: .body) private var bulletRise: CGFloat = 4.5

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Rectangle()
                .fill(Theme.bone)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height / 2 + bulletRise }
                .accessibilityHidden(true)
            Text(text)
                .textRole(.body)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
