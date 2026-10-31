import SwiftUI
import UIKit
import UserNotifications

/// Owns the app's shared state and handles taps on notifications.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()
    let favorites = Favorites(defaults: LaunchOptions.defaults)
    let reminders = ReminderStore(scheduler: AppDelegate.makeScheduler(), defaults: LaunchOptions.defaults)
    let customerDetails = CustomerDetailsStore(defaults: LaunchOptions.defaults)
    /// The shop's server, or an in-memory fake while UI testing.
    let api: any ShopAPI = APIConfiguration.makeAPI()
    private(set) lazy var appointments = AppointmentStore(
        api: api,
        tokens: AppDelegate.makeTokenStore(),
        scheduler: AppDelegate.makeScheduler(),
        defaults: LaunchOptions.defaults
    )
    private(set) lazy var products = ProductsStore { [api] in try await api.products() }

    /// Manage tokens live in the Keychain. UI tests keep them in memory, so every run starts
    /// empty and nothing is left in the simulator's Keychain.
    private static func makeTokenStore() -> SecretStore {
        LaunchOptions.isUITesting ? InMemorySecretStore() : KeychainSecretStore(service: "com.izzyclipz.app.manage-tokens")
    }

    /// UI tests never see a permission alert; everyone else gets the real thing.
    private static func makeScheduler() -> NotificationScheduling {
        LaunchOptions.isUITesting ? AlwaysAllowedNotificationScheduler() : SystemNotificationScheduler()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        if LaunchOptions.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        return true
    }

    /// Rolls reminders forward, drops old appointments, and treats the latest
    /// appointment that's over as the client's last cut.
    func becameActive() {
        appointments.refreshLocally()
        if let lastAppointment = appointments.latestFinishedStart, lastAppointment > reminders.lastCut {
            reminders.setLastCut(lastAppointment)
        } else {
            // Also notices permission changes made in Settings.
            reminders.refresh()
        }
    }

    /// Shows notifications even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A cut reminder opens booking; an appointment reminder opens Home, where
    /// the appointment card is.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if identifier.hasPrefix(ReminderIdentifiers.prefix) {
                self.router.startBooking()
            } else if identifier.hasPrefix(AppointmentStore.identifierPrefix) {
                self.router.closeSheet()
                self.router.homePath = NavigationPath()
                self.router.selectedTab = .home
            }
            completionHandler()
        }
    }
}
