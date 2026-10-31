import SwiftUI

/// The owner app's look: the system font, dark mode, standard iOS lists and
/// forms, and the shop's red for the one main action on a screen.
///
/// Everything else (backgrounds, grouped list colors, secondary text) comes
/// from the system, so Dynamic Type, Increase Contrast and Bold Text work as
/// people expect. Info.plist sets `UIUserInterfaceStyle: Dark`.
enum BusinessTheme {
    /// The shop's red, the customer app's `dripRed` (#D7141C). White text on it
    /// is 5.24:1.
    static let red = Color(red: 215 / 255, green: 20 / 255, blue: 28 / 255)
    /// Paid badges and "ready" states.
    static let paid = Color.green
    /// Warnings: test mode, things that need a look.
    static let caution = Color.orange

    /// Apple's minimum tap target.
    static let minimumTapSize: CGFloat = 44
}

/// The one main button on a screen: full width, red, white text, at least
/// 50 pt tall.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BusinessTheme.red.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            )
            .contentShape(Rectangle())
    }
}

/// A small rounded label: "Paid", "No-show", "Hidden".
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .fixedSize()
    }
}

/// The "Test mode — no real charge" strip on every screen that could take a
/// card while no real card can be charged.
struct TestModeBanner: View {
    var text = "Test mode — no real charge"

    var body: some View {
        Label(text, systemImage: "testtube.2")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BusinessTheme.caution))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("testModeBanner")
    }
}

/// A message under a section with a way forward, for errors that leave the
/// screen usable.
struct InlineMessage: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"
    var color: Color = BusinessTheme.caution

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}
