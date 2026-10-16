import UIKit
import UserNotifications

/// Owns the app's shared state and handles taps on reminder notifications.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()
    let favorites = Favorites(defaults: LaunchOptions.defaults)
    let reminders = ReminderStore(scheduler: SystemNotificationScheduler(), defaults: LaunchOptions.defaults)

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

    /// Shows reminders even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping a reminder takes the client straight to booking.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isReminder = response.notification.request.identifier.hasPrefix(ReminderIdentifiers.prefix)
        Task { @MainActor in
            if isReminder {
                self.router.startBooking()
            }
            completionHandler()
        }
    }
}
