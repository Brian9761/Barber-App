import SwiftUI

@main
struct IzzyClipzApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.router)
                .environment(appDelegate.favorites)
                .environment(appDelegate.reminders)
                .preferredColorScheme(.dark)
                .tint(Theme.red)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Rolls reminders forward and notices permission changes made in Settings.
                appDelegate.reminders.refresh()
            }
        }
    }
}
