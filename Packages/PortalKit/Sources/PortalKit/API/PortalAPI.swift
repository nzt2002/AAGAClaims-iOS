import Foundation

/// Every call the app makes to Salesforce (spec §5). All data access goes through this;
/// the app never queries objects directly.
public protocol PortalAPI: Sendable {
    // Claims
    func claims() async throws -> [ClaimSummary]
    func claim(id: String) async throws -> ClaimDetail
    func claimPayments(id: String) async throws -> [Payment]

    // Leads
    func leads() async throws -> [LeadSummary]
    func lead(id: String) async throws -> LeadDetail
    func createLead(_ submission: LeadSubmission) async throws -> String
    func insuranceCompanies(matching query: String) async throws -> [InsuranceCompany]
    func perilValues() async throws -> [String]

    // Shared by claims and leads
    func updates(for record: RecordRef) async throws -> [PortalUpdate]
    func files(for record: RecordRef) async throws -> [PortalFile]
    func addComment(to record: RecordRef, text: String) async throws

    // Activity
    func activity() async throws -> [ActivityItem]
    func markActivityRead(commentIds: [String]) async throws

    // Support
    func cases() async throws -> [SupportCase]
    func supportCase(id: String) async throws -> SupportCaseDetail
    func replyToCase(id: String, body: String) async throws
    /// Request Assistance. `recordId` is a claim or lead id. Returns the new case id.
    func requestAssistance(recordId: String, comments: String) async throws -> String

    // Files [new endpoints]
    /// `GET /files/{contentDocumentId}/content`: the file's bytes, for Quick Look.
    func fileContent(contentDocumentId: String) async throws -> Data
    /// `POST /claims|leads/{id}/files`: multipart upload (`file`, `title`).
    func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile
}

/// A file ready to upload (already checked and downscaled by `FileUploadRules`).
public struct FileUpload: Hashable, Sendable {
    public let fileName: String
    public let title: String
    public let mimeType: String
    public let data: Data

    public init(fileName: String, title: String, mimeType: String, data: Data) {
        self.fileName = fileName
        self.title = title
        self.mimeType = mimeType
        self.data = data
    }
}

public enum PortalAPIError: Error, Equatable, Sendable {
    /// 401: the session has expired and the user must sign in again.
    case sessionExpired
    /// 404: the record doesn't exist or isn't the user's.
    case notFound
    /// 400: the server rejected the input.
    case invalidRequest
    /// No network connection.
    case offline
    /// Any other status >= 400. Retryable.
    case server(status: Int)
    /// The response didn't match the expected shape.
    case decoding(String)

    public var isRetryable: Bool {
        switch self {
        case .sessionExpired, .notFound, .invalidRequest, .decoding: false
        case .offline, .server: true
        }
    }
}

/// Character limits the server enforces (spec §5).
public enum PortalLimits {
    public static let commentLength = 5_000
    public static let assistanceLength = 5_000
    public static let caseReplyLength = 2_000
}
