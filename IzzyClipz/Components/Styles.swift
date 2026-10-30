import SwiftUI

// MARK: - Buttons

/// The screen's one red thing: its primary action. Drip red, 60 pt tall, radius 18, a white
/// uppercase label in Archivo Expanded and, by default, a bone square with an arrow at the end.
///
/// - `trailingSymbol: nil` centres the label with no square (e.g. "Save appointment").
/// - `drips: true` hangs the logo's paint drips under it (only Home's "Book an appointment" and
///   "Confirm on Squire"). The drips take 22 pt below the button.
/// - Disabled: `ink3` with a `smoke` label, so it never reads as the red action.
/// - Long labels wrap to two lines rather than clipping at large text sizes.
///
/// Use it at most once per screen, and never for selection.
struct PrimaryButtonStyle: ButtonStyle {
    var trailingSymbol: String? = Symbol.forward
    var drips = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        let fill = isEnabled ? Theme.dripRed : Theme.ink3
        let dripDepth = DripEdge.depth(of: DripEdge.underButton)
        return HStack(spacing: 12) {
            configuration.label
                .textRole(.button)
                .foregroundStyle(isEnabled ? Color.white : Theme.smoke)
                .multilineTextAlignment(trailingSymbol == nil ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: trailingSymbol == nil ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isEnabled ? Theme.dripRed : Theme.smoke)
                    .frame(width: 44, height: 44)
                    .background(isEnabled ? Theme.bone : Theme.ink4,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.arrowSquare, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, trailingSymbol == nil ? 20 : 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(fill, in: shape)
        .overlay(alignment: .bottom) {
            if drips && isEnabled {
                // Hangs from the bottom edge, overlapping it by 1 pt so there's no seam.
                DripEdge(drips: DripEdge.underButton)
                    .fill(fill)
                    .frame(height: dripDepth)
                    .offset(y: dripDepth - 1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .brightness(configuration.isPressed ? -0.08 : 0)
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        .padding(.bottom, drips && isEnabled ? dripDepth : 0)
    }
}

/// A strong second action: a bone button with ink text ("Add to calendar", "Pick another time").
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.smoke)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                isEnabled ? (configuration.isPressed ? Theme.bone2 : Theme.bone) : Theme.ink3,
                in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A quiet action on the ink canvas: `ink3` with bone text and a hairline ("Browse all on Squire",
/// "Call (442) 341-3053").
struct TertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        return configuration.label
            .textRole(.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Theme.bone : Theme.smoke)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? Theme.ink4 : Theme.ink3, in: shape)
            .overlay(shape.strokeBorder(Theme.line))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small bone capsule inside a row or card ("Book", "+ Add"): 36 pt to see, 44 pt to tap.
struct CompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.buttonSmall)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.smoke)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isEnabled ? (configuration.isPressed ? Theme.bone2 : Theme.bone) : Theme.ink4, in: Capsule())
            .frame(minHeight: Theme.minimumTapSize)
            .contentShape(Rectangle())
    }
}

/// Dims and shrinks a tappable card while it's pressed. For cards that are one big button.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A text-only action, 44 pt tall: "All 5 barbers ›", "Open Squire again ↗", "I didn't book".
struct TextLinkButtonStyle: ButtonStyle {
    /// Bone or smoke on ink; `electric` for links on dark cards; `ink` on bone.
    var color: Color = Theme.bone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.callout)
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: Theme.minimumTapSize)
            .contentShape(Rectangle())
    }
}

/// A 44 pt round icon button: `ink3` with a bone symbol on the canvas. Give it an accessibility label.
/// (Not inside `.toolbar`: on iOS 26 the system draws its own glass circle there.)
struct IconButtonStyle: ButtonStyle {
    var fill: Color = Theme.ink3
    var foreground: Color = Theme.bone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: Theme.minimumTapSize, height: Theme.minimumTapSize)
            .background(fill, in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Circle())
    }
}

/// A selectable chip: `ink3` with a hairline, or `bone` with ink, bold text when selected (selection
/// is never red). For filter and jump chips (capsules) and time slots (`cornerRadius: 12`, 44 pt).
/// Pair it with `.accessibilityAddTraits(.isSelected)`; `FilterChip` does both.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    /// `nil` for a capsule.
    var cornerRadius: CGFloat? = nil
    var minHeight: CGFloat = 40

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? minHeight / 2, style: .continuous)
        return configuration.label
            .font((isSelected ? BrandFont.bold : BrandFont.semiBold).font(size: 14, relativeTo: .subheadline).monospacedDigit())
            .foregroundStyle(isSelected ? Theme.ink : (isEnabled ? Theme.bone : Theme.boneDisabled))
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight)
            .background(isSelected ? Theme.bone : (configuration.isPressed ? Theme.ink4 : Theme.ink3), in: shape)
            .overlay(shape.strokeBorder(isSelected ? Color.clear : Theme.line))
            // The visible chip is 40 pt; the tap target is at least 44.
            .frame(minHeight: Theme.minimumTapSize)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// The red primary action with an arrow square.
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }

    /// The red primary action, with a different end symbol (`nil` for none) or drips.
    static func primary(trailingSymbol: String? = Symbol.forward, drips: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(trailingSymbol: trailingSymbol, drips: drips)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == TertiaryButtonStyle {
    static var tertiary: TertiaryButtonStyle { TertiaryButtonStyle() }
}

extension ButtonStyle where Self == CompactButtonStyle {
    static var compact: CompactButtonStyle { CompactButtonStyle() }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    static var textLink: TextLinkButtonStyle { TextLinkButtonStyle() }

    static func textLink(color: Color) -> TextLinkButtonStyle {
        TextLinkButtonStyle(color: color)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

// MARK: - Surfaces

/// What a component sits on, so tags, stars and secondary text pick readable colors by themselves.
/// `boneCard()` sets it to `.bone`; everything else is on ink.
enum SurfaceTone {
    case ink
    case bone

    /// Main text and icons.
    var primary: Color {
        switch self {
        case .ink: return Theme.bone
        case .bone: return Theme.ink
        }
    }

    /// Secondary text: `smoke` on ink, `smokeDark` on bone.
    var secondary: Color {
        switch self {
        case .ink: return Theme.smoke
        case .bone: return Theme.smokeDark
        }
    }
}

private struct SurfaceToneKey: EnvironmentKey {
    static let defaultValue = SurfaceTone.ink
}

extension EnvironmentValues {
    var surfaceTone: SurfaceTone {
        get { self[SurfaceToneKey.self] }
        set { self[SurfaceToneKey.self] = newValue }
    }
}

extension View {
    /// An ink card: `ink3`, radius 22, no border. Most cards on the canvas.
    func card(padding: CGFloat = Theme.Space.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// A bone card for tickets, quotes and scores: ink text, radius 22, no border. Inside it the
    /// surface tone is `.bone`, plain buttons are ink and system controls use their light look.
    func boneCard(padding: CGFloat = Theme.Space.cardPadding) -> some View {
        self
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .environment(\.surfaceTone, .bone)
            .environment(\.colorScheme, .light)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bone, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// The ink canvas behind a whole screen.
    func screenBackground() -> some View {
        background(Theme.ink.ignoresSafeArea())
    }

    /// Pins a bar of actions to the bottom of the screen over an ink fade, above the floating tab
    /// bar (tab roots reserve that space). Scroll content passes under it and stops above it.
    ///
    ///     ScrollView { … }
    ///         .stickyBottomBar {
    ///             Button("Continue") { … }.buttonStyle(.primary)
    ///         }
    func stickyBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            StickyBottomBar(content: bar())
        }
    }
}

/// The bar `stickyBottomBar` pins: its content, padded to the gutter, over a fade from clear to ink.
struct StickyBottomBar<Content: View>: View {
    let content: Content

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            content
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Theme.ink.opacity(0), location: 0),
                    .init(color: Theme.ink.opacity(0.9), location: 0.4),
                    .init(color: Theme.ink, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .offset(y: -28)
            .allowsHitTesting(false)
        }
        .background {
            Theme.ink
                .padding(.top, 12)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Images

/// An image that fills whatever space it's given, cropping the overflow.
///
/// The size comes from the container, never the photo, so a wide photo can't
/// push the surrounding layout off-screen.
struct FillImage: View {
    let name: String
    /// Which point of the photo lines up with the same point of the frame, like CSS
    /// `object-position`. The portrait cut photos crop best at `FillImage.editorial` (18–22% from
    /// the top), which keeps the head, the fade line and the beard in the frame.
    var anchor: UnitPoint = .center

    /// The editorial crop for the portrait cut photos.
    static let editorial = UnitPoint(x: 0.5, y: 0.2)

    var body: some View {
        Color.clear
            .alignmentGuide(.photoAnchorX) { $0.width * anchor.x }
            .alignmentGuide(.photoAnchorY) { $0.height * anchor.y }
            .overlay(alignment: Alignment(horizontal: .photoAnchorX, vertical: .photoAnchorY)) {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .alignmentGuide(.photoAnchorX) { $0.width * anchor.x }
                    .alignmentGuide(.photoAnchorY) { $0.height * anchor.y }
            }
            .clipped()
    }
}

private enum PhotoAnchorX: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions.width / 2 }
}

private enum PhotoAnchorY: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions.height / 2 }
}

private extension HorizontalAlignment {
    static let photoAnchorX = HorizontalAlignment(PhotoAnchorX.self)
}

private extension VerticalAlignment {
    static let photoAnchorY = VerticalAlignment(PhotoAnchorY.self)
}
