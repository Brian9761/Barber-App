import SwiftUI

/// A Bravo product on the Shop's grid: its photo on a white tile, the name, the size and the price.
///
/// The price is Bravo's current one once the store has answered, otherwise the one bundled with
/// the app, swapped in place with no spinner. The card is the face of a link to the product; the
/// "+" that adds it to the bag is not part of it (a button can't sit inside a link's label), so
/// `ShopProductTile` lays that over the photo as a sibling. Give the card its row's full height so
/// cards side by side line up.
struct ProductCard: View {
    let product: Product
    /// How many sizes the item comes in (White Hair Gel: 4 oz and 16 oz). More than one shows a tag.
    var sizeCount = 1

    @Environment(BravoStore.self) private var bravo

    /// The photo tile's width over its height: 128 pt tall in a 173 pt column, as in the mock.
    static let photoAspectRatio: CGFloat = 1.35

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ProductPhoto(product: product, cornerRadius: Theme.Radius.tile, inset: 10, aspectRatio: Self.photoAspectRatio)
                .overlay(alignment: .topLeading) {
                    tags
                        .padding(Theme.Space.s)
                }
                .accessibilityHidden(true)
            Text(product.name)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            sizeAndPrice
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    /// "SOLD OUT" and "2 SIZES" on the photo's top-left corner.
    @ViewBuilder private var tags: some View {
        let isSoldOut = bravo.isSoldOut(product)
        if isSoldOut || sizeCount > 1 {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                if isSoldOut {
                    ProductSoldOutBadge()
                }
                if sizeCount > 1 {
                    MonoTag(text: "\(sizeCount) sizes", style: .ink)
                }
            }
        }
    }

    /// "16 OZ" on the left and the price on the right, or the price under the size when they
    /// don't fit side by side.
    private var sizeAndPrice: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                size
                Spacer(minLength: Theme.Space.xxs)
                price
            }
            VStack(alignment: .leading, spacing: 2) {
                size
                price
            }
        }
    }

    @ViewBuilder private var size: some View {
        if let size = product.size {
            Text(size)
                .textRole(.monoNumber)
                .foregroundStyle(Theme.smoke)
                .lineLimit(1)
        }
    }

    private var price: some View {
        PriceText(bravo.price(for: product).label)
            .foregroundStyle(Theme.bone)
    }

    /// What VoiceOver reads for a product: "Blue Hair Gel, 16 oz, $17.99, also in 4 oz, sold out".
    static func accessibilityText(for product: Product, price: Price, isSoldOut: Bool, otherSizes: [String] = []) -> String {
        var parts = [product.name]
        if let size = product.size {
            parts.append(size)
        }
        parts.append(price.label)
        if !otherSizes.isEmpty {
            parts.append("also in \(otherSizes.joined(separator: " and "))")
        }
        if isSoldOut {
            parts.append("sold out")
        }
        return parts.joined(separator: ", ")
    }
}

/// A product's photo on a white tile. The photos are studio shots on pure white, so the tile is
/// white to match: no blend modes, no visible photo edge. The photo is fitted inside, whatever the
/// tile's shape.
struct ProductPhoto: View {
    let product: Product
    var cornerRadius: CGFloat = Theme.Radius.tile
    /// White space between the photo and the tile's edge.
    var inset: CGFloat = 8
    /// The tile's width over its height.
    var aspectRatio: CGFloat = 1

    var body: some View {
        Color.white
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                Image(product.imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(inset)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// "Sold out", laid over a product's photo: an ink tag on the white tile. Hidden from VoiceOver:
/// the product's label or a note next to it says so instead.
struct ProductSoldOutBadge: View {
    var body: some View {
        MonoTag(text: "Sold out", style: .ink)
            .accessibilityHidden(true)
    }
}

// MARK: - Quick add

/// The "+" on a product tile: a 34 pt ink circle on the white photo, 44 pt to tap. It adds one to
/// the bag with a success haptic, turns into a check mark for 1.2 s and tells VoiceOver. Disabled
/// (a pale circle) when the product is sold out or the bag can't take another.
///
/// VoiceOver: "Add White Hair Gel to bag", with the size as its value when the item comes in several.
struct ShopQuickAddButton: View {
    let product: Product

    @Environment(BagStore.self) private var bag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var justAdded = false
    @State private var addCount = 0

    var body: some View {
        Button {
            guard bag.add(product) else { return }
            ShopBagFeedback.announceAdded(product)
            addCount += 1
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                justAdded = true
            }
        } label: {
            Image(systemName: justAdded ? Symbol.checkmark : Symbol.add)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ShopQuickAddButtonStyle())
        .disabled(!bag.canAdd(product) && !justAdded)
        .sensoryFeedback(.success, trigger: addCount)
        .task(id: addCount) {
            guard addCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    justAdded = false
                }
            } catch {
                // Tapped again: the newer tap's task resets it.
            }
        }
        .onDisappear { justAdded = false }
        .accessibilityLabel("Add \(product.name) to bag")
        .accessibilityValue(BravoShopCopy.otherSizes(of: product).isEmpty ? "" : (product.size ?? ""))
        .accessibilityIdentifier("quickAdd-\(product.id)")
    }
}

/// The quick-add circle: ink with a bone "+" on the photo's white, or bone2 with a smokeDark "+"
/// when it can't add. 34 pt to see, 44 pt to tap.
private struct ShopQuickAddButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.bone : Theme.smokeDark)
            .frame(width: 34, height: 34)
            .background(isEnabled ? Theme.ink : Theme.bone2, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .frame(width: Theme.minimumTapSize, height: Theme.minimumTapSize)
            .contentShape(Circle())
    }
}
