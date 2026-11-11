import XCTest
@testable import IzzyClipz

/// The website the app links to (the build setting IZZY_WEBSITE_URL), its legal pages, and the
/// lines that link them.
final class WebsiteTests: XCTestCase {
    /// The build setting's value as the site's address: https only, without a trailing slash, a
    /// query or a fragment. Anything else is the current public site.
    func testTheBuildSettingIsTheSitesAddress() {
        XCTAssertEqual(Website.baseURL(from: "https://izzy-clipz.vercel.app").absoluteString, "https://izzy-clipz.vercel.app")
        XCTAssertEqual(Website.baseURL(from: " https://www.izzyclipz.com/ ").absoluteString, "https://www.izzyclipz.com")
        XCTAssertEqual(Website.baseURL(from: "https://example.com/shop/?a=1#top").absoluteString, "https://example.com/shop")
        for unusable: Any? in [nil, "", "   ", "$(IZZY_WEBSITE_URL)", "http://izzy-clipz.vercel.app", "izzy-clipz.vercel.app", "https://", 42] {
            XCTAssertEqual(Website.baseURL(from: unusable), Website.fallback, "\(String(describing: unusable))")
        }
    }

    /// Without a usable setting, the app links to the shop's new website, never the older one.
    func testTheFallbackIsTheNewWebsite() {
        XCTAssertEqual(Website.fallback.absoluteString, "https://izzy-clipz.vercel.app")
        XCTAssertEqual(AppData.shop.websiteURL, Website.fallback)
        XCTAssertFalse(Website.fallback.absoluteString.contains("izzyclipzbarbershop.net"))
    }

    func testTheWebsiteRowShowsTheSitesName() {
        XCTAssertEqual(Website.displayName(of: URL(string: "https://izzy-clipz.vercel.app")!), "izzy-clipz.vercel.app")
        XCTAssertEqual(Website.displayName(of: URL(string: "https://www.izzyclipz.com")!), "izzyclipz.com")
    }

    /// The four pages, in the order Visit lists them, at the website's own paths.
    func testTheLegalPages() {
        let base = URL(string: "https://izzy-clipz.vercel.app")!
        XCTAssertEqual(Website.LegalPage.allCases.map(\.title), [
            "Privacy Policy", "Terms of Service", "Cancellation & No-Show Policy", "Accessibility",
        ])
        XCTAssertEqual(Website.LegalPage.allCases.map { $0.url(on: base).absoluteString }, [
            "https://izzy-clipz.vercel.app/privacy",
            "https://izzy-clipz.vercel.app/terms",
            "https://izzy-clipz.vercel.app/cancellation-policy",
            "https://izzy-clipz.vercel.app/accessibility",
        ])
        XCTAssertEqual(Website.LegalPage.cancellationPolicy.identifier, "legal-cancellation-policy")
        XCTAssertEqual(Set(Website.LegalPage.allCases.map(\.identifier)).count, 4)
        for page in Website.LegalPage.allCases {
            XCTAssertFalse(page.summary.isEmpty, page.title)
        }
        // A site that lives under a path keeps it.
        XCTAssertEqual(Website.LegalPage.terms.url(on: URL(string: "https://example.com/shop")!).absoluteString, "https://example.com/shop/terms")
    }

    /// The website's words, and every page they link is named in them (so the link has words to sit on).
    func testTheLinesThatLinkThePages() {
        XCTAssertEqual(LegalCopy.bookingConsent, "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy.")
        XCTAssertEqual(LegalCopy.bookingConsentPages, [.terms, .cancellationPolicy])
        XCTAssertEqual(
            LegalCopy.detailsPrivacy,
            "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains."
        )
        XCTAssertEqual(LegalCopy.detailsPrivacyPages, [.privacy])
        for page in LegalCopy.bookingConsentPages {
            XCTAssertTrue(LegalCopy.bookingConsent.contains(page.title), page.title)
        }
        for page in LegalCopy.detailsPrivacyPages {
            XCTAssertTrue(LegalCopy.detailsPrivacy.contains(page.title), page.title)
        }
        XCTAssertFalse(LegalCopy.demoDetailsPrivacy.contains("go to"), "The demo sends nothing anywhere")
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The legal pages linked inside a sentence (on Review, under the details form, in Your details).
@MainActor
final class LegalLinksTextTests: XCTestCase {
    private let base = URL(string: "https://izzy-clipz.vercel.app")!

    /// The words of each page's title link to that page, and the sentence reads as written.
    private func links(in text: AttributedString) -> [(words: String, url: String)] {
        text.runs.compactMap { run in
            guard let url = run.link else { return nil }
            return (String(text[run.range].characters), url.absoluteString)
        }
    }

    func testTheConsentLineLinksTheTermsAndTheCancellationPolicy() {
        let text = LegalLinksText.attributed(LegalCopy.bookingConsent, linking: LegalCopy.bookingConsentPages, on: base)
        XCTAssertEqual(String(text.characters), "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy.")
        let found = links(in: text)
        XCTAssertEqual(found.map(\.words), ["Terms of Service", "Cancellation & No-Show Policy"])
        XCTAssertEqual(found.map(\.url), ["https://izzy-clipz.vercel.app/terms", "https://izzy-clipz.vercel.app/cancellation-policy"])
    }

    func testTheDetailsLineLinksThePrivacyPolicy() {
        let text = LegalLinksText.attributed(LegalCopy.detailsPrivacy, linking: LegalCopy.detailsPrivacyPages, on: base)
        XCTAssertEqual(String(text.characters), LegalCopy.detailsPrivacy)
        let found = links(in: text)
        XCTAssertEqual(found.map(\.words), ["Privacy Policy"])
        XCTAssertEqual(found.map(\.url), ["https://izzy-clipz.vercel.app/privacy"])
    }

    /// A page whose title isn't in the sentence links nothing, rather than the wrong words.
    func testAMissingTitleLinksNothing() {
        let text = LegalLinksText.attributed("Nothing to link here.", linking: Website.LegalPage.allCases, on: base)
        XCTAssertTrue(links(in: text).isEmpty)
    }
}
#endif
