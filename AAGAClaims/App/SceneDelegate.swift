import SalesforceSDKCore
import SwiftUI
import UIKit

/// Follows the Mobile SDK's native template, with one change: signed-out users see the app's own
/// welcome screen, and the SDK's login appears only when they tap Sign In.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let session = AppSession(environment: .current)
    /// True while the SDK's login screen is up. Leaving the app during login (to copy a
    /// verification code from Authenticator, Messages or Mail, or for a password prompt) brings
    /// it back through `sceneWillEnterForeground`; without this, that started a second login
    /// that replaced the first and lost what was typed.
    private var isSigningIn = false

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

        // Links that launched the app.
        for context in connectionOptions.urlContexts {
            DeepLinkInbox.shared.receive(context.url)
        }
        for activity in connectionOptions.userActivities {
            receive(activity)
        }

        switch self.session.environment.auth {
        case .demo:
            self.session.didSignIn(.demo)
        case .salesforce:
            self.session.startSignIn = { [weak self, weak scene] in
                guard let self, let scene else { return }
                self.signIn(scene)
            }
            AuthHelper.registerBlock(forCurrentUserChangeNotifications: scene) { [weak self] in
                self?.restoreSession(scene)
            }
            AuthHelper.registerBlock(forLogoutNotifications: scene) { [weak self] in
                // Back to the welcome screen after sign-out or an expired session.
                self?.session.didSignOut()
                self?.setSigningIn(false)
            }
            // A cancelled login never calls back: back to the welcome screen's Sign In button.
            NotificationCenter.default.addObserver(
                forName: UserAccountManager.userCancelledAuthentication, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSigningIn(false) }
            }
            restoreSession(scene)
        }
    }

    // MARK: - Deep links (spec §8)

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            DeepLinkInbox.shared.receive(context.url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        receive(userActivity)
    }

    /// Portal universal links (https://portal.accurateadjustmentsga.com/s/...).
    private func receive(_ activity: NSUserActivity) {
        if activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL {
            DeepLinkInbox.shared.receive(url)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        session.lock.willEnterForeground()
        if session.environment.auth == .salesforce {
            restoreSession(scene)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        session.lock.didEnterBackground()
    }

    /// Mask content in the app switcher when the lock is on (spec §10).
    func sceneWillResignActive(_ scene: UIScene) {
        if session.lock.isEnabled {
            session.isShielded = true
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        session.isShielded = false
    }

    private var hasSavedSession: Bool {
        UserAccountManager.shared.currentUserAccount?.credentials.accessToken != nil
    }

    private func setSigningIn(_ value: Bool) {
        isSigningIn = value
        session.isSigningIn = value
    }

    /// A saved session (launch, return to the app): carry on without showing any login.
    /// Without one, the welcome screen stays up until the user taps Sign In.
    private func restoreSession(_ scene: UIScene) {
        guard hasSavedSession, !isSigningIn else { return }
        if case .signedIn = session.state { return }
        session.isRestoringSession = true
        login(scene)
    }

    /// Sign In on the welcome screen: the SDK's login, pointed at the portal (`SFDCOAuthLoginHost`).
    private func signIn(_ scene: UIScene) {
        // A login is already on screen: leave it alone.
        guard !isSigningIn else { return }
        setSigningIn(true)
        login(scene)
    }

    private func login(_ scene: UIScene) {
        AuthHelper.loginIfRequired(scene) { [weak self] in
            guard let self else { return }
            self.setSigningIn(false)
            self.session.isRestoringSession = false
            guard let user = Self.currentUser() else { return }
            self.session.didSignIn(user)
            Task { await PushNotifications.registerIfAllowed(registerWithSalesforce: true) }
        }
    }

    private static func currentUser() -> CurrentUser? {
        guard let identity = UserAccountManager.shared.currentUserAccount?.idData else { return nil }
        return CurrentUser(
            firstName: identity.firstName,
            fullName: identity.displayName ?? identity.email,
            email: identity.email,
            // "STANDARD" for internal users; portal licences have other types.
            isInternal: identity.userType.caseInsensitiveCompare("STANDARD") == .orderedSame,
            instanceURL: UserAccountManager.shared.currentUserAccount?.credentials.instanceUrl
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
