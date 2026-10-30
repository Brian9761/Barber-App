import SwiftUI

/// The logo's paint drip as a shape: rounded tongues hanging from the top edge, some with a droplet
/// below, over an optional band along the top (spec §5, the same geometry as the mock's `drip()`).
///
/// It's a signature, not wallpaper, so it appears in only three places: under the main Book button
/// (and the Confirm on Squire button, its twin), along the top of the Shop's featured gel card, and
/// built into the Rubik Wet Paint drip word. Drips never animate.
struct DripEdge: Shape {
    struct Drip {
        /// Centre, in the design width's points.
        var x: CGFloat
        var width: CGFloat
        var length: CGFloat
        var hasDroplet = false
    }

    var drips: [Drip]
    /// How tall the solid strip along the top is (0 for drips hanging straight off a button).
    var band: CGFloat = 0
    /// The width the drip positions were designed at. Drips keep their size and spread out or
    /// close up with the actual width.
    var designWidth: CGFloat = 358

    /// Under the main Book button (and Confirm on Squire).
    static let underButton: [Drip] = [
        Drip(x: 34, width: 7, length: 11),
        Drip(x: 58, width: 5.5, length: 20, hasDroplet: true),
        Drip(x: 150, width: 6, length: 9),
        Drip(x: 236, width: 8, length: 15),
        Drip(x: 262, width: 5, length: 8),
    ]

    /// Along the top of the Shop's featured gel card, with a 5 pt band.
    static let gelCard: [Drip] = [
        Drip(x: 22, width: 9, length: 14),
        Drip(x: 46, width: 6, length: 24, hasDroplet: true),
        Drip(x: 112, width: 8, length: 10),
        Drip(x: 150, width: 5, length: 18),
        Drip(x: 196, width: 10, length: 12),
        Drip(x: 236, width: 6, length: 8),
    ]

    /// How far the longest drip and its droplet reach below the top edge.
    static func depth(of drips: [Drip], band: CGFloat = 0) -> CGFloat {
        let reach = drips.map { drip in
            drip.hasDroplet ? drip.length + 3 + 0.9 * drip.width / 2 + 0.72 * drip.width / 2 : drip.length
        }
        return band + (reach.max() ?? 0)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = rect.minY + band
        if band > 0 {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: band))
        }
        let scale = designWidth > 0 ? rect.width / designWidth : 1
        let shoulder: CGFloat = 3.2
        let kappa: CGFloat = 0.5523
        for drip in drips {
            let x = rect.minX + drip.x * scale
            let r = drip.width / 2
            let tipCentre = t + drip.length - r
            path.move(to: CGPoint(x: x - r - shoulder, y: t))
            path.addCurve(to: CGPoint(x: x - r, y: t + 4), control1: CGPoint(x: x - r, y: t), control2: CGPoint(x: x - r, y: t + 1.6))
            path.addLine(to: CGPoint(x: x - r, y: tipCentre))
            // The round tip, as two quarter ellipses.
            path.addCurve(to: CGPoint(x: x, y: tipCentre + r),
                          control1: CGPoint(x: x - r, y: tipCentre + kappa * r),
                          control2: CGPoint(x: x - kappa * r, y: tipCentre + r))
            path.addCurve(to: CGPoint(x: x + r, y: tipCentre),
                          control1: CGPoint(x: x + kappa * r, y: tipCentre + r),
                          control2: CGPoint(x: x + r, y: tipCentre + kappa * r))
            path.addLine(to: CGPoint(x: x + r, y: t + 4))
            path.addCurve(to: CGPoint(x: x + r + shoulder, y: t), control1: CGPoint(x: x + r, y: t + 1.6), control2: CGPoint(x: x + r, y: t))
            path.closeSubpath()
            if drip.hasDroplet {
                let dropRadius = 0.72 * r
                let centre = CGPoint(x: x, y: t + drip.length + 3 + 0.9 * r)
                path.addEllipse(in: CGRect(x: centre.x - dropRadius, y: centre.y - dropRadius, width: 2 * dropRadius, height: 2 * dropRadius))
            }
        }
        return path
    }
}
