import SwiftUI

// The spinning barber pole: the motion signature of the app. The pole replaces the clipper
// everywhere (there's no clipper in v3).
//
//   BarberPole              the pole itself, any size, with its stripe phase as an input (this file)
//   BarberPoleSpinner       the loading indicator (this file)
//   PoleTabContainer        the five tab roots and the full-screen sweep between them (PoleTabContainer.swift)
//   PoleTabIndicator        the mini pole that marks the selected tab (PoleTabIndicator.swift)
//   .barberPolePushRide()   a slim pole riding a native push (BarberPolePushRide.swift)
//   PoleProgressBar         the booking steps (PoleProgressBar.swift)
//
// Geometry, timing and wiring follow the pole spec (redesign/street-drip-pole/pole-spec.md).
// iOS 17 API only. Nothing animates at rest: every pole is still unless something is moving.

// MARK: - Colors

/// The pole's colors: the Street Drip tokens, plus a bone-tinted chrome for the caps.
///
/// The blue stripes are `royal`, not `electric`: they sit on bone, where royal has 9.6:1 contrast
/// and electric only 3.2:1. The silhouette against ink comes from the bone bands, the chrome and
/// the hairlines along the glass.
struct BarberPoleColors {
    var red = Theme.dripRed
    var bone = Theme.bone
    var blue = Theme.royal
    /// Shading.
    var ink = Theme.ink

    static let streetDrip = BarberPoleColors()

    /// Bone-tinted chrome for the caps, collars and rods, as a horizontal ramp (left edge → right edge).
    /// Its dark edges read on the bone tab bar and its bright core on the ink canvas.
    static let chrome = Gradient(stops: [
        .init(color: Color(hex: 0x2A2926), location: 0.00),
        .init(color: Color(hex: 0x8E897F), location: 0.10),
        .init(color: Color(hex: 0xF2EEE5), location: 0.24),
        .init(color: .white, location: 0.32),
        .init(color: Color(hex: 0xCFCAC0), location: 0.42),
        .init(color: Color(hex: 0x8E897F), location: 0.60),
        .init(color: Color(hex: 0xE4DFD3), location: 0.78),
        .init(color: Color(hex: 0x6B665E), location: 0.92),
        .init(color: Color(hex: 0x2A2926), location: 1.00),
    ])
}

// MARK: - Geometry

/// Every length is a multiple of the glass width `w`. The same numbers drive the mock's `poleSVG`.
enum BarberPoleGeometry {
    /// The widest part: the collars.
    static let collarWidth: CGFloat = 1.16
    static let collarHeight: CGFloat = 0.14
    static let domeWidth: CGFloat = 1.04
    static let domeHeight: CGFloat = 0.30
    /// The finial ball.
    static let ballDiameter: CGFloat = 0.20
    /// From the finial apex: dome 0.16…0.46 w, collar 0.44…0.58 w, glass from 0.55 w (tucked under the collar).
    static let domeTop: CGFloat = 0.16
    static let domeBase: CGFloat = 0.46
    static let collarTop: CGFloat = 0.44
    static let glassInset: CGFloat = 0.55

    /// Vertical distance between two red bands, measured on the centre line.
    static let stripePeriod: CGFloat = 0.92
    /// How far one band edge climbs across the visible half of the glass, in periods.
    static let stripeRise: CGFloat = 0.90
    /// Bands inside one period (bone shows through 0.30–0.50 and 0.80–1.00).
    static let redBand: ClosedRange<CGFloat> = 0.00...0.30
    static let blueBand: ClosedRange<CGFloat> = 0.50...0.80
    /// Below this width the caps would be sub-pixel mush, so `BarberPole` draws the glass only.
    static let minimumWidthForCaps: CGFloat = 10
}

// MARK: - Renderer

/// Draws a pole into a `GraphicsContext`. Shared by `BarberPole`, the sweep overlay and the progress
/// bar, so they're pixel-identical.
enum BarberPoleRenderer {
    enum Detail {
        /// Finials, domes, collars and glass.
        case full
        /// The glass only: the slim push rider and the progress segments.
        case glassOnly
    }

    private typealias G = BarberPoleGeometry

    /// Draws one pole that exactly fills `rect`. With caps, the glass width is `rect.width / 1.16`.
    static func draw(in context: GraphicsContext, rect: CGRect, phase: Double, detail: Detail, colors: BarberPoleColors) {
        let caps = detail == .full
        let w = caps ? rect.width / G.collarWidth : rect.width
        let glassTop = caps ? rect.minY + G.glassInset * w : rect.minY
        let glassBottom = caps ? rect.maxY - G.glassInset * w : rect.maxY
        guard w > 0, glassBottom > glassTop else { return }
        let glass = CGRect(x: rect.midX - w / 2, y: glassTop, width: w, height: glassBottom - glassTop)

        drawGlass(in: context, glass: glass, phase: phase, caps: caps, colors: colors)
        if caps {
            drawCaps(in: context, rect: rect, w: w, colors: colors)
        }
    }

    private static func drawGlass(in context: GraphicsContext, glass: CGRect, phase: Double, caps: Bool, colors: BarberPoleColors) {
        var g = context
        g.clip(to: Path(glass))
        // Only the red and blue bands are drawn over a bone base, so neighbouring bands never
        // leave an anti-aliasing seam between them.
        g.fill(Path(glass), with: .color(colors.bone))

        // Helical bands. A band edge on a cylinder of radius r, seen side-on: x = r·sin θ, y = y0 − k·θ for
        // θ in −π/2…π/2. Sampling evenly in θ puts the points where the curve bends, near the silhouette;
        // that bend is what makes the pole read as round.
        let w = glass.width, r = w / 2, cx = glass.midX
        let period = G.stripePeriod * w
        let k = G.stripeRise * period / .pi
        let fraction = phase - phase.rounded(.down)            // the pattern repeats every period
        let shift = -CGFloat(fraction) * period                  // phase up = stripes climb
        let samples = max(12, Int((w / 3).rounded()))
        var xs: [CGFloat] = [], dys: [CGFloat] = []
        for i in 0...samples {
            let theta = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(i) / CGFloat(samples)
            xs.append(cx + r * sin(theta))
            dys.append(-k * theta)
        }
        let reach = k * .pi / 2
        let first = Int(((-reach - period - shift) / period).rounded(.down)) - 1
        let last = Int(((glass.height + reach - shift) / period).rounded(.up)) + 1
        var red = Path(), blue = Path()
        for n in first...last {
            let base = glass.minY + CGFloat(n) * period + shift
            addBand(to: &red, top: base + G.redBand.lowerBound * period, bottom: base + G.redBand.upperBound * period, xs: xs, dys: dys)
            addBand(to: &blue, top: base + G.blueBand.lowerBound * period, bottom: base + G.blueBand.upperBound * period, xs: xs, dys: dys)
        }
        g.fill(red, with: .color(colors.red))
        g.fill(blue, with: .color(colors.blue))

        // Cylinder shading: dark edges, a soft specular band plus a crisp line at 0.27 w, a faint rim light.
        let left = CGPoint(x: glass.minX, y: glass.midY), right = CGPoint(x: glass.maxX, y: glass.midY)
        let ink = colors.ink
        g.fill(Path(glass), with: .linearGradient(Gradient(stops: [
            .init(color: ink.opacity(0.62), location: 0.00),
            .init(color: ink.opacity(0.26), location: 0.10),
            .init(color: ink.opacity(0.00), location: 0.28),
            .init(color: ink.opacity(0.00), location: 0.60),
            .init(color: ink.opacity(0.22), location: 0.82),
            .init(color: ink.opacity(0.66), location: 1.00),
        ]), startPoint: left, endPoint: right))
        g.fill(Path(glass), with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.00), location: 0.18),
            .init(color: .white.opacity(0.55), location: 0.29),
            .init(color: .white.opacity(0.18), location: 0.35),
            .init(color: .white.opacity(0.00), location: 0.44),
            .init(color: .white.opacity(0.00), location: 0.86),
            .init(color: .white.opacity(0.16), location: 0.91),
            .init(color: .white.opacity(0.00), location: 0.96),
        ]), startPoint: left, endPoint: right))
        g.fill(Path(CGRect(x: glass.minX + 0.27 * w, y: glass.minY, width: max(0.03 * w, 0.5), height: glass.height)),
               with: .color(.white.opacity(0.5)))

        // The collars shade the glass just under and over them.
        if caps {
            let band = 0.16 * w
            g.fill(Path(CGRect(x: glass.minX, y: glass.minY, width: w, height: band)), with: .linearGradient(
                Gradient(colors: [ink.opacity(0.5), ink.opacity(0)]),
                startPoint: CGPoint(x: 0, y: glass.minY), endPoint: CGPoint(x: 0, y: glass.minY + band)))
            g.fill(Path(CGRect(x: glass.minX, y: glass.maxY - band, width: w, height: band)), with: .linearGradient(
                Gradient(colors: [ink.opacity(0), ink.opacity(0.5)]),
                startPoint: CGPoint(x: 0, y: glass.maxY - band), endPoint: CGPoint(x: 0, y: glass.maxY)))
        }

        // Glass silhouette: a hairline of light on both edges keeps the pole round against the ink canvas,
        // because the edge shade pushes royal close to black.
        let rim = max(0.012 * w, 0.5)
        g.fill(Path(CGRect(x: glass.minX, y: glass.minY, width: rim, height: glass.height)), with: .color(.white.opacity(0.2)))
        g.fill(Path(CGRect(x: glass.maxX - rim, y: glass.minY, width: rim, height: glass.height)), with: .color(.white.opacity(0.14)))
    }

    private static func addBand(to path: inout Path, top: CGFloat, bottom: CGFloat, xs: [CGFloat], dys: [CGFloat]) {
        path.move(to: CGPoint(x: xs[0], y: top + dys[0]))
        for i in 1..<xs.count {
            path.addLine(to: CGPoint(x: xs[i], y: top + dys[i]))
        }
        for i in stride(from: xs.count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: xs[i], y: bottom + dys[i]))
        }
        path.closeSubpath()
    }

    private static func drawCaps(in context: GraphicsContext, rect: CGRect, w: CGFloat, colors: BarberPoleColors) {
        let cx = rect.midX
        let outline = GraphicsContext.Shading.color(colors.ink.opacity(0.5))
        let line = max(0.012 * w, 0.4)
        let ballRadius = G.ballDiameter * w / 2
        let domeHalf = G.domeWidth * w / 2, domeHeight = G.domeHeight * w
        let collarWidth = G.collarWidth * w, collarHeight = G.collarHeight * w
        let domeLight = Gradient(stops: [
            .init(color: .white.opacity(0.38), location: 0),
            .init(color: .white.opacity(0), location: 0.5),
            .init(color: colors.ink.opacity(0.32), location: 1),
        ])
        let ballChrome = Gradient(stops: [
            .init(color: .white, location: 0),
            .init(color: Color(hex: 0xF2EEE5), location: 0.35),
            .init(color: Color(hex: 0x8E897F), location: 0.75),
            .init(color: Color(hex: 0x2A2926), location: 1),
        ])

        for isTop in [true, false] {
            // Finial ball.
            let ballY = isTop ? rect.minY : rect.maxY - 2 * ballRadius
            let ball = Path(ellipseIn: CGRect(x: cx - ballRadius, y: ballY, width: 2 * ballRadius, height: 2 * ballRadius))
            context.fill(ball, with: .radialGradient(ballChrome,
                center: CGPoint(x: cx - ballRadius + 0.72 * ballRadius, y: ballY + 0.64 * ballRadius),
                startRadius: 0, endRadius: 1.5 * ballRadius))
            context.stroke(ball, with: outline, lineWidth: line)

            // Dome: half an ellipse sitting on the collar (top) or hanging under it (base).
            let base = isTop ? rect.minY + G.domeBase * w : rect.maxY - G.domeBase * w
            let apex = isTop ? base - domeHeight : base + domeHeight
            let dome = halfEllipse(cx: cx, base: base, apex: apex, halfWidth: domeHalf)
            let domeBox = CGRect(x: cx - domeHalf, y: min(base, apex), width: 2 * domeHalf, height: domeHeight)
            context.fill(dome, with: .linearGradient(BarberPoleColors.chrome,
                startPoint: CGPoint(x: domeBox.minX, y: 0), endPoint: CGPoint(x: domeBox.maxX, y: 0)))
            var lit = context
            lit.opacity = isTop ? 1 : 0.7
            lit.fill(dome, with: .linearGradient(domeLight,
                startPoint: CGPoint(x: 0, y: domeBox.minY), endPoint: CGPoint(x: 0, y: domeBox.maxY)))
            context.stroke(dome, with: outline, lineWidth: line)

            // Collar.
            let collarY = isTop ? rect.minY + G.collarTop * w : rect.maxY - G.collarTop * w - collarHeight
            let collarRect = CGRect(x: cx - collarWidth / 2, y: collarY, width: collarWidth, height: collarHeight)
            let collar = Path(roundedRect: collarRect, cornerRadius: 0.03 * w)
            context.fill(collar, with: .linearGradient(BarberPoleColors.chrome,
                startPoint: CGPoint(x: collarRect.minX, y: 0), endPoint: CGPoint(x: collarRect.maxX, y: 0)))
            context.stroke(collar, with: outline, lineWidth: line)
        }
    }

    /// Half an ellipse from (cx − halfWidth, base) through (cx, apex) to (cx + halfWidth, base), closed along the base.
    private static func halfEllipse(cx: CGFloat, base: CGFloat, apex: CGFloat, halfWidth a: CGFloat) -> Path {
        let kappa: CGFloat = 0.5523
        let b = apex - base   // negative for the top dome
        var p = Path()
        p.move(to: CGPoint(x: cx - a, y: base))
        p.addCurve(to: CGPoint(x: cx, y: apex), control1: CGPoint(x: cx - a, y: base + kappa * b), control2: CGPoint(x: cx - kappa * a, y: apex))
        p.addCurve(to: CGPoint(x: cx + a, y: base), control1: CGPoint(x: cx + kappa * a, y: apex), control2: CGPoint(x: cx + a, y: base + kappa * b))
        p.closeSubpath()
        return p
    }
}

// MARK: - The pole

/// A classic barber pole: chrome finials, domes and collars around a glass cylinder with red, bone
/// and royal helical stripes. Any size: from 10 pt wide it draws the caps, below that the glass only.
///
/// `phase` is the stripe position in periods. Adding 1 moves the stripes up one full period, which
/// looks identical, so whole-number phases are interchangeable rest states. The view is
/// `Animatable`, so drive it from `withAnimation`, a `TimelineView` or a `keyframeAnimator`. It
/// never animates by itself. Hidden from VoiceOver: it's decoration.
///
///     BarberPole(phase: spin).frame(width: 11, height: 30)
struct BarberPole: View, Animatable {
    var phase: Double
    /// `nil` picks `.full` from 10 pt wide and `.glassOnly` below that.
    var detail: BarberPoleRenderer.Detail? = nil
    var colors: BarberPoleColors = .streetDrip

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let resolved = detail ?? (size.width >= BarberPoleGeometry.minimumWidthForCaps ? .full : .glassOnly)
            BarberPoleRenderer.draw(in: context, rect: CGRect(origin: .zero, size: size), phase: phase, detail: resolved, colors: colors)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Loading

/// The only loading indicator in the app (never a system `ProgressView`): an 18 × 44 pt pole that
/// climbs one stripe period per second, at up to 30 fps and only while it's on screen. With Reduce
/// Motion it holds still. VoiceOver reads it as one element, "Loading".
///
///     BarberPoleSpinner()
///     BarberPoleSpinner(label: "Scheduling")
struct BarberPoleSpinner: View {
    var size = CGSize(width: 18, height: 44)
    var periodsPerSecond: Double = 1
    /// What VoiceOver says.
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            BarberPole(phase: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * periodsPerSecond)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
    }
}
