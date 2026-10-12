import SalesforceSDKCore
import SwiftUI
import UIKit

/// Follows the Mobile SDK's native template: the SDK presents its login screen over this
/// scene's window, and we swap in the SwiftUI app once a user is signed in.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let session = AppSession(environment: .current)

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: RootView(session: self.session))
        window.makeKeyAndVisible()
        self.window = window

        switch self.session.environment.auth {
        case .demo:
            self.session.didSignIn(.demo)
        case .salesforce:
            AuthHelper.registerBlock(forCurrentUserChangeNotifications: scene) { [weak self] in
                self?.signInIfNeeded(scene)
            }
            AuthHelper.registerBlock(forLogoutNotifications: scene) { [weak self] in
                self?.session.didSignOut()
                self?.signInIfNeeded(scene)
            }
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        if session.environment.auth == .salesforce {
            signInIfNeeded(scene)
        }
    }

    /// Shows the SDK login (pointed at the portal domain via `SFDCOAuthLoginHost`) when there's
    /// no session, then publishes the user.
    private func signInIfNeeded(_ scene: UIScene) {
        AuthHelper.loginIfRequired(scene) { [weak self] in
            guard let self, let user = Self.currentUser() else { return }
            self.session.didSignIn(user)
        }
    }

    private static func currentUser() -> CurrentUser? {
        guard let identity = UserAccountManager.shared.currentUserAccount?.idData else { return nil }
        return CurrentUser(
            firstName: identity.firstName,
            fullName: identity.displayName ?? identity.email,
            email: identity.email
        )
    }
}

enum SalesforceSession {
    /// Revokes the token and clears the SDK's keychain and caches (spec §6.11). The logout
    /// notification registered in `SceneDelegate` then shows the login screen again.
    static func signOut() {
        UserAccountManager.shared.logout()
    }
}
