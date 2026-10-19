import Foundation

/// Stores the last good response for each read endpoint.
public protocol ResponseCache: Sendable {
    func store(_ data: Data, for key: String) async
    func load(_ key: String) async -> (data: Data, savedAt: Date)?
    func clear() async
}

/// Files in Caches, encrypted at rest with complete file protection. Only response JSON is
/// stored; never file contents (spec §8).
public actor FileResponseCache: ResponseCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> FileResponseCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return FileResponseCache(directory: caches.appending(path: "PortalCache", directoryHint: .isDirectory))
    }

    public func store(_ data: Data, for key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: key), options: [.atomic, .completeFileProtection])
        } catch {
            // A failed cache write only means less offline data.
        }
    }

    public func load(_ key: String) -> (data: Data, savedAt: Date)? {
        let url = url(for: key)
        guard let data = try? Data(contentsOf: url),
              let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        return (data, savedAt)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for key: String) -> URL {
        // Keys are endpoint paths built from validated ids; make them safe file names anyway.
        let name = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appending(path: name + ".json")
    }
}

/// In-memory cache for tests and previews.
public actor MemoryResponseCache: ResponseCache {
    private var entries: [String: (Data, Date)] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func store(_ data: Data, for key: String) { entries[key] = (data, now()) }
    public func load(_ key: String) -> (data: Data, savedAt: Date)? { entries[key].map { ($0.0, $0.1) } }
    public func clear() { entries = [:] }
}

/// Wraps another `PortalAPI` with a read-only offline cache (spec §7, §8).
///
/// Online, reads go to the network and successful responses are saved. Offline (or when the
/// network call fails as offline), reads return the saved response and report its age; writes
/// throw `.offline` without trying.
public actor CachingPortalAPI: PortalAPI {
    private let base: PortalAPI
    private let cache: ResponseCache
    private var isOnline = true
    /// Called with the save time whenever cached data is shown.
    private let onServedFromCache: @Sendable (Date) async -> Void
    /// Called when the server says the session has expired (401), so the app can sign in again (spec §5).
    private var onSessionExpired: @Sendable () async -> Void = {}

    public init(base: PortalAPI, cache: ResponseCache, onServedFromCache: @escaping @Sendable (Date) async -> Void = { _ in }) {
        self.base = base
        self.cache = cache
        self.onServedFromCache = onServedFromCache
    }

    public func setSessionExpiredHandler(_ handler: @escaping @Sendable () async -> Void) {
        onSessionExpired = handler
    }

    public func setOnline(_ online: Bool) {
        isOnline = online
    }

    public func clearCache() async {
        await cache.clear()
    }

    // MARK: Reads (cached)

    public func claims() async throws -> [ClaimSummary] { try await read("claims") { try await $0.claims() } }
    public func claim(id: String) async throws -> ClaimDetail { try await read("claims/\(id)") { try await $0.claim(id: id) } }
    public func claimPayments(id: String) async throws -> [Payment] { try await read("claims/\(id)/payments") { try await $0.claimPayments(id: id) } }
    public func leads() async throws -> [LeadSummary] { try await read("leads") { try await $0.leads() } }
    public func lead(id: String) async throws -> LeadDetail { try await read("leads/\(id)") { try await $0.lead(id: id) } }
    public func updates(for record: RecordRef) async throws -> [PortalUpdate] {
        try await read("\(record.collectionPath)/\(record.id)/updates") { try await $0.updates(for: record) }
    }
    public func files(for record: RecordRef) async throws -> [PortalFile] {
        try await read("\(record.collectionPath)/\(record.id)/files") { try await $0.files(for: record) }
    }
    public func activity() async throws -> [ActivityItem] { try await read("activity") { try await $0.activity() } }
    public func agenda() async throws -> Agenda { try await read("agenda") { try await $0.agenda() } }

    public func activitySubjects() async throws -> ActivitySubjects {
        try requireOnline()
        return try await guarded { try await $0.activitySubjects() }
    }

    public func taskAssignees() async throws -> [TaskAssignee] {
        try requireOnline()
        return try await guarded { try await $0.taskAssignees() }
    }

    public func createTask(_ task: NewTask, on record: RecordRef) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.createTask(task, on: record) }
    }

    public func createEvent(_ event: NewEvent, on record: RecordRef) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.createEvent(event, on: record) }
    }

    // New Claim is online only, and never cached.
    public func newClaimOptions() async throws -> NewClaimOptions {
        try requireOnline()
        return try await guarded { try await $0.newClaimOptions() }
    }

    public func searchAccounts(_ query: String, commercialOnly: Bool) async throws -> [AccountMatch] {
        try requireOnline()
        return try await guarded { try await $0.searchAccounts(query, commercialOnly: commercialOnly) }
    }

    public func matchingAccounts(firstName: String?, lastName: String, email: String?) async throws -> [AccountMatch] {
        try requireOnline()
        return try await guarded { try await $0.matchingAccounts(firstName: firstName, lastName: lastName, email: email) }
    }

    public func matchingPartnerAccounts(name: String) async throws -> [AccountMatch] {
        try requireOnline()
        return try await guarded { try await $0.matchingPartnerAccounts(name: name) }
    }

    public func searchContacts(_ query: String) async throws -> [ContactMatch] {
        try requireOnline()
        return try await guarded { try await $0.searchContacts(query) }
    }

    public func matchingContacts(firstName: String?, lastName: String, email: String?) async throws -> [ContactMatch] {
        try requireOnline()
        return try await guarded { try await $0.matchingContacts(firstName: firstName, lastName: lastName, email: email) }
    }

    public func createClaim(_ request: NewClaimRequest) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.createClaim(request) }
    }

    public func search(_ query: String, includePeople: Bool) async throws -> [SearchResult] {
        try requireOnline()
        return try await guarded { try await $0.search(query, includePeople: includePeople) }
    }

    // Lead actions are online only and never cached.
    public func leadStaff(id: String) async throws -> LeadStaff {
        try requireOnline()
        return try await guarded { try await $0.leadStaff(id: id) }
    }

    public func editLead(id: String, _ edit: LeadEdit) async throws {
        try requireOnline()
        try await guarded { try await $0.editLead(id: id, edit) }
    }

    public func leadFeed(leadId: String) async throws -> [ChatterPost] {
        try requireOnline()
        return try await guarded { try await $0.leadFeed(leadId: leadId) }
    }

    public func postToLead(leadId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        try requireOnline()
        return try await guarded { try await $0.postToLead(leadId: leadId, text: text, mentions: mentions, fileIds: fileIds) }
    }

    public func convertLead(id: String, account: NewClaimRequest.Account, contact: NewClaimRequest.Contact?) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.convertLead(id: id, account: account, contact: contact) }
    }

    // Claim actions are online only and never cached.
    public func staffClaim(id: String) async throws -> StaffClaim {
        try requireOnline()
        return try await guarded { try await $0.staffClaim(id: id) }
    }

    public func editClaim(id: String, _ edit: ClaimEdit) async throws {
        try requireOnline()
        try await guarded { try await $0.editClaim(id: id, edit) }
    }

    public func updateClaimAddress(id: String, _ address: ClaimAddress) async throws {
        try requireOnline()
        try await guarded { try await $0.updateClaimAddress(id: id, address) }
    }

    public func changeClaimOwner(id: String, ownerId: String) async throws {
        try requireOnline()
        try await guarded { try await $0.changeClaimOwner(id: id, ownerId: ownerId) }
    }

    public func saveProofOfLoss(id: String, _ proofOfLoss: ProofOfLoss) async throws {
        try requireOnline()
        try await guarded { try await $0.saveProofOfLoss(id: id, proofOfLoss) }
    }

    public func paymentSetup(claimId: String) async throws -> PaymentSetup {
        try requireOnline()
        return try await guarded { try await $0.paymentSetup(claimId: claimId) }
    }

    public func applyPayments(claimId: String, _ entry: PaymentEntry) async throws {
        try requireOnline()
        try await guarded { try await $0.applyPayments(claimId: claimId, entry) }
    }

    public func claimContactMatches(claimId: String, firstName: String?, lastName: String, email: String?, mobile: String?) async throws -> [ContactMatch] {
        try requireOnline()
        return try await guarded { try await $0.claimContactMatches(claimId: claimId, firstName: firstName, lastName: lastName, email: email, mobile: mobile) }
    }

    public func addClaimContact(claimId: String, _ contact: NewClaimRequest.Contact) async throws {
        try requireOnline()
        try await guarded { try await $0.addClaimContact(claimId: claimId, contact) }
    }

    public func claimFeed(claimId: String) async throws -> [ChatterPost] {
        try requireOnline()
        return try await guarded { try await $0.claimFeed(claimId: claimId) }
    }

    public func claimActivities(claimId: String) async throws -> [AgendaItem] {
        try requireOnline()
        return try await guarded { try await $0.claimActivities(claimId: claimId) }
    }

    public func postToClaim(claimId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        try requireOnline()
        return try await guarded { try await $0.postToClaim(claimId: claimId, text: text, mentions: mentions, fileIds: fileIds) }
    }

    public func logCall(claimId: String, _ call: CallLog) async throws {
        try requireOnline()
        try await guarded { try await $0.logCall(claimId: claimId, call) }
    }

    public func sendEmail(claimId: String, _ email: OutgoingEmail) async throws {
        try requireOnline()
        try await guarded { try await $0.sendEmail(claimId: claimId, email) }
    }

    // People and Chatter are online only.
    public func person(id: String) async throws -> Person {
        try requireOnline()
        return try await guarded { try await $0.person(id: id) }
    }

    public func personFeed(id: String) async throws -> [ChatterPost] {
        try requireOnline()
        return try await guarded { try await $0.personFeed(id: id) }
    }

    public func mentionCandidates(_ query: String) async throws -> [Mention] {
        try requireOnline()
        return try await guarded { try await $0.mentionCandidates(query) }
    }

    public func addReply(toPost postId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterReply {
        try requireOnline()
        return try await guarded { try await $0.addReply(toPost: postId, text: text, mentions: mentions, fileIds: fileIds) }
    }

    public func editReply(id: String, text: String, mentions: [Mention]) async throws -> ChatterReply {
        try requireOnline()
        return try await guarded { try await $0.editReply(id: id, text: text, mentions: mentions) }
    }

    public func feed() async throws -> [FeedPost] { try await read("feed") { try await $0.feed() } }

    public func cases() async throws -> [SupportCase] { try await read("cases") { try await $0.cases() } }
    public func supportCase(id: String) async throws -> SupportCaseDetail { try await read("cases/\(id)") { try await $0.supportCase(id: id) } }

    // MARK: Online only (not cached, and they only matter while submitting)

    public func insuranceCompanies(matching query: String) async throws -> [InsuranceCompany] {
        try requireOnline()
        return try await guarded { try await $0.insuranceCompanies(matching: query) }
    }

    public func perilValues() async throws -> [String] { try await read("picklists/peril") { try await $0.perilValues() } }

    // MARK: Writes (refused offline)

    public func createLead(_ submission: LeadSubmission) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.createLead(submission) }
    }

    public func addComment(to record: RecordRef, text: String) async throws {
        try requireOnline()
        try await guarded { try await $0.addComment(to: record, text: text) }
    }

    public func markActivityRead(commentIds: [String]) async throws {
        try requireOnline()
        try await guarded { try await $0.markActivityRead(commentIds: commentIds) }
    }

    public func replyToCase(id: String, body: String) async throws {
        try requireOnline()
        try await guarded { try await $0.replyToCase(id: id, body: body) }
    }

    public func requestAssistance(recordId: String, comments: String) async throws -> String {
        try requireOnline()
        return try await guarded { try await $0.requestAssistance(recordId: recordId, comments: comments) }
    }

    // MARK: Files (never cached: spec §8)

    public func fileContent(contentDocumentId: String) async throws -> Data {
        try requireOnline()
        return try await guarded { try await $0.fileContent(contentDocumentId: contentDocumentId) }
    }

    public func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile {
        try requireOnline()
        return try await guarded { try await $0.uploadFile(upload, to: record) }
    }

    // MARK: - Plumbing

    /// Runs a call against the base API, reporting an expired session.
    private func guarded<T: Sendable>(_ call: @Sendable (PortalAPI) async throws -> T) async throws -> T {
        do {
            return try await call(base)
        } catch {
            if PortalAPIError.wrap(error) == .sessionExpired {
                await onSessionExpired()
            }
            throw error
        }
    }

    private func requireOnline() throws {
        guard isOnline else { throw PortalAPIError.offline }
    }

    private func read<T: Codable & Sendable>(_ key: String, _ fetch: @Sendable (PortalAPI) async throws -> T) async throws -> T {
        if isOnline {
            do {
                let value = try await guarded(fetch)
                if let data = try? PortalJSON.makeEncoder().encode(value) {
                    await cache.store(data, for: key)
                }
                return value
            } catch {
                // Only fall back for connectivity failures. A 404 must stay a 404.
                guard PortalAPIError.wrap(error) == .offline else { throw error }
            }
        }

        guard let cached = await cache.load(key),
              let value = try? PortalJSON.makeDecoder().decode(T.self, from: cached.data) else {
            throw PortalAPIError.offline
        }
        await onServedFromCache(cached.savedAt)
        return value
    }
}
