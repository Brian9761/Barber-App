import SwiftUI

/// Every kind of text in the app, on the system font (SF Pro) and its Dynamic Type text styles.
///
/// Each role is a text style and a weight, so text grows and shrinks with the person's text size
/// setting exactly like the rest of iOS. Nothing is set in capitals or letter-spaced: strings are
/// written in sentence case and shown as written.
///
/// The display roles stop growing at an accessibility size (the words are repeated in the
/// navigation title and for VoiceOver, and huge titles would push everything else off screen).
///
/// Apply one with `.textRole(.displayM)`, or use `role.font` where only a `Font` fits.
enum TextRole: CaseIterable {
    /// Large title: the biggest heading on a screen.
    case displayXL
    /// Title: a step's heading, "You're booked".
    case displayL
    /// Title 2: section titles, the day and time of an appointment.
    case displayM
    /// Title 3: service names, card titles, the month on the calendar.
    case displayS
    /// Title 2 with tabular figures: a big price or score.
    case priceL
    /// Headline with tabular figures: prices on cards and rows.
    case price
    /// Headline: main button labels.
    case button
    /// Subheadline, semibold: labels on small buttons and pills.
    case buttonSmall
    /// Headline: names in rows ("Carlos"), card headings.
    case headline
    /// Subheadline, semibold: short emphasized lines.
    case callout
    /// Body: sentences.
    case body
    /// Callout: a client's words in a review.
    case quote
    /// Footnote: notes and helper text.
    case caption
    /// Footnote, medium: short labels above a title or on a card ("Next appointment", "Owner").
    case label
    /// Subheadline, medium, tabular figures: lengths, counts and hours people read and act on.
    case detail

    /// The Dynamic Type text style it scales with.
    var textStyle: Font.TextStyle {
        switch self {
        case .displayXL: return .largeTitle
        case .displayL: return .title
        case .displayM, .priceL: return .title2
        case .displayS: return .title3
        case .price, .button, .headline: return .headline
        case .buttonSmall, .callout, .detail: return .subheadline
        case .body: return .body
        case .quote: return .callout
        case .caption, .label: return .footnote
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayXL, .displayL, .displayM, .priceL: return .bold
        case .displayS, .price, .button, .buttonSmall, .headline, .callout: return .semibold
        case .label, .detail: return .medium
        case .body, .quote, .caption: return .regular
        }
    }

    /// Prices and numbers line their digits up.
    var usesTabularDigits: Bool {
        switch self {
        case .priceL, .price, .detail: return true
        default: return false
        }
    }

    /// Dynamic Type stops growing here.
    var largestDynamicTypeSize: DynamicTypeSize {
        switch self {
        case .displayXL, .displayL: return .accessibility2
        case .displayM, .priceL: return .accessibility3
        default: return .accessibility5
        }
    }

    /// The font alone, for `Text` concatenation or a `.font` on a `Label`. Prefer `.textRole(_:)`,
    /// which also sets the Dynamic Type limit.
    var font: Font {
        let font = Font.system(textStyle, design: .default, weight: weight)
        return usesTabularDigits ? font.monospacedDigit() : font
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: TextRole

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .dynamicTypeSize(...role.largestDynamicTypeSize)
    }
}

extension View {
    /// Styles text as one of the app's roles: the system font in a Dynamic Type text style and
    /// weight. Works on a container too, for every `Text` inside it.
    func textRole(_ role: TextRole) -> some View {
        modifier(TextRoleModifier(role: role))
    }
}
