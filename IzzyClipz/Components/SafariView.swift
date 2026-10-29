import SafariServices
import SwiftUI

/// Shows a web page in Safari's in-app browser, keeping the client in the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(Theme.red)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone()
        }
    }
}

/// A web page in a sheet: Squire for booking, Bravo for products, Google for reviews.
///
/// The in-app browser only accepts http(s) links, so anything else is opened
/// by the system instead of crashing.
struct WebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        if LaunchOptions.isUITesting {
            // UI tests check where a link leads without depending on the network.
            WebLinkPreview(url: url)
        } else if url.scheme == "https" || url.scheme == "http" {
            SafariView(url: url) { dismiss() }
                .ignoresSafeArea()
        } else {
            Color.clear
                .onAppear {
                    openURL(url)
                    dismiss()
                }
        }
    }
}

private struct WebLinkPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(url.host ?? "Web page")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("webURL")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
