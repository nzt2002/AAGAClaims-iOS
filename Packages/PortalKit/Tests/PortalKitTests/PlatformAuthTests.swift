import Foundation
import Testing
@testable import PortalKit

/// Replies to requests with whatever the script says, and keeps them.
private actor ScriptedHTTP: PlatformHTTP {
    typealias Reply = (status: Int, body: String)
    private(set) var requests: [URLRequest] = []
    private var handler: @Sendable (URLRequest, Int) -> Reply
    private var delay: Duration

    init(delay: Duration = .zero, _ handler: @escaping @Sendable (URLRequest, Int) -> Reply) {
        self.handler = handler
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let n = requests.count
        let reply = handler(request, n)
        if delay > .zero { try await Task.sleep(for: delay) }
        if reply.status == -1 { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }

    func count(path suffix: String) -> Int { requests.filter { $0.url?.path.hasSuffix(suffix) == true }.count }
}

private final class MemoryStore: PlatformSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: PlatformSession?
    init(_ session: PlatformSession? = nil) { saved = session }
    func load() -> PlatformSession? { lock.withLock { saved } }
    func save(_ session: PlatformSession) { lock.withLock { saved = session } }
    func clear() { lock.withLock { saved = nil } }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func jsonBody(_ request: URLRequest) -> [String: String] {
    guard let data = request.httpBody, let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
    return object
}

private let config = PlatformConfig(supabaseURL: URL(string: "https://proj.supabase.co")!, publishableKey: "sb_publishable_x", apiBaseURL: URL(string: "https://aaga.myproclaimer.com")!)

private func tokenBody(access: String = "access-1", refresh: String = "refresh-1", expiresIn: Int = 3600) -> String {
    #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn),"token_type":"bearer","user":{"id":"u1"}}"#
}

private func session(access: String = "access-1", refresh: String = "refresh-1", expiresAt: Date) -> PlatformSession {
    PlatformSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, email: "amy@a.test")
}

@Suite("Platform sign-in")
struct PlatformAuthTests {
    @Test("Signing in posts the email and password and keeps the session")
    func signIn() async throws {
        let http = ScriptedHTTP { _, _ in (200, tokenBody()) }
        let store = MemoryStore()
        let clock = Clock()
        let auth = PlatformAuth(config: config, http: http, store: store, now: { clock.now })

        let s = try await auth.signIn(email: " amy@a.test ", password: "secret")

        #expect(s.accessToken == "access-1" && s.refreshToken == "refresh-1" && s.email == "amy@a.test")
        #expect(s.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(store.load() == s)
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://proj.supabase.co/auth/v1/token?grant_type=password")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_x")
        let body = jsonBody(request)
        #expect(body == ["email": "amy@a.test", "password": "secret"])
    }

    @Test("A wrong password is reported, and nothing is kept")
    func wrongPassword() async throws {
        let http = ScriptedHTTP { _, _ in (400, #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#) }
        let store = MemoryStore()
        let auth = PlatformAuth(config: config, http: http, store: store)
        await #expect(throws: PlatformAuthError.invalidCredentials) { try await auth.signIn(email: "amy@a.test", password: "nope") }
        #expect(store.load() == nil)
        #expect(await !auth.isSignedIn)
    }

    @Test("Other refusals carry their message, and outages are server errors")
    func otherFailures() async throws {
        let limited = PlatformAuth(config: config, http: ScriptedHTTP { _, _ in (429, #"{"msg":"Too many attempts"}"#) }, store: MemoryStore())
        await #expect(throws: PlatformAuthError.rejected("Too many attempts")) { try await limited.signIn(email: "a@a.test", password: "x") }
        let down = PlatformAuth(config: config, http: ScriptedHTTP { _, _ in (503, "") }, store: MemoryStore())
        await #expect(throws: PlatformAuthError.server(503)) { try await down.signIn(email: "a@a.test", password: "x") }
    }

    @Test("A saved session is picked up on the next launch")
    func restore() async throws {
        let saved = session(expiresAt: Date().addingTimeInterval(3000))
        let auth = PlatformAuth(config: config, http: ScriptedHTTP { _, _ in (500, "") }, store: MemoryStore(saved))
        #expect(await !auth.isSignedIn)
        #expect(await auth.restore() == saved)
        #expect(await auth.isSignedIn)
    }

    @Test("A fresh token is used as it is; one about to run out is renewed first")
    func renewsWhenNeeded() async throws {
        let clock = Clock()
        let http = ScriptedHTTP { _, _ in (200, tokenBody(access: "access-2", refresh: "refresh-2")) }
        let store = MemoryStore(session(expiresAt: clock.now.addingTimeInterval(600)))
        let auth = PlatformAuth(config: config, http: http, store: store, now: { clock.now })
        await auth.restore()

        #expect(try await auth.validAccessToken() == "access-1")
        #expect(await http.requests.isEmpty)

        clock.advance(560) // 40 seconds left: under the one-minute margin
        #expect(try await auth.validAccessToken() == "access-2")
        #expect(await http.count(path: "/token") == 1)
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://proj.supabase.co/auth/v1/token?grant_type=refresh_token")
        let body = jsonBody(request)
        #expect(body == ["refresh_token": "refresh-1"])
        #expect(store.load()?.refreshToken == "refresh-2") // refresh tokens are single-use: the new one is kept
    }

    @Test("Many requests at once renew the token once")
    func singleRefresh() async throws {
        let clock = Clock()
        let http = ScriptedHTTP(delay: .milliseconds(80)) { _, _ in (200, tokenBody(access: "access-2", refresh: "refresh-2")) }
        let auth = PlatformAuth(config: config, http: http, store: MemoryStore(session(expiresAt: clock.now.addingTimeInterval(10))), now: { clock.now })
        await auth.restore()

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<6 { group.addTask { try await auth.validAccessToken() } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(Set(tokens) == ["access-2"])
        #expect(await http.count(path: "/token") == 1)
    }

    @Test("A refresh token the server refuses ends the sign-in")
    func refreshRefused() async throws {
        let clock = Clock()
        let http = ScriptedHTTP { _, _ in (400, #"{"error_code":"validation_failed","msg":"Refresh token is not valid"}"#) }
        let store = MemoryStore(session(expiresAt: clock.now.addingTimeInterval(5)))
        let auth = PlatformAuth(config: config, http: http, store: store, now: { clock.now })
        await auth.restore()
        await #expect(throws: PlatformAuthError.notSignedIn) { try await auth.validAccessToken() }
        #expect(store.load() == nil)
        #expect(await !auth.isSignedIn)
    }

    @Test("An outage while renewing keeps the sign-in for next time")
    func refreshOutage() async throws {
        let clock = Clock()
        let http = ScriptedHTTP { _, _ in (-1, "") }
        let saved = session(expiresAt: clock.now.addingTimeInterval(5))
        let store = MemoryStore(saved)
        let auth = PlatformAuth(config: config, http: http, store: store, now: { clock.now })
        await auth.restore()
        await #expect(throws: URLError.self) { try await auth.validAccessToken() }
        #expect(store.load() == saved)
        #expect(await auth.isSignedIn)
    }

    @Test("Signing out tells the server and forgets the session, even if the server can't be reached")
    func signOut() async throws {
        let ok = ScriptedHTTP { _, _ in (204, "") }
        let store = MemoryStore(session(expiresAt: Date().addingTimeInterval(3000)))
        let auth = PlatformAuth(config: config, http: ok, store: store)
        await auth.restore()
        await auth.signOut()
        let request = try #require(await ok.requests.first)
        #expect(request.url?.absoluteString == "https://proj.supabase.co/auth/v1/logout")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(store.load() == nil)

        let offline = MemoryStore(session(expiresAt: Date().addingTimeInterval(3000)))
        let auth2 = PlatformAuth(config: config, http: ScriptedHTTP { _, _ in (-1, "") }, store: offline)
        await auth2.restore()
        await auth2.signOut()
        #expect(offline.load() == nil)
        #expect(await !auth2.isSignedIn)
    }

    @Test("A password reset asks Supabase to email the link")
    func passwordReset() async throws {
        let http = ScriptedHTTP { _, _ in (200, "{}") }
        let auth = PlatformAuth(config: config, http: http, store: MemoryStore())
        try await auth.requestPasswordReset(email: " amy@a.test ")
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://proj.supabase.co/auth/v1/recover")
        let body = jsonBody(request)
        #expect(body == ["email": "amy@a.test"])

        let limited = PlatformAuth(config: config, http: ScriptedHTTP { _, _ in (429, #"{"msg":"Email rate limit exceeded"}"#) }, store: MemoryStore())
        await #expect(throws: PlatformAuthError.rejected("Email rate limit exceeded")) { try await limited.requestPasswordReset(email: "a@a.test") }
    }

    @Test("The profile comes from /me with the token")
    func profile() async throws {
        let http = ScriptedHTTP { _, _ in (200, #"{"firstName":"Amy","fullName":"Amy Lee","email":"amy@a.test","isInternal":true,"company":"Accurate Adjustments GA"}"#) }
        let auth = PlatformAuth(config: config, http: http, store: MemoryStore(session(expiresAt: Date().addingTimeInterval(3000))))
        await auth.restore()
        let p = try await auth.profile()
        #expect(p == PlatformProfile(firstName: "Amy", fullName: "Amy Lee", email: "amy@a.test", isInternal: true, company: "Accurate Adjustments GA"))
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://aaga.myproclaimer.com/api/portal/v1/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }
}

@Suite("Platform transport")
struct PlatformTransportTests {
    private func transport(_ http: ScriptedHTTP, session: PlatformSession? = nil, clock: Clock = Clock()) async -> PlatformTransport {
        let auth = PlatformAuth(config: config, http: http, store: MemoryStore(session ?? self.session(clock)), now: { clock.now })
        await auth.restore()
        return PlatformTransport(config: config, auth: auth, http: http)
    }

    private func session(_ clock: Clock) -> PlatformSession { PortalKitTests.session(expiresAt: clock.now.addingTimeInterval(3000)) }

    @Test("Requests go to the company's API with the token, query and body")
    func buildsRequests() async throws {
        let http = ScriptedHTTP { _, _ in (201, #"{"recordId":"c1"}"#) }
        let t = await transport(http)
        let body = Data(#"{"leadName":"Jordan"}"#.utf8)

        let response = try await t.send(TransportRequest(method: .post, path: "/leads", queryItems: [URLQueryItem(name: "fileName", value: "a b.pdf")], body: body, contentType: "application/json"))

        #expect(response.statusCode == 201)
        #expect(String(decoding: response.body, as: UTF8.self) == #"{"recordId":"c1"}"#)
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://aaga.myproclaimer.com/api/portal/v1/leads?fileName=a%20b.pdf")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == body)
    }

    @Test("Error answers pass through with their body, so the app can read the code")
    func passesErrors() async throws {
        let http = ScriptedHTTP { _, _ in (409, #"{"error":"duplicate_account","matches":[]}"#) }
        let response = try await transport(http).send(TransportRequest(method: .post, path: "/new-claim"))
        #expect(response.statusCode == 409)
        #expect(String(decoding: response.body, as: UTF8.self).contains("duplicate_account"))
    }

    @Test("A 401 renews the token and tries once more")
    func retriesAfter401() async throws {
        let http = ScriptedHTTP { request, _ in
            if request.url?.path.hasSuffix("/token") == true { return (200, tokenBody(access: "access-2", refresh: "refresh-2")) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2" ? (200, "[]") : (401, #"{"error":"unauthorized"}"#)
        }
        let response = try await transport(http).send(TransportRequest(method: .get, path: "/claims"))
        #expect(response.statusCode == 200)
        #expect(await http.count(path: "/claims") == 2)
        #expect(await http.count(path: "/token") == 1)
    }

    @Test("A second 401 is passed on, not retried forever")
    func giveUp() async throws {
        let http = ScriptedHTTP { request, _ in request.url?.path.hasSuffix("/token") == true ? (200, tokenBody(access: "access-2", refresh: "refresh-2")) : (401, "") }
        let response = try await transport(http).send(TransportRequest(method: .get, path: "/claims"))
        #expect(response.statusCode == 401)
        #expect(await http.count(path: "/claims") == 2)
    }

    @Test("When the sign-in has ended the answer is 401, so the app shows sign-in")
    func signedOut() async throws {
        let clock = Clock()
        let http = ScriptedHTTP { _, _ in (400, #"{"msg":"Refresh token is not valid"}"#) }
        let expired = PortalKitTests.session(expiresAt: clock.now.addingTimeInterval(1))
        let response = try await transport(http, session: expired, clock: clock).send(TransportRequest(method: .get, path: "/claims"))
        #expect(response.statusCode == 401)
        #expect(await http.count(path: "/claims") == 0)
    }

    @Test("Salesforce-only paths are 'not found' without a request")
    func absolutePaths() async throws {
        let http = ScriptedHTTP { _, _ in (200, "") }
        let response = try await transport(http).send(TransportRequest(method: .get, path: "/services/data/v62.0/sobjects/ContentVersion", isAbsolutePath: true))
        #expect(response.statusCode == 404)
        #expect(await http.requests.isEmpty)
    }

    @Test("It carries the app's real calls: HTTPPortalAPI over it reads claims")
    func endToEnd() async throws {
        let http = ScriptedHTTP { request, _ in
            request.url?.path == "/api/portal/v1/claims"
                ? (200, #"[{"recordId":"c1","recordName":"Harris","claimStatus":"Inspection","lastModifiedDate":"2026-11-14T20:22:50.641Z"}]"#)
                : (404, #"{"error":"not_found"}"#)
        }
        let api = HTTPPortalAPI(transport: await transport(http))
        let claims = try await api.claims()
        #expect(claims.map(\.recordName) == ["Harris"])
        await #expect(throws: PortalAPIError.notFound) { try await api.claim(id: "zzz") }
    }
}

/// Test helper shared by both suites.
enum PortalKitTests {
    static func session(expiresAt: Date) -> PlatformSession {
        PlatformSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: expiresAt, email: "amy@a.test")
    }
}
