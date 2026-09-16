import SwiftUI
import UIKit
import UserNotifications

final class LittleRipAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        LittleRipNotificationDesign.configureCategories()

        // Ask on the first app launch instead of waiting until the user's first
        // scheduled notification. iOS only presents this system dialog once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Task {
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .notDetermined else { return }
                _ = try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge, .timeSensitive]
                )
            }
        }
        return true
    }

    /// Show LittleRip alerts even while the app is open, so short test timers are
    /// visible instead of silently disappearing in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == LittleRipNotificationDesign.snoozeActionIdentifier else {
            return
        }

        let original = response.notification.request.content
        let message = (original.userInfo["littleripMessage"] as? String) ?? original.body
        let content = LittleRipNotificationDesign.brandedContent(message: message)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "littlerip.notification.snooze.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}

@main
struct LittleRipApp: App {
    @UIApplicationDelegateAdaptor(LittleRipAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
