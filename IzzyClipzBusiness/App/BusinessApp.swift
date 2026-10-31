import SwiftUI

/// Izzy Clipz Business: the shop owner's app.
@main
struct BusinessApp: App {
    @State private var model = AppModel(environment: .forLaunch())

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(BusinessTheme.red)
        }
    }
}

/// Sign in, or the five tabs once signed in.
struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading")
            case .signedOut:
                SignInView(model: model)
            case .signedIn(let workspace):
                MainTabView(workspace: workspace, model: model)
                    .id(ObjectIdentifier(workspace))
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Back in the foreground: Stripe's status is checked again and Tap
            // to Pay reconnects (Apple asks apps to warm it up every time).
            Task { await model.becameActive() }
        }
    }
}

/// Schedule, New booking, Take payment, Products, Settings.
struct MainTabView: View {
    @Bindable var workspace: Workspace
    let model: AppModel

    var body: some View {
        TabView(selection: $workspace.selectedTab) {
            ScheduleView(store: workspace.schedule, workspace: workspace)
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Workspace.Tab.schedule)
            NewBookingView(store: workspace.booking, workspace: workspace)
                .tabItem { Label("New booking", systemImage: "person.badge.plus") }
                .tag(Workspace.Tab.newBooking)
            TakePaymentView(checkout: workspace.checkout, workspace: workspace)
                .tabItem { Label("Take payment", systemImage: "wave.3.right.circle") }
                .tag(Workspace.Tab.payment)
            ProductsView(store: workspace.products, allowsTestPhoto: workspace.environment.usesSampleServer)
                .tabItem { Label("Products", systemImage: "bag") }
                .tag(Workspace.Tab.products)
            SettingsView(workspace: workspace, model: model)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Workspace.Tab.settings)
        }
        .sheet(isPresented: $workspace.showsHowToTap) {
            HowToTapView()
        }
    }
}
