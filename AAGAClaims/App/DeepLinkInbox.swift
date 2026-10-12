import Observation
import PortalKit
import SalesforceSDKCore
import SwiftUI
import UserNotifications

/// Holds a deep link, universal link or notification tap until the signed-in UI can open it.
/// Links that arrive before sign-in (e.g. a push that launches the app) wait here.
@MainActor
@Observable
final class DeepLinkInbox {
    static let shared = DeepLinkInbox()
    var pending: DeepLink?

    /// Accepts a URL the app was opened with. Returns false if it isn't one of ours.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        pending = link
        return true
    }
}

/// Push permission and registration (spec §8). Registration goes through the Mobile SDK, which
/// registers the device with Salesforce for the signed-in user.
enum PushNotifications {
    enum Status {
        case notDetermined, allowed, denied
    }

    static func status() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    /// Asks for permission (alerts, sounds and the unread badge) and registers if granted.
    @MainActor
    static func requestPermission(registerWithSalesforce: Bool) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted, registerWithSalesforce {
            register()
        }
        return granted
    }

    /// Re-registers on each sign-in when permission was already granted.
    @MainActor
    static func registerIfAllowed(registerWithSalesforce: Bool) async {
        guard registerWithSalesforce, await status() == .allowed else { return }
        register()
    }

    @MainActor
    private static func register() {
        PushNotificationManager.sharedInstance().registerForRemoteNotifications()
    }

    @MainActor
    static func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
