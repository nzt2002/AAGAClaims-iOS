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

    // Home agenda and tasks
    /// `GET /agenda`: the user's open tasks and upcoming events, plus upcoming events on their records.
    func agenda() async throws -> Agenda
    /// `GET /activity-subjects`: Task and Event subject suggestions. Staff and adjusters only.
    func activitySubjects() async throws -> ActivitySubjects
    /// `GET /task-assignees`: people a task can be assigned to. Staff and adjusters only.
    func taskAssignees() async throws -> [TaskAssignee]
    /// `POST /claims/{id}/tasks`. Returns the new task id. Staff and adjusters only.
    func createTask(_ task: NewTask, on record: RecordRef) async throws -> String

    /// `POST /claims/{id}/events`. Returns the new event id. Staff and adjusters only.
    func createEvent(_ event: NewEvent, on record: RecordRef) async throws -> String

    // New Claim (staff): the Prospect Conversion Guided Process without a Prospect
    /// `GET /new-claim/options`: picklists and internal users.
    func newClaimOptions() async throws -> NewClaimOptions
    /// `GET /new-claim/accounts?q=`: accounts by name (Commercial only for partner accounts).
    func searchAccounts(_ query: String, commercialOnly: Bool) async throws -> [AccountMatch]
    /// `GET /new-claim/account-matches`: Residential accounts with the same email, or the same first and last name.
    func matchingAccounts(firstName: String?, lastName: String, email: String?) async throws -> [AccountMatch]
    /// `GET /new-claim/partner-matches?name=`: Commercial accounts with exactly this name.
    func matchingPartnerAccounts(name: String) async throws -> [AccountMatch]
    /// `GET /new-claim/contacts?q=`: contacts by name or email.
    func searchContacts(_ query: String) async throws -> [ContactMatch]
    /// `GET /new-claim/contact-matches`: contacts with the same email, or the same first and last name.
    func matchingContacts(firstName: String?, lastName: String, email: String?) async throws -> [ContactMatch]
    /// `POST /new-claim`. Returns the new claim id. Throws `.duplicate` when a match must be used instead.
    func createClaim(_ request: NewClaimRequest) async throws -> String

    // Claim actions (staff)
    func staffClaim(id: String) async throws -> StaffClaim
    func editClaim(id: String, _ edit: ClaimEdit) async throws
    func updateClaimAddress(id: String, _ address: ClaimAddress) async throws
    func changeClaimOwner(id: String, ownerId: String) async throws
    func saveProofOfLoss(id: String, _ proofOfLoss: ProofOfLoss) async throws
    func paymentSetup(claimId: String) async throws -> PaymentSetup
    func applyPayments(claimId: String, _ entry: PaymentEntry) async throws
    /// Add_Claim_Contact's matches: email, mobile phone, or first and last name.
    func claimContactMatches(claimId: String, firstName: String?, lastName: String, email: String?, mobile: String?) async throws -> [ContactMatch]
    func addClaimContact(claimId: String, _ contact: NewClaimRequest.Contact) async throws
    func claimFeed(claimId: String) async throws -> [ChatterPost]
    func postToClaim(claimId: String, text: String, mentions: [Mention]) async throws -> ChatterPost
    func logCall(claimId: String, _ call: CallLog) async throws
    func sendEmail(claimId: String, _ email: OutgoingEmail) async throws

    // Lead actions (staff)
    func leadStaff(id: String) async throws -> LeadStaff
    func editLead(id: String, _ edit: LeadEdit) async throws
    func leadFeed(leadId: String) async throws -> [ChatterPost]
    func postToLead(leadId: String, text: String, mentions: [Mention]) async throws -> ChatterPost
    /// Convert to Account: the account and claim contact as for New Claim; the claim comes from the lead.
    /// Returns the new claim id. Throws `.alreadyConverted` if the lead was converted already.
    func convertLead(id: String, account: NewClaimRequest.Account, contact: NewClaimRequest.Contact?) async throws -> String

    // Search and Chatter
    /// `GET /search?q=`: claims, leads (and, for portal users, cases) the user can open.
    func search(_ query: String, includePeople: Bool) async throws -> [SearchResult]
    // People (staff only)
    /// `GET /people/{id}`.
    func person(id: String) async throws -> Person
    /// `GET /people/{id}/feed`: their Chatter profile feed.
    func personFeed(id: String) async throws -> [ChatterPost]
    /// `GET /people?q=`: people to @mention.
    func mentionCandidates(_ query: String) async throws -> [Mention]
    /// `POST /chatter/posts/{id}/replies`. Each "@Name" of a mention in the text becomes a real Chatter mention.
    func addReply(toPost postId: String, text: String, mentions: [Mention]) async throws -> ChatterReply
    /// `POST /chatter/replies/{id}`: edit your own reply.
    func editReply(id: String, text: String, mentions: [Mention]) async throws -> ChatterReply
    /// `GET /feed`: Chatter posts from a staff member's news feed; empty for portal users.
    func feed() async throws -> [FeedPost]

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
    /// 409 from New Claim: matching records exist, and the user must pick one instead.
    case duplicate(DuplicateMatches)
    /// 400 or 409 with a message written for users (a validation rule, "already on the claim").
    case rejected(String)
    /// 409 from Convert to Account: the lead is already converted (to this claim, when known).
    case alreadyConverted(claimId: String?)

    public var isRetryable: Bool {
        switch self {
        case .sessionExpired, .notFound, .invalidRequest, .decoding, .duplicate, .rejected, .alreadyConverted: false
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
