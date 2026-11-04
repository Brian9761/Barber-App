import SwiftUI

@main
struct IzzyClipzApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NavigationBarAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.router)
                .environment(appDelegate.favorites)
                .environment(appDelegate.reminders)
                .environment(appDelegate.appointments)
                .environment(appDelegate.products)
                .environment(appDelegate.reviews)
                .environment(appDelegate.customerDetails)
                .environment(appDelegate.savedCard)
                .environment(appDelegate.noShowPolicies)
                .environment(\.shopAPI, appDelegate.api)
                .environment(\.cardSaver, appDelegate.cardSaver)
                // Street Drip is dark only: the palette is the brand.
                .preferredColorScheme(.dark)
                .tint(Theme.dripRed)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appDelegate.becameActive()
            }
        }
    }
}
