import UIKit
import XCTest
@testable import IzzyClipz

/// The floating tab bar and the barber-pole sweep between tabs: the identifiers the UI tests use,
/// where the bar sits, the room every tab keeps above it, and the sweep's geometry and timing from
/// the pole spec.
@MainActor
final class TabBarTests: XCTestCase {
    // MARK: The bar

    func testTabsInBarOrderWithTheirIdentifiersAndTitles() {
        XCTAssertEqual(AppTab.barOrder, [.home, .services, .book, .shop, .visit])
        XCTAssertEqual(AppTab.barOrder.map(\.barIdentifier), ["tab.home", "tab.services", "tab.book", "tab.shop", "tab.visit"])
        XCTAssertEqual(AppTab.barOrder.map(\.barTitle), ["Home", "Services", "Book", "Shop", "Visit"])
    }

    func testEveryTabSymbolExists() {
        for tab in AppTab.barOrder {
            for isSelected in [false, true] {
                let name = tab.barSymbol(isSelected: isSelected)
                XCTAssertNotNil(UIImage(systemName: name), "\(tab) (selected: \(isSelected)): \(name)")
            }
        }
    }

    /// Just inside the home indicator on Face ID iPhones, and 12 pt off the edge on iPhones with a
    /// Home button. Never floating high above the bottom, never on top of the home indicator.
    func testTheBarSitsOnTheBottomEdge() {
        let faceID = StreetTabBar.bottomGap(safeAreaBottom: 34)
        XCTAssertGreaterThanOrEqual(faceID, 8)
        XCTAssertLessThanOrEqual(faceID, 34)
        XCTAssertEqual(StreetTabBar.bottomGap(safeAreaBottom: 0), 12)
        XCTAssertGreaterThanOrEqual(StreetTabBar.barHeight, Theme.minimumTapSize)
    }

    /// Each tab root reserves room so its content and its sticky bars (Continue, Book this, Add to
    /// bag) end above the floating bar: above the raised Book button, or on the Book tab, where the
    /// button has settled into the bar, above the mini pole standing on it.
    func testContentEndsAboveTheBar() {
        for inset in [0, 20, 34] as [CGFloat] {
            let barTop = StreetTabBar.bottomGap(safeAreaBottom: inset) + StreetTabBar.barHeight
            for tab in AppTab.barOrder {
                let contentBottom = inset + StreetTabBar.contentReserve(for: tab, safeAreaBottom: inset)
                let tallest = tab == .book ? StreetTabBar.indicatorRise : StreetTabBar.raisedLift
                XCTAssertGreaterThan(contentBottom, barTop + tallest, "\(tab) with a \(inset) pt home-indicator inset")
            }
        }
    }

    /// The pole spec's numbers on a 390 × 844 iPhone: Book's Continue bar ends 22 pt above the bar,
    /// 3 pt clear of the mini pole.
    func testBooksContinueBarClearsTheMiniPole() {
        let barTop = StreetTabBar.bottomGap(safeAreaBottom: 34) + StreetTabBar.barHeight
        let contentBottom = 34 + StreetTabBar.contentReserve(for: .book, safeAreaBottom: 34)
        XCTAssertEqual(contentBottom - barTop, 22)
        XCTAssertEqual(contentBottom - barTop - StreetTabBar.indicatorRise, 3)
    }

    // MARK: The sweep

    /// Going to a tab on the right, the pole comes in from the right edge and travels left; the
    /// raised Book button counts as the middle tab.
    func testTheSweepDirectionFollowsTheTabOrder() {
        func direction(_ from: AppTab, _ to: AppTab) -> PoleSweepDirection {
            PoleSweepDirection(
                fromIndex: AppTab.barOrder.firstIndex(of: from) ?? 0,
                toIndex: AppTab.barOrder.firstIndex(of: to) ?? 0
            )
        }
        XCTAssertEqual(direction(.home, .services), .rightToLeft)
        XCTAssertEqual(direction(.home, .book), .rightToLeft)
        XCTAssertEqual(direction(.visit, .book), .leftToRight)
        XCTAssertEqual(direction(.shop, .home), .leftToRight)
    }

    /// pole-spec.md §3b on the 390 × 844 reference screen.
    func testSweepGeometryOnTheReferenceScreen() {
        let geometry = PoleSweepGeometry(screen: CGSize(width: 390, height: 844), safeAreaTop: 54, metrics: .streetDrip)
        XCTAssertEqual(geometry.glassWidth, 98)
        XCTAssertEqual(geometry.trackWidth, 130)
        XCTAssertEqual(geometry.poleTop, 58)
        XCTAssertEqual(geometry.poleBottom, 732)
        // It starts and ends off screen, on either side.
        XCTAssertEqual(geometry.centerX(at: 0, direction: .rightToLeft), 455)
        XCTAssertEqual(geometry.centerX(at: 1, direction: .rightToLeft), -65)
        XCTAssertEqual(geometry.centerX(at: 0, direction: .leftToRight), -65)
        XCTAssertEqual(geometry.centerX(at: 1, direction: .leftToRight), 455)
    }

    func testTheGlassWidthIsClamped() {
        let narrow = PoleSweepGeometry(screen: CGSize(width: 280, height: 600), safeAreaTop: 20, metrics: .streetDrip)
        XCTAssertEqual(narrow.glassWidth, 80)
        let wide = PoleSweepGeometry(screen: CGSize(width: 1024, height: 1366), safeAreaTop: 24, metrics: .streetDrip)
        XCTAssertEqual(wide.glassWidth, 128)
    }

    /// 460 ms on the soft S curve: the glass shows 22 ms after the tap, crosses mid-screen at 200 ms
    /// and has left by 406 ms (pole-spec.md §3d).
    func testTheSweepTimeline() {
        let metrics = PoleSweepMetrics.streetDrip
        XCTAssertEqual(metrics.duration, 0.46, accuracy: 0.0001)
        XCTAssertEqual(metrics.spinPeriods, 2, accuracy: 0.0001)
        XCTAssertEqual(metrics.fadeDuration, 0.2, accuracy: 0.0001)
        XCTAssertEqual(metrics.curve.value(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(metrics.curve.value(at: 1), 1, accuracy: 0.0001)

        let geometry = PoleSweepGeometry(screen: CGSize(width: 390, height: 844), safeAreaTop: 54, metrics: metrics)
        func centerX(atMilliseconds ms: Double) -> CGFloat {
            geometry.centerX(at: CGFloat(metrics.curve.value(at: ms / 1000 / metrics.duration)), direction: .rightToLeft)
        }
        XCTAssertEqual(centerX(atMilliseconds: 22), 439, accuracy: 1.5)
        XCTAssertEqual(centerX(atMilliseconds: 200), 200, accuracy: 1.5)
        XCTAssertEqual(centerX(atMilliseconds: 406), -41, accuracy: 1.5)
        // The pole only ever moves one way.
        var previous = centerX(atMilliseconds: 0)
        for ms in stride(from: 20.0, through: 460, by: 20) {
            let x = centerX(atMilliseconds: ms)
            XCTAssertLessThanOrEqual(x, previous, "\(ms) ms")
            previous = x
        }
    }

    /// The pole's base ends 16 pt above the floating bar, which it passes behind.
    func testThePoleEndsAboveTheBar() {
        let barTop = StreetTabBar.bottomGap(safeAreaBottom: 34) + StreetTabBar.barHeight
        XCTAssertEqual(PoleSweepMetrics.streetDrip.bottomInset - barTop, 16)
    }
}
