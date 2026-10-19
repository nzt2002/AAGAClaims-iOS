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

/// Replies by path, in order of the requests that match.
private actor ScriptedTransport: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    private let replies: [(String, Int, String)]

    init(_ replies: [(pathSuffix: String, status: Int, body: String)]) {
        self.replies = replies.map { ($0.pathSuffix, $0.status, $0.body) }
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        let reply = replies.first { request.path.hasSuffix($0.0) } ?? ("", 500, "")
        return TransportResponse(statusCode: reply.1, body: Data(reply.2.utf8))
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

    @Test("Large files: uploaded to the standard API as multipart, then linked")
    func largeUpload() async throws {
        let transport = ScriptedTransport([
            ("/files/upload-config", 200, #"{"networkId":"0DB000000000001","maxBytes":26214400}"#),
            ("/sobjects/ContentVersion", 201, #"{"id":"068000000000001AAA","success":true}"#),
            ("/files/link", 201, #"{"contentDocumentId":"069000000000001AAA","title":"Scan","fileType":"PDF","contentSize":5000000}"#),
        ])
        let api = HTTPPortalAPI(transport: transport)
        let upload = FileUpload(fileName: "Scan.pdf", title: "Scan", mimeType: "application/pdf", data: Data(count: 5_000_000))
        let file = try await api.uploadFile(upload, to: .claim("a23000000000001AAA"))
        #expect(file.contentDocumentId == "069000000000001AAA")

        let requests = await transport.requests
        #expect(requests.map(\.path) == ["/files/upload-config", "/services/data/v62.0/sobjects/ContentVersion",
                                         "/claims/a23000000000001AAA/files/link"])
        #expect(requests[1].isAbsolutePath)
        #expect(requests[1].contentType?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try #require(requests[1].body).prefix(400), as: UTF8.self)
        #expect(body.contains(#""NetworkId":"0DB000000000001""#))
        #expect(body.contains("name=\"VersionData\"; filename=\"Scan.pdf\""))
        let link = try #require(requests[2].body)
        #expect(String(decoding: link, as: UTF8.self).contains("068000000000001AAA"))
    }

    @Test("Large files: too big for the server, or a server without large files")
    func largeUploadRefused() async throws {
        let big = FileUpload(fileName: "Video.pdf", title: "Video", mimeType: "application/pdf", data: Data(count: 5_000_000))
        let tooBig = HTTPPortalAPI(transport: ScriptedTransport([("/files/upload-config", 200, #"{"maxBytes":4000000}"#)]))
        await #expect(throws: PortalAPIError.rejected("Files can be up to 3 MB.")) {
            _ = try await tooBig.uploadFile(big, to: .claim("a23000000000001AAA"))
        }
        let old = HTTPPortalAPI(transport: ScriptedTransport([("/files/upload-config", 404, "")]))
        await #expect(throws: PortalAPIError.rejected("This file is larger than 4 MB. Make it smaller and try again.")) {
            _ = try await old.uploadFile(big, to: .claim("a23000000000001AAA"))
        }
    }

    @Test("Large downloads: access, then the standard API")
    func largeDownload() async throws {
        let transport = ScriptedTransport([
            ("/content", 400, #"{"error":"too_large"}"#),
            ("/access", 201, #"{"contentVersionId":"068000000000002AAA","contentSize":9000000}"#),
            ("/VersionData", 200, "PDFBYTES"),
        ])
        let data = try await HTTPPortalAPI(transport: transport).fileContent(contentDocumentId: "069000000000002AAA")
        #expect(String(decoding: data, as: UTF8.self) == "PDFBYTES")
        #expect(await transport.requests.last?.path == "/services/data/v62.0/sobjects/ContentVersion/068000000000002AAA/VersionData")
    }

    @Test("Account deletion and diagnostics post to their endpoints")
    func deletionAndDiagnostics() async throws {
        let transport = ScriptedTransport([
            ("/account/deletion-request", 201, #"{"caseId":"500000000000001AAA","alreadyRequested":false}"#),
            ("/diagnostics", 201, #"{"received":1}"#),
        ])
        let api = HTTPPortalAPI(transport: transport)
        let request = try await api.requestAccountDeletion(reason: "Moving")
        #expect(request.caseId == "500000000000001AAA")
        try await api.sendDiagnostics(DiagnosticsReport(appVersion: "0.4.0 (15)", device: "iPhone",
                                                        reports: [.init(kind: "App crash", reason: "SIGABRT", details: "{}")]))
        #expect(await transport.requests.map(\.path) == ["/account/deletion-request", "/diagnostics"])
    }
}
