import SafariServices
import SwiftUI

/// A web page in Safari's in-app browser, in a sheet, so the owner stays in the app: the
/// website's legal pages (Settings → Legal).
///
/// UI tests (`-ui-testing`) see the page's address instead of Safari, so they check where a link
/// leads without depending on the network. Anything that isn't an http(s) address is opened by
/// the system instead (the in-app browser only takes web pages).
struct WebPageSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains(LaunchArgument.uiTesting) {
            WebAddressPreview(url: url)
        } else if url.scheme == "https" || url.scheme == "http" {
            SafariPage(url: url) { dismiss() }
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

/// `SFSafariViewController`, with Done closing the sheet.
private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(BusinessTheme.red)
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

/// What UI tests see instead of Safari: the page's site and its full address.
private struct WebAddressPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(url.host ?? "Web page")
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("webURL")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("webDone")
                }
            }
        }
    }
}
