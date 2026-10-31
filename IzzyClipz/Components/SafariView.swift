import SafariServices
import SwiftUI

/// Shows a web page in Safari's in-app browser, keeping the client in the app. Its bars are ink
/// and its buttons bone, to match the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    /// Called once the first page has loaded (or failed to).
    var onInitialLoad: () -> Void = {}
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInitialLoad: onInitialLoad, onDone: onDone)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredBarTintColor = UIColor(Theme.ink2)
        controller.preferredControlTintColor = UIColor(Theme.bone)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onInitialLoad: () -> Void
        private let onDone: () -> Void

        init(onInitialLoad: @escaping () -> Void, onDone: @escaping () -> Void) {
            self.onInitialLoad = onInitialLoad
            self.onDone = onDone
        }

        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            onInitialLoad()
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone()
        }
    }
}

/// A web page in a sheet: Squire for booking, Bravo for products, Google for reviews.
///
/// Until the first page draws, a barber-pole spinner sits in the middle (it never blocks Safari's
/// own Done button, and gives up after 12 seconds in case Safari never reports the load). The
/// in-app browser only accepts http(s) links, so anything else is opened by the system instead of
/// crashing.
struct WebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isLoading = true

    var body: some View {
        if LaunchOptions.isUITesting {
            // UI tests check where a link leads without depending on the network.
            WebLinkPreview(url: url)
        } else if url.scheme == "https" || url.scheme == "http" {
            SafariView(url: url, onInitialLoad: { isLoading = false }) { dismiss() }
                .ignoresSafeArea()
                .overlay {
                    if isLoading {
                        WebLoadingBadge(host: url.host)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isLoading)
                .task {
                    try? await Task.sleep(for: .seconds(12))
                    isLoading = false
                }
        } else {
            Color.clear
                .onAppear {
                    openURL(url)
                    dismiss()
                }
        }
    }
}

/// The spinner and where it's going, on a small ink card.
private struct WebLoadingBadge: View {
    let host: String?

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            ProgressView()
                .accessibilityLabel(loadingLabel)
            if let host {
                Text(host.replacingOccurrences(of: "www.", with: ""))
                    .textRole(.label)
                    .foregroundStyle(Theme.smoke)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Theme.ink2, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line))
    }

    private var loadingLabel: String {
        guard let host else { return "Loading" }
        return "Loading \(host.replacingOccurrences(of: "www.", with: ""))"
    }
}

/// What UI tests see instead of Safari: the link's host and full address.
private struct WebLinkPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(url.host ?? "Web page")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.bone)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("webURL")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink2.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
