import SwiftUI

// Pieces the Shop tab, the product page and the bag sheet share.

// MARK: - Quantity

/// − / quantity / + with 44 pt buttons on an `ink3` capsule, for the product page and the bag.
///
/// VoiceOver and the UI tests see a standard stepper (its accessibility representation): one
/// adjustable element with "Increment" and "Decrement" buttons, its label and the quantity as its value.
struct ShopQuantityStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// What VoiceOver calls it, e.g. "Quantity" or "Blue Hair Gel quantity".
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            step(Symbol.subtract, isEnabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text("\(value)")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.bone)
                .lineLimit(1)
                .frame(minWidth: 28)
                .contentTransition(.numericText(value: Double(value)))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            step(Symbol.add, isEnabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .background(Theme.ink3, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .fixedSize()
        .accessibilityRepresentation {
            Stepper(label, value: $value, in: range)
                .accessibilityValue("\(value)")
        }
    }

    private func step(_ symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(ShopStepButtonStyle())
        .disabled(!isEnabled)
    }
}

/// One end of the quantity stepper: a bone glyph, 44 × 44 to tap, `boneDisabled` at the end of its range.
private struct ShopStepButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.bone : Theme.boneDisabled)
            .frame(width: Theme.minimumTapSize, height: Theme.minimumTapSize)
            .background(configuration.isPressed ? Theme.ink4 : Color.clear, in: Circle())
            .contentShape(Rectangle())
    }
}

// MARK: - Bag in the navigation bar

/// The bag in a navigation bar, on the Shop and on product pages: a bone bag glyph and, once
/// something's in it, the count on a red capsule (the Shop's one red). No circle (on iOS 26 the bar
/// draws its own glass). The count bumps when something goes in, except with Reduce Motion.
struct ShopToolbarBagButton: View {
    let identifier: String

    @Environment(BagStore.self) private var bag
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bumps = 0

    var body: some View {
        Button {
            router.openBag()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: bag.isEmpty ? Symbol.shop : Symbol.shopSelected)
                    .font(.system(size: 17, weight: .semibold))
                if !bag.isEmpty {
                    Text(ShopBagFeedback.badgeText(bag.count))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Theme.dripRed, in: Capsule())
                }
            }
            .foregroundStyle(Theme.bone)
            // The bar has a fixed height.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .keyframeAnimator(initialValue: 1.0, trigger: bumps) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(1.2, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
            .frame(minWidth: Theme.minimumTapSize, minHeight: Theme.minimumTapSize)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Bag")
        .accessibilityValue(bag.isEmpty ? "Empty" : ShopBagFeedback.itemCount(bag.count))
        .accessibilityHint("Shows what's in your bag")
        .accessibilityIdentifier(identifier)
        .onChange(of: bag.count) { old, new in
            if new > old, !reduceMotion {
                bumps += 1
            }
        }
    }
}

// MARK: - Feedback

/// What every way of adding to the bag says.
enum ShopBagFeedback {
    /// Tells VoiceOver what just went in the bag, since the button it's on doesn't move.
    @MainActor
    static func announceAdded(_ product: Product, quantity: Int = 1) {
        let name = BravoShopCopy.name(of: product)
        let what = quantity > 1 ? "\(quantity) \(name)" : name
        AccessibilityNotification.Announcement("Added \(what) to your bag").post()
    }

    /// "1 item", "3 items".
    static func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// The count on a bag button: "3", or "99+".
    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

// MARK: - Copy

/// Wording and assets shared by the Shop screens.
enum BravoShopCopy {
    /// Bravo's wordmark. A template image, so it can be tinted bone.
    static let logoAsset = "BravoLogo"

    /// The store's address as people know it: "bravohairgel.com".
    static var storeHost: String {
        let host = AppData.products.sponsor.storeURL.host ?? "bravohairgel.com"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Who sells the products and where the prices come from.
    static var finePrint: String {
        let sponsor = AppData.products.sponsor.name
        return "Sold and shipped by \(sponsor). Prices from \(storeHost); you'll see the final price at checkout."
    }

    /// The sizes other than this one, e.g. ["4 oz"] for Blue Hair Gel 16 oz.
    static func otherSizes(of product: Product) -> [String] {
        AppData.products.sizes(of: product)
            .filter { $0.id != product.id }
            .compactMap(\.size)
    }

    /// The name, with the size when the item comes in several: "Blue Hair Gel 16 oz", "Matte Clay".
    static func name(of product: Product) -> String {
        guard let size = product.size, !otherSizes(of: product).isEmpty else { return product.name }
        return "\(product.name) \(size)"
    }
}
