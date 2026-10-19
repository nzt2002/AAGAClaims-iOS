import PortalKit
import SalesforceSDKCore
import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        if AppEnvironment.current.auth == .salesforce {
            SalesforceManager.initializeSDK()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Crash and hang reports from earlier sessions arrive through MetricKit.
        CrashReporter.shared.start()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: - Push registration (Mobile SDK)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard AppEnvironment.current.auth == .salesforce else { return }
        // The SDK stores the token and registers it with Salesforce for the signed-in user.
        PushNotificationManager.sharedInstance().didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Nothing to show the user: push is optional. Don't log the error, it can include device details.
    }

    // MARK: - Notification taps

    /// Tapping a push deep-links to the record and update (spec §8).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = DeepLink(pushPayload: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            DeepLinkInbox.shared.pending = link
        }
    }

    /// Shows pushes that arrive while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }
}
