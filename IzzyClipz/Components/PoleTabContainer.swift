import SwiftUI

// The tab switch: a full-height barber pole sweeps across the screen toward the tab you picked,
// and the new tab is revealed behind it (pole-spec.md §3).

// MARK: - Sweep: metrics, direction, geometry

/// Timing and proportions of the tab-switch sweep. One place to tune them.
struct PoleSweepMetrics {
    /// Glass width as a share of the screen width (98 pt on a 390 pt iPhone), clamped to 80–128 pt.
    var widthFraction: CGFloat = 0.25
    /// Soft ink shadow beside the glass, each side.
    var shadowWidth: CGFloat = 16
    /// Finial apex this far below the top safe-area inset.
    var topGap: CGFloat = 4
    /// Base finial this far above the screen bottom: it ends 16 pt above the floating tab bar (bar top = 96 pt up).
    var bottomInset: CGFloat = 112
    /// Pole travel, stripe spin and reveal all run this long, on `curve`.
    var duration: Double = 0.46
    /// A soft S: the glass shows 22 ms after the tap and is gone at 406 ms. Peak speed is 1.4 × average,
    /// about 27 pt per frame at 60 Hz, so the stripes stay readable while it crosses.
    var curve: UnitCurve = .bezier(startControlPoint: UnitPoint(x: 0.35, y: 0.2), endControlPoint: UnitPoint(x: 0.55, y: 0.88))
    /// Stripe periods climbed during one sweep: enough to read as turning, never strobing.
    var spinPeriods: Double = 2
    /// The Reduce Motion cross-fade.
    var fadeDuration: Double = 0.2

    static let streetDrip: PoleSweepMetrics = {
        var metrics = PoleSweepMetrics()
        // 1 except in demo recordings (see `LaunchOptions.poleSlowMotion`).
        metrics.duration *= LaunchOptions.poleSlowMotion
        return metrics
    }()
}

/// Which way the pole travels. A tab to the right of the current one brings the pole in from the right edge
/// (it travels right → left), so the new screen is revealed from the side its tab is on, like turning a page.
enum PoleSweepDirection {
    case rightToLeft
    case leftToRight

    init(fromIndex: Int, toIndex: Int) {
        self = toIndex > fromIndex ? .rightToLeft : .leftToRight
    }
}

/// Where the pole is, in screen points (origin at the screen's top-left, safe area included).
struct PoleSweepGeometry {
    var screen: CGSize
    var safeAreaTop: CGFloat
    var metrics: PoleSweepMetrics

    var glassWidth: CGFloat { min(max((screen.width * metrics.widthFraction).rounded(), 80), 128) }
    var poleWidth: CGFloat { BarberPoleGeometry.collarWidth * glassWidth }
    /// Width of everything that moves: the collars or the shadowed glass, whichever is wider (130 pt on 390).
    var trackWidth: CGFloat { max(poleWidth, glassWidth + 2 * metrics.shadowWidth).rounded(.up) }
    var poleTop: CGFloat { safeAreaTop + metrics.topGap }
    var poleBottom: CGFloat { screen.height - metrics.bottomInset }

    /// The pole's centre line at `progress` (0…1, already eased). The reveal edge is exactly here.
    func centerX(at progress: CGFloat, direction: PoleSweepDirection) -> CGFloat {
        let offRight = screen.width + trackWidth / 2
        let offLeft = -trackWidth / 2
        switch direction {
        case .rightToLeft: return offRight + (offLeft - offRight) * progress
        case .leftToRight: return offLeft + (offRight - offLeft) * progress
        }
    }
}

extension BarberPoleRenderer {
    /// The sweep overlay: shadow, mount rods and the pole, centred in a track-wide canvas.
    static func drawSweep(in context: GraphicsContext, size: CGSize, geometry g: PoleSweepGeometry, phase: Double, colors: BarberPoleColors) {
        let w = g.glassWidth, cx = size.width / 2
        let top = g.poleTop, bottom = g.poleBottom
        guard bottom - top > 2 * BarberPoleGeometry.glassInset * w else { return }

        // Ambient shadow beside the glass: two gradients instead of a blurred drop shadow.
        let s = g.metrics.shadowWidth
        let dark = colors.ink.opacity(0.42), clear = colors.ink.opacity(0)
        context.fill(Path(CGRect(x: cx - w / 2 - s, y: top, width: s, height: bottom - top)), with: .linearGradient(
            Gradient(colors: [clear, dark]), startPoint: CGPoint(x: cx - w / 2 - s, y: 0), endPoint: CGPoint(x: cx - w / 2, y: 0)))
        context.fill(Path(CGRect(x: cx + w / 2, y: top, width: s, height: bottom - top)), with: .linearGradient(
            Gradient(colors: [dark, clear]), startPoint: CGPoint(x: cx + w / 2, y: 0), endPoint: CGPoint(x: cx + w / 2 + s, y: 0)))

        // Mount rods from the finials to the screen edges: they cover the reveal edge above and below the pole.
        let rod = max(0.05 * w, 2)
        let rodShading = GraphicsContext.Shading.linearGradient(BarberPoleColors.chrome,
            startPoint: CGPoint(x: cx - rod / 2, y: 0), endPoint: CGPoint(x: cx + rod / 2, y: 0))
        context.fill(Path(CGRect(x: cx - rod / 2, y: 0, width: rod, height: top + 0.04 * w)), with: rodShading)
        context.fill(Path(CGRect(x: cx - rod / 2, y: bottom - 0.04 * w, width: rod, height: size.height - bottom + 0.04 * w)), with: rodShading)

        let poleWidth = BarberPoleGeometry.collarWidth * w
        BarberPoleRenderer.draw(in: context, rect: CGRect(x: cx - poleWidth / 2, y: top, width: poleWidth, height: bottom - top),
                                phase: phase, detail: .full, colors: colors)
    }
}

// MARK: - Sweep: the reveal

/// A rectangle that keeps one side of a vertical edge. No feather and no corner radius: the cheapest clip there is.
/// It reaches far above and below the view, so backgrounds that ignore the safe area are never cut.
struct PoleSweepWindow: Shape {
    /// Edge x in the clipped view's own coordinates.
    var edgeX: CGFloat
    var keepsLeftSide: Bool

    var animatableData: CGFloat {
        get { edgeX }
        set { edgeX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let pad: CGFloat = 10_000
        let edge = rect.minX + edgeX
        let minX = keepsLeftSide ? rect.minX - pad : edge
        let maxX = keepsLeftSide ? edge : rect.maxX + pad
        return Path(CGRect(x: minX, y: rect.minY - pad, width: max(0, maxX - minX), height: rect.height + 2 * pad))
    }
}

/// Clips the OUTGOING tab to the side of the screen the pole has not reached yet. The incoming tab sits fully drawn
/// underneath (and is already interactive), so it appears behind the pole. Driven by one eased progress value, the
/// same one `PoleSweepOverlay` reads, so the edge always lies on the pole's centre line.
///
/// Always attach it, active or not: wrapping it in an `if` would change the tab root's identity and reset its state.
struct PoleSweepClip: ViewModifier, Animatable {
    var progress: CGFloat
    var direction: PoleSweepDirection
    var geometry: PoleSweepGeometry
    /// The clipped view's minX in screen coordinates (the leading safe-area inset; 0 on a portrait iPhone).
    var originX: CGFloat = 0
    var isActive = true

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let edge = geometry.centerX(at: progress, direction: direction) - originX
        content.clipShape(PoleSweepWindow(
            edgeX: isActive ? edge : 1_000_000,
            keepsLeftSide: isActive ? direction == .rightToLeft : true
        ))
    }
}

/// The moving pole: soft shadow, mount rods to the screen edges, and the pole. Screen-sized, never takes touches,
/// hidden from VoiceOver. Its origin must sit on the screen's top-left corner (`PoleTabContainer` offsets it by the
/// safe-area insets), because `PoleSweepGeometry` is in screen points.
struct PoleSweepOverlay: View, Animatable {
    var progress: CGFloat
    var direction: PoleSweepDirection
    var geometry: PoleSweepGeometry
    var colors: BarberPoleColors = .streetDrip

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let g = geometry
        let phase = Double(progress) * g.metrics.spinPeriods
        Canvas { context, size in
            BarberPoleRenderer.drawSweep(in: context, size: size, geometry: g, phase: phase, colors: colors)
        }
        .frame(width: g.trackWidth, height: g.screen.height)
        .drawingGroup()      // one small Metal texture per frame; the offset below just moves it
        .offset(x: g.centerX(at: progress, direction: direction) - g.trackWidth / 2)
        .frame(width: g.screen.width, height: g.screen.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Tab container

private struct IsSelectedTabKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the tab this view lives in is the selected one. Every tab root stays alive (and
    /// `onAppear` doesn't fire again when its tab comes back), so anything that refreshed on appear,
    /// like "now" and the open time slots, should also refresh when this turns true:
    ///
    ///     @Environment(\.isSelectedTab) private var isSelectedTab
    ///     .onChange(of: isSelectedTab) { _, selected in if selected { refresh() } }
    ///
    /// `true` outside a `PoleTabContainer` (sheets, previews).
    var isSelectedTab: Bool {
        get { self[IsSelectedTabKey.self] }
        set { self[IsSelectedTabKey.self] = newValue }
    }
}

/// Keeps every tab root alive in one ZStack (so each keeps its scroll position and navigation path)
/// and turns the pole between them.
///
///     PoleTabContainer(tabs: AppTab.allCases, selection: $router.selectedTab) { tab in
///         switch tab { … }
///     }
///
/// Rules (pole-spec.md §3, §7, §8):
/// - Selection changes at 0 ms: the new tab takes taps and VoiceOver at once; the outgoing tab is drawn on top,
///   clipped to the side the pole has not reached, with hit testing and accessibility off.
/// - Rapid taps: a change during a sweep finishes the running sweep instantly (its outgoing tab is hidden) and
///   starts a fresh one from the tab that is fully drawn underneath. No queue, no blending.
/// - Tabs that aren't showing stay alive at opacity 0, hidden from VoiceOver and not hit-testable.
/// - Reduce Motion: no pole. The new tab fades in over the old one in 0.2 s.
/// - Nothing runs at rest: the clock is paused unless a sweep is on screen.
struct PoleTabContainer<Tab: Hashable, Content: View>: View {
    private let tabs: [Tab]
    @Binding private var selection: Tab
    private let metrics: PoleSweepMetrics
    private let content: (Tab) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Sweep?
    @State private var sweepCount = 0
    /// The selection the last sweep started from. Differs from `selection` for the one update
    /// between a tab change and its sweep starting, so a push that happens with the tab change
    /// ("Book with Carlos") never gets a slim pole of its own.
    @State private var settledSelection: Tab?

    private struct Sweep: Equatable {
        enum Kind { case pole, fade }
        let id: Int
        let from: Tab
        let direction: PoleSweepDirection
        let kind: Kind
        let start: Date
        let duration: Double
    }

    init(tabs: [Tab], selection: Binding<Tab>, metrics: PoleSweepMetrics = .streetDrip, @ViewBuilder content: @escaping (Tab) -> Content) {
        self.tabs = tabs
        self._selection = selection
        self.metrics = metrics
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let geometry = PoleSweepGeometry(
                screen: CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                               height: proxy.size.height + insets.top + insets.bottom),
                safeAreaTop: insets.top,
                metrics: metrics)
            // A clock, not withAnimation: restarting is then just "replace `sweep`", with no dependence on how
            // SwiftUI merges an interrupted timing-curve animation. Paused (no frames at all) when nothing moves.
            TimelineView(.animation(paused: sweep == nil)) { timeline in
                let progress = sweep.map { eased($0, at: timeline.date) } ?? 1
                ZStack {
                    ForEach(tabs, id: \.self) { tab in
                        layer(for: tab, progress: progress, geometry: geometry, originX: insets.leading)
                    }
                }
                // An overlay, not a ZStack child: the screen-sized pole must not resize the stack the tabs live in.
                .overlay(alignment: .topLeading) {
                    if let sweep, sweep.kind == .pole {
                        PoleSweepOverlay(progress: progress, direction: sweep.direction, geometry: geometry)
                            .offset(x: -insets.leading, y: -insets.top)
                    }
                }
            }
        }
        .onChange(of: selection) { oldTab, newTab in
            begin(from: oldTab, to: newTab)
        }
        .task(id: sweep?.id) {
            guard let running = sweep else { return }
            try? await Task.sleep(for: .seconds(running.duration))
            if sweep?.id == running.id {
                sweep = nil
            }
        }
    }

    private func layer(for tab: Tab, progress: CGFloat, geometry: PoleSweepGeometry, originX: CGFloat) -> some View {
        let isSelected = tab == selection
        let isOutgoing = !isSelected && sweep?.from == tab
        let kind = sweep?.kind
        let isClipped = isOutgoing && kind == .pole
        let opacity: Double
        let z: Double
        if isSelected {
            opacity = kind == .fade ? Double(progress) : 1
            z = kind == .fade ? 2 : 1
        } else if isOutgoing {
            opacity = 1
            z = kind == .pole ? 2 : 1
        } else {
            opacity = 0
            z = 0
        }
        let pushRideEnabled = sweep == nil && (settledSelection == nil || settledSelection == selection)
        return content(tab)
            .environment(\.isSelectedTab, isSelected)
            .environment(\.barberPolePushRideEnabled, pushRideEnabled)
            .modifier(PoleSweepClip(
                progress: isClipped ? progress : 0,
                direction: sweep?.direction ?? .rightToLeft,
                geometry: geometry,
                originX: originX,
                isActive: isClipped))
            .opacity(opacity)
            .zIndex(z)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            // The clock owns this motion. If anything changes `selection` inside withAnimation, nothing here
            // may interpolate (a springing opacity would show through the reveal).
            .animation(nil, value: selection)
    }

    private func eased(_ sweep: Sweep, at date: Date) -> CGFloat {
        let t = min(max(date.timeIntervalSince(sweep.start) / sweep.duration, 0), 1)
        let curve: UnitCurve = sweep.kind == .pole ? metrics.curve : .easeInOut
        return CGFloat(curve.value(at: t))
    }

    private func begin(from oldTab: Tab, to newTab: Tab) {
        guard oldTab != newTab else { return }
        let fromIndex = tabs.firstIndex(of: oldTab) ?? 0
        let toIndex = tabs.firstIndex(of: newTab) ?? 0
        sweepCount += 1
        // Replacing `sweep` is the rapid-tap rule: the previous outgoing tab is dropped (finished instantly) and
        // `oldTab`, fully drawn under it until now, becomes the new outgoing tab.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            settledSelection = newTab
            sweep = Sweep(
                id: sweepCount,
                from: oldTab,
                direction: PoleSweepDirection(fromIndex: fromIndex, toIndex: toIndex),
                kind: reduceMotion ? .fade : .pole,
                start: Date(),
                duration: reduceMotion ? metrics.fadeDuration : metrics.duration)
        }
    }
}
