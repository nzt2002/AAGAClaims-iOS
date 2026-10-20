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
    /// A saved session is being restored: keep the splash up rather than flash the welcome screen.
    var isRestoringSession = false

    init(environment: AppEnvironment) {
        self.environment = environment
        let base: PortalAPI = switch environment.dataSource {
        case .mock:
            // -MockFailure YES makes every call fail, to check error states (spec §7).
            UserDefaults.standard.bool(forKey: "MockFailure")
                ? MockPortalAPI(fixtures: .empty, latency: environment.mockLatency, failure: .server(status: 500))
                : MockPortalAPI.standard(latency: environment.mockLatency)
        case .live: HTTPPortalAPI(transport: SalesforceTransport())
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
        connectivity.start { online in
            offline.setOffline(!online)
            Task { await cachingAPI.setOnline(online) }
        }
    }

    var isDemo: Bool { environment.auth == .demo }

    func didSignIn(_ user: CurrentUser) {
        state = .signedIn(user)
    }

    func didSignOut() {
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
