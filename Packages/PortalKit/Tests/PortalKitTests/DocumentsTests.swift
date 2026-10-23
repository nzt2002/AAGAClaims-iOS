import Foundation
import Testing
@testable import PortalKit

private actor DocsTransport: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    private let status: Int
    private let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: status, body: Data(body.utf8))
    }
}

@Suite("Document generation (pilot)")
struct DocumentsTests {
    @Test("Templates come from the separate portaldocs API, filtered by the record's object")
    func templates() async throws {
        let transport = DocsTransport(body: #"[{"id":"a0z1","name":"PA - GA LOR Contract","objectName":"Prospects__c","category":"Agreement_LOR","signerCount":2}]"#)
        let api = HTTPPortalAPI(transport: transport)
        let templates = try await api.documentTemplates(for: .lead("a0r1"))
        #expect(templates.map(\.name) == ["PA - GA LOR Contract"])
        #expect(templates.first?.signerCount == 2)
        let request = try #require(await transport.requests.first)
        #expect(request.isAbsolutePath)
        #expect(request.path == "/services/apexrest/portaldocs/v1/templates")
        #expect(request.queryItems == [URLQueryItem(name: "object", value: "Prospects__c")])
    }

    @Test("Generate posts the template and save flag and decodes the PDF")
    func generate() async throws {
        let pdf = Data("%PDF-1.7".utf8).base64EncodedString()
        let transport = DocsTransport(body: #"{"title":"PoL - Smith","pageCount":2,"pdfBase64":"\#(pdf)","contentDocumentId":"069x"}"#)
        let api = HTTPPortalAPI(transport: transport)
        let doc = try await api.generateDocument(templateId: "a0z2", for: .claim("a23x"), save: true)
        #expect(doc.title == "PoL - Smith")
        #expect(doc.pdfData == Data("%PDF-1.7".utf8))
        #expect(doc.contentDocumentId == "069x")
        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/services/apexrest/portaldocs/v1/records/a23x/documents")
        let body = try JSONSerialization.jsonObject(with: try #require(request.jsonBody)) as? [String: Any]
        #expect(body?["templateId"] as? String == "a0z2")
        #expect(body?["save"] as? Bool == true)
    }

    @Test("Users outside the pilot get 403, which hides the feature")
    func forbidden() async {
        let api = HTTPPortalAPI(transport: DocsTransport(status: 403, body: #"{"error":"forbidden"}"#))
        await #expect(throws: PortalAPIError.server(status: 403)) {
            try await api.documentTemplates(for: .claim("a23x"))
        }
    }

    @Test("Demo mode returns a template per object and a real PDF")
    func mock() async throws {
        let api = MockPortalAPI(fixtures: .empty)
        let templates = try await api.documentTemplates(for: .claim("a23x"))
        #expect(templates.count == 1)
        let doc = try await api.generateDocument(templateId: templates[0].id, for: .claim("a23x"), save: false)
        #expect(doc.pdfData?.prefix(4) == Data("%PDF".utf8))
        #expect(doc.contentDocumentId == nil)
    }

    @Test("Signing setup, send and status use the portaldocs paths")
    func signing() async throws {
        let setupJSON = #"{"templates":[{"id":"a0z1","name":"PA Contract","objectName":"Prospects__c","category":"Agreement_LOR","signerCount":2,"fields":[],"anchors":[],"issues":[]}],"signers":[{"index":1,"label":"Public Adjuster","name":"Alexis Smith","email":"alexis@example.com","userId":"005x"},{"index":2,"label":"Insured","name":"Jane Doe","email":"jane@example.com"}],"templateId":"a0z1"}"#
        let api = HTTPPortalAPI(transport: DocsTransport(body: setupJSON))
        let setup = try await api.signingSetup(for: .lead("a0r1"), templateId: nil)
        #expect(setup.signers.map(\.label) == ["Public Adjuster", "Insured"])
        let complete = setup.signers.allSatisfy { $0.isComplete }
        #expect(complete)

        let sendTransport = DocsTransport(body: #"{"requestId":"a3x1"}"#)
        let id = try await HTTPPortalAPI(transport: sendTransport)
            .sendForSignature(templateId: "a0z1", signers: setup.signers, message: "Hi", for: .lead("a0r1"))
        #expect(id == "a3x1")
        let request = try #require(await sendTransport.requests.first)
        #expect(request.path == "/services/apexrest/portaldocs/v1/records/a0r1/signature-requests")
        let body = try JSONSerialization.jsonObject(with: try #require(request.jsonBody)) as? [String: Any]
        #expect((body?["signers"] as? [[String: Any]])?.count == 2)

        let listJSON = #"[{"id":"a3x1","name":"SR-000001","subject":"PA Contract - Jane Doe","status":"Viewed","source":"In-house","sentAt":"2026-10-22T14:00:00.000Z","signers":[{"index":1,"name":"Alexis Smith","email":"a@x.com","status":"Signed","signedAt":"2026-10-22T14:05:00.000Z"}]}]"#
        let rows = try await HTTPPortalAPI(transport: DocsTransport(body: listJSON)).signatureRequests(for: .lead("a0r1"))
        #expect(rows.first?.isOpen == true)
        #expect(rows.first?.signers.first?.signedAt != nil)
    }

    @Test("Demo send records a request and rejects incomplete signers")
    func mockSend() async throws {
        let api = MockPortalAPI(fixtures: .empty)
        let setup = try await api.signingSetup(for: .lead("a0r1"), templateId: nil)
        var bad = setup.signers
        bad[1].email = "nope"
        await #expect(throws: PortalAPIError.rejected("Enter a name and valid email for every signer.")) {
            try await api.sendForSignature(templateId: setup.templateId!, signers: bad, message: nil, for: .lead("a0r1"))
        }
        _ = try await api.sendForSignature(templateId: setup.templateId!, signers: setup.signers, message: nil, for: .lead("a0r1"))
        let sent = try await api.signatureRequests(for: .lead("a0r1"))
        #expect(sent.count == 1)
    }
}
