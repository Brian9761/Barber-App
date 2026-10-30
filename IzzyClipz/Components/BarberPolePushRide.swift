import SwiftUI

private struct BarberPolePushRideEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `PoleTabContainer` turns this off while a tab sweep runs (and for the update in which the tab
    /// changes). Turn it off yourself around a navigation path that is restored or replaced without
    /// animation, so no slim pole appears on a push nobody saw.
    var barberPolePushRideEnabled: Bool {
        get { self[BarberPolePushRideEnabledKey.self] }
        set { self[BarberPolePushRideEnabledKey.self] = newValue }
    }
}

/// The push variant of the pole (pole-spec.md §5). The NavigationStack push stays 100% native, so
/// swipe-back works; this only attaches an 8 pt slim pole (glass, no caps) centred on the pushed
/// screen's leading edge, so it rides in with the screen on UIKit's own push curve.
///
/// It shows on the screen's FIRST appearance only, climbs one stripe period, fades over its last
/// 120 ms and is removed at 0.5 s. A pop never shows it: the revealed screen has already appeared
/// once, and the screen being popped has no pole any more. Off with Reduce Motion, during a tab
/// sweep, and wherever `barberPolePushRideEnabled` is false.
struct BarberPolePushRide: ViewModifier {
    var width: CGFloat = 8
    var duration: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.barberPolePushRideEnabled) private var isEnabled
    @State private var hasAppeared = false
    @State private var rideStart: Date?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if let rideStart {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSince(rideStart)
                        BarberPole(phase: min(max(t / duration, 0), 1), detail: .glassOnly)
                            .opacity(t < duration - 0.12 ? 1 : max(0, (duration - t) / 0.12))
                    }
                    .frame(width: width)
                    .offset(x: -width / 2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                guard isEnabled, !reduceMotion else { return }
                rideStart = Date()
            }
            .task(id: rideStart) {
                guard rideStart != nil else { return }
                try? await Task.sleep(for: .seconds(duration))
                rideStart = nil
            }
    }
}

extension View {
    /// Put this on the ROOT view of a pushed destination (booking steps 2–4, service, barber and
    /// product detail, gallery, team, reviews), inside its `navigationDestination`. Never on a tab root.
    func barberPolePushRide() -> some View {
        modifier(BarberPolePushRide())
    }
}
