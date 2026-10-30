import SwiftUI

/// The selected-tab marker: an 11 × 30 pt pole standing on the tab bar's top edge over the
/// selected slot (pole-spec.md §4).
///
/// It glides on the bar's spring, and every move adds two stripe periods of spin on the same
/// spring, so it spins while it glides, rocks back a hair on the overshoot and is completely still
/// at rest. There's no idle animation, no timeline and no timer. The spin is always whole periods
/// and doesn't depend on distance, so it looks the same on every tab and a long jump can't strobe.
/// With Reduce Motion it jumps and doesn't spin. Hidden from VoiceOver: the selected tab button's
/// `.isSelected` trait carries the state.
///
///     barShape.overlay(alignment: .top) {
///         PoleTabIndicator(selectedIndex: index, count: 5).offset(y: -19)   // reaches 11 pt into the bar
///     }
struct PoleTabIndicator: View {
    var selectedIndex: Int
    var count: Int
    var size = CGSize(width: 11, height: 30)
    var colors: BarberPoleColors = .streetDrip

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    /// The tab bar's spring: overshoots by about 2% at 272 ms and settles by about 450 ms.
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)

    var body: some View {
        GeometryReader { proxy in
            let slot = proxy.size.width / CGFloat(max(count, 1))
            BarberPole(phase: spin, detail: .full, colors: colors)
                .frame(width: size.width, height: size.height)
                .background(alignment: .bottom) {
                    // Contact shadow on the sole, so the pole stands on the bar instead of floating over it.
                    EllipticalGradient(colors: [colors.ink.opacity(0.38), colors.ink.opacity(0)],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: size.width + 8, height: 6)
                        .offset(y: 3)
                }
                .offset(x: slot * (CGFloat(selectedIndex) + 0.5) - size.width / 2)
        }
        .frame(height: size.height)
        .animation(reduceMotion ? nil : Self.spring, value: selectedIndex)
        .onChange(of: selectedIndex) {
            guard !reduceMotion else { return }   // Reduce Motion: the pole jumps and does not spin
            withAnimation(Self.spring) {
                spin += 2                         // whole periods, so every rest state looks the same
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
