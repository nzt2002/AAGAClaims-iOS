import Foundation

/// Opening Salesforce web pages (DocMerge documents) already signed in.
///
/// The app's OAuth session isn't shared with the in-app browser, so a plain page URL asks the
/// user to log in again. Instead the app asks Salesforce for a single-use front-door link
/// (`POST /services/oauth2/singleaccess`) and opens that, which signs the browser in once and goes
/// to the page. The access token itself never goes in a URL.
public enum SalesforcePageLink {
    /// `/services/oauth2/singleaccess`, called with the app's OAuth token.
    public static let singleAccessPath = "/services/oauth2/singleaccess"

    /// The request body: where the front door should send the browser.
    public static func requestBody(for pagePath: String) -> Data {
        Data("redirect_uri=\(pagePath.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? pagePath)".utf8)
    }

    /// The URL to open, from the single-access response. Adds `retURL` (front door's own redirect
    /// parameter) when the response doesn't already carry the page. Nil if the response has no link.
    public static func url(fromResponse data: Data, pagePath: String) -> URL? {
        struct Body: Decodable { let frontdoor_uri: String? }
        guard let link = (try? JSONDecoder().decode(Body.self, from: data))?.frontdoor_uri,
              var components = URLComponents(string: link) else { return nil }
        var items = components.queryItems ?? []
        let hasRedirect = items.contains { ["retURL", "startURL"].contains($0.name) }
        if !hasRedirect {
            items.append(URLQueryItem(name: "retURL", value: pagePath))
            components.queryItems = items
        }
        return components.url
    }

    /// A page path with its query, e.g. "/apex/hic_docmerge__Composer?id=…".
    public static func path(_ page: String, query: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = page
        components.queryItems = query
        return components.url?.absoluteString ?? page
    }

    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
