import Foundation
import PortalKit

/// How this build talks to Salesforce. Decided once at launch.
nonisolated struct AppEnvironment: Sendable {
    enum Auth: Sendable {
        /// Real Mobile SDK login against the portal.
        case salesforce
        /// No login: a fixed demo user. Used until the consumer key is configured, and by UI tests.
        case demo
    }

    enum DataSource: String, Sendable {
        /// Bundled fixtures (spec §3: build against the mock until the REST prerequisite is confirmed).
        case mock
        /// Apex REST endpoints under /services/apexrest/portal/v1.
        case live
    }

    let auth: Auth
    let dataSource: DataSource
    /// Artificial mock latency, so skeleton states are visible.
    let mockLatency: Duration

    static let current: AppEnvironment = {
        let defaults = UserDefaults.standard
        let info = Bundle.main.infoDictionary ?? [:]
        let isUITest = defaults.bool(forKey: "UITestDemo")

        // Launch arguments (-PortalDataSource live) override Info.plist.
        let sourceName = defaults.string(forKey: "PortalDataSource") ?? info["PortalDataSource"] as? String
        let dataSource = DataSource(rawValue: sourceName ?? "") ?? .mock

        let auth: Auth = isUITest || !BootConfigCheck.hasConsumerKey ? .demo : .salesforce

        return AppEnvironment(
            // Live data needs a real session.
            auth: dataSource == .live ? .salesforce : auth,
            dataSource: dataSource,
            mockLatency: isUITest ? .zero : .milliseconds(500)
        )
    }()
}

nonisolated enum BootConfigCheck {
    static let placeholder = "REPLACE_WITH_CONSUMER_KEY"

    static var hasConsumerKey: Bool {
        guard let url = Bundle.main.url(forResource: "bootconfig", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key = dict["remoteAccessConsumerKey"] as? String else {
            return false
        }
        return !key.isEmpty && key != placeholder
    }
}
