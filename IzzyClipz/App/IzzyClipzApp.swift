import SwiftUI

@main
struct IzzyClipzApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    /// iOS's age range, asked at launch where a law requires it (`AgeCheck`); kept only in memory.
    @State private var ageCheck = AgeCheck.launchOutcome(arguments: ProcessInfo.processInfo.arguments, isUITesting: LaunchOptions.isUITesting)

    init() {
        NavigationBarAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Someone under 13: a screen asking a parent or guardian to book, and nothing else.
                if AgeCheck.showsParentScreen(ageCheck) {
                    ParentScreen()
                } else {
                    RootView()
                }
            }
            .ageRangeCheck(isEnabled: AgeCheck.asks(isUITesting: LaunchOptions.isUITesting), outcome: $ageCheck)
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
