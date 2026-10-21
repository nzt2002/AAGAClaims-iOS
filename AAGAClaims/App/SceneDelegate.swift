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
            if BootConfigCheck.usesNativeLogin, let key = BootConfigCheck.consumerKey {
                // The SDK shows our sign-in screen instead of the web page whenever sign-in is needed.
                self.session.usesNativeLogin = true
                SalesforceManager.shared.useNativeLogin(
                    withConsumerKey: key,
                    callbackUrl: NativeSignIn.callbackURL,
                    communityUrl: NativeSignIn.portalURL,
                    nativeLoginViewController: NativeSignIn.makeViewController(),
                    scene: scene
                )
            }
            self.session.startSignIn = { [weak self, weak scene] in
                guard let self, let scene else { return }
                self.signIn(scene)
            }
            AuthHelper.registerBlock(forCurrentUserChangeNotifications: scene) { [weak self] in
                // Native sign-in ends here (the SDK doesn't call loginIfRequired's completion for it):
                // clear the in-progress flag so the new session is picked up straight away.
                self?.setSigningIn(false)
                self?.restoreSession(scene)
            }
            AuthHelper.registerBlock(forLogoutNotifications: scene) { [weak self] in
                // Back to the welcome screen (or native sign-in) after sign-out or an expired session.
                self?.session.didSignOut()
                self?.setSigningIn(false)
                self?.showNativeSignInIfNeeded(scene)
            }
            // A cancelled login never calls back: back to the welcome screen's Sign In button, or
            // (native) back to the app's sign-in screen, e.g. after closing the staff web sign-in.
            NotificationCenter.default.addObserver(
                forName: UserAccountManager.userCancelledAuthentication, object: nil, queue: .main
            ) { [weak self, weak scene] _ in
                MainActor.assumeIsolated {
                    self?.setSigningIn(false)
                    if let scene { self?.showNativeSignInIfNeeded(scene) }
                }
            }
            // The app's sign-in screen succeeded: don't rely on the SDK calling back (it may
            // announce the new user before the session or profile is saved).
            NotificationCenter.default.addObserver(
                forName: NativeSignIn.didSucceed, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setSigningIn(false)
                    self?.finishSignIn()
                }
            }
            restoreSession(scene)
            showNativeSignInIfNeeded(scene)
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

    /// Native login: the app's sign-in screen is the welcome screen, so show it straight away.
    private func showNativeSignInIfNeeded(_ scene: UIScene) {
        guard session.usesNativeLogin, !hasSavedSession else { return }
        signIn(scene)
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
            self.finishSignIn()
        }
    }

    private var finishing: Task<Void, Never>?

    /// Shows the app once the session and the user's profile are saved. On a phone the profile
    /// can arrive a moment after sign-in reports success; giving up then left the app on the
    /// splash until it was reopened.
    private func finishSignIn() {
        if case .signedIn = session.state { return }
        guard finishing == nil else { return }
        finishing = Task { @MainActor [weak self] in
            defer { self?.finishing = nil }
            var user: CurrentUser?
            // Up to about 10 seconds for the SDK to save the session and profile.
            for _ in 0..<40 {
                if let found = Self.currentUser() { user = found; break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if user == nil { user = await Self.fetchCurrentUser() }
            guard let self else { return }
            self.session.isRestoringSession = false
            guard let user else {
                // No profile at all: sign out so the sign-in screen comes back instead of a stuck splash.
                SalesforceSession.signOut()
                return
            }
            if case .signedIn = self.session.state { return }
            self.session.didSignIn(user)
            Task { await PushNotifications.registerIfAllowed(registerWithSalesforce: true) }
        }
    }

    private static func currentUser() -> CurrentUser? {
        guard let account = UserAccountManager.shared.currentUserAccount,
              account.credentials.accessToken != nil,
              let identity = UserAccountManager.shared.currentUserAccount?.idData,
              !identity.email.isEmpty else { return nil }
        return CurrentUser(
            firstName: identity.firstName,
            fullName: identity.displayName ?? identity.email,
            email: identity.email,
            // "STANDARD" for internal users; portal licences have other types.
            isInternal: identity.userType.caseInsensitiveCompare("STANDARD") == .orderedSame,
            instanceURL: account.credentials.instanceUrl
        )
    }

    /// The profile straight from Salesforce's identity URL, when the SDK hasn't saved one.
    private static func fetchCurrentUser() async -> CurrentUser? {
        guard let credentials = UserAccountManager.shared.currentUserAccount?.credentials,
              let token = credentials.accessToken, let url = credentials.identityUrl else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct Identity: Decodable {
            let first_name: String?
            let display_name: String?
            let email: String?
            let user_type: String?
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let identity = try? JSONDecoder().decode(Identity.self, from: data),
              let email = identity.email else { return nil }
        return CurrentUser(
            firstName: identity.first_name,
            fullName: identity.display_name ?? email,
            email: email,
            isInternal: identity.user_type?.caseInsensitiveCompare("STANDARD") == .orderedSame,
            instanceURL: credentials.instanceUrl
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
