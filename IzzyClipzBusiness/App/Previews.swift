#if DEBUG
import IzzyClipzKit
import SwiftUI

/// Xcode previews: every screen on the in-memory sample server with the
/// simulated reader, at the UI tests' fixed "now" (Monday, November 2, 2026,
/// 11:05 AM in the shop). Nothing touches the network, the keychain or Stripe.
@MainActor
enum PreviewSupport {
    static func model(_ arguments: Set<String> = [LaunchArgument.signedIn]) -> AppModel {
        AppModel(environment: .sample(arguments: arguments))
    }

    static func workspace(_ arguments: Set<String> = []) -> (AppModel, Workspace) {
        let model = model(arguments.union([LaunchArgument.signedIn]))
        let environment = model.environment
        var stripe = IzzyAPI.StripeStatus(configured: true, mode: .test, locationId: "tml_sample_location")
        if arguments.contains(LaunchArgument.stripeNotConfigured) { stripe = IzzyAPI.StripeStatus(configured: false) }
        let workspace = Workspace(environment: environment, ownerKey: FakeServer.ownerKey, status: IzzyAPI.OwnerStatus(stripe: stripe))
        return (model, workspace)
    }

    static var sampleAppointmentID: String {
        let (_, workspace) = workspace()
        guard case .sample(let server) = workspace.environment.backend else { return "" }
        return server.appointments.first { $0.status == .booked }?.id ?? ""
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(model: PreviewSupport.model())
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
            .previewDisplayName("Signed in")
        RootView(model: PreviewSupport.model([]))
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
            .previewDisplayName("Sign in")
    }
}

struct ScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        ScheduleView(store: workspace.schedule, workspace: workspace)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
    }
}

struct AppointmentDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        NavigationStack {
            AppointmentDetailView(appointmentID: PreviewSupport.sampleAppointmentID, store: workspace.schedule, workspace: workspace)
        }
        .task { await workspace.schedule.refresh() }
        .preferredColorScheme(.dark)
        .tint(BusinessTheme.red)
    }
}

struct NewBookingView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        NewBookingView(store: workspace.booking, workspace: workspace)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
    }
}

struct TakePaymentView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        TakePaymentView(checkout: workspace.checkout, workspace: workspace)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
            .previewDisplayName("Test mode")
        let (_, unconfigured) = PreviewSupport.workspace([LaunchArgument.stripeNotConfigured])
        TakePaymentView(checkout: unconfigured.checkout, workspace: unconfigured)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
            .previewDisplayName("Stripe not set up")
    }
}

struct ProductsView_Previews: PreviewProvider {
    static var previews: some View {
        let (_, workspace) = PreviewSupport.workspace()
        ProductsView(store: workspace.products, allowsTestPhoto: true)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
        ProductEditorView(store: workspace.products, product: nil, allowsTestPhoto: true)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
            .previewDisplayName("New product")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let (model, workspace) = PreviewSupport.workspace()
        SettingsView(workspace: workspace, model: model)
            .preferredColorScheme(.dark)
            .tint(BusinessTheme.red)
        HowToTapView()
            .preferredColorScheme(.dark)
            .previewDisplayName("How to Tap")
    }
}
#endif
