import Foundation

/// The shop's website, where Settings → Legal opens the Privacy Policy, the Terms of Service, the
/// Cancellation & No-Show Policy and the Accessibility Statement (in the in-app browser).
///
/// Its address is the build setting `IZZY_WEBSITE_URL` (project.yml), which Info.plist passes on as
/// `IzzyWebsiteURL`: https://izzy-clipz.vercel.app, the current public site, until the shop's own
/// domain replaces it there, in that one place.
enum Website {
    /// The Info.plist key: `$(IZZY_WEBSITE_URL)`.
    static let infoKey = "IzzyWebsiteURL"

    /// The current public site, for a build without a usable address.
    static let fallback = URL(string: "https://izzy-clipz.vercel.app")!

    /// The site this build links to.
    static func baseURL(bundle: Bundle = .main) -> URL {
        baseURL(from: bundle.object(forInfoDictionaryKey: infoKey))
    }

    /// An Info.plist value as the site's address: an https address with a host, without a trailing
    /// slash. Anything else, including no value and an unexpanded `$(IZZY_WEBSITE_URL)`, is the
    /// current public site.
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

    /// The four legal pages, as the website serves them.
    enum LegalPage: String, CaseIterable, Identifiable, Hashable {
        case privacy
        case terms
        case cancellationPolicy
        case accessibility

        var id: String { rawValue }

        /// The row's title.
        var title: String {
            switch self {
            case .privacy: return "Privacy Policy"
            case .terms: return "Terms of Service"
            case .cancellationPolicy: return "Cancellation & No-Show Policy"
            case .accessibility: return "Accessibility"
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
        func url(on base: URL) -> URL {
            base.appendingPathComponent(path)
        }
    }
}
