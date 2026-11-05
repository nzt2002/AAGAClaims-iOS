import UIKit

/// The Dark Mode toggle in Account: follows the iPhone until the user picks light or dark. Set on
/// every window (the app's, and the sign-in and lock windows the Salesforce SDK adds later).
enum AppAppearance: String {
    case system, light, dark

    static let storageKey = "appearance"

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Restyles the windows on screen now.
    @MainActor static func apply() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = current.style
            }
        }
    }

    /// Styles each window as it appears. Call once, at launch.
    @MainActor static func observeWindows() {
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply() }
        }
    }
}
