import SwiftUI

/// A sentence with the shop's legal pages linked in it, each opening in the in-app browser: "By
/// booking, you agree to our Terms of Service and Cancellation & No-Show Policy." The links are
/// electric and underlined, so they never depend on color alone, and VoiceOver reads the sentence
/// and offers its links in the rotor, as for any text with links.
struct LegalLinksText: View {
    let text: String
    /// The pages whose titles in `text` become links.
    let pages: [Website.LegalPage]
    /// Opens a tapped page; `nil` opens it in the app's own web sheet (`AppRouter.openWeb`), which
    /// takes the place of any sheet that's up. A sheet with the line in it opens the page over
    /// itself instead, so it stays open underneath.
    var open: ((URL) -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        Text(Self.attributed(text, linking: pages))
            .tint(Theme.electric)
            .environment(\.openURL, OpenURLAction { url in
                if let open {
                    open(url)
                } else {
                    router.openWeb(url)
                }
                return .handled
            })
    }

    /// `text` with each page's title in it linked to that page on `base`, underlined. A title that
    /// isn't in `text` is skipped.
    static func attributed(_ text: String, linking pages: [Website.LegalPage], on base: URL = Website.baseURL) -> AttributedString {
        var attributed = AttributedString(text)
        for page in pages {
            guard let range = attributed.range(of: page.title) else { continue }
            attributed[range].link = page.url(on: base)
            attributed[range].swiftUI.underlineStyle = .single
            attributed[range].swiftUI.foregroundColor = Theme.electric
        }
        return attributed
    }
}
