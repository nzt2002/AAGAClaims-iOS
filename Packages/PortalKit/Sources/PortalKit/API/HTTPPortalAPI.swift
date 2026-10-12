import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct TransportRequest: Hashable, Sendable {
    public let method: HTTPMethod
    /// Path under `/services/apexrest/portal/v1`, starting with "/".
    public let path: String
    public let queryItems: [URLQueryItem]
    public let body: Data?
    /// Content type of `body`, e.g. "application/json" or "multipart/form-data; boundary=…".
    public let contentType: String?

    public init(method: HTTPMethod, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.contentType = contentType
    }

    public init(method: HTTPMethod, path: String, jsonBody: Data) {
        self.init(method: method, path: path, body: jsonBody, contentType: "application/json")
    }

    /// The JSON body, for tests.
    public var jsonBody: Data? {
        contentType == "application/json" ? body : nil
    }
}

public struct TransportResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Sends an authenticated request. The app implements this with the Mobile SDK's `RestClient`,
/// which handles OAuth tokens and refresh.
public protocol PortalTransport: Sendable {
    func send(_ request: TransportRequest) async throws -> TransportResponse
}

/// `PortalAPI` over the Apex REST endpoints in spec §5.
public struct HTTPPortalAPI: PortalAPI {
    public static let basePath = "/services/apexrest/portal/v1"

    private let transport: PortalTransport

    public init(transport: PortalTransport) {
        self.transport = transport
    }

    public func claims() async throws -> [ClaimSummary] {
        try await get("/claims")
    }

    public func claim(id: String) async throws -> ClaimDetail {
        try await get("/claims/\(escaped(id))")
    }

    public func claimPayments(id: String) async throws -> [Payment] {
        try await get("/claims/\(escaped(id))/payments")
    }

    public func leads() async throws -> [LeadSummary] {
        try await get("/leads")
    }

    public func lead(id: String) async throws -> LeadDetail {
        try await get("/leads/\(escaped(id))")
    }

    public func createLead(_ submission: LeadSubmission) async throws -> String {
        let response: RecordIdResponse = try await post("/leads", body: submission)
        return response.recordId
    }

    public func insuranceCompanies(matching query: String) async throws -> [InsuranceCompany] {
        try await get("/insurance-companies", query: [URLQueryItem(name: "q", value: query)])
    }

    public func perilValues() async throws -> [String] {
        try await get("/picklists/peril")
    }

    public func updates(for record: RecordRef) async throws -> [PortalUpdate] {
        try await get("/\(record.collectionPath)/\(escaped(record.id))/updates")
    }

    public func files(for record: RecordRef) async throws -> [PortalFile] {
        try await get("/\(record.collectionPath)/\(escaped(record.id))/files")
    }

    public func addComment(to record: RecordRef, text: String) async throws {
        try await postNoContent("/\(record.collectionPath)/\(escaped(record.id))/comments", body: ["text": text])
    }

    public func activity() async throws -> [ActivityItem] {
        try await get("/activity")
    }

    public func markActivityRead(commentIds: [String]) async throws {
        try await postNoContent("/activity/read", body: ["commentIds": commentIds])
    }

    public func cases() async throws -> [SupportCase] {
        try await get("/cases")
    }

    public func supportCase(id: String) async throws -> SupportCaseDetail {
        try await get("/cases/\(escaped(id))")
    }

    public func replyToCase(id: String, body: String) async throws {
        try await postNoContent("/cases/\(escaped(id))/replies", body: ["body": body])
    }

    public func requestAssistance(recordId: String, comments: String) async throws -> String {
        let response: CaseIdResponse = try await post("/cases", body: ["recordId": recordId, "comments": comments])
        return response.caseId
    }

    public func fileContent(contentDocumentId: String) async throws -> Data {
        try await send(TransportRequest(method: .get, path: "/files/\(escaped(contentDocumentId))/content")).body
    }

    /// The body is the file's bytes; `fileName` and `title` are query parameters. (Apex can't
    /// parse multipart bodies, so the server takes the raw file.)
    public func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile {
        let response = try await send(TransportRequest(
            method: .post,
            path: "/\(record.collectionPath)/\(escaped(record.id))/files",
            queryItems: [
                URLQueryItem(name: "fileName", value: upload.fileName),
                URLQueryItem(name: "title", value: upload.title)
            ],
            body: upload.data,
            contentType: upload.mimeType
        ))
        return try decode(response.body)
    }

    // MARK: - Plumbing

    private struct RecordIdResponse: Decodable { let recordId: String }
    private struct CaseIdResponse: Decodable { let caseId: String }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let response = try await send(TransportRequest(method: .get, path: path, queryItems: query))
        return try decode(response.body)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try PortalJSON.makeEncoder().encode(body)
        let response = try await send(TransportRequest(method: .post, path: path, jsonBody: data))
        return try decode(response.body)
    }

    private func postNoContent<Body: Encodable>(_ path: String, body: Body) async throws {
        let data = try PortalJSON.makeEncoder().encode(body)
        _ = try await send(TransportRequest(method: .post, path: path, jsonBody: data))
    }

    private func send(_ request: TransportRequest) async throws -> TransportResponse {
        let response = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return response
        case 400: throw PortalAPIError.invalidRequest
        case 401: throw PortalAPIError.sessionExpired
        case 404: throw PortalAPIError.notFound
        default: throw PortalAPIError.server(status: response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try PortalJSON.makeDecoder().decode(T.self, from: data)
        } catch {
            // Never include the body: it can hold personal data (spec §10).
            throw PortalAPIError.decoding(String(describing: T.self))
        }
    }

    private func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }
}
