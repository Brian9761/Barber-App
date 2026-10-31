import SwiftUI

// Pieces the menu and crew screens share (Services, Service detail, the crew and a barber's page):
// the navigation bar title that waits for the in-content title to scroll away, a name with its price
// beside it (or under it when they don't fit), big names that never break inside a word, lengths
// that keep each number with its unit, and the row chevron.

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
                        .font(.headline)
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
                MenuTitleText(name, role: .displayS)
                    .foregroundStyle(tone.primary)
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

// MARK: - Big names

/// A name or title in a display role that wraps between words but never inside one, which plain
/// `Text` does when a word is wider than the line (Flowxbori as a large title, Enhancements as a
/// title at the largest text sizes, on a 375 pt phone). When every word fits, it wraps like
/// any text; when one doesn't, it sets one word per line and shrinks them together until the
/// longest fits. VoiceOver reads it once, as written.
struct MenuTitleText: View {
    let text: String
    let role: TextRole

    init(_ text: String, role: TextRole) {
        self.text = text
        self.role = role
    }

    /// Split where a line may break: at spaces, not at the no-break spaces that tie "45 MIN".
    private var words: [String] {
        text.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
    }

    var body: some View {
        let words = words
        ViewThatFits(in: .horizontal) {
            // As wide as its widest word: the hidden words set the width it needs, and the text
            // itself asks for none (`idealWidth: 0`), so it only wraps within that.
            ZStack(alignment: .topLeading) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    Text(word)
                        .lineLimit(1)
                        .hidden()
                }
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(idealWidth: 0, alignment: .leading)
            }
            // A word per line, all shrunk by the same factor until the longest fits its line.
            Text(words.joined(separator: "\n"))
                .lineLimit(max(words.count, 1))
                .minimumScaleFactor(0.4)
        }
        .textRole(role)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Lengths and lists

extension String {
    /// "Owner · Barber" as "Owner, Barber", so VoiceOver pauses instead of reading the dot.
    var menuSpokenList: String {
        replacingOccurrences(of: " · ", with: ", ")
    }

    /// A length with each number tied to its unit, so a narrow line breaks "1 hr 15 min" as
    /// "1 HR" / "15 MIN", never "1 HR 15" / "MIN".
    var menuKeepingUnits: String {
        replacingOccurrences(of: " min", with: "\u{00A0}min")
            .replacingOccurrences(of: " hr", with: "\u{00A0}hr")
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
