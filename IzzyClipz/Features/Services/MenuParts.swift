import SwiftUI

// Pieces the menu and crew screens share (Services, Service detail, the crew and a barber's page):
// the navigation bar title that waits for the in-content title to scroll away, a name with its price
// beside it (or under it when they don't fit), and the row chevron.

// MARK: - Title in the content, then in the bar

/// The scroll view's coordinate space, which the in-content title is measured against.
private enum MenuTitleSpace {
    static let name = "menu.scroll"
}

extension View {
    /// For a pushed screen that shows its own big title in the content: the native navigation bar
    /// stays (back button, swipe-back), titled `title` for VoiceOver and the next screen's back
    /// button, but the title only appears in the bar once the in-content one has scrolled up under
    /// it, so the two never show at once. Put it on the screen's `ScrollView`, and
    /// `menuTitleScrolledUnderBar(_:)` on the in-content title.
    func menuNavigationTitle(_ title: String, showsInBar: Bool) -> some View {
        modifier(MenuNavigationTitle(title: title, showsInBar: showsInBar))
    }

    /// Sets `isUnderBar` when this view's bottom edge passes under the top of the enclosing
    /// `menuNavigationTitle` scroll view. Only the crossing is reported, not every scrolled point.
    func menuTitleScrolledUnderBar(_ isUnderBar: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named(MenuTitleSpace.name)).maxY < 8
        } action: { scrolledAway in
            isUnderBar.wrappedValue = scrolledAway
        }
    }
}

private struct MenuNavigationTitle: ViewModifier {
    let title: String
    let showsInBar: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(MenuTitleSpace.name))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Set like the system's inline title (NavigationBarAppearance), which this replaces.
                    Text(title)
                        .font(BrandFont.condensedExtraBold.font(size: 19, relativeTo: .headline))
                        .foregroundStyle(Theme.bone)
                        .lineLimit(1)
                        // The bar has a fixed height.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .opacity(showsInBar ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsInBar)
                        .accessibilityHidden(!showsInBar)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

// MARK: - The featured service

/// The one service on the menu set apart on a bone card with a "THE WORKS" tag: VIP, whose own
/// description is "The works in one appointment".
enum MenuFeaturedService {
    static let id = "vip"
    static let tag = "The works"
}

// MARK: - Name and price

/// A menu item's name with its price on the same line, pushed to the trailing edge, like a printed
/// menu. When the two can't share a line (a long name, "Included with cut", big text), the price
/// moves under the name and both may wrap, so nothing is cut off or broken mid-word.
struct MenuNamePriceLine: View {
    let name: String
    let price: String

    @Environment(\.surfaceTone) private var tone

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                nameText
                    .lineLimit(1)
                Spacer(minLength: 0)
                priceText
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                nameText
                    .fixedSize(horizontal: false, vertical: true)
                priceText
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nameText: some View {
        Text(name)
            .textRole(.displayS)
            .foregroundStyle(tone.primary)
    }

    private var priceText: some View {
        Text(price)
            .textRole(.price)
            .foregroundStyle(tone.primary)
            .accessibilityLabel(price.spokenRanges)
    }
}

// MARK: - Chevron

/// The chevron at the end of a row that opens or starts something. Decorative.
struct MenuChevron: View {
    @Environment(\.surfaceTone) private var tone

    var body: some View {
        Image(systemName: Symbol.chevron)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tone.secondary)
            .accessibilityHidden(true)
    }
}
