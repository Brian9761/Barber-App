import Foundation

/// The shop's website: the Visit tab's Website row and Share link, every Add to Calendar event, and
/// the Privacy Policy, Terms of Service, Cancellation & No-Show Policy and Accessibility pages the
/// app links to (opened in the in-app browser).
///
/// Its address is the build setting `IZZY_WEBSITE_URL` (project.yml), which Info.plist passes on as
/// `IzzyWebsiteURL`: https://izzy-clipz.vercel.app, the current public site, until the shop's own
/// domain replaces it there, in that one place. The app never links to the shop's older website
/// (izzyclipzbarbershop.net, on Squarespace), which the legal documents don't cover.
enum Website {
    /// The Info.plist key: `$(IZZY_WEBSITE_URL)`.
    static let infoKey = "IzzyWebsiteURL"

    /// The site this build links to.
    static let baseURL = baseURL(from: Bundle.main.object(forInfoDictionaryKey: infoKey))

    /// The current public site, the Kit's `ShopInfo.websiteURL`, for a build without a usable address.
    static var fallback: URL { AppData.shop.websiteURL }

    /// An Info.plist value as the site's address: an https address with a host, without a trailing
    /// slash, a query or a fragment. Anything else, including no value and an unexpanded
    /// `$(IZZY_WEBSITE_URL)`, is the current public site.
    static func baseURL(from value: Any?) -> URL {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              var components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty
        else { return fallback }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        components.query = nil
        components.fragment = nil
        return components.url ?? fallback
    }

    /// "izzy-clipz.vercel.app": the site as the Website row shows it, without "www.".
    static func displayName(of url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The four legal pages, as the website serves them.
    enum LegalPage: String, CaseIterable, Identifiable, Hashable {
        case privacy
        case terms
        case cancellationPolicy
        case accessibility

        var id: String { rawValue }

        /// The row's title, and the words that link to the page in a sentence.
        var title: String {
            switch self {
            case .privacy: return "Privacy Policy"
            case .terms: return "Terms of Service"
            case .cancellationPolicy: return "Cancellation & No-Show Policy"
            case .accessibility: return "Accessibility"
            }
        }

        /// What the page is for, in one line, under the row's title.
        var summary: String {
            switch self {
            case .privacy: return "What the shop keeps about you, and for how long"
            case .terms: return "The rules for booking and using this app"
            case .cancellationPolicy: return "When cancelling is free, and when a fee may be charged"
            case .accessibility: return "Help with booking or getting to the shop"
            }
        }

        /// The page on the website: `/privacy`, `/terms`, `/cancellation-policy`, `/accessibility`.
        var path: String {
            switch self {
            case .privacy: return "privacy"
            case .terms: return "terms"
            case .cancellationPolicy: return "cancellation-policy"
            case .accessibility: return "accessibility"
            }
        }

        /// The row's accessibility identifier, for UI tests: "legal-privacy", "legal-cancellation-policy"…
        var identifier: String { "legal-\(path)" }

        /// The page on the site at `base`.
        func url(on base: URL = Website.baseURL) -> URL {
            base.appendingPathComponent(path)
        }
    }
}

/// What the app says about the legal pages where it links them, in the website's words.
enum LegalCopy {
    /// Right above "Book appointment" on Review: booking is agreeing to these two, both linked.
    static let bookingConsent = "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy."
    /// The pages `bookingConsent` links.
    static let bookingConsentPages: [Website.LegalPage] = [.terms, .cancellationPolicy]

    /// Under the details form: who gets the name and number, with the Privacy Policy linked.
    static var detailsPrivacy: String {
        "Your details go to \(AppData.shop.fullName) and the services that run its booking, as our Privacy Policy explains."
    }

    /// The pages `detailsPrivacy` links.
    static let detailsPrivacyPages: [Website.LegalPage] = [.privacy]

    /// The same line in the demo version, where nothing leaves the iPhone.
    static var demoDetailsPrivacy: String {
        "Demo version: your name and number stay on this iPhone. Nothing is sent to \(AppData.shop.name) or anywhere else."
    }
}
