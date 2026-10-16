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

/// The shop's Squire booking page for a request.
struct BookingSheet: View {
    let request: BookingRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let url = AppData.bookingURL(for: request)
        if LaunchOptions.isUITesting {
            // UI tests check where booking leads without depending on Squire being up.
            BookingLinkPreview(url: url)
        } else {
            SafariView(url: url) { dismiss() }
                .ignoresSafeArea()
        }
    }
}

private struct BookingLinkPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Squire booking page")
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("bookingURL")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
