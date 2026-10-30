import SwiftUI
import UIKit

/// Dark native navigation bars, set once at launch.
///
/// Pushed screens keep the system bar so the back button and swipe-back work exactly as
/// everywhere else in iOS. It's styled to match: transparent over the ink canvas at rest (screens
/// put their big Display title in the content), solid `ink` with a hairline once content scrolls
/// under it, the title in bone Archivo Condensed ExtraBold and the back button in bone, so the
/// screen's one red stays its main action.
///
/// It sets only UIKit appearance proxies, so on iOS 26 the bar keeps its Liquid Glass buttons.
enum NavigationBarAppearance {
    static func apply() {
        let bone = UIColor(Theme.bone)
        let title: [NSAttributedString.Key: Any] = [
            .font: BrandFont.condensedExtraBold.uiFont(size: 19, relativeTo: .headline),
            .foregroundColor: bone,
        ]
        let largeTitle: [NSAttributedString.Key: Any] = [
            .font: BrandFont.extraCondensedBlack.uiFont(size: 40, relativeTo: .largeTitle),
            .foregroundColor: bone,
        ]
        let backButton = UIBarButtonItemAppearance(style: .plain)
        backButton.normal.titleTextAttributes = [
            .font: BrandFont.semiBold.uiFont(size: 16, relativeTo: .body),
            .foregroundColor: bone,
        ]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithOpaqueBackground()
        scrolled.backgroundColor = UIColor(Theme.ink)
        scrolled.shadowColor = UIColor(Theme.line)
        scrolled.titleTextAttributes = title
        scrolled.largeTitleTextAttributes = largeTitle
        scrolled.backButtonAppearance = backButton

        let atRest = UINavigationBarAppearance()
        atRest.configureWithTransparentBackground()
        atRest.titleTextAttributes = title
        atRest.largeTitleTextAttributes = largeTitle
        atRest.backButtonAppearance = backButton

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = atRest
        bar.compactScrollEdgeAppearance = atRest
        bar.tintColor = bone
    }
}
