import CryptoKit
import Foundation
import SalesforceSDKCore
import UIKit

/// Salesforce Headless Login (Authorization Code and Credentials flow) for the app's own sign-in
/// screen. The SDK's native login builds the same two requests, but its network layer failed against
/// the portal (it reported every failure as a wrong password), so the app makes them itself and
/// hands the token response to the SDK, which then owns the session as usual.
///
/// 1. POST {portal}/services/oauth2/authorize with `Authorization: Basic base64(username:password)`
///    and `Auth-Request-Type: Named-User`; Salesforce redirects to the echo URL, which returns
///    `{ code, sfdc_community_url }`.
/// 2. POST {sfdc_community_url}/services/oauth2/token with the code and the PKCE verifier.
enum HeadlessSignIn {
    enum Failure: Error, Equatable {
        /// Wrong username or password.
        case invalidCredentials
        /// The user isn't allowed to use the app (not in its permission sets).
        case notApproved
        /// No connection, or Salesforce couldn't be reached.
        case network
        /// Anything else Salesforce refused.
        case other(String)
    }

    @MainActor
    static func signIn(username: String, password: String, clientId: String, scene: UIScene?) async -> Failure? {
        let verifier = codeVerifier()
        let challenge = codeChallenge(for: verifier)
        // Credentials are sent once, over TLS, in the Authorization header; never logged.
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()

        var authorize = URLRequest(url: URL(string: NativeSignIn.portalURL + "/services/oauth2/authorize")!)
        authorize.httpMethod = "POST"
        authorize.setValue("Named-User", forHTTPHeaderField: "Auth-Request-Type")
        authorize.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        authorize.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        authorize.httpBody = form([
            "response_type": "code_credentials",
            "client_id": clientId,
            "redirect_uri": NativeSignIn.callbackURL,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        ])

        // An ephemeral session: no cookies or cache from the sign-in are kept.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        struct EchoResponse: Decodable { let code: String; let sfdc_community_url: String? }
        let echo: EchoResponse
        do {
            let (data, response) = try await session.data(for: authorize)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let decoded = try? JSONDecoder().decode(EchoResponse.self, from: data) else {
                return failure(from: data)
            }
            echo = decoded
        } catch {
            return .network
        }

        var token = URLRequest(url: URL(string: (echo.sfdc_community_url ?? NativeSignIn.portalURL) + "/services/oauth2/token")!)
        token.httpMethod = "POST"
        token.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        token.httpBody = form([
            "grant_type": "authorization_code",
            "code": echo.code,
            "client_id": clientId,
            "redirect_uri": NativeSignIn.callbackURL,
            "code_verifier": verifier,
        ])
        do {
            let (data, response) = try await session.data(for: token)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["access_token"] != nil else {
                return failure(from: data)
            }
            // The SDK stores the session (keychain), loads the user and finishes the login flow.
            UserAccountManager.shared.createNativeUserAccount(with: data, scene: scene)
            return nil
        } catch {
            return .network
        }
    }

    private static func failure(from data: Data) -> Failure {
        struct OAuthError: Decodable { let error: String?; let error_description: String? }
        let error = try? JSONDecoder().decode(OAuthError.self, from: data)
        switch (error?.error, error?.error_description) {
        case ("invalid_grant", _): return .invalidCredentials
        case ("invalid_app_access", _): return .notApproved
        case (let code?, let description): return .other(description ?? code)
        default: return .other("unexpected response")
        }
    }

    /// application/x-www-form-urlencoded, with every value escaped (codes can contain + and /).
    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
