import SwiftUI

// The same loading, empty and error states on every screen that loads something from the shop's
// server: a spinner with a line saying what's loading, a message with what to do next, and for
// errors "Try again" plus "Call the shop", so there's always a way forward.

/// A spinner and what's loading, centred in the space it's given.
struct LoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.bone)
            Text(text)
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
        .accessibilityElement(children: .combine)
    }
}

/// Something went wrong: what happened in plain words, "Try again", and "Call the shop".
struct ErrorStateView: View {
    var title = "Couldn't load this"
    let message: String
    /// `nil` hides "Try again", e.g. when trying again can't help.
    var onRetry: (() -> Void)?
    var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.warning)
                    .font(.title3)
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title)
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("errorMessage")

            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: Theme.Space.s) {
                        if isRetrying {
                            ProgressView()
                                .tint(Theme.ink)
                        }
                        Text(isRetrying ? "Trying again…" : "Try again")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isRetrying)
                .accessibilityIdentifier("retryButton")
            }
            CallButton {
                Label("Call the shop", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("errorCallButton")
        }
        .card(padding: Theme.Space.xl)
    }
}

/// A one-line note above content that couldn't be refreshed, e.g. "Couldn't check for changes".
struct StaleDataNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: Symbol.warning)
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text(text)
                .textRole(.caption)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.l)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("staleDataNote")
    }
}
