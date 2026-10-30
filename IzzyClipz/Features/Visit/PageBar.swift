import SwiftUI

/// The native navigation bar over a page that carries its own big title in the content (Visit,
/// Reviews, the gallery).
///
/// The bar stays native, so the back button and swipe-back work as everywhere else in iOS. At rest
/// it's transparent and empty; the page's Display title is in the content. Once the content
/// scrolls under it the bar turns solid ink, and once the in-content title has gone under it the
/// title appears in the bar, so it's never shown twice.
///
/// Positions are read in `PageBar.space`, a coordinate space on a container around the scroll
/// view whose origin is the bottom of the bar (the top of the safe area), so it doesn't matter
/// whether the scroll view itself reaches under the bar:
///
///     GeometryReader { _ in
///         ScrollView {
///             VStack { ScreenHeader(title: "Reviews").pageScrolledUnderBar($titleIsUnderBar) … }
///                 .pageScrolled($isScrolled)
///         }
///     }
///     .coordinateSpace(.named(PageBar.space))
///     .pageBar(title: "Reviews", showsTitle: titleIsUnderBar, isScrolled: isScrolled)
enum PageBar {
    static let space = "pageBar"
}

extension View {
    /// The bar's title (shown once `showsTitle`) and its background (once `isScrolled`): ink, or
    /// `ink2` in a sheet.
    func pageBar(title: String, showsTitle: Bool, isScrolled: Bool, background: Color = Theme.ink) -> some View {
        modifier(PageBarModifier(title: title, showsTitle: showsTitle, isScrolled: isScrolled, background: background))
    }

    /// Sets `isUnderBar` while this view's bottom edge is under the navigation bar. Only the
    /// crossing is reported, not every scrolled point. Needs `PageBar.space` around the scroll view.
    func pageScrolledUnderBar(_ isUnderBar: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named(PageBar.space)).maxY < 8
        } action: { underBar in
            isUnderBar.wrappedValue = underBar
        }
    }

    /// Sets `isScrolled` while this view's top edge (put it on the scroll view's content) has moved
    /// up under the navigation bar.
    func pageScrolled(_ isScrolled: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named(PageBar.space)).minY < -1
        } action: { scrolled in
            isScrolled.wrappedValue = scrolled
        }
    }
}

private struct PageBarModifier: ViewModifier {
    let title: String
    let showsTitle: Bool
    let isScrolled: Bool
    let background: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(background, for: .navigationBar)
            // Solid once anything has scrolled under it; until then the system's own transparent
            // look at the scroll edge.
            .toolbarBackground(isScrolled ? .visible : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Set like the system's inline title (NavigationBarAppearance), which this replaces.
                    Text(title)
                        .font(BrandFont.condensedExtraBold.font(size: 19, relativeTo: .headline))
                        .foregroundStyle(Theme.bone)
                        .lineLimit(1)
                        // The bar has a fixed height.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .opacity(showsTitle ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsTitle)
                        // Hidden from VoiceOver while it's invisible: the page's own title is the heading.
                        .accessibilityHidden(!showsTitle)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
