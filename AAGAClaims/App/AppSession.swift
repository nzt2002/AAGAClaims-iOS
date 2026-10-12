import Foundation
import Observation
import PortalKit

/// The signed-in user, from the SDK's identity data (there's no `/me` endpoint).
struct CurrentUser: Equatable {
    let firstName: String?
    let fullName: String
    let email: String

    static let demo = CurrentUser(firstName: "Alex", fullName: "Alex Smith", email: "alex.smith@example.com")
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
    /// Covers the UI while the app is inactive, so the app switcher snapshot shows no data.
    var isShielded = false

    init(environment: AppEnvironment) {
        self.environment = environment
        let base: PortalAPI = switch environment.dataSource {
        case .mock: MockPortalAPI.standard(latency: environment.mockLatency)
        case .live: HTTPPortalAPI(transport: SalesforceTransport())
        }
        let offline = self.offline
        cachingAPI = CachingPortalAPI(base: base, cache: FileResponseCache.standard()) { savedAt in
            await offline.servedFromCache(savedAt: savedAt)
        }
        api = cachingAPI

        let cachingAPI = self.cachingAPI
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
        // Sign-out clears cached data (spec §6.11).
        let cachingAPI = self.cachingAPI
        Task { await cachingAPI.clearCache() }
        state = .signingIn
    }
}
