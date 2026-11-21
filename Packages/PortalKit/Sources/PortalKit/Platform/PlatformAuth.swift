import Foundation

/// Where the new ProClaimer platform lives (replaces the Salesforce org). Sign-in is Supabase Auth; the data API
/// is the company's own site, e.g. https://aaga.myproclaimer.com/api/portal/v1.
public struct PlatformConfig: Sendable, Equatable {
    /// The Supabase project, e.g. https://abcd.supabase.co
    public let supabaseURL: URL
    /// The project's publishable key. It's public by design: it only lets the app ask to sign in.
    public let publishableKey: String
    /// The company's site, e.g. https://aaga.myproclaimer.com (no path).
    public let apiBaseURL: URL

    public static let apiPath = "/api/portal/v1"

    public init(supabaseURL: URL, publishableKey: String, apiBaseURL: URL) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.apiBaseURL = apiBaseURL
    }
}

/// A signed-in session: the short-lived access token the API checks, and the refresh token that gets the next one.
public struct PlatformSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var email: String
    /// The signed-in person's company site, learned from `GET /me`. Nil: use the default address.
    public var apiBase: URL?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, email: String, apiBase: URL? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
        self.apiBase = apiBase
    }

    /// Still good for at least `margin` seconds, so a request started now won't expire in flight.
    public func isFresh(at now: Date, margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }
}

/// Where the session is kept between launches (the keychain in the app).
public protocol PlatformSessionStore: Sendable {
    func load() -> PlatformSession?
    func save(_ session: PlatformSession)
    func clear()
}

/// Sends one HTTP request. `URLSession` does it in the app; tests use a script.
public protocol PlatformHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: PlatformHTTP {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum PlatformAuthError: Error, Equatable, Sendable {
    /// Wrong email or password.
    case invalidCredentials
    /// No session, or the refresh token no longer works: sign in again.
    case notSignedIn
    /// The server refused with a message worth showing.
    case rejected(String)
    /// The server answered with an error status.
    case server(Int)
}

/// A company on the platform: its own address and look. `GET /company?email=` and `GET /me` describe it.
public struct PlatformCompany: Codable, Equatable, Sendable {
    public let name: String
    public let subdomain: String
    /// The company's site, e.g. https://aaga.myproclaimer.com (its own domain if it has one).
    public let apiBase: URL
    /// "#014486", when the company has set one.
    public let brandColor: String?
    public let logoUrl: URL?
    public let markText: String?

    public init(name: String, subdomain: String, apiBase: URL, brandColor: String? = nil, logoUrl: URL? = nil, markText: String? = nil) {
        self.name = name
        self.subdomain = subdomain
        self.apiBase = apiBase
        self.brandColor = brandColor
        self.logoUrl = logoUrl
        self.markText = markText
    }
}

/// `GET /me`: who's signed in.
public struct PlatformProfile: Codable, Equatable, Sendable {
    public let firstName: String?
    public let fullName: String
    public let email: String
    /// On the company's team (staff), rather than a homeowner.
    public let isInternal: Bool
    public let company: PlatformCompany?

    public init(firstName: String?, fullName: String, email: String, isInternal: Bool, company: PlatformCompany?) {
        self.firstName = firstName
        self.fullName = fullName
        self.email = email
        self.isInternal = isInternal
        self.company = company
    }
}

/// Signs in with Supabase Auth and keeps the session fresh. One refresh at a time, however many requests ask at once.
public actor PlatformAuth {
    private let config: PlatformConfig
    private let http: PlatformHTTP
    private let store: PlatformSessionStore
    private let now: @Sendable () -> Date
    private var session: PlatformSession?
    private var refreshing: Task<PlatformSession, Error>?

    public init(config: PlatformConfig, http: PlatformHTTP = URLSession.shared, store: PlatformSessionStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.http = http
        self.store = store
        self.now = now
    }

    public var isSignedIn: Bool { session != nil }

    /// Where API requests go: the company's own site once known, otherwise the default address.
    public func apiBase() -> URL { session?.apiBase ?? config.apiBaseURL }

    /// The company's site couldn't be reached (not set up yet, or a bad address): go back to the default address.
    public func fallBackToDefaultBase() {
        guard var current = session, current.apiBase != nil else { return }
        current.apiBase = nil
        session = current
        store.save(current)
    }

    /// Which company (or companies) an email address belongs to, for "Signing in to …" while the email is typed.
    /// Quiet on any failure: it's a nicety, and sign-in doesn't depend on it.
    public func discoverCompanies(email: String) async -> [PlatformCompany] {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard address.contains("@"), var parts = URLComponents(url: config.apiBaseURL.appending(path: PlatformConfig.apiPath + "/company"), resolvingAgainstBaseURL: false) else { return [] }
        parts.queryItems = [URLQueryItem(name: "email", value: address)]
        guard let url = parts.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        struct Found: Decodable { let companies: [PlatformCompany] }
        guard let (data, response) = try? await http.send(request), response.statusCode == 200,
              let found = try? JSONDecoder().decode(Found.self, from: data) else { return [] }
        return found.companies
    }

    private func adopt(_ company: PlatformCompany?) {
        guard var current = session, let base = company?.apiBase, current.apiBase != base else { return }
        current.apiBase = base
        session = current
        store.save(current)
    }

    /// Picks up the session saved by an earlier launch.
    @discardableResult
    public func restore() -> PlatformSession? {
        session = store.load()
        return session
    }

    /// Signs in. With a `company` (the one the person chose, for someone on several), that company is made the active one on the
    /// server and the token is renewed: the token carries the company it was issued for, which is the one used last on the
    /// website, so without this every company would open the same one.
    public func signIn(email: String, password: String, company: PlatformCompany? = nil) async throws -> PlatformSession {
        let (data, response) = try await http.send(authRequest("token", query: "grant_type=password", body: ["email": email.trimmingCharacters(in: .whitespaces), "password": password]))
        guard response.statusCode == 200 else { throw Self.failure(response.statusCode, data) }
        var signedIn = try tokens(from: data, email: email.trimmingCharacters(in: .whitespaces))
        session = signedIn
        store.save(signedIn)
        if let company {
            do {
                try await choose(company, token: signedIn.accessToken)
                signedIn = try await renew(signedIn)
                signedIn.apiBase = company.apiBase
                session = signedIn
                store.save(signedIn)
            } catch let error as PlatformAuthError {
                // Not on that company's team: don't leave a session open for a company they didn't get.
                if error == .notSignedIn { signOutLocally(); throw error }
                if case .rejected = error { signOutLocally(); throw error }
                throw error
            }
        }
        return signedIn
    }

    /// `POST /session/company` on the default address (which serves every company). An older server without it answers 404: carry on.
    private func choose(_ company: PlatformCompany, token: String) async throws {
        var request = URLRequest(url: config.apiBaseURL.appending(path: PlatformConfig.apiPath + "/session/company"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["subdomain": company.subdomain])
        let (data, response) = try await http.send(request)
        switch response.statusCode {
        case 200, 404: return
        case 403: throw PlatformAuthError.rejected("You're not on the team at \(company.name).")
        case 401: throw PlatformAuthError.notSignedIn
        default: throw Self.failure(response.statusCode, data)
        }
    }

    /// A token that's good for the next minute: the saved one, or a fresh one if it's about to run out.
    public func validAccessToken() async throws -> String {
        guard let current = session else { throw PlatformAuthError.notSignedIn }
        if current.isFresh(at: now()) { return current.accessToken }
        return try await refresh().accessToken
    }

    /// A new token whatever the clock says (after the server said 401).
    public func refreshNow() async throws -> String {
        guard session != nil else { throw PlatformAuthError.notSignedIn }
        return try await refresh().accessToken
    }

    private func refresh() async throws -> PlatformSession {
        if let running = refreshing { return try await running.value }
        guard let current = session else { throw PlatformAuthError.notSignedIn }
        let task = Task { try await self.renew(current) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func renew(_ current: PlatformSession) async throws -> PlatformSession {
        let (data, response) = try await http.send(authRequest("token", query: "grant_type=refresh_token", body: ["refresh_token": current.refreshToken]))
        guard response.statusCode == 200 else {
            // The refresh token was refused: this sign-in is over. Anything else (an outage) keeps it for next time.
            if response.statusCode == 400 || response.statusCode == 401 { signOutLocally(); throw PlatformAuthError.notSignedIn }
            throw PlatformAuthError.server(response.statusCode)
        }
        let renewed = try tokens(from: data, email: current.email)
        session = renewed
        store.save(renewed)
        return renewed
    }

    /// Ends the session here and on the server (the server part is best effort).
    public func signOut() async {
        if let token = session?.accessToken {
            var request = authRequest("logout", query: nil, body: [:])
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await http.send(request)
        }
        signOutLocally()
    }

    private func signOutLocally() {
        session = nil
        store.clear()
    }

    /// Emails a reset link. It answers the same for an unknown address, so it can't be used to look people up.
    public func requestPasswordReset(email: String) async throws {
        let (data, response) = try await http.send(authRequest("recover", query: nil, body: ["email": email.trimmingCharacters(in: .whitespaces)]))
        guard response.statusCode == 200 else { throw Self.failure(response.statusCode, data) }
    }

    /// Who's signed in, from the platform's `GET /me`.
    public func profile() async throws -> PlatformProfile {
        let token = try await validAccessToken()
        let (data, response) = try await meRequest(token: token, base: apiBase())
        guard response.statusCode == 200, let profile = try? JSONDecoder().decode(PlatformProfile.self, from: data) else {
            throw response.statusCode == 401 ? PlatformAuthError.notSignedIn : PlatformAuthError.server(response.statusCode)
        }
        adopt(profile.company)
        return profile
    }

    /// Asks the company's site first; if it can't be reached, the default address (which serves every company).
    private func meRequest(token: String, base: URL) async throws -> (Data, HTTPURLResponse) {
        func ask(_ base: URL) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: base.appending(path: PlatformConfig.apiPath + "/me"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try await http.send(request)
        }
        do { return try await ask(base) } catch let error as URLError where base != config.apiBaseURL && error.isUnreachableHost {
            fallBackToDefaultBase()
            return try await ask(config.apiBaseURL)
        }
    }

    // MARK: - Requests

    private func authRequest(_ endpoint: String, query: String?, body: [String: String]) -> URLRequest {
        var url = config.supabaseURL.appending(path: "auth/v1/\(endpoint)")
        if let query, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.query = query
            url = parts.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
    }

    private func tokens(from data: Data, email: String) throws -> PlatformSession {
        guard let t = try? JSONDecoder().decode(Tokens.self, from: data) else { throw PlatformAuthError.server(200) }
        return PlatformSession(accessToken: t.access_token, refreshToken: t.refresh_token, expiresAt: now().addingTimeInterval(t.expires_in), email: email)
    }

    private struct ErrorBody: Decodable {
        let error_code: String?
        let msg: String?
        let error_description: String?
    }

    private static func failure(_ status: Int, _ data: Data) -> PlatformAuthError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        if body?.error_code == "invalid_credentials" { return .invalidCredentials }
        if status == 400 || status == 422 || status == 429, let message = body?.msg ?? body?.error_description { return .rejected(message) }
        return .server(status)
    }
}

/// Sends the app's API requests to the platform with the person's access token. A token that's about to expire is renewed
/// first; a 401 renews it and tries once more. The API's paths and JSON are the Salesforce API's, so `HTTPPortalAPI` is unchanged.
public struct PlatformTransport: PortalTransport {
    private let config: PlatformConfig
    private let auth: PlatformAuth
    private let http: PlatformHTTP

    public init(config: PlatformConfig, auth: PlatformAuth, http: PlatformHTTP = URLSession.shared) {
        self.config = config
        self.auth = auth
        self.http = http
    }

    private static let notFound = TransportResponse(statusCode: 404, body: Data(#"{"error":"not_found"}"#.utf8))
    private static let unauthorized = TransportResponse(statusCode: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))

    public func send(_ request: TransportRequest) async throws -> TransportResponse {
        // Paths from the Salesforce server root (its standard data API, the documents service) don't exist here.
        if request.isAbsolutePath { return Self.notFound }
        let token: String
        do { token = try await auth.validAccessToken() } catch PlatformAuthError.notSignedIn { return Self.unauthorized }

        var response = try await perform(request, token: token)
        if response.statusCode == 401 {
            do { response = try await perform(request, token: try await auth.refreshNow()) } catch PlatformAuthError.notSignedIn { return Self.unauthorized }
        }
        return response
    }

    private func perform(_ request: TransportRequest, token: String) async throws -> TransportResponse {
        let base = await auth.apiBase()
        do { return try await perform(request, token: token, base: base) } catch let error as URLError where base != config.apiBaseURL && error.isUnreachableHost {
            // The company's own site isn't reachable (yet): use the default address, which serves every company.
            await auth.fallBackToDefaultBase()
            return try await perform(request, token: token, base: config.apiBaseURL)
        }
    }

    private func perform(_ request: TransportRequest, token: String, base: URL) async throws -> TransportResponse {
        var parts = URLComponents(url: base.appending(path: PlatformConfig.apiPath + request.path), resolvingAgainstBaseURL: false)
        if !request.queryItems.isEmpty { parts?.queryItems = request.queryItems }
        guard let url = parts?.url else { throw URLError(.badURL) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue(request.contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.send(urlRequest)
        return TransportResponse(statusCode: response.statusCode, body: data)
    }
}

extension URLError {
    /// The server's name or address can't be reached or trusted (not the same as being offline).
    var isUnreachableHost: Bool {
        [.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed,
         .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid].contains(code)
    }
}
