import Foundation
import Testing
@testable import PortalKit

/// Records requests and replies with a canned response.
private actor FakeTransport: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    private let status: Int
    private let body: Data

    init(status: Int = 200, body: String = "[]") {
        self.status = status
        self.body = Data(body.utf8)
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: status, body: body)
    }
}

@Suite("HTTPPortalAPI")
struct HTTPPortalAPITests {
    @Test("Claim and lead endpoints use the spec paths")
    func paths() async throws {
        let transport = FakeTransport()
        let api = HTTPPortalAPI(transport: transport)

        _ = try await api.claims()
        _ = try await api.updates(for: .claim("a0X1"))
        _ = try await api.files(for: .lead("a0P1"))
        _ = try await api.cases()

        let paths = await transport.requests.map(\.path)
        #expect(paths == ["/claims", "/claims/a0X1/updates", "/leads/a0P1/files", "/cases"])
    }

    @Test("Comments post JSON to the record's comments endpoint")
    func commentBody() async throws {
        let transport = FakeTransport(status: 204, body: "")
        let api = HTTPPortalAPI(transport: transport)

        try await api.addComment(to: .lead("a0P1"), text: "Hello")

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/leads/a0P1/comments")
        let body = try #require(request.jsonBody)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["text": "Hello"])
    }

    @Test("Insurance search sends q")
    func insuranceQuery() async throws {
        let transport = FakeTransport()
        _ = try await HTTPPortalAPI(transport: transport).insuranceCompanies(matching: "sta")
        let request = try #require(await transport.requests.first)
        #expect(request.path == "/insurance-companies")
        #expect(request.queryItems == [URLQueryItem(name: "q", value: "sta")])
    }

    @Test(
        "Status codes map to errors (spec §5)",
        arguments: [
            (400, PortalAPIError.invalidRequest), (401, .sessionExpired),
            (404, .notFound), (500, .server(status: 500)), (503, .server(status: 503))
        ]
    )
    func statusMapping(status: Int, expected: PortalAPIError) async {
        let api = HTTPPortalAPI(transport: FakeTransport(status: status, body: "{}"))
        await #expect(throws: expected) {
            _ = try await api.claims()
        }
    }

    @Test("Malformed JSON is a decoding error that doesn't leak the body")
    func decodingError() async {
        let api = HTTPPortalAPI(transport: FakeTransport(body: #"{"secret":"alex@example.com"}"#))
        await #expect(throws: PortalAPIError.decoding("Array<ClaimSummary>")) {
            _ = try await api.claims()
        }
    }

    @Test("createLead returns the new record id")
    func createLead() async throws {
        let api = HTTPPortalAPI(transport: FakeTransport(body: #"{"recordId":"a0P9"}"#))
        var submission = LeadSubmission(leadName: "Jane")
        submission.email = "jane@example.com"
        #expect(try await api.createLead(submission) == "a0P9")
    }
}
