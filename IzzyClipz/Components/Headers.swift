import SwiftUI

/// A short line above a title: "The menu · 12 services". `smoke` on ink, `smokeDark` on bone.
struct Kicker: View {
    let text: String
    @Environment(\.surfaceTone) private var tone

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textRole(.label)
            .foregroundStyle(tone.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small boxed label on a card or tile: "Owner", "The works", "Today".
struct Badge: View {
    enum Style {
        /// Ink box, bone text: on bone and on photos.
        case ink
        /// Bone box, ink text: on ink, blue and red.
        case bone
        /// `ink3` box with a hairline, bone text: a quiet tag on the canvas.
        case quiet
        /// Caution box, ink text: warnings (a time that has passed).
        case caution
    }

    let text: String
    var style: Style = .ink
    /// An optional leading symbol, e.g. a checkmark.
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .heavy))
                    .accessibilityHidden(true)
            }
            Text(text)
                .textRole(.label)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            if style == .quiet {
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line)
            }
        }
    }

    private var foreground: Color {
        switch style {
        case .ink, .quiet: return Theme.bone
        case .bone, .caution: return Theme.ink
        }
    }

    private var background: Color {
        switch style {
        case .ink: return Theme.ink
        case .bone: return Theme.bone
        case .quiet: return Theme.ink3
        case .caution: return Theme.caution
        }
    }
}

/// The top of a screen: a kicker over a large title, in the content (the navigation bar
/// above stays native). The title stops growing at accessibility2, wraps to two lines and then
/// shrinks, since it's decoration repeated in the navigation title.
///
///     ScreenHeader(kicker: "The menu · 12 services", title: "Services")
///     ScreenHeader(title: "The shop") { BagButton() }
struct ScreenHeader<Trailing: View>: View {
    var kicker: String?
    let title: String
    let trailing: Trailing

    init(kicker: String? = nil, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.kicker = kicker
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                if let kicker {
                    Kicker(kicker)
                }
                Text(title)
                    .textRole(.displayXL)
                    .foregroundStyle(Theme.bone)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(kicker: String? = nil, title: String) {
        self.init(kicker: kicker, title: title) { EmptyView() }
    }
}

/// A section title with an optional trailing link ("All 5 barbers ›"), 44 pt tall.
/// The trailing control is styled as a smoke text link.
///
///     SectionHeader("The crew") {
///         NavigationLink("All 5 barbers", value: HomeRoute.team)
///     }
struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.l) {
            Text(title)
                .textRole(.displayM)
                .foregroundStyle(Theme.bone)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .buttonStyle(.textLink(color: Theme.smoke))
        }
        .frame(minHeight: Theme.minimumTapSize)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// A price with tabular figures, so digits line up from row to row: card size or big. VoiceOver
/// reads a range like "$35–$45" as "$35 to $45".
struct PriceText: View {
    let label: String
    var isLarge = false

    init(_ label: String, isLarge: Bool = false) {
        self.label = label
        self.isLarge = isLarge
    }

    var body: some View {
        Text(label)
            .textRole(isLarge ? .priceL : .price)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(label.spokenRanges)
    }
}

extension String {
    /// "$35–$45" as "$35 to $45" and "45 min – 1 hr" as "45 min to 1 hr":
    /// VoiceOver doesn't always read a dash between values as "to".
    var spokenRanges: String {
        replacingOccurrences(of: " – ", with: " to ").replacingOccurrences(of: "–", with: " to ")
    }
}

/// Where you are in booking, as a thin bar: the finished part in bone, the rest in `ink4`.
/// Decoration for the text beside it ("Step 2 of 5"), so VoiceOver skips it.
///
///     StepProgressBar(step: 2, total: 5)
struct StepProgressBar: View {
    /// The current step, from 1.
    let step: Int
    var total = 5

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(step, 1), max(total, 1))) / CGFloat(max(total, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink4)
                Capsule().fill(Theme.bone)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
