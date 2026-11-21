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
    /// Staff: the record's "Recent Portal Update" draft (`GET /{record}/portal-update`).
    func portalUpdateDraft(for record: RecordRef) async throws -> PortalUpdateDraft
    /// Staff: publishes the reviewed update to the portal and the app, and optionally emails it.
    func postPortalUpdate(to record: RecordRef, _ update: PortalUpdatePost) async throws -> PortalUpdatePosted
    func files(for record: RecordRef) async throws -> [PortalFile]
    /// Folders of a record (servers with `fileFolders`; others have none).
    func folders(for record: RecordRef) async throws -> [PortalFolder]
    /// Staff: a new folder, at the top level when `parentId` is nil.
    func createFolder(named name: String, parentId: String?, in record: RecordRef) async throws -> PortalFolder
    /// Staff: rename, show to the policyholder, move or delete a folder.
    func changeFolder(_ id: String, _ change: FolderChange, in record: RecordRef) async throws
    /// Staff: move, show, hide, remove or restore several files at once. `folderId` is for `.move` (nil: top level).
    func organizeFiles(_ ids: [String], _ op: FileOrganizeOp, folderId: String?, in record: RecordRef) async throws
    func addComment(to record: RecordRef, text: String) async throws

    // Activity
    func activity() async throws -> [ActivityItem]
    func markActivityRead(commentIds: [String]) async throws

    // Support
    func cases() async throws -> [SupportCase]
    func supportCase(id: String) async throws -> SupportCaseDetail
    func replyToCase(id: String, body: String) async throws
    /// `GET /{claims|leads}/{id}/cases`: support cases on a claim or lead (portal users: their own).
    func cases(for record: RecordRef) async throws -> [SupportCase]
    /// `GET /{claims|leads}/{id}/contacts` (staff, servers with `recordContacts`): the record's contacts.
    func contacts(for record: RecordRef) async throws -> [RecordContact]
    /// `POST /cases/{id}/complete`: the case contact marks their case Completed.
    func completeCase(id: String) async throws
    /// Request Assistance. `recordId` is a claim or lead id. Returns the new case id.
    func requestAssistance(recordId: String, comments: String) async throws -> String

    // Home agenda and tasks
    /// `GET /agenda`: the user's open tasks and upcoming events, plus upcoming events on their records.
    func agenda() async throws -> Agenda
    /// `GET /agenda/completed`: the user's latest finished tasks. Fetched only when Home's "show completed" is on.
    func completedTasks() async throws -> [AgendaItem]
    /// Your own settings (`/settings/me`): name, phone and email alerts. Servers with `appSettings`.
    func mySettings() async throws -> MySettings
    func saveMySettings(fullName: String, phone: String) async throws
    func saveEmailAlerts(_ on: [String: Bool]) async throws
    func changePassword(current: String, new: String) async throws
    /// The company's everyday settings (`/settings/company`), staff only.
    func companySettings() async throws -> CompanySettings
    func saveCompanySetting(_ change: CompanySettingChange) async throws
    /// `GET /signatures/waiting`: documents waiting on a signature (staff).
    func waitingSignatures() async throws -> WaitingSignatures
    /// `GET /cases?open=1&limit=`: a few open support requests for Home.
    func openCases(limit: Int) async throws -> [SupportCase]
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
    /// Staff: the claim's or lead's tasks and events (and emails, if asked), open first.
    func activities(on record: RecordRef, includeEmails: Bool) async throws -> [AgendaItem]
    /// Staff: edit or reassign a task or event on a claim or lead.
    func editActivity(id: String, _ edit: ActivityEdit) async throws -> AgendaItem
    /// Staff: Mark Complete.
    func completeTask(id: String) async throws -> AgendaItem
    func activityOptions() async throws -> ActivityOptions
    /// What the server supports (`ServerMeta.legacy` for servers without `/meta`).
    func serverMeta() async throws -> ServerMeta
    /// Staff: Twilio Voice access token for in-app calling (`ServerMeta.canCallInApp`).
    func voiceToken() async throws -> VoiceToken
    /// Staff: pause (`false`) or resume (`true`) recording on the user's in-app call
    /// (`POST /voice/recording`, servers with `voiceRecording`). Returns whether it is now recording.
    func setCallRecording(callSid: String, recording: Bool) async throws -> Bool
    /// Account deletion (App Store 5.1.1(v)): opens a support case to delete the user's account.
    func requestAccountDeletion(reason: String?) async throws -> AccountDeletionRequest
    /// Crash and hang reports from MetricKit, for Mobile App Logs in Salesforce.
    func sendDiagnostics(_ report: DiagnosticsReport) async throws
    /// Tells the ProClaimer platform which phone to send this person's push notifications to
    /// (`POST /devices`). `environment` is "sandbox" for Xcode builds and "production" for TestFlight and the App Store.
    func registerPushDevice(token: String, environment: String) async throws
    /// Stops sending to this phone (`POST /devices/remove`), on sign-out.
    func unregisterPushDevice(token: String) async throws
    /// Which kinds of push notification the user wants.
    func notificationPreferences() async throws -> NotificationPreferences
    /// Saves them and returns what the server stored.
    func saveNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences
    /// Staff: saves a closed Alex chat as an Alex Conversation in Salesforce (feature `assistantHistory`).
    /// Returns its Id.
    @discardableResult
    func saveAssistantConversation(_ conversation: AssistantConversation) async throws -> String
    /// Saved Alex chats on a claim or lead (`recordId`), or the user's own (`recordId` nil), newest first.
    func assistantConversations(recordId: String?) async throws -> [AssistantChatSummary]
    func assistantConversation(id: String) async throws -> AssistantChatDetail
    /// Staff at a company with Alex (feature `assistantChat`): sends the chat so far (the last turn is the user's) and
    /// returns Alex's reply (`POST /assistant/chat`). `recordId` is the claim on screen, if any.
    func assistantChat(messages: [AssistantChatTurn], recordId: String?) async throws -> String
    /// "Did Alex help?" on one of the user's own chats.
    func rateAssistantConversation(id: String, helpful: Bool, reason: AssistantFeedbackReason?) async throws -> AssistantChatSummary
    func postToClaim(claimId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost
    func logCall(claimId: String, _ call: CallLog) async throws
    func sendEmail(claimId: String, _ email: OutgoingEmail) async throws

    // Lead actions (staff)
    func leadStaff(id: String) async throws -> LeadStaff
    func editLead(id: String, _ edit: LeadEdit) async throws
    func leadFeed(leadId: String) async throws -> [ChatterPost]
    func postToLead(leadId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost
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
    /// `fileIds`: files already uploaded to the post's claim or lead (one per reply).
    func addReply(toPost postId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterReply
    /// `POST /chatter/replies/{id}`: edit your own reply.
    func editReply(id: String, text: String, mentions: [Mention]) async throws -> ChatterReply
    /// `GET /feed`: Chatter posts from a staff member's news feed; empty for portal users.
    func feed() async throws -> [FeedPost]

    // Documents (in-house e-sign pilot; a separate Apex REST class, `/portaldocs/v1`)
    /// Active templates for the record's object. Throws `.server(status: 403)` for users without
    /// the pilot permission, which hides the feature.
    func documentTemplates(for record: RecordRef) async throws -> [DocumentTemplate]
    /// Merge the record into the template and return the PDF; `save` also files it on the record.
    func generateDocument(templateId: String, for record: RecordRef, save: Bool) async throws -> GeneratedDocument
    /// Templates with signature places, and signers prefilled from the record for `templateId` (or the first).
    func signingSetup(for record: RecordRef, templateId: String?) async throws -> SigningSetup
    /// Email each signer a personal signing link. Returns the new request id.
    func sendForSignature(templateId: String, signers: [SignerInput], message: String?, for record: RecordRef) async throws -> String
    /// The record's signature requests, newest first.
    func signatureRequests(for record: RecordRef) async throws -> [SignatureRequestSummary]

    // Files [new endpoints]
    /// `GET /files/{contentDocumentId}/content`: the file's bytes, for Quick Look.
    func fileContent(contentDocumentId: String) async throws -> Data
    /// `POST /claims|leads/{id}/files`: multipart upload (`file`, `title`).
    func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile

    // Jobs (Contractor add-on). Declared here, not only in the extension below: a call through `any PortalAPI` uses the
    // extension's empty default unless the protocol itself requires the function.
    func jobs() async throws -> [JobSummary]
    func job(id: String) async throws -> JobDetail
    func jobUpdates(id: String) async throws -> [PortalUpdate]
    func jobFiles(id: String) async throws -> [PortalFile]
    func moveJob(id: String, to stage: String) async throws
}

/// A file ready to upload (already checked and downscaled by `FileUploadRules`).
public struct FileUpload: Hashable, Sendable {
    public let fileName: String
    public let title: String
    public let mimeType: String
    public let data: Data
    /// Staff: the folder to file it in (nil: the top level).
    public var folderId: String?

    public init(fileName: String, title: String, mimeType: String, data: Data, folderId: String? = nil) {
        self.fileName = fileName
        self.title = title
        self.mimeType = mimeType
        self.data = data
        self.folderId = folderId
    }
}

/// `POST /account/deletion-request`.
public struct AccountDeletionRequest: Codable, Hashable, Sendable {
    public let caseId: String?
    /// A request was already open; nothing new was created.
    public let alreadyRequested: Bool

    public init(caseId: String?, alreadyRequested: Bool) {
        self.caseId = caseId
        self.alreadyRequested = alreadyRequested
    }
}

/// `POST /assistant/conversations`: one chat with Alex, saved when it's closed.
public struct AssistantConversation: Codable, Hashable, Sendable {
    public struct Message: Codable, Hashable, Sendable {
        /// "user" or "alex".
        public let role: String
        public let text: String
        public let at: Date?

        public init(role: String, text: String, at: Date?) {
            self.role = role
            self.text = text
            self.at = at
        }

        public var isAlex: Bool { role == "alex" }
    }

    /// The claim or lead the chat was about, if any.
    public let recordId: String?
    public let startedAt: Date
    public let endedAt: Date
    /// e.g. "iOS app 2.3.0 (47)".
    public let source: String
    public let messages: [Message]
    /// "Did Alex help?", when answered as the chat closed.
    public var helpful: Bool?
    public var reason: AssistantFeedbackReason?

    public init(recordId: String?, startedAt: Date, endedAt: Date, source: String, messages: [Message],
                helpful: Bool? = nil, reason: AssistantFeedbackReason? = nil) {
        self.recordId = recordId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.messages = messages
        self.helpful = helpful
        self.reason = reason
    }
}

/// `POST /diagnostics`: at most 5 reports at a time.
public struct DiagnosticsReport: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        /// "App crash" or "App hang".
        public let kind: String
        public let reason: String
        /// MetricKit's JSON, truncated.
        public let details: String

        public init(kind: String, reason: String, details: String) {
            self.kind = kind
            self.reason = reason
            self.details = details
        }
    }

    public let appVersion: String
    public let device: String
    public let reports: [Item]

    public init(appVersion: String, device: String, reports: [Item]) {
        self.appVersion = appVersion
        self.device = device
        self.reports = Array(reports.prefix(5))
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

/// Jobs (the Contractor add-on): only the platform serves them (`ServerMeta.Feature.jobs`), so other servers have none.
public extension PortalAPI {
    func jobs() async throws -> [JobSummary] { [] }
    func job(id: String) async throws -> JobDetail { throw PortalAPIError.notFound }
    func jobUpdates(id: String) async throws -> [PortalUpdate] { [] }
    func jobFiles(id: String) async throws -> [PortalFile] { [] }
    func moveJob(id: String, to stage: String) async throws { throw PortalAPIError.notFound }
}

/// Servers without folders: nothing to list, nothing to change.
public extension PortalAPI {
    func folders(for record: RecordRef) async throws -> [PortalFolder] { [] }
    func createFolder(named name: String, parentId: String?, in record: RecordRef) async throws -> PortalFolder { throw PortalAPIError.notFound }
    func changeFolder(_ id: String, _ change: FolderChange, in record: RecordRef) async throws { throw PortalAPIError.notFound }
    func organizeFiles(_ ids: [String], _ op: FileOrganizeOp, folderId: String?, in record: RecordRef) async throws { throw PortalAPIError.notFound }
}

public extension PortalAPI {
    /// Servers without the Home endpoints: no completed tasks, and open cases cut from the full list.
    func completedTasks() async throws -> [AgendaItem] { [] }
    func waitingSignatures() async throws -> WaitingSignatures { .none }
    func mySettings() async throws -> MySettings { throw PortalAPIError.notFound }
    func saveMySettings(fullName: String, phone: String) async throws { throw PortalAPIError.notFound }
    func saveEmailAlerts(_ on: [String: Bool]) async throws { throw PortalAPIError.notFound }
    func changePassword(current: String, new: String) async throws { throw PortalAPIError.notFound }
    func companySettings() async throws -> CompanySettings { throw PortalAPIError.notFound }
    func saveCompanySetting(_ change: CompanySettingChange) async throws { throw PortalAPIError.notFound }
    func openCases(limit: Int) async throws -> [SupportCase] {
        Array(try await cases().filter { !$0.isClosed }.prefix(limit))
    }
}
