import SwiftUI
import UIKit
#if canImport(ProximityReader)
import ProximityReader
#endif

/// Apple's "How to Tap" merchant education for Tap to Pay on iPhone, which
/// Apple asks apps to show after the terms are accepted and to keep in
/// Settings.
///
/// On iOS 18 Apple provides the screens itself (`ProximityReaderDiscovery`).
/// Where they can't be shown (the Simulator, an iPhone without Tap to Pay, UI
/// tests), the app shows its own short version, `HowToTapView`.
enum TapToPayEducation {
    /// Whether this iPhone has the hardware for Tap to Pay on iPhone.
    static var isSupportedOnThisDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif canImport(ProximityReader)
        return PaymentCardReader.isSupported
        #else
        return false
        #endif
    }

    /// Presents Apple's "How to Tap" screens over the app. `false` when they
    /// couldn't be shown, so the caller can show `HowToTapView` instead.
    @MainActor
    static func presentAppleContent() async -> Bool {
        #if canImport(ProximityReader) && !targetEnvironment(simulator)
        // The app targets iOS 18, where Apple added these screens; the check
        // keeps this right if the deployment target ever goes lower.
        guard #available(iOS 18.0, *) else { return false }
        guard isSupportedOnThisDevice, let presenter = topViewController() else { return false }
        do {
            let discovery = ProximityReaderDiscovery()
            let content = try await discovery.content(for: .payment(.howToTap))
            try await discovery.presentContent(content, from: presenter)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// The view controller on top of everything, which Apple's sheet must be
    /// presented from.
    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
            ?? scenes.compactMap(\.keyWindow).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// The app's own "How to Tap" steps, for when Apple's can't be shown.
struct HowToTapView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("hand.tap", "Start the payment", "Enter the amount and tap Tap to Pay on iPhone. Check the amount with the customer first."),
        ("iphone.gen3", "Hand over or hold out the iPhone", "Turn the screen toward the customer, so they can see the amount."),
        ("wave.3.right.circle", "Customer taps near the top", "They hold their card, phone or watch flat against the top of the iPhone, near the camera, until they see a checkmark."),
        ("lock.shield", "PIN if asked", "Some cards ask for a PIN. The customer types it on the iPhone's screen."),
        ("checkmark.seal", "Wait for the result", "The app shows Paid or tells you what went wrong. Offer the email receipt."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(steps, id: \.title) { step in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } icon: {
                            Image(systemName: step.symbol)
                                .foregroundStyle(BusinessTheme.red)
                                .imageScale(.large)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Contactless cards, Apple Pay and other digital wallets all work the same way.")
                }
            }
            .navigationTitle("How to Tap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("howToTapDone")
                }
            }
        }
        .accessibilityIdentifier("howToTapScreen")
    }
}
