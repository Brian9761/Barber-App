import SwiftUI

/// A sentence with the shop's legal pages linked in it, each opening in the in-app browser: "By
/// booking, you agree to our Terms of Service and Cancellation & No-Show Policy." The links are
/// electric and underlined, so they never depend on color alone, and VoiceOver reads the sentence
/// and offers its links in the rotor, as for any text with links.
struct LegalLinksText: View {
    let text: String
    /// The pages whose titles in `text` become links.
    let pages: [Website.LegalPage]
    /// Whether "Refunds" in `text` links to the refund policy (the Terms' refunds, `Website.Refunds`).
    var linksRefunds = false
    /// Opens a tapped page; `nil` opens it in the app's own web sheet (`AppRouter.openWeb`), which
    /// takes the place of any sheet that's up. A sheet with the line in it opens the page over
    /// itself instead, so it stays open underneath.
    var open: ((URL) -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        Text(Self.attributed(text, linking: pages, refunds: linksRefunds))
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

    /// `text` with each page's title in it linked to that page on `base`, underlined, and with
    /// `refunds`, "Refunds" linked to the Terms' refunds. A title that isn't in `text` is skipped.
    static func attributed(
        _ text: String,
        linking pages: [Website.LegalPage],
        refunds: Bool = false,
        on base: URL = Website.baseURL
    ) -> AttributedString {
        var attributed = AttributedString(text)
        var links = pages.map { ($0.title, $0.url(on: base)) }
        if refunds { links.append((Website.Refunds.title, Website.Refunds.url(on: base))) }
        for (title, url) in links {
            guard let range = attributed.range(of: title) else { continue }
            attributed[range].link = url
            attributed[range].swiftUI.underlineStyle = .single
            attributed[range].swiftUI.foregroundColor = Theme.electric
        }
        return attributed
    }
}
