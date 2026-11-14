import Foundation
import UIKit
import Observation
import PortalKit

/// The signed-in user, from the SDK's identity data (there's no `/me` endpoint).
struct CurrentUser: Equatable {
    let firstName: String?
    let fullName: String
    let email: String
    /// Internal staff (Salesforce user type Standard) rather than a portal user.
    var isInternal = false
    /// The org's web address (for pages only Salesforce can show, e.g. document generation). Nil in demo mode.
    var instanceURL: URL? = nil

    // Demo mode shows staff features (Chatter, New Task), like the mock data.
    static let demo = CurrentUser(firstName: "Alex", fullName: "Alex Smith", email: "alex.smith@example.com", isInternal: true)
}

@Observable
final class AppSession {
    enum State: Equatable {
        case signingIn
        case signedIn(CurrentUser)
    }

    private(set) var state: State = .signingIn
    let environment: AppEnvironment
    /// Signs in to the platform and keeps the sign-in fresh. Nil unless this build uses the platform.
    let platform: PlatformAuth?
    let api: PortalAPI
    let lock = AppLock()
    let offline = OfflineState()
    let connectivity = ConnectivityMonitor()
    /// The offline cache in front of the API (spec §8).
    private let cachingAPI: CachingPortalAPI
    /// App-wide, so uploads continue when the user leaves the screen (spec §6.10).
    let uploads: UploadQueue
    /// Covers the UI while the app is inactive, so the app switcher snapshot shows no data.
    var isShielded = false
    /// Opens Salesforce's sign-in (set by the scene). Nil in demo mode.
    var startSignIn: (() -> Void)?
    /// Salesforce's sign-in is on screen.
    var isSigningIn = false
    /// The app's own sign-in screen (native login) is used instead of the web page.
    var usesNativeLogin = false
    /// A saved session is being restored: keep the splash up rather than flash the welcome screen.
    var isRestoringSession = false
    /// Sign-in steps reached so far (no personal data), shown if sign-in seems stuck.
    private(set) var signInSteps: [String] = []
    /// Restarts a sign-in that seems stuck (set by the scene).
    var retrySignIn: (() -> Void)?

    func noteSignInStep(_ step: String) {
        signInSteps.append(step)
        if signInSteps.count > 12 { signInSteps.removeFirst() }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        let platform = environment.platform.map { PlatformAuth(config: $0, store: KeychainPlatformSessionStore()) }
        self.platform = platform
        let base: PortalAPI = switch environment.dataSource {
        case .mock:
            // -MockFailure YES makes every call fail, to check error states (spec §7).
            UserDefaults.standard.bool(forKey: "MockFailure")
                ? MockPortalAPI(fixtures: .empty, latency: environment.mockLatency, failure: .server(status: 500))
                : MockPortalAPI.standard(latency: environment.mockLatency)
        case .live:
            if let config = environment.platform, let platform {
                HTTPPortalAPI(transport: PlatformTransport(config: config, auth: platform))
            } else {
                HTTPPortalAPI(transport: SalesforceTransport())
            }
        }
        let offline = self.offline
        cachingAPI = CachingPortalAPI(base: base, cache: FileResponseCache.standard()) { savedAt in
            await offline.servedFromCache(savedAt: savedAt)
        }
        api = cachingAPI
        uploads = UploadQueue(api: cachingAPI)
        uploads.keepAlive = {
            // Finish the current upload if the app goes to the background.
            let task = UIApplication.shared.beginBackgroundTask(withName: "Uploads")
            return { UIApplication.shared.endBackgroundTask(task) }
        }

        let cachingAPI = self.cachingAPI
        if environment.auth == .salesforce {
            // 401: the session has expired. Signing out shows the SDK login again (spec §5).
            Task {
                await cachingAPI.setSessionExpiredHandler {
                    await MainActor.run { SalesforceSession.signOut() }
                }
            }
        }
        if environment.auth == .platform {
            // 401 after a renewal: the sign-in is over. Back to the sign-in screen.
            Task {
                await cachingAPI.setSessionExpiredHandler {
                    await MainActor.run { NotificationCenter.default.post(name: AppSession.platformSessionExpired, object: nil) }
                }
            }
            NotificationCenter.default.addObserver(forName: Self.platformSessionExpired, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.signOut() }
            }
        }
        connectivity.start { online in
            offline.setOffline(!online)
            Task { await cachingAPI.setOnline(online) }
        }
    }

    var isDemo: Bool { environment.auth == .demo }

    /// Push notifications are registered through Salesforce; the platform doesn't send them yet.
    var registersPush: Bool { environment.auth == .salesforce }

    static let platformSessionExpired = Notification.Name("PlatformSessionExpired")

    /// Signs out whichever way this build signs in.
    func signOut() {
        switch environment.auth {
        case .demo: didSignOut()
        case .salesforce: SalesforceSession.signOut()
        case .platform:
            Task {
                await platform?.signOut()
                PlatformProfileCache.clear()
                didSignOut()
            }
        }
    }

    // MARK: - Platform sign-in

    /// Email and password: signs in, loads who it is, and opens the app.
    func signInPlatform(email: String, password: String) async throws {
        guard let platform else { return }
        noteSignInStep("signing in")
        _ = try await platform.signIn(email: email, password: password)
        do {
            let profile = try await platform.profile()
            PlatformProfileCache.save(profile)
            lock.didSignIn()
            didSignIn(CurrentUser(profile))
        } catch {
            // Signed in but couldn't be identified: don't leave a half-open session.
            await platform.signOut()
            throw error
        }
    }

    func requestPasswordReset(email: String) async throws {
        try await platform?.requestPasswordReset(email: email)
    }

    /// Picks up the sign-in from the last launch. Offline, the saved profile opens the app (the cache holds its data).
    func restorePlatformSession() async {
        guard let platform, await platform.restore() != nil else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }
        do {
            let profile = try await platform.profile()
            PlatformProfileCache.save(profile)
            didSignIn(CurrentUser(profile))
        } catch PlatformAuthError.notSignedIn {
            await platform.signOut()
        } catch {
            if let cached = PlatformProfileCache.load() { didSignIn(CurrentUser(cached)) }
        }
    }

    func didSignIn(_ user: CurrentUser) {
        signInSteps = []
        state = .signedIn(user)
    }

    func didSignOut() {
        CallManager.shared.signOut()
        lock.reset()
        // Searches can contain customer names; don't keep them across accounts.
        UserDefaultsRecentSearchStore.clear()
        // Unsent posts and replies belong to this account.
        Outbox.shared.clear()
        // Sign-out clears cached data (spec §6.11).
        let cachingAPI = self.cachingAPI
        Task { await cachingAPI.clearCache() }
        state = .signingIn
    }
}
