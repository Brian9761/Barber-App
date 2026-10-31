import SwiftUI
import UIKit

/// Dark native navigation bars (and the tab bar's colors), set once at launch.
///
/// Every screen keeps the system bar, so the back button, swipe-back and large titles work exactly
/// as everywhere else in iOS. It's styled to match the dark canvas: transparent at rest, solid
/// `ink` with a hairline once content scrolls under it, titles in bone on the system font, and the
/// back button in bone, so each screen's one red stays its main action.
///
/// It sets only UIKit appearance proxies, so on iOS 26 the bar keeps its Liquid Glass buttons.
enum NavigationBarAppearance {
    static func apply() {
        let bone = UIColor(Theme.bone)
        let title: [NSAttributedString.Key: Any] = [.foregroundColor: bone]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithOpaqueBackground()
        scrolled.backgroundColor = UIColor(Theme.ink)
        scrolled.shadowColor = UIColor(Theme.line)
        scrolled.titleTextAttributes = title
        scrolled.largeTitleTextAttributes = title

        let atRest = UINavigationBarAppearance()
        atRest.configureWithTransparentBackground()
        atRest.titleTextAttributes = title
        atRest.largeTitleTextAttributes = title

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = atRest
        bar.compactScrollEdgeAppearance = atRest
        bar.tintColor = bone

        // The system tab bar: the selected tab in red (as the TabView's tint says), the rest smoke.
        let tabBar = UITabBar.appearance()
        tabBar.tintColor = UIColor(Theme.dripRed)
        tabBar.unselectedItemTintColor = UIColor(Theme.smoke)
    }
}
