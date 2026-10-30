import SwiftUI

/// The bag sheet, opened from the Shop's bag buttons: what's in the client's Bravo bag and
/// "Checkout on Bravo".
///
/// Top to bottom: "YOUR BAG" with the item count and a close button; the free-shipping meter
/// (electric, not red, since the app only estimates it from its own prices); a row per product with
/// its photo, price, a 44 pt stepper and "Remove" (or swipe to delete); the subtotal and a note that
/// payment and shipping happen on bravohairgel.com; and the red "CHECKOUT ON BRAVO ↗" bar, the
/// sheet's one red, which opens Bravo's checkout with the items in its cart. Empty, it says so and
/// offers "BROWSE THE SHOP".
struct BagView: View {
    @Environment(BagStore.self) private var bag
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            if bag.isEmpty {
                BagEmptyState()
            } else {
                BagContents()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bagSheet")
    }

    /// "YOUR BAG", "3 ITEMS" and the close button.
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Your bag")
                    .textRole(.displayM)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !bag.isEmpty {
                    Text(ShopBagFeedback.itemCount(bag.count))
                        .textRole(.monoNumber)
                        .foregroundStyle(Theme.smoke)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismiss()
            } label: {
                Image(systemName: Symbol.close)
            }
            .buttonStyle(.icon)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("bagDoneButton")
        }
        .padding(.horizontal, Theme.gutter)
        // Clear of the drag indicator.
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.s)
    }
}

// MARK: - Contents

/// The meter, the lines, the subtotal and the checkout bar. A `List`, so lines swipe to delete.
private struct BagContents: View {
    @Environment(BagStore.self) private var bag
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            BagShippingMeter()
                .bagRow(separator: true)
            ForEach(bag.lines) { line in
                BagLineRow(line: line)
                    .bagRow(separator: true)
            }
            BagTotals()
                .bagRow(separator: false)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .stickyBottomBar {
            Button {
                if let url = bag.checkoutURL {
                    router.checkOut(url)
                }
            } label: {
                Text("Checkout on \(AppData.products.sponsor.name)")
            }
            .buttonStyle(.primary(trailingSymbol: Symbol.external))
            .disabled(bag.checkoutURL == nil)
            .accessibilityHint("Opens \(AppData.products.sponsor.name)'s checkout on \(BravoShopCopy.storeHost) with these items")
            .accessibilityIdentifier("bagCheckoutButton")
        }
    }
}

private extension View {
    /// A bag row on the sheet's own background, gutter-wide, with a hairline under it or none.
    func bagRow(separator: Bool) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Space.l, leading: Theme.gutter, bottom: Theme.Space.l, trailing: Theme.gutter))
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Theme.line)
    }
}

// MARK: - Free shipping

/// How far the bag is from Bravo's free U.S. shipping: a 6 pt `ink4` track with an `electric` fill
/// (not red: it's a status, not the action), "$18.03 AWAY FROM FREE SHIPPING", then "FREE U.S.
/// SHIPPING AT CHECKOUT" with a green dot at $64. The app works it out from its own prices; Bravo
/// decides at checkout, and the caption says so.
private struct BagShippingMeter: View {
    @Environment(BagStore.self) private var bag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sponsor = AppData.products.sponsor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                if bag.reachesFreeShipping {
                    Circle()
                        .fill(Theme.go)
                        .frame(width: 8, height: 8)
                }
                Text(headline)
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BagMeterFill(progress: 1)
                .fill(Theme.ink4)
                .overlay {
                    BagMeterFill(progress: bag.freeShippingProgress)
                        .fill(Theme.electric)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: bag.freeShippingProgress)
                }
                .frame(height: 6)
            Text("\(sponsor.shippingNote). Final total at checkout.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("bagShippingMeter")
    }

    private var headline: String {
        bag.reachesFreeShipping
            ? "Free U.S. shipping at checkout"
            : "\(bag.amountToFreeShipping.label) away from free shipping"
    }

    private var spoken: String {
        let threshold = bag.freeShippingThreshold.label
        if bag.reachesFreeShipping {
            return "Your bag reaches \(sponsor.name)'s free U.S. shipping (\(threshold)+). Final total at checkout."
        }
        return "\(bag.amountToFreeShipping.label) away from \(sponsor.name)'s free U.S. shipping (\(threshold)+). Final total at checkout."
    }
}

/// The meter's fill: a capsule `progress` (0…1) of the way across, never narrower than it is tall
/// once there's anything to show.
private struct BagMeterFill: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }
        let width = max(rect.height, rect.width * clamped)
        return Capsule().path(in: CGRect(x: rect.minX, y: rect.minY, width: min(width, rect.width), height: rect.height))
    }
}

// MARK: - Lines

/// A product in the bag: its photo on a 64 pt white tile, the name and size, the line's price (and
/// the unit price when there's more than one), then the quantity stepper and "Remove". Swipe to
/// delete works too. A product that sold out since it went in says it's left out of checkout and
/// can only go down.
private struct BagLineRow: View {
    let line: BagStore.Line

    @Environment(BagStore.self) private var bag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            ProductPhoto(product: line.product, cornerRadius: Theme.Radius.thumbnail, inset: 4)
                .frame(width: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                details
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenDetails)
                if line.isSoldOut {
                    soldOutNote
                }
                controls
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove()
            } label: {
                Label("Remove", systemImage: Symbol.remove)
            }
            .tint(Theme.dripRed)
        }
    }

    /// The name and size on the left, the prices on the right (under them when they don't fit).
    private var details: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                name
                Spacer(minLength: 0)
                prices(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                name
                prices(alignment: .leading)
            }
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.product.name)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            if let size = line.product.size {
                Text(size)
                    .textRole(.monoNumber)
                    .foregroundStyle(Theme.smoke)
            }
        }
    }

    private func prices(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            PriceText(line.total.label)
                .foregroundStyle(line.isSoldOut ? Theme.smoke : Theme.bone)
            if line.quantity > 1 {
                Text("\(line.unitPrice.label) each")
                    .textRole(.monoTag)
                    .foregroundStyle(Theme.smoke)
                    .lineLimit(1)
            }
        }
    }

    private var spokenDetails: String {
        var parts = [line.product.name]
        if let size = line.product.size {
            parts.append(size)
        }
        parts.append(line.quantity > 1 ? "\(line.quantity) at \(line.unitPrice.label), \(line.total.label)" : line.total.label)
        if line.isSoldOut {
            parts.append("sold out at \(AppData.products.sponsor.name), left out of checkout")
        }
        return parts.joined(separator: ", ")
    }

    private var soldOutNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Image(systemName: Symbol.warning)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.caution)
            Text("Sold out at \(AppData.products.sponsor.name), so it's left out of checkout.")
                .textRole(.caption)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHidden(true)
    }

    /// The stepper and "Remove", side by side or stacked at the biggest text sizes.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.l) {
                stepper
                removeButton
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                stepper
                removeButton
            }
        }
    }

    private var stepper: some View {
        ShopQuantityStepper(value: quantity, range: quantityRange, label: "\(line.product.name) quantity")
            .accessibilityIdentifier("bagStepper-\(line.product.id)")
    }

    private var removeButton: some View {
        Button("Remove") {
            remove()
        }
        .buttonStyle(.textLink(color: Theme.smoke))
        .accessibilityLabel("Remove \(line.product.name)")
        .accessibilityIdentifier("bagRemove-\(line.product.id)")
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

    private func remove() {
        withAnimation(reduceMotion ? nil : .default) {
            bag.remove(line.product)
        }
    }
}

// MARK: - Totals

/// "SUBTOTAL" and the total, then where shipping, tax and payment happen.
private struct BagTotals: View {
    @Environment(BagStore.self) private var bag

    private var hasSoldOut: Bool {
        bag.lines.contains(where: \.isSoldOut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                Text("Subtotal")
                    .textRole(.monoTag)
                    .foregroundStyle(Theme.smoke)
                Spacer(minLength: 0)
                Text(bag.subtotal.label)
                    .textRole(.priceL)
                    .foregroundStyle(Theme.bone)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Subtotal")
            .accessibilityValue(bag.subtotal.label)
            .accessibilityIdentifier("bagSubtotal")
            Text(note)
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var note: String {
        let sponsor = AppData.products.sponsor.name
        let base = "Shipping and tax on \(sponsor)'s checkout. Payment and shipping happen on \(BravoShopCopy.storeHost)."
        return hasSoldOut ? "Sold-out items aren't included. " + base : base
    }
}

// MARK: - Empty

/// "BAG'S EMPTY", what the bag is for, and a bone "BROWSE THE SHOP" that closes the sheet on the
/// Shop tab. Drawn on the sheet's own `ink2` (the shared empty state sits on the `ink` canvas).
private struct BagEmptyState: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: Symbol.shop)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                    .frame(width: 64, height: 64)
                    .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: Theme.Space.s) {
                    Text("Bag's empty")
                        .textRole(.displayM)
                        .foregroundStyle(Theme.bone)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(AppData.products.sponsor.name) gels, clay and pomade, shipped by \(AppData.products.sponsor.name).")
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                Button("Browse the shop") {
                    router.closeSheet()
                    router.selectedTab = .shop
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("bagBrowseShopButton")
                .padding(.top, Theme.Space.s)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.section)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
