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
                .environment(appDelegate.appointments)
                .environment(appDelegate.bravo)
                .environment(appDelegate.bag)
                .preferredColorScheme(.light)
                .tint(Theme.red)
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
