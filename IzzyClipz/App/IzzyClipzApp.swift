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
                .environment(appDelegate.bravo)
                .environment(appDelegate.bag)
                // Street Drip is dark only: the palette is the brand.
                .preferredColorScheme(.dark)
                .tint(Theme.dripRed)
                .task {
                    await appDelegate.bravo.refresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appDelegate.becameActive()
            }
        }
    }
}
