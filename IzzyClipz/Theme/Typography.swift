import SwiftUI
import UIKit

/// The bundled Street Drip typefaces, by PostScript name.
///
/// Every one is a static, open-licensed (SIL OFL) file in `Resources/Fonts`, built by
/// `scripts/build_fonts.py`, named after its PostScript name and listed under `UIAppFonts` in
/// Info.plist. Nothing else in the app spells a font name: views use `TextRole`, and the few
/// fixed-size or UIKit uses go through `font(fixedSize:)` and `uiFont(size:relativeTo:)` here.
enum BrandFont: String, CaseIterable {
    /// Archivo at 62% width, weight 900. Display type at 24 pt and up, and prices that big.
    case extraCondensedBlack = "ArchivoExtraCondensed-Black"
    /// Archivo at 75% width, weight 800. Display type below 24 pt (at 20 pt the ExtraCondensed Black
    /// fills in the openings of $, 8, 9, B and R), small prices, the Instagram handle, nav bar titles.
    case condensedExtraBold = "ArchivoCondensed-ExtraBold"
    /// Archivo at 125% width, weight 900. The "IZZY CLIPZ" wordmark.
    case expandedBlack = "ArchivoExpanded-Black"
    /// Archivo at 125% width, weight 800. Button labels.
    case expandedExtraBold = "ArchivoExpanded-ExtraBold"
    case regular = "Archivo-Regular"
    /// Body text and captions.
    case medium = "Archivo-Medium"
    /// Quotes.
    case semiBold = "Archivo-SemiBold"
    /// Names, list titles and tab labels.
    case bold = "Archivo-Bold"
    case monoRegular = "SpaceMono-Regular"
    /// Short uppercase tags and numbers, like a drop tag. Never sentences.
    case monoBold = "SpaceMono-Bold"
    /// The one dripping word a screen may have ("BOOKED"), never below 40 pt.
    case wetPaint = "RubikWetPaint-Regular"

    var postScriptName: String { rawValue }

    /// The file in the app bundle, as listed under `UIAppFonts`.
    var fileName: String { "\(rawValue).ttf" }

    /// Every bundled PostScript name, for a test that checks each one is registered.
    static let postScriptNames: [String] = allCases.map(\.postScriptName)

    /// Every bundled font file, in the order Info.plist lists them.
    static let fileNames: [String] = allCases.map(\.fileName)

    /// Scales with Dynamic Type along `textStyle`, the way the system fonts do.
    func font(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        .custom(rawValue, size: size, relativeTo: textStyle)
    }

    /// A size that never changes, for decorative type inside fixed shapes (monogram tiles).
    func font(fixedSize size: CGFloat) -> Font {
        .custom(rawValue, fixedSize: size)
    }

    /// The UIKit font, scaled for Dynamic Type, e.g. for `UINavigationBarAppearance`.
    func uiFont(size: CGFloat, relativeTo textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

/// Every kind of text in Street Drip, from the design spec (§3) with the art director's rules:
/// - Archivo ExtraCondensed Black only at 24 pt or larger; Condensed ExtraBold below that.
/// - Space Mono at 11 pt or more for tags and 12 pt or more for numbers people act on.
/// - Tabular figures where digits line up (prices, numbers).
/// - The huge display sizes stop growing at an accessibility size, since they'd overflow and the
///   words are repeated in the navigation title and for VoiceOver.
///
/// Apply one with `.textRole(.displayXL)`. It sets the font (scaling with Dynamic Type), the
/// tracking, the line spacing, the case and any Dynamic Type cap. Uppercase roles keep the string
/// as written, so pass sentence case ("Book an appointment") and VoiceOver reads words, not letters.
enum TextRole: CaseIterable {
    /// 58 pt screen titles: "THE SHOP", "SERVICES". Capped at accessibility2, 2 lines, shrinks to 70%.
    case displayXL
    /// 42 pt: hero lines, "PICK A TIME", "DID YOU BOOK IT?". Capped at accessibility2.
    case displayL
    /// 30 pt: section titles, the ticket date, the hero price. Capped at accessibility3.
    case displayM
    /// 22 pt Condensed ExtraBold: service names, card titles, the month.
    case displayS
    /// 30 pt with tabular figures: a big price, the score on a rating tile.
    case priceL
    /// 20 pt Condensed ExtraBold with tabular figures: prices on cards and rows.
    case price
    /// 19 pt Archivo Expanded Black: "IZZY CLIPZ" in a header.
    case wordmark
    /// 15 pt: the wordmark in a compact header.
    case wordmarkCompact
    /// 15 pt Archivo Expanded ExtraBold, uppercase: main button labels.
    case button
    /// 12 pt: labels on small buttons and pills.
    case buttonSmall
    /// 17 pt Archivo Bold: names in rows ("Carlos"), card headings.
    case headline
    /// 15 pt Archivo Bold: names, list titles, short emphasized lines.
    case callout
    /// 15/21 pt Archivo Medium: sentences.
    case body
    /// 14/18 pt Archivo SemiBold: a client's words.
    case quote
    /// 12.5/15 pt Archivo Medium: notes and helper text.
    case caption
    /// 10.5 pt Archivo Bold, uppercase: tab bar labels. Capped at xLarge (the bar shows the
    /// large content viewer above that).
    case tabLabel
    /// 11 pt Space Mono Bold, uppercase: kickers and tags ("THE MENU · 12 SERVICES", "OWNER").
    case monoTag
    /// 12 pt Space Mono Bold, uppercase: numbers people read and act on ("45 MIN", "16 OZ").
    case monoNumber
    /// 50 pt Rubik Wet Paint, uppercase: the one dripping word ("BOOKED"). Capped at accessibility2.
    case dripWord

    var face: BrandFont {
        switch self {
        case .displayXL, .displayL, .displayM, .priceL: return .extraCondensedBlack
        case .displayS, .price: return .condensedExtraBold
        case .wordmark, .wordmarkCompact: return .expandedBlack
        case .button, .buttonSmall: return .expandedExtraBold
        case .headline, .callout, .tabLabel: return .bold
        case .body, .caption: return .medium
        case .quote: return .semiBold
        case .monoTag, .monoNumber: return .monoBold
        case .dripWord: return .wetPaint
        }
    }

    /// The size at the default Dynamic Type setting (Large).
    var size: CGFloat {
        switch self {
        case .displayXL: return 58
        case .displayL: return 42
        case .displayM, .priceL: return 30
        case .displayS: return 22
        case .price: return 20
        case .wordmark: return 19
        case .wordmarkCompact, .button, .callout, .body: return 15
        case .buttonSmall, .monoNumber: return 12
        case .headline: return 17
        case .quote: return 14
        case .caption: return 12.5
        case .tabLabel: return 10.5
        case .monoTag: return 11
        case .dripWord: return 50
        }
    }

    /// The text style it scales with.
    var textStyle: Font.TextStyle {
        switch self {
        case .displayXL, .dripWord: return .largeTitle
        case .displayL: return .title
        case .displayM, .priceL: return .title2
        case .displayS, .price: return .title3
        case .wordmark, .wordmarkCompact, .button, .buttonSmall, .headline: return .headline
        case .callout: return .subheadline
        case .body: return .body
        case .quote: return .callout
        case .caption, .monoNumber: return .caption
        case .tabLabel, .monoTag: return .caption2
        }
    }

    /// Letter spacing as a share of the size (CSS `em`).
    var trackingEm: CGFloat {
        switch self {
        case .displayXL, .displayL: return -0.005
        case .wordmark, .wordmarkCompact: return -0.01
        case .button, .buttonSmall: return 0.02
        case .tabLabel: return 0.05
        case .monoTag: return 0.07
        case .monoNumber: return 0.06
        default: return 0
        }
    }

    var tracking: CGFloat { trackingEm * size }

    var isUppercase: Bool {
        switch self {
        case .displayXL, .displayL, .displayM, .displayS, .wordmark, .wordmarkCompact, .button, .buttonSmall,
             .tabLabel, .monoTag, .monoNumber, .dripWord:
            return true
        case .priceL, .price, .headline, .callout, .body, .quote, .caption:
            return false
        }
    }

    /// Prices and numbers line their digits up (Archivo has the `tnum` feature; Space Mono is
    /// monospaced anyway).
    var usesTabularDigits: Bool {
        switch self {
        case .priceL, .price, .monoNumber: return true
        default: return false
        }
    }

    /// Extra space between lines, on top of the font's own 1.09 × size, to reach the spec's line
    /// heights (body 15/21, quote 14/18, caption 12.5/15).
    var lineSpacing: CGFloat {
        switch self {
        case .body: return 4.7
        case .quote: return 2.8
        case .caption: return 1.4
        default: return 0
        }
    }

    /// Dynamic Type stops growing here.
    var largestDynamicTypeSize: DynamicTypeSize {
        switch self {
        case .displayXL, .displayL, .dripWord: return .accessibility2
        case .displayM, .priceL: return .accessibility3
        case .tabLabel: return .xLarge
        default: return .accessibility5
        }
    }

    /// Dynamic Type doesn't shrink it below this. Space Mono gets too thin to read under 11 pt.
    var smallestDynamicTypeSize: DynamicTypeSize {
        switch self {
        case .monoTag, .monoNumber: return .large
        default: return .xSmall
        }
    }

    /// The font alone, for `Text` concatenation or a `.font` on a `Label`. Prefer `.textRole(_:)`,
    /// which also sets the case, tracking and Dynamic Type cap.
    var font: Font {
        let font = face.font(size: size, relativeTo: textStyle)
        return usesTabularDigits ? font.monospacedDigit() : font
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: TextRole

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(role.tracking)
            // Only what the role sets, and only where the caller hasn't set its own further out:
            // a plain `.lineLimit(nil)` here would undo the caller's `.lineLimit(1)`.
            .transformEnvironment(\.lineSpacing) { spacing in
                if role.lineSpacing > 0 { spacing = role.lineSpacing }
            }
            .transformEnvironment(\.textCase) { textCase in
                if role.isUppercase { textCase = .uppercase }
            }
            .transformEnvironment(\.lineLimit) { limit in
                if role == .displayXL && limit == nil { limit = 2 }
            }
            .transformEnvironment(\.minimumScaleFactor) { factor in
                if role == .displayXL && factor == 1 { factor = 0.7 }
            }
            .dynamicTypeSize(role.smallestDynamicTypeSize...role.largestDynamicTypeSize)
    }
}

extension View {
    /// Styles text as one of Street Drip's roles: font, tracking, line spacing, case and Dynamic
    /// Type limits. Works on a container too, for every `Text` inside it.
    func textRole(_ role: TextRole) -> some View {
        modifier(TextRoleModifier(role: role))
    }
}
