import SwiftUI

/// The Analytics tab: the whole shop's, or one barber's, sales, services, products and
/// productivity, live. This is the tab's place in the app until the Analytics screen replaces this
/// file (the same file name and the same `AnalyticsTab` view).
struct AnalyticsTab: View {
    let workspace: Workspace

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Analytics",
                systemImage: "chart.bar.xaxis",
                description: Text("The shop's sales, top barbers, services and products will show here.")
            )
            .accessibilityIdentifier("analyticsPlaceholder")
            .navigationTitle("Analytics")
        }
    }
}
