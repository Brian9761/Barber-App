import SwiftUI

/// "Demo version: bookings aren't sent to the shop." A quiet line on ink, shown only in the demo
/// version (`DemoMode`) where a tester would otherwise take a booking for the real thing: under
/// Home's Book button, and under "No payment now" when reviewing a booking and once it's booked.
struct DemoNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: Symbol.info)
                .foregroundStyle(Theme.electric)
                .accessibilityHidden(true)
            Text(DemoMode.notice)
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("demoNotice")
    }
}

extension View {
    /// This view with `DemoNotice` under it in the demo version; just this view in every other.
    @ViewBuilder
    func withDemoNotice() -> some View {
        if DemoMode.isOn {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                self
                DemoNotice()
            }
        } else {
            self
        }
    }
}
