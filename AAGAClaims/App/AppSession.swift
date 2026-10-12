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

    init(environment: AppEnvironment) {
        self.environment = environment
        switch environment.dataSource {
        case .mock: api = MockPortalAPI.standard(latency: environment.mockLatency)
        case .live: api = HTTPPortalAPI(transport: SalesforceTransport())
        }
    }

    var isDemo: Bool { environment.auth == .demo }

    func didSignIn(_ user: CurrentUser) {
        state = .signedIn(user)
    }

    func didSignOut() {
        state = .signingIn
    }
}
