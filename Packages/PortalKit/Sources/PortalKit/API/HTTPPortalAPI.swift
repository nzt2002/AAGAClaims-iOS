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
    /// `path` is from the server root (e.g. "/services/data/…"), not under the portal API.
    public let isAbsolutePath: Bool

    public init(method: HTTPMethod, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil,
                isAbsolutePath: Bool = false) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.contentType = contentType
        self.isAbsolutePath = isAbsolutePath
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

    public func cases(for record: RecordRef) async throws -> [SupportCase] {
        try await get("/\(record.collectionPath)/\(escaped(record.id))/cases")
    }

    public func completeCase(id: String) async throws {
        try await postNoContent("/cases/\(escaped(id))/complete", body: [String: String]())
    }

    public func requestAssistance(recordId: String, comments: String) async throws -> String {
        let response: CaseIdResponse = try await post("/cases", body: ["recordId": recordId, "comments": comments])
        return response.caseId
    }

    public func agenda() async throws -> Agenda {
        try await get("/agenda")
    }

    public func activitySubjects() async throws -> ActivitySubjects {
        try await get("/activity-subjects")
    }

    public func taskAssignees() async throws -> [TaskAssignee] {
        try await get("/task-assignees")
    }

    public func createTask(_ task: NewTask, on record: RecordRef) async throws -> String {
        let response: RecordIdResponse = try await post("/\(record.collectionPath)/\(escaped(record.id))/tasks", body: task)
        return response.recordId
    }

    public func createEvent(_ event: NewEvent, on record: RecordRef) async throws -> String {
        let response: RecordIdResponse = try await post("/\(record.collectionPath)/\(escaped(record.id))/events", body: event)
        return response.recordId
    }

    public func newClaimOptions() async throws -> NewClaimOptions {
        try await get("/new-claim/options")
    }

    public func searchAccounts(_ query: String, commercialOnly: Bool) async throws -> [AccountMatch] {
        var items = [URLQueryItem(name: "q", value: query)]
        if commercialOnly { items.append(URLQueryItem(name: "type", value: "commercial")) }
        return try await get("/new-claim/accounts", query: items)
    }

    public func matchingAccounts(firstName: String?, lastName: String, email: String?) async throws -> [AccountMatch] {
        try await get("/new-claim/account-matches", query: personQuery(firstName, lastName, email))
    }

    public func matchingPartnerAccounts(name: String) async throws -> [AccountMatch] {
        try await get("/new-claim/partner-matches", query: [URLQueryItem(name: "name", value: name)])
    }

    public func searchContacts(_ query: String) async throws -> [ContactMatch] {
        try await get("/new-claim/contacts", query: [URLQueryItem(name: "q", value: query)])
    }

    public func matchingContacts(firstName: String?, lastName: String, email: String?) async throws -> [ContactMatch] {
        try await get("/new-claim/contact-matches", query: personQuery(firstName, lastName, email))
    }

    public func createClaim(_ request: NewClaimRequest) async throws -> String {
        let response: RecordIdResponse = try await post("/new-claim", body: request)
        return response.recordId
    }

    private func personQuery(_ firstName: String?, _ lastName: String, _ email: String?) -> [URLQueryItem] {
        [URLQueryItem(name: "firstName", value: firstName), URLQueryItem(name: "lastName", value: lastName),
         URLQueryItem(name: "email", value: email)].filter { $0.value?.isEmpty == false }
    }

    // MARK: - Claim actions

    private func claimPath(_ id: String, _ action: String) -> String { "/claims/\(escaped(id))/\(action)" }
    private struct Ignored: Decodable {}
    private struct OwnerBody: Encodable { let ownerId: String }
    private struct TextBody: Encodable { let text: String }

    public func staffClaim(id: String) async throws -> StaffClaim { try await get(claimPath(id, "staff")) }
    public func editClaim(id: String, _ edit: ClaimEdit) async throws { let _: Ignored = try await post(claimPath(id, "edit"), body: edit) }
    public func updateClaimAddress(id: String, _ address: ClaimAddress) async throws { let _: Ignored = try await post(claimPath(id, "address"), body: address) }
    public func changeClaimOwner(id: String, ownerId: String) async throws { let _: Ignored = try await post(claimPath(id, "owner"), body: OwnerBody(ownerId: ownerId)) }
    public func saveProofOfLoss(id: String, _ proofOfLoss: ProofOfLoss) async throws { let _: Ignored = try await post(claimPath(id, "proof-of-loss"), body: proofOfLoss) }
    public func paymentSetup(claimId: String) async throws -> PaymentSetup { try await get(claimPath(claimId, "payment-setup")) }
    public func applyPayments(claimId: String, _ entry: PaymentEntry) async throws { let _: Ignored = try await post(claimPath(claimId, "payments"), body: entry) }

    public func claimContactMatches(claimId: String, firstName: String?, lastName: String, email: String?, mobile: String?) async throws -> [ContactMatch] {
        var items = personQuery(firstName, lastName, email)
        if let mobile, !mobile.isEmpty { items.append(URLQueryItem(name: "mobile", value: mobile)) }
        return try await get(claimPath(claimId, "contact-matches"), query: items)
    }

    public func addClaimContact(claimId: String, _ contact: NewClaimRequest.Contact) async throws {
        // Same body shape as New Claim's contact.
        let wrapper = NewClaimRequest(account: .existing(id: ""), claim: .init(name: ""), contact: contact)
        let data = try PortalJSON.makeEncoder().encode(wrapper)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let contactJSON = try JSONSerialization.data(withJSONObject: object?["contact"] ?? [:])
        _ = try await send(TransportRequest(method: .post, path: claimPath(claimId, "contacts"), jsonBody: contactJSON))
    }

    public func claimFeed(claimId: String) async throws -> [ChatterPost] { try await get(claimPath(claimId, "feed")) }
    public func activities(on record: RecordRef, includeEmails: Bool) async throws -> [AgendaItem] {
        let path = switch record {
        case .claim(let id): claimPath(id, "activities")
        case .lead(let id): leadPath(id, "activities")
        }
        return try await get(path, query: includeEmails ? [URLQueryItem(name: "include", value: "emails")] : [])
    }
    public func editActivity(id: String, _ edit: ActivityEdit) async throws -> AgendaItem {
        try await post("/activities/\(escaped(id))", body: edit)
    }
    public func completeTask(id: String) async throws -> AgendaItem {
        try await post("/activities/\(escaped(id))/complete", body: [String: String]())
    }
    public func activityOptions() async throws -> ActivityOptions { try await get("/activity-options") }
    public func serverMeta() async throws -> ServerMeta {
        do {
            return try await get("/meta")
        } catch PortalAPIError.notFound {
            // Deployed before /meta existed.
            return .legacy
        }
    }
    public func postToClaim(claimId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        try await post(claimPath(claimId, "posts"), body: ChatterBody(text, mentions, fileIds: fileIds))
    }
    public func logCall(claimId: String, _ call: CallLog) async throws { let _: Ignored = try await post(claimPath(claimId, "calls"), body: call) }
    public func sendEmail(claimId: String, _ email: OutgoingEmail) async throws { let _: Ignored = try await post(claimPath(claimId, "emails"), body: email) }

    // MARK: - Lead actions

    private func leadPath(_ id: String, _ action: String) -> String { "/leads/\(escaped(id))/\(action)" }

    public func leadStaff(id: String) async throws -> LeadStaff { try await get(leadPath(id, "staff")) }
    public func editLead(id: String, _ edit: LeadEdit) async throws { let _: Ignored = try await post(leadPath(id, "edit"), body: edit) }
    public func leadFeed(leadId: String) async throws -> [ChatterPost] { try await get(leadPath(leadId, "feed")) }
    public func postToLead(leadId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        try await post(leadPath(leadId, "posts"), body: ChatterBody(text, mentions, fileIds: fileIds))
    }

    public func convertLead(id: String, account: NewClaimRequest.Account, contact: NewClaimRequest.Contact?) async throws -> String {
        // New Claim's body, without the claim (the server builds it from the lead).
        let wrapper = NewClaimRequest(account: account, claim: .init(name: ""), contact: contact)
        let data = try PortalJSON.makeEncoder().encode(wrapper)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        object["claim"] = nil
        let body = try JSONSerialization.data(withJSONObject: object)
        let response = try await send(TransportRequest(method: .post, path: leadPath(id, "convert"), jsonBody: body))
        return try (decode(response.body) as RecordIdResponse).recordId
    }

    public func search(_ query: String, includePeople: Bool) async throws -> [SearchResult] {
        var items = [URLQueryItem(name: "q", value: query)]
        if includePeople { items.append(URLQueryItem(name: "includeUsers", value: "true")) }
        return try await get("/search", query: items)
    }

    public func person(id: String) async throws -> Person {
        try await get("/people/\(escaped(id))")
    }

    public func personFeed(id: String) async throws -> [ChatterPost] {
        try await get("/people/\(escaped(id))/feed")
    }

    /// `{ text, mentions: [{id, name}] }`.
    private struct ChatterBody: Encodable {
        struct Ref: Encodable { let id: String; let name: String }
        let text: String
        let mentions: [Ref]
        /// Omitted when empty (edits can't change attachments).
        let fileIds: [String]?
        init(_ text: String, _ mentions: [Mention], fileIds: [String] = []) {
            self.text = text
            self.mentions = mentions.map { Ref(id: $0.id, name: $0.name) }
            self.fileIds = fileIds.isEmpty ? nil : fileIds
        }
    }

    public func mentionCandidates(_ query: String) async throws -> [Mention] {
        try await get("/people", query: [URLQueryItem(name: "q", value: query)])
    }

    public func addReply(toPost postId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterReply {
        try await post("/chatter/posts/\(escaped(postId))/replies", body: ChatterBody(text, mentions, fileIds: fileIds))
    }

    public func editReply(id: String, text: String, mentions: [Mention]) async throws -> ChatterReply {
        try await post("/chatter/replies/\(escaped(id))", body: ChatterBody(text, mentions))
    }

    public func feed() async throws -> [FeedPost] {
        try await get("/feed")
    }

    public func fileContent(contentDocumentId: String) async throws -> Data {
        do {
            return try await send(TransportRequest(method: .get, path: "/files/\(escaped(contentDocumentId))/content")).body
        } catch PortalAPIError.invalidRequest {
            // Too big for Apex (400 too_large): get access, then download from the standard API.
            struct Access: Decodable { let contentVersionId: String }
            let access: Access = try await post("/files/\(escaped(contentDocumentId))/access", body: [String: String]())
            return try await send(TransportRequest(
                method: .get, path: "/services/data/\(Self.dataAPIVersion)/sobjects/ContentVersion/\(escaped(access.contentVersionId))/VersionData",
                isAbsolutePath: true
            )).body
        }
    }

    /// Salesforce's standard REST API version, for large files.
    public static let dataAPIVersion = "v62.0"
    /// Larger files than this go to the standard API, past Apex's 4 MB limit.
    public static let apexUploadLimit = 3_500_000

    /// Small files: the body is the file's bytes; `fileName` and `title` are query parameters (Apex
    /// can't parse multipart bodies). Large files: uploaded to Salesforce directly, then linked.
    public func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile {
        if upload.data.count > Self.apexUploadLimit {
            return try await uploadLargeFile(upload, to: record)
        }
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

    /// A ContentVersion created with the standard REST API (multipart, up to 25 MB here), then
    /// linked to the claim or lead by the portal API, which checks access.
    private func uploadLargeFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile {
        struct Config: Decodable { let networkId: String?; let maxBytes: Int }
        let config: Config
        do {
            config = try await get("/files/upload-config")
        } catch PortalAPIError.notFound {
            throw PortalAPIError.rejected("This file is larger than 4 MB. Make it smaller and try again.")
        }
        guard upload.data.count <= config.maxBytes else {
            throw PortalAPIError.rejected("Files can be up to \(config.maxBytes / 1_048_576) MB.")
        }
        var entity: [String: String] = ["Title": upload.title, "PathOnClient": upload.fileName]
        if let networkId = config.networkId { entity["NetworkId"] = networkId }
        let boundary = "AAGA-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"entity_content\"\r\nContent-Type: application/json\r\n\r\n")
        body.append(try JSONSerialization.data(withJSONObject: entity))
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"VersionData\"; filename=\"\(upload.fileName.replacingOccurrences(of: "\"", with: ""))\"\r\n")
        append("Content-Type: \(upload.mimeType)\r\n\r\n")
        body.append(upload.data)
        append("\r\n--\(boundary)--\r\n")

        struct Created: Decodable { let id: String }
        let response = try await send(TransportRequest(
            method: .post, path: "/services/data/\(Self.dataAPIVersion)/sobjects/ContentVersion",
            body: body, contentType: "multipart/form-data; boundary=\(boundary)", isAbsolutePath: true
        ))
        let created: Created = try decode(response.body)
        return try await post("/\(record.collectionPath)/\(escaped(record.id))/files/link", body: ["contentVersionId": created.id])
    }

    public func requestAccountDeletion(reason: String?) async throws -> AccountDeletionRequest {
        try await post("/account/deletion-request", body: ["reason": reason ?? ""])
    }

    public func sendDiagnostics(_ report: DiagnosticsReport) async throws {
        struct Received: Decodable { let received: Int }
        let _: Received = try await post("/diagnostics", body: report)
    }

    public func notificationPreferences() async throws -> NotificationPreferences {
        try await get("/notification-preferences")
    }

    public func saveNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        try await post("/notification-preferences", body: preferences)
    }

    // MARK: - Documents (pilot)

    public static let documentsBasePath = "/services/apexrest/portaldocs/v1"

    public func documentTemplates(for record: RecordRef) async throws -> [DocumentTemplate] {
        let response = try await send(TransportRequest(
            method: .get, path: "\(Self.documentsBasePath)/templates",
            queryItems: [URLQueryItem(name: "object", value: record.objectApiName)], isAbsolutePath: true))
        return try decode(response.body)
    }

    public func generateDocument(templateId: String, for record: RecordRef, save: Bool) async throws -> GeneratedDocument {
        struct Body: Encodable { let templateId: String; let save: Bool }
        let data = try PortalJSON.makeEncoder().encode(Body(templateId: templateId, save: save))
        let response = try await send(TransportRequest(
            method: .post, path: "\(Self.documentsBasePath)/records/\(escaped(record.id))/documents",
            body: data, contentType: "application/json", isAbsolutePath: true))
        return try decode(response.body)
    }

    public func signingSetup(for record: RecordRef, templateId: String?) async throws -> SigningSetup {
        let query = templateId.map { [URLQueryItem(name: "templateId", value: $0)] } ?? []
        let response = try await send(TransportRequest(
            method: .get, path: "\(Self.documentsBasePath)/records/\(escaped(record.id))/signing-setup",
            queryItems: query, isAbsolutePath: true))
        return try decode(response.body)
    }

    public func sendForSignature(templateId: String, signers: [SignerInput], message: String?, for record: RecordRef) async throws -> String {
        struct Body: Encodable { let templateId: String; let signers: [SignerInput]; let message: String? }
        struct Sent: Decodable { let requestId: String }
        let data = try PortalJSON.makeEncoder().encode(Body(templateId: templateId, signers: signers, message: message))
        let response = try await send(TransportRequest(
            method: .post, path: "\(Self.documentsBasePath)/records/\(escaped(record.id))/signature-requests",
            body: data, contentType: "application/json", isAbsolutePath: true))
        let sent: Sent = try decode(response.body)
        return sent.requestId
    }

    public func signatureRequests(for record: RecordRef) async throws -> [SignatureRequestSummary] {
        let response = try await send(TransportRequest(
            method: .get, path: "\(Self.documentsBasePath)/records/\(escaped(record.id))/signature-requests", isAbsolutePath: true))
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
        case 400: throw Self.message(response.body).map(PortalAPIError.rejected) ?? PortalAPIError.invalidRequest
        case 401: throw PortalAPIError.sessionExpired
        case 404: throw PortalAPIError.notFound
        case 409:
            if Self.errorCode(response.body) == "already_converted" {
                struct Body: Decodable { let matches: String? }
                throw PortalAPIError.alreadyConverted(claimId: (try? JSONDecoder().decode(Body.self, from: response.body))?.matches)
            }
            if let message = Self.message(response.body), Self.errorCode(response.body).flatMap(DuplicateMatches.Kind.init(rawValue:)) == nil {
                throw PortalAPIError.rejected(message)
            }
            throw PortalAPIError.duplicate(Self.duplicateMatches(response.body))
        default: throw PortalAPIError.server(status: response.statusCode)
        }
    }

    private struct ErrorBody: Decodable { let error: String?; let message: String? }

    static func message(_ body: Data) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: body))?.message.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func errorCode(_ body: Data) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
    }

    /// `{"error": "duplicate_account", "matches": [...]}`.
    static func duplicateMatches(_ body: Data) -> DuplicateMatches {
        struct Body<M: Decodable>: Decodable { let error: String; let matches: [M]? }
        let decoder = PortalJSON.makeDecoder()
        let code = (try? decoder.decode(Body<AccountMatch>.self, from: body).error)
            ?? (try? decoder.decode(Body<ContactMatch>.self, from: body).error)
        let kind = code.flatMap(DuplicateMatches.Kind.init(rawValue:)) ?? .account
        if kind == .contact {
            return DuplicateMatches(kind: kind, contacts: (try? decoder.decode(Body<ContactMatch>.self, from: body).matches) ?? [])
        }
        return DuplicateMatches(kind: kind, accounts: (try? decoder.decode(Body<AccountMatch>.self, from: body).matches) ?? [])
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
