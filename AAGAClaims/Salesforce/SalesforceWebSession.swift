import Foundation
import PortalKit
import SalesforceSDKCore

/// Signed-in links to Salesforce web pages, so the in-app browser doesn't ask for a new login.
nonisolated enum SalesforceWebSession {
    /// A single-use front-door link to `pagePath` (see `SalesforcePageLink`). Falls back to the
    /// plain page URL, which may ask the user to sign in, if Salesforce doesn't give one.
    static func signedInURL(for pagePath: String, instanceURL: URL) async -> URL? {
        let request = RestRequest(method: .POST, serviceHostType: .instance,
                                  path: SalesforcePageLink.singleAccessPath, queryParams: nil)
        // The path is absolute; don't prefix /services/data.
        request.endpoint = ""
        request.setCustomRequestBodyData(SalesforcePageLink.requestBody(for: pagePath),
                                         contentType: "application/x-www-form-urlencoded")
        if let response = try? await RestClient.shared.send(request: request),
           let url = SalesforcePageLink.url(fromResponse: response.asData(), pagePath: pagePath) {
            return url
        }
        return URL(string: pagePath, relativeTo: instanceURL)?.absoluteURL
    }
}

/// Opens a Salesforce page path signed in. Nil in demo mode (there's no Salesforce session).
struct SalesforcePageAction {
    let resolve: (_ pagePath: String) async -> URL?

    func url(for pagePath: String) async -> URL? {
        await resolve(pagePath)
    }
}
