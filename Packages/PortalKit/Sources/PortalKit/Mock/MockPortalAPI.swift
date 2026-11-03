import Foundation

/// Serves the JSON fixtures and keeps writes in memory, so every screen works before the
/// Salesforce REST layer exists (spec §3, "Blocking prerequisite").
public actor MockPortalAPI: PortalAPI {
    public struct Fixtures: Sendable {
        var claims: [ClaimSummary]
        var claimDetails: [String: ClaimDetail]
        var payments: [String: [Payment]]
        var updates: [String: [PortalUpdate]]
        var files: [String: [PortalFile]]
        var leads: [LeadSummary]
        var leadDetails: [String: LeadDetail]
        var activity: [ActivityItem]
        var cases: [SupportCase]
        var caseDetails: [String: SupportCaseDetail]
        var insuranceCompanies: [InsuranceCompany]
        var perils: [String]
        var agenda: Agenda
        var assignees: [TaskAssignee]
        var feed: [FeedPost]
        var accounts: [AccountMatch] = []
        var contacts: [ContactMatch] = []
        var newClaimOptions: NewClaimOptions?
        var people: [String: PeopleFixture] = [:]
        /// Claim actions: edited values, claim feeds and linked contacts, by claim id.
        var staffClaims: [String: StaffClaim] = [:]
        var claimFeeds: [String: [ChatterPost]] = [:]
        var claimContacts: [String: Set<String>] = [:]
        var paymentsApplied: [String: [PaymentEntry]] = [:]
        var callsLogged: [String: [CallLog]] = [:]
        var emailsSent: [String: [OutgoingEmail]] = [:]
        /// Lead actions: edited values, feeds and conversions, by lead id.
        var staffLeads: [String: LeadStaff] = [:]
        var leadFeeds: [String: [ChatterPost]] = [:]

        /// The fixtures bundled with PortalKit.
        public static func bundled() throws -> Fixtures {
            var fixtures = Fixtures(
                claims: try load("claims"),
                claimDetails: try load("claim_details"),
                payments: try load("payments"),
                updates: try load("updates"),
                files: try load("files"),
                leads: try load("leads"),
                leadDetails: try load("lead_details"),
                activity: try load("activity"),
                cases: try load("cases"),
                caseDetails: try load("case_details"),
                insuranceCompanies: try load("insurance_companies"),
                perils: try load("peril"),
                agenda: try load("agenda"),
                assignees: try load("task_assignees"),
                feed: try load("feed")
            )
            fixtures.accounts = try load("new_claim_accounts")
            fixtures.contacts = try load("new_claim_contacts")
            fixtures.newClaimOptions = try load("new_claim_options")
            fixtures.people = try load("people")
            return fixtures
        }

        /// No claims, leads, activity or cases: for empty-state previews and tests.
        public static let empty = Fixtures(
            claims: [], claimDetails: [:], payments: [:], updates: [:], files: [:],
            leads: [], leadDetails: [:], activity: [], cases: [], caseDetails: [:],
            insuranceCompanies: [], perils: [],
            agenda: Agenda(items: [], canCreateTasks: false), assignees: [], feed: []
        )

        public static func load<T: Decodable>(_ name: String) throws -> T {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
                throw PortalAPIError.decoding("Missing fixture \(name).json")
            }
            return try PortalJSON.makeDecoder().decode(T.self, from: Data(contentsOf: url))
        }
    }

    private var data: Fixtures
    private let latency: Duration
    /// When set, every call throws this error. Used for error-state previews and tests.
    private var failure: PortalAPIError?
    private var nextId = 1

    public init(fixtures: Fixtures, latency: Duration = .zero, failure: PortalAPIError? = nil) {
        self.data = fixtures
        self.latency = latency
        self.failure = failure
    }

    /// Mock backed by the bundled fixtures. Crashes only if the package itself is broken.
    public static func standard(latency: Duration = .milliseconds(400)) -> MockPortalAPI {
        // swiftlint:disable:next force_try
        MockPortalAPI(fixtures: try! .bundled(), latency: latency)
    }

    public func setFailure(_ error: PortalAPIError?) {
        failure = error
    }

    // MARK: - Claims

    public func claims() async throws -> [ClaimSummary] {
        try await simulate()
        return data.claims
    }

    public func claim(id: String) async throws -> ClaimDetail {
        try await simulate()
        return try found(data.claimDetails[id])
    }

    public func claimPayments(id: String) async throws -> [Payment] {
        try await simulate()
        try requireClaim(id)
        return data.payments[id] ?? []
    }

    // MARK: - Leads

    public func leads() async throws -> [LeadSummary] {
        try await simulate()
        return data.leads
    }

    public func lead(id: String) async throws -> LeadDetail {
        try await simulate()
        return try found(data.leadDetails[id])
    }

    public func createLead(_ submission: LeadSubmission) async throws -> String {
        try await simulate()
        let name = submission.leadName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContact = !(submission.email ?? "").isEmpty || !(submission.phone ?? "").isEmpty
        guard !name.isEmpty, hasContact else { throw PortalAPIError.invalidRequest }

        let id = makeId(prefix: "a0r")
        let now = Date()
        data.leads.insert(
            LeadSummary(
                recordId: id, recordName: name, prospectStatus: "New",
                lossAddress: [submission.street, submission.city, submission.stateCode, submission.postalCode]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                lossDate: nil, peril: submission.peril,
                claimNumber: submission.didFileClaim == "Yes" ? submission.claimNumber : nil,
                policyNumber: submission.policyNumber, customerEmail: submission.email,
                associatedPartyName: submission.associatedPartyName,
                associatedPartyCompany: submission.associatedPartyCompany,
                associatedPartyEmail: submission.associatedPartyEmail,
                insuranceCompanyName: data.insuranceCompanies.first { $0.id == submission.insuranceCompanyId }?.name,
                adjusterName: nil, accountManagerName: nil, lastModifiedDate: now,
                agreementSentDate: nil, agreementCompletedDate: nil
            ),
            at: 0
        )
        data.leadDetails[id] = LeadDetail(
            prospectName: name, prospectStatus: "New", peril: submission.peril,
            lossAddress: data.leads.first?.lossAddress, email: submission.email, phone: submission.phone,
            mobile: nil, associatedPartyName: submission.associatedPartyName,
            associatedPartyCompany: submission.associatedPartyCompany,
            associatedPartyEmail: submission.associatedPartyEmail,
            associatedPartyPhone: submission.associatedPartyPhone,
            adjusterName: nil, adjusterEmail: nil, adjusterPhone: nil,
            deskAdjusterName: nil, deskAdjusterEmail: nil,
            accountManagerName: nil, accountManagerEmail: nil, accountManagerPhone: nil,
            insuranceCompanyName: data.leads.first?.insuranceCompanyName,
            claimNumber: data.leads.first?.claimNumber, policyNumber: submission.policyNumber,
            didFileClaim: submission.didFileClaim, adjusterFees: nil, lossDate: nil,
            lossDescription: submission.lossDescription, documentsUrl: submission.fileLink,
            createdDate: now, lastModifiedDate: now,
            agreement: Agreement(
                hasAgreement: false, agreementId: nil, agreementName: nil, agreementStatus: nil,
                sentDate: nil, viewedDate: nil, completedDate: nil
            )
        )
        return id
    }

    public func insuranceCompanies(matching query: String) async throws -> [InsuranceCompany] {
        try await simulate()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            data.insuranceCompanies
                .filter { trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed) }
                .prefix(10)
        )
    }

    public func perilValues() async throws -> [String] {
        try await simulate()
        return data.perils
    }

    // MARK: - Shared

    public func updates(for record: RecordRef) async throws -> [PortalUpdate] {
        try await simulate()
        try requireRecord(record)
        return data.updates[record.id] ?? []
    }

    public func files(for record: RecordRef) async throws -> [PortalFile] {
        try await simulate()
        try requireRecord(record)
        return data.files[record.id] ?? []
    }

    public func addComment(to record: RecordRef, text: String) async throws {
        try await simulate()
        try requireRecord(record)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= PortalLimits.commentLength else {
            throw PortalAPIError.invalidRequest
        }

        // Lead comments are published back to the lead's updates feed; claim comments are not (spec §5.2).
        if case .lead(let id) = record {
            let update = PortalUpdate(
                commentId: makeId(prefix: "a1Y"), relatedRecordId: id,
                relatedRecordName: data.leadDetails[id]?.prospectName, createdDate: Date(),
                title: "Customer Comment", text: escapeHTML(text)
            )
            data.updates[id, default: []].insert(update, at: 0)
        }
    }

    // MARK: - Activity

    public func activity() async throws -> [ActivityItem] {
        try await simulate()
        return data.activity
    }

    public func markActivityRead(commentIds: [String]) async throws {
        try await simulate()
        let ids = Set(commentIds)
        for index in data.activity.indices where ids.contains(data.activity[index].commentId) {
            data.activity[index].isRead = true
        }
    }

    // MARK: - Support

    public func cases() async throws -> [SupportCase] {
        try await simulate()
        return data.cases
    }

    public func supportCase(id: String) async throws -> SupportCaseDetail {
        try await simulate()
        return try found(data.caseDetails[id])
    }

    public func cases(for record: RecordRef) async throws -> [SupportCase] {
        try await simulate()
        try requireRecord(record)
        return data.cases.filter { $0.relatedRecordId == record.id }
    }

    public func completeCase(id: String) async throws {
        try await simulate()
        let detail = try found(data.caseDetails[id])
        data.caseDetails[id] = detail.with(status: SupportCase.completedStatus)
        data.cases = data.cases.map { $0.caseId == id ? $0.with(status: SupportCase.completedStatus) : $0 }
    }

    public func replyToCase(id: String, body: String) async throws {
        try await simulate()
        let detail = try found(data.caseDetails[id])
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, body.count <= PortalLimits.caseReplyLength else {
            throw PortalAPIError.invalidRequest
        }

        let comment = CaseComment(
            commentId: makeId(prefix: "00a"), body: trimmed, authorName: "You",
            createdDate: Date(), isOwn: true
        )
        data.caseDetails[id] = detail.appending(comment)
    }

    public func requestAssistance(recordId: String, comments: String) async throws -> String {
        try await simulate()
        guard !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              comments.count <= PortalLimits.assistanceLength else {
            throw PortalAPIError.invalidRequest
        }

        let related: (name: String?, type: RelatedRecordType, stage: String?, manager: String?)
        if let claim = data.claims.first(where: { $0.recordId == recordId }) {
            related = (claim.recordName, .claim, claim.claimStatus, claim.accountManagerName)
        } else if let lead = data.leads.first(where: { $0.recordId == recordId }) {
            related = (lead.recordName, .prospect, nil, lead.accountManagerName)
        } else {
            throw PortalAPIError.notFound
        }

        let id = makeId(prefix: "500")
        let number = String(format: "%08d", 13_000 + nextId)
        let subject = "Assistance Requested - \(related.name ?? "")"
        let now = Date()

        data.cases.insert(
            SupportCase(
                caseId: id, caseNumber: number, subject: subject, description: comments, status: "New",
                createdDate: now, relatedRecordId: recordId, relatedRecordName: related.name,
                relatedRecordType: related.type, relatedRecordStage: related.stage,
                accountManager: related.manager
            ),
            at: 0
        )
        data.caseDetails[id] = SupportCaseDetail(
            caseId: id, caseNumber: number, subject: subject, description: comments, status: "New",
            createdDate: now, relatedRecordId: recordId, relatedRecordName: related.name,
            relatedRecordType: related.type, relatedRecordStage: related.stage,
            accountManager: related.manager, comments: []
        )
        return id
    }

    // MARK: - Agenda and tasks

    public func agenda() async throws -> Agenda {
        try await simulate()
        return data.agenda
    }

    public func activitySubjects() async throws -> ActivitySubjects {
        try await simulate()
        guard data.agenda.canCreateTasks else { throw PortalAPIError.notFound }
        return ActivitySubjects(
            taskSubjects: ["Call - Follow-up on supplement review", "Check - Received from Insurer",
                           "Documents - Requested from insurance company", "Estimate - Estimate sent to Insurance Adjuster",
                           "POL - Proof of Loss received from Client", "Settlement - Full Payment Received"],
            eventSubjects: ["Call", "Email", "Meeting", "Send Letter/Quote", "Other"]
        )
    }

    public func taskAssignees() async throws -> [TaskAssignee] {
        try await simulate()
        guard data.agenda.canCreateTasks else { throw PortalAPIError.notFound }
        return data.assignees
    }

    public func createTask(_ task: NewTask, on record: RecordRef) async throws -> String {
        try await simulate()
        guard data.agenda.canCreateTasks else { throw PortalAPIError.notFound }
        try requireRecord(record)
        guard !task.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let assignee = data.assignees.first(where: { $0.userId == task.assignedToId }) else {
            throw PortalAPIError.invalidRequest
        }
        let id = makeId(prefix: "00T")
        let item = AgendaItem(
            id: id, kind: .task, subject: task.subject, dueDate: task.dueDate, startDateTime: nil,
            endDateTime: nil, isAllDay: nil, location: nil, status: "Not Started", isOverdue: false,
            assignedToName: assignee.name, relatedRecordId: record.id,
            relatedRecordName: recordName(record), relatedRecordType: recordType(record)
        )
        data.agenda = Agenda(items: data.agenda.items + [item], canCreateTasks: true)
        return id
    }

    public func createEvent(_ event: NewEvent, on record: RecordRef) async throws -> String {
        try await simulate()
        guard data.agenda.canCreateTasks else { throw PortalAPIError.notFound }
        try requireRecord(record)
        guard !event.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let assignee = data.assignees.first(where: { $0.userId == event.assignedToId }) else {
            throw PortalAPIError.invalidRequest
        }
        if !event.isAllDay, let start = event.startDateTime, let end = event.endDateTime, end < start {
            throw PortalAPIError.invalidRequest
        }
        let id = makeId(prefix: "00U")
        var start = event.startDateTime
        var end = event.endDateTime
        if event.isAllDay, let date = event.date {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            start = utc.date(from: DateComponents(year: date.year, month: date.month, day: date.day))
            end = start?.addingTimeInterval(86_400)
        }
        let item = AgendaItem(
            id: id, kind: .event, subject: event.subject, dueDate: nil, startDateTime: start, endDateTime: end,
            isAllDay: event.isAllDay, location: event.location, status: nil, isOverdue: false,
            assignedToName: assignee.name, relatedRecordId: record.id,
            relatedRecordName: recordName(record), relatedRecordType: recordType(record)
        )
        data.agenda = Agenda(items: data.agenda.items + [item], canCreateTasks: true)
        return id
    }

    // MARK: - Search and Chatter

    public func search(_ query: String, includePeople: Bool) async throws -> [SearchResult] {
        try await simulate()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        func matches(_ values: String?...) -> Bool {
            values.compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        let claims = data.claims.filter { matches($0.recordName, $0.claimNumber, $0.lossAddress, $0.policyNumber) }.map {
            SearchResult(type: .claim, id: $0.recordId, title: $0.recordName,
                         subtitle: [$0.claimNumber, $0.claimStatus].compactMap { $0 }.joined(separator: " · "))
        }
        let leads = data.leads.filter { matches($0.recordName, $0.claimNumber, $0.lossAddress, $0.customerEmail) }.map {
            SearchResult(type: .prospect, id: $0.recordId, title: $0.recordName,
                         subtitle: [$0.prospectStatus, $0.peril].compactMap { $0 }.joined(separator: " · "))
        }
        let cases = data.cases.filter { matches($0.subject, $0.caseNumber, $0.relatedRecordName) }.map {
            SearchResult(type: .supportCase, id: $0.caseId, title: $0.subject,
                         subtitle: ["Case \($0.caseNumber ?? "")", $0.status ?? ""].joined(separator: " · "))
        }
        let people = !includePeople ? [] : data.people.values.map(\.person).filter { matches($0.name) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
            .map { SearchResult(type: .user, id: $0.id, title: $0.name,
                                subtitle: [$0.title, $0.department].compactMap { $0 }.joined(separator: " · ")) }
        return claims + leads + cases + people
    }

    public func person(id: String) async throws -> Person {
        try await simulate()
        return try found(data.people[id]?.person)
    }

    public func personFeed(id: String) async throws -> [ChatterPost] {
        try await simulate()
        return try found(data.people[id]).feed
    }

    public func mentionCandidates(_ query: String) async throws -> [Mention] {
        try await simulate()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return (data.newClaimOptions?.users ?? [])
            .filter { $0.name.lowercased().hasPrefix(q.lowercased()) || $0.name.lowercased().contains(" " + q.lowercased()) }
            .map { Mention(id: $0.userId, name: $0.name) }
    }

    /// The mentions whose "@Name" is in the text, as the server would record them.
    private func mentionNames(_ text: String, _ mentions: [Mention]) -> [String]? {
        let names = mentions.filter { text.contains("@" + $0.name) }.map(\.name)
        return names.isEmpty ? nil : names
    }

    public func addReply(toPost postId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterReply {
        try await simulate()
        // As the server: one file per reply; the text may be empty with a file (the file's name is used).
        guard fileIds.count <= 1 else { throw PortalAPIError.invalidRequest }
        let attachments = try uploadedAttachments(fileIds)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { throw PortalAPIError.invalidRequest }
        let reply = ChatterReply(id: makeId(prefix: "0D7"), authorName: "Alex Smith", text: trimmed.isEmpty ? attachments[0].title : text,
                                 createdDate: Date(), isMine: true, mentions: mentionNames(text, mentions), attachments: attachments)
        // Claim and lead feeds, then people's profile feeds.
        for (claimId, var feed) in data.claimFeeds {
            if let index = feed.firstIndex(where: { $0.id == postId }) {
                feed[index].replies.append(reply)
                feed[index].totalReplies = (feed[index].totalReplies ?? 0) + 1
                data.claimFeeds[claimId] = feed
                return reply
            }
        }
        for (leadId, var feed) in data.leadFeeds {
            if let index = feed.firstIndex(where: { $0.id == postId }) {
                feed[index].replies.append(reply)
                feed[index].totalReplies = (feed[index].totalReplies ?? 0) + 1
                data.leadFeeds[leadId] = feed
                return reply
            }
        }
        for (userId, var fixture) in data.people {
            if let index = fixture.feed.firstIndex(where: { $0.id == postId }) {
                fixture.feed[index].replies.append(reply)
                fixture.feed[index].totalReplies = (fixture.feed[index].totalReplies ?? 0) + 1
                data.people[userId] = fixture
                return reply
            }
        }
        throw PortalAPIError.notFound
    }

    public func editReply(id: String, text: String, mentions: [Mention]) async throws -> ChatterReply {
        try await simulate()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PortalAPIError.invalidRequest }
        for (userId, var fixture) in data.people {
            for p in fixture.feed.indices {
                if let r = fixture.feed[p].replies.firstIndex(where: { $0.id == id }) {
                    // As in Chatter: only your own replies.
                    guard fixture.feed[p].replies[r].isMine == true else { throw PortalAPIError.invalidRequest }
                    fixture.feed[p].replies[r].text = text
                    fixture.feed[p].replies[r].mentions = mentionNames(text, mentions)
                    data.people[userId] = fixture
                    return fixture.feed[p].replies[r]
                }
            }
        }
        throw PortalAPIError.notFound
    }

    public func feed() async throws -> [FeedPost] {
        try await simulate()
        return data.feed
    }

    // MARK: - Files

    private var fileContents: [String: Data] = [:]

    public func fileContent(contentDocumentId: String) async throws -> Data {
        try await simulate()
        guard data.files.values.contains(where: { $0.contains { $0.contentDocumentId == contentDocumentId } }) else {
            throw PortalAPIError.notFound
        }
        // Uploaded files come back as uploaded; fixture files are a small sample PDF.
        return fileContents[contentDocumentId] ?? Self.samplePDF
    }

    private var deletionRequested = false
    private var pushPreferences = NotificationPreferences()
    public private(set) var diagnosticsReceived: [DiagnosticsReport.Item] = []
    public private(set) var assistantConversations: [AssistantConversation] = []

    /// Claim and lead activity, seeded on first view (by record id).
    private var activityStore: [String: [AgendaItem]] = [:]

    /// Files uploaded to a claim or lead, as attachments; anything else is refused, as on the server.
    private func uploadedAttachments(_ fileIds: [String]) throws -> [ChatterAttachment] {
        try fileIds.map { id in
            guard let file = data.files.values.lazy.flatMap({ $0 }).first(where: { $0.contentDocumentId == id }) else {
                throw PortalAPIError.invalidRequest
            }
            return ChatterAttachment(file)
        }
    }

    public func uploadFile(_ upload: FileUpload, to record: RecordRef) async throws -> PortalFile {
        try await simulate()
        try requireRecord(record)
        let file = PortalFile(
            contentDocumentId: makeId(prefix: "069"),
            title: upload.title,
            fileType: FileUploadRules.fileExtension(of: upload.fileName).uppercased(),
            contentSize: upload.data.count,
            createdDate: Date(),
            createdByName: "You"
        )
        data.files[record.id, default: []].insert(file, at: 0)
        fileContents[file.contentDocumentId] = upload.data
        return file
    }

    /// A one-page PDF that says "Sample document".
    static let samplePDF = Data("""
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj
    4 0 obj << /Length 52 >> stream
    BT /F1 24 Tf 72 700 Td (Sample document) Tj ET
    endstream endobj
    5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
    trailer << /Root 1 0 R >>
    %%EOF
    """.utf8)

    // MARK: - Helpers

    // MARK: - Documents (pilot)

    public func documentTemplates(for record: RecordRef) async throws -> [DocumentTemplate] {
        try await simulate()
        switch record {
        case .lead:
            return [DocumentTemplate(id: "a0zDEMO0000000001", name: "PA - GA LOR Contract", objectName: "Prospects__c",
                                     category: "Agreement_LOR", signerCount: 2)]
        case .claim:
            return [DocumentTemplate(id: "a0zDEMO0000000002", name: "Sworn Proof of Loss", objectName: "Claims2__c",
                                     category: "Proof_of_Loss", signerCount: 1)]
        }
    }

    public func generateDocument(templateId: String, for record: RecordRef, save: Bool) async throws -> GeneratedDocument {
        try await simulate()
        guard let url = Bundle.module.url(forResource: "sample_document", withExtension: "pdf", subdirectory: "Fixtures"),
              let pdf = try? Data(contentsOf: url) else {
            throw PortalAPIError.notFound
        }
        let name = try await documentTemplates(for: record).first { $0.id == templateId }?.name ?? "Document"
        return GeneratedDocument(title: "\(name) - Demo", pageCount: 3, pdfBase64: pdf.base64EncodedString(),
                                 contentDocumentId: save ? "069DEMO000000001" : nil)
    }

    private var sentRequests: [String: [SignatureRequestSummary]] = [:]

    public func signingSetup(for record: RecordRef, templateId: String?) async throws -> SigningSetup {
        try await simulate()
        let templates = try await documentTemplates(for: record).filter { $0.signerCount > 0 }
        let chosen = templateId ?? templates.first?.id
        let signers: [SignerInput]
        switch record {
        case .lead:
            signers = [SignerInput(index: 1, label: "Public Adjuster", name: "Alex Smith", email: "alex.smith@example.com"),
                       SignerInput(index: 2, label: "Insured", name: "Jordan Lee", email: "jordan.lee@example.com")]
        case .claim:
            signers = [SignerInput(index: 1, label: "Insured", name: "Jordan Lee", email: "jordan.lee@example.com")]
        }
        return SigningSetup(templates: templates, signers: chosen == nil ? [] : signers, templateId: chosen)
    }

    public func sendForSignature(templateId: String, signers: [SignerInput], message: String?, for record: RecordRef) async throws -> String {
        try await simulate()
        guard !signers.isEmpty, signers.allSatisfy(\.isComplete) else {
            throw PortalAPIError.rejected("Enter a name and valid email for every signer.")
        }
        let name = try await documentTemplates(for: record).first { $0.id == templateId }?.name ?? "Document"
        let id = "a3xDEMO\(sentRequests[record.id, default: []].count + 1)"
        let summary = SignatureRequestSummary(
            id: id, name: "SR-DEMO", subject: "\(name) - Demo", status: "Sent", source: "In-house", sentAt: Date(),
            completedAt: nil, expiresAt: Date().addingTimeInterval(14 * 86_400), lastError: nil,
            signers: signers.map { .init(index: $0.index, name: $0.name, email: $0.email, status: "Sent", signedAt: nil) })
        sentRequests[record.id, default: []].insert(summary, at: 0)
        return id
    }

    public func signatureRequests(for record: RecordRef) async throws -> [SignatureRequestSummary] {
        try await simulate()
        return sentRequests[record.id] ?? []
    }

    private func simulate() async throws {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        if let failure {
            throw failure
        }
    }

    private func found<T>(_ value: T?) throws -> T {
        guard let value else { throw PortalAPIError.notFound }
        return value
    }

    private func requireClaim(_ id: String) throws {
        guard data.claimDetails[id] != nil else { throw PortalAPIError.notFound }
    }

    private func requireRecord(_ record: RecordRef) throws {
        switch record {
        case .claim(let id): try requireClaim(id)
        case .lead(let id): guard data.leadDetails[id] != nil else { throw PortalAPIError.notFound }
        }
    }

    // MARK: - New Claim

    public func newClaimOptions() async throws -> NewClaimOptions {
        try await simulate()
        // Staff only, like the server (the demo user is staff).
        guard let options = data.newClaimOptions else { throw PortalAPIError.notFound }
        return options
    }

    public func searchAccounts(_ query: String, commercialOnly: Bool) async throws -> [AccountMatch] {
        try await simulate()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return data.accounts.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q) && (!commercialOnly || $0.kind == "Business")
        }
    }

    public func matchingAccounts(firstName: String?, lastName: String, email: String?) async throws -> [AccountMatch] {
        try await simulate()
        return personMatches(firstName: firstName, lastName: lastName, email: email)
    }

    public func matchingPartnerAccounts(name: String) async throws -> [AccountMatch] {
        try await simulate()
        return partnerMatches(name)
    }

    public func searchContacts(_ query: String) async throws -> [ContactMatch] {
        try await simulate()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return data.contacts.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q) || ($0.email ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    public func matchingContacts(firstName: String?, lastName: String, email: String?) async throws -> [ContactMatch] {
        try await simulate()
        return contactMatches(firstName: firstName, lastName: lastName, email: email)
    }

    /// Mirrors the server: duplicates are refused, and everything is created together or not at all.
    public func createClaim(_ request: NewClaimRequest) async throws -> String {
        try await simulate()
        guard data.newClaimOptions != nil else { throw PortalAPIError.notFound }
        guard !request.claim.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PortalAPIError.invalidRequest }

        var newAccount: AccountMatch?
        switch request.account {
        case .existing(let id):
            guard data.accounts.contains(where: { $0.id == id }) else { throw PortalAPIError.invalidRequest }
        case .new(let details):
            let matches = personMatches(firstName: details.firstName, lastName: details.lastName, email: details.email)
            if !matches.isEmpty { throw PortalAPIError.duplicate(DuplicateMatches(kind: .account, accounts: matches)) }
            let name = [details.firstName, details.lastName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " ")
            newAccount = AccountMatch(id: makeId(prefix: "001"), name: name, email: details.email, phone: details.phone,
                                      city: request.claim.city, state: request.claim.state, kind: "Person")
        }

        var newPartner: AccountMatch?
        var newContact: ContactMatch?
        if case .new(let details, _, let partner) = request.contact {
            if case .new(let name) = partner {
                let matches = partnerMatches(name)
                if !matches.isEmpty { throw PortalAPIError.duplicate(DuplicateMatches(kind: .partnerAccount, accounts: matches)) }
                newPartner = AccountMatch(id: makeId(prefix: "001"), name: name, kind: "Business")
            }
            // The mock's "duplicate rule": same email.
            if let email = PortalFormat.nonEmpty(details.email),
               case let duplicates = data.contacts.filter({ $0.email?.caseInsensitiveCompare(email) == .orderedSame }),
               !duplicates.isEmpty {
                throw PortalAPIError.duplicate(DuplicateMatches(kind: .contact, contacts: duplicates))
            }
            let name = [details.firstName, details.lastName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " ")
            newContact = ContactMatch(id: makeId(prefix: "003"), name: name, email: details.email, phone: details.phone, accountName: details.company)
        }

        if let newAccount { data.accounts.append(newAccount) }
        if let newPartner { data.accounts.append(newPartner) }
        if let newContact { data.contacts.append(newContact) }

        let id = makeId(prefix: "a23")
        let c = request.claim
        let address = [c.street, [c.city, [c.state, c.postalCode].compactMap { $0 }.joined(separator: " ")].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: ", ")]
            .compactMap { PortalFormat.nonEmpty($0) }.joined(separator: ", ")
        let adjuster = data.newClaimOptions?.users.first { $0.userId == (c.ownerId ?? data.newClaimOptions?.currentUserId) }?.name
        let fields: [String: Any?] = [
            "recordId": id, "recordName": c.name, "claimName": c.name, "claimNumber": c.claimNumber,
            "policyNumber": c.policyNumber, "claimStatus": "Preparation", "peril": c.peril,
            "lossAddress": address.isEmpty ? nil : address, "lossReason": c.lossDescription,
            "lossDescription": c.lossDescription, "email": c.email, "mainPhone": c.phone,
            "adjusterName": adjuster, "lastModifiedDate": ISO8601DateFormatter().string(from: Date()),
            "lossDate": c.lossDate.map { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) }
        ]
        let json = try JSONSerialization.data(withJSONObject: fields.compactMapValues { $0 })
        let decoder = PortalJSON.makeDecoder()
        data.claims.append(try decoder.decode(ClaimSummary.self, from: json))
        data.claimDetails[id] = try decoder.decode(ClaimDetail.self, from: json)
        return id
    }

    private func personMatches(firstName: String?, lastName: String, email: String?) -> [AccountMatch] {
        let fullName = [firstName, lastName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " ")
        return data.accounts.filter { account in
            guard account.kind == "Person" else { return false }
            if let email = PortalFormat.nonEmpty(email), account.email?.caseInsensitiveCompare(email) == .orderedSame { return true }
            return !lastName.isEmpty && account.name?.caseInsensitiveCompare(fullName) == .orderedSame
        }
    }

    private func partnerMatches(_ name: String) -> [AccountMatch] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return data.accounts.filter { $0.kind == "Business" && $0.name?.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func contactMatches(firstName: String?, lastName: String, email: String?) -> [ContactMatch] {
        let fullName = [firstName, lastName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " ")
        return data.contacts.filter { contact in
            if let email = PortalFormat.nonEmpty(email), contact.email?.caseInsensitiveCompare(email) == .orderedSame { return true }
            return !lastName.isEmpty && contact.name?.caseInsensitiveCompare(fullName) == .orderedSame
        }
    }

    // MARK: - Claim actions

    private func staff(_ id: String) throws -> StaffClaim {
        guard data.newClaimOptions != nil else { throw PortalAPIError.notFound }
        if let existing = data.staffClaims[id] { return existing }
        guard let detail = data.claimDetails[id] else { throw PortalAPIError.notFound }
        var pol = ProofOfLoss()
        pol.lossDate = detail.lossDate
        pol.policyNumber = detail.policyNumber
        let address = (detail.lossAddress ?? "").components(separatedBy: ", ")
        let options = data.newClaimOptions
        let recipients = [detail.email.map { ValueOption(value: $0, label: "Claim email <\($0)>") }].compactMap { $0 }
        let claim = StaffClaim(
            id: id, name: detail.claimName, status: detail.claimStatus, peril: detail.peril, lossDate: detail.lossDate,
            lossDescription: detail.lossDescription, claimNumber: detail.claimNumber, policyNumber: detail.policyNumber,
            insuranceCompanyId: nil, insuranceCompanyName: detail.insuranceCompanyName,
            deductible: detail.deductible, adjusterFees: detail.adjusterFees, accountManagerId: nil,
            ownerId: options?.currentUserId, ownerName: detail.adjusterName,
            street: address.first, city: address.count > 1 ? address[1] : nil,
            state: address.count > 2 ? String(address[2].prefix(2)) : nil,
            postalCode: address.count > 2 ? address[2].split(separator: " ").last.map(String.init) : nil,
            proofOfLoss: pol, statuses: ClaimLifecycle.stages, perils: options?.perils ?? [], states: options?.states ?? [],
            occupancyValues: ["Occupied", "Vacant"], primaryHomeValues: ["Primary", "Rental"],
            contactRoles: options?.contactRoles ?? [], users: options?.users ?? [],
            emailRecipients: recipients,
            fromAddresses: [ValueOption(value: nil, label: "Alex Smith <alex.smith@example.com>"),
                            ValueOption(value: "0D2000000000001AAA", label: "Accurate Adjustments GA <claims@example.com>")],
            contacts: data.contacts.prefix(2).map { ValueOption(value: $0.id, label: $0.name ?? "Contact") }
        )
        data.staffClaims[id] = claim
        return claim
    }

    public func staffClaim(id: String) async throws -> StaffClaim {
        try await simulate()
        return try staff(id)
    }

    public func editClaim(id: String, _ edit: ClaimEdit) async throws {
        try await simulate()
        var claim = try staff(id)
        guard !edit.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PortalAPIError.invalidRequest }
        if let fees = edit.adjusterFees, fees > 100 { throw PortalAPIError.invalidRequest }
        // The org's Required_for_Inspection rule.
        if edit.status == "Inspection" && (edit.deductible == nil || edit.adjusterFees == nil) {
            throw PortalAPIError.rejected("Required fields for this stage haven’t been updated. Please update Deductible and/or Adjuster Fees to continue.")
        }
        claim.name = edit.name
        claim.status = edit.status
        claim.peril = edit.peril
        claim.lossDate = edit.lossDate
        claim.lossDescription = edit.lossDescription
        claim.claimNumber = edit.claimNumber
        claim.policyNumber = edit.policyNumber
        claim.insuranceCompanyId = edit.insuranceCompanyId
        claim.deductible = edit.deductible
        claim.adjusterFees = edit.adjusterFees
        claim.accountManagerId = edit.accountManagerId
        data.staffClaims[id] = claim
        try patchDetail(id) { fields in
            fields["claimName"] = edit.name
            fields["claimStatus"] = edit.status
            fields["peril"] = edit.peril
            fields["claimNumber"] = edit.claimNumber
            fields["policyNumber"] = edit.policyNumber
            fields["deductible"] = edit.deductible.map { NSDecimalNumber(decimal: $0) }
            fields["adjusterFees"] = edit.adjusterFees.map { NSDecimalNumber(decimal: $0) }
        }
    }

    public func updateClaimAddress(id: String, _ address: ClaimAddress) async throws {
        try await simulate()
        var claim = try staff(id)
        claim.street = address.street
        claim.city = address.city
        claim.state = address.state
        claim.postalCode = address.postalCode
        data.staffClaims[id] = claim
        let line = [address.street, address.city, [address.state, address.postalCode].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        try patchDetail(id) { $0["lossAddress"] = line.isEmpty ? nil : line }
    }

    public func changeClaimOwner(id: String, ownerId: String) async throws {
        try await simulate()
        var claim = try staff(id)
        guard let user = claim.users.first(where: { $0.userId == ownerId }) else { throw PortalAPIError.invalidRequest }
        claim.ownerId = user.userId
        claim.ownerName = user.name
        data.staffClaims[id] = claim
        try patchDetail(id) { $0["adjusterName"] = user.name }
    }

    public func saveProofOfLoss(id: String, _ proofOfLoss: ProofOfLoss) async throws {
        try await simulate()
        var claim = try staff(id)
        if let start = proofOfLoss.policyEffectiveDate, let end = proofOfLoss.policyExpirationDate,
           (end.year, end.month, end.day) < (start.year, start.month, start.day) {
            throw PortalAPIError.rejected("The policy expiration date must be after the effective date.")
        }
        claim.proofOfLoss = proofOfLoss
        data.staffClaims[id] = claim
    }

    public func paymentSetup(claimId: String) async throws -> PaymentSetup {
        try await simulate()
        let claim = try staff(claimId)
        return PaymentSetup(
            claimName: claim.name, deductible: claim.deductible, adjusterFees: claim.adjusterFees,
            lifetimePaymentsReceived: data.claimDetails[claimId]?.paymentCollected,
            paymentTypes: ["Additional Payments", "Deductible", "NET Payment (ACV)", "Replacement Cash Value (RCV)"]
        )
    }

    public func applyPayments(claimId: String, _ entry: PaymentEntry) async throws {
        try await simulate()
        let claim = try staff(claimId)
        guard let deductible = claim.deductible, deductible > 0 else {
            throw PortalAPIError.rejected("Please add the Deductible on this claim before using the payment calculator.")
        }
        guard !entry.rows.isEmpty else { throw PortalAPIError.invalidRequest }
        if entry.applyDeductible && entry.rows.contains(where: { $0.rowType == "Deductible" }) {
            throw PortalAPIError.rejected("Deductible cannot be added as a row when Apply deductible is on.")
        }
        data.paymentsApplied[claimId, default: []].append(entry)
    }

    public func claimContactMatches(claimId: String, firstName: String?, lastName: String, email: String?, mobile: String?) async throws -> [ContactMatch] {
        try await simulate()
        _ = try staff(claimId)
        var matches = contactMatches(firstName: firstName, lastName: lastName, email: email)
        if let mobile = PortalFormat.nonEmpty(mobile) {
            let digits = mobile.filter(\.isNumber)
            for contact in data.contacts where (contact.phone ?? "").filter(\.isNumber) == digits && !matches.contains(contact) {
                matches.append(contact)
            }
        }
        return matches
    }

    public func addClaimContact(claimId: String, _ contact: NewClaimRequest.Contact) async throws {
        try await simulate()
        _ = try staff(claimId)
        let contactId: String
        switch contact {
        case .existing(let id, _):
            contactId = id
        case .new(let details, _, let partner):
            if case .new(let name) = partner, !partnerMatches(name).isEmpty {
                throw PortalAPIError.duplicate(DuplicateMatches(kind: .partnerAccount, accounts: partnerMatches(name)))
            }
            if let email = PortalFormat.nonEmpty(details.email),
               case let duplicates = data.contacts.filter({ $0.email?.caseInsensitiveCompare(email) == .orderedSame }),
               !duplicates.isEmpty {
                throw PortalAPIError.duplicate(DuplicateMatches(kind: .contact, contacts: duplicates))
            }
            let name = [details.firstName, details.lastName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " ")
            let created = ContactMatch(id: makeId(prefix: "003"), name: name, email: details.email, phone: details.phone, accountName: details.company)
            data.contacts.append(created)
            contactId = created.id
        }
        guard !(data.claimContacts[claimId]?.contains(contactId) ?? false) else {
            throw PortalAPIError.rejected("This contact is already on the claim.")
        }
        data.claimContacts[claimId, default: []].insert(contactId)
    }

    public func claimFeed(claimId: String) async throws -> [ChatterPost] {
        try await simulate()
        _ = try staff(claimId)
        if let feed = data.claimFeeds[claimId] { return feed }
        // The first post carries the claim's first file, to show attachments.
        let firstFile = data.files[claimId]?.first.map(ChatterAttachment.init)
        let seeded = data.feed.filter { $0.parentId == claimId }.enumerated().map { index, item in
            ChatterPost(id: item.id, authorName: item.authorName, text: item.text, createdDate: item.createdDate,
                        parentName: nil, replies: [], totalReplies: 0,
                        attachments: index == 0 ? firstFile.map { [$0] } : nil)
        }
        data.claimFeeds[claimId] = seeded
        return seeded
    }

    public func activities(on record: RecordRef, includeEmails: Bool) async throws -> [AgendaItem] {
        try await simulate()
        switch record {
        case .claim(let id): _ = try staff(id)
        case .lead(let id): _ = try staffLead(id)
        }
        let recordId = record.id
        // Seeded once, so edits stick; new tasks and events (in the agenda) and logged calls join it.
        if activityStore[recordId] == nil {
            activityStore[recordId] = seededHistory(for: record)
        }
        let stored = activityStore[recordId] ?? []
        let known = Set(stored.map(\.id))
        let open = data.agenda.items.filter { $0.relatedRecordId == recordId && !known.contains($0.id) }.map { item -> AgendaItem in
            var item = item
            item.isClosed = false
            item.subtype = item.kind == .task ? "Task" : nil
            item.createdByName = item.assignedToName
            item.assignedToId = data.assignees.first { $0.name == item.assignedToName }?.userId
            return item
        }
        activityStore[recordId] = open + stored
        let calls = (data.callsLogged[recordId] ?? []).enumerated().reversed().map { index, call in
            pastTask("00Tcall\(recordId.suffix(4))\(index)", call.subject, subtype: "Call", daysAgo: 0, description: call.description, record: record)
        }
        let all = (activityStore[recordId] ?? []) + calls
        let sorted = all.filter { $0.isClosed != true } + all.filter { $0.isClosed == true }
        guard includeEmails else { return sorted }
        return sorted + seededEmails(for: record)
    }

    public func editActivity(id: String, _ edit: ActivityEdit) async throws -> AgendaItem {
        try await simulate()
        guard let (recordId, index) = activityStore.lazy.compactMap({ key, items in items.firstIndex { $0.id == id }.map { (key, $0) } }).first,
              var item = activityStore[recordId]?[index] else { throw PortalAPIError.notFound }
        if let subject = edit.subject {
            guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else { throw PortalAPIError.invalidRequest }
            item.subject = subject
        }
        if let status = edit.status { item.status = status; item.isClosed = status == "Completed" }
        if let priority = edit.priority { item.priority = priority }
        if edit.changesDueDate { item.dueDate = edit.dueDate }
        if let description = edit.description { item.description = description.isEmpty ? nil : description }
        if let location = edit.location { item.location = location.isEmpty ? nil : location }
        if let start = edit.startDateTime { item.startDateTime = start }
        if let end = edit.endDateTime { item.endDateTime = end }
        if let assigneeId = edit.assignedToId {
            guard let assignee = data.assignees.first(where: { $0.userId == assigneeId }) else {
                throw PortalAPIError.rejected("Choose someone tasks can be assigned to.")
            }
            item.assignedToId = assignee.userId
            item.assignedToName = assignee.name
        }
        item.isOverdue = item.kind == .task && item.isClosed != true && (item.dueDate.map { $0 < CalendarDate.today } ?? false)
        activityStore[recordId]?[index] = item
        return item
    }

    public func completeTask(id: String) async throws -> AgendaItem {
        var edit = ActivityEdit()
        edit.status = "Completed"
        guard activityStore.values.contains(where: { $0.contains { $0.id == id && $0.kind == .task } }) else {
            throw PortalAPIError.notFound
        }
        return try await editActivity(id: id, edit)
    }

    public func activityOptions() async throws -> ActivityOptions {
        try await simulate()
        return ActivityOptions(taskStatuses: ["Not Started", "Working", "Completed"], taskPriorities: ["High", "Normal"])
    }

    public func requestAccountDeletion(reason: String?) async throws -> AccountDeletionRequest {
        try await simulate()
        defer { deletionRequested = true }
        return AccountDeletionRequest(caseId: "500000000000099AAA", alreadyRequested: deletionRequested)
    }

    public func sendDiagnostics(_ report: DiagnosticsReport) async throws {
        try await simulate()
        diagnosticsReceived.append(contentsOf: report.reports)
    }

    public func serverMeta() async throws -> ServerMeta {
        try await simulate()
        return .all
    }

    public func notificationPreferences() async throws -> NotificationPreferences {
        try await simulate()
        return pushPreferences
    }

    public func saveNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        try await simulate()
        pushPreferences = preferences
        return preferences
    }

    public func saveAssistantConversation(_ conversation: AssistantConversation) async throws {
        try await simulate()
        assistantConversations.append(conversation)
    }

    private func pastTask(_ id: String, _ subject: String, subtype: String, daysAgo: Int, description: String?, record: RecordRef) -> AgendaItem {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var item = AgendaItem(
            id: id, kind: .task, subject: subject, dueDate: CalendarDate(year: parts.year!, month: parts.month!, day: parts.day!),
            startDateTime: nil, endDateTime: nil, isAllDay: nil, location: nil, status: "Completed", isOverdue: false,
            assignedToName: "Alex Smith", relatedRecordId: record.id, relatedRecordName: recordName(record), relatedRecordType: recordType(record)
        )
        item.description = description
        item.subtype = subtype
        item.isClosed = true
        item.priority = "Normal"
        item.createdDate = day
        item.createdByName = "Alex Smith"
        item.assignedToId = data.assignees.first { $0.name == "Alex Smith" }?.userId
        return item
    }

    private func seededHistory(for record: RecordRef) -> [AgendaItem] {
        let suffix = record.id.suffix(4)
        switch record {
        case .claim:
            return [
                pastTask("00Thist\(suffix)1", "Documents - Requested from insurance company", subtype: "Task", daysAgo: 3,
                         description: "Asked the carrier for the full policy and the field adjuster's estimate.", record: record),
                pastTask("00Thist\(suffix)2", "Call - Initial contact with homeowner", subtype: "Call", daysAgo: 7,
                         description: "Walked through the claims process and booked the inspection.", record: record),
            ]
        case .lead:
            return [
                pastTask("00Thist\(suffix)1", "Call - Intro call with the homeowner", subtype: "Call", daysAgo: 2,
                         description: "Explained how we work and sent the agreement.", record: record),
            ]
        }
    }

    private func seededEmails(for record: RecordRef) -> [AgendaItem] {
        let sent = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var email = AgendaItem(
            id: "02s\(record.id.suffix(12))1", kind: .email, subject: "RE: Estimate for \(recordName(record) ?? "your claim")", dueDate: nil,
            startDateTime: sent, endDateTime: nil, isAllDay: nil, location: nil, status: nil, isOverdue: false,
            assignedToName: nil, relatedRecordId: record.id, relatedRecordName: recordName(record), relatedRecordType: recordType(record)
        )
        email.fromName = "Pat Carrier"
        email.fromAddress = "pat.carrier@example.com"
        email.toAddress = "claims@example.com"
        email.isIncoming = true
        email.hasAttachment = true
        email.isClosed = true
        email.createdDate = sent
        email.description = "Thanks for sending the estimate. We'll review it this week and come back to you with any questions."
        return [email]
    }

    public func postToClaim(claimId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        let existing = try await claimFeed(claimId: claimId)
        let attachments = try uploadedAttachments(fileIds)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { throw PortalAPIError.invalidRequest }
        let post = ChatterPost(id: makeId(prefix: "0D5"), authorName: "Alex Smith", text: trimmed.isEmpty ? attachments[0].title : text,
                               createdDate: Date(), parentName: nil, replies: [], totalReplies: 0, mentions: mentionNames(text, mentions),
                               attachments: attachments)
        data.claimFeeds[claimId] = [post] + existing
        return post
    }

    public func logCall(claimId: String, _ call: CallLog) async throws {
        try await simulate()
        _ = try staff(claimId)
        guard !call.subject.trimmingCharacters(in: .whitespaces).isEmpty else { throw PortalAPIError.invalidRequest }
        data.callsLogged[claimId, default: []].append(call)
    }

    public func sendEmail(claimId: String, _ email: OutgoingEmail) async throws {
        try await simulate()
        _ = try staff(claimId)
        guard !email.to.isEmpty, !email.subject.isEmpty, !email.body.isEmpty else { throw PortalAPIError.invalidRequest }
        data.emailsSent[claimId, default: []].append(email)
    }

    // MARK: - Lead actions

    private func staffLead(_ id: String) throws -> LeadStaff {
        guard let options = data.newClaimOptions else { throw PortalAPIError.notFound }
        if let existing = data.staffLeads[id] { return existing }
        guard let detail = data.leadDetails[id] else { throw PortalAPIError.notFound }
        // "88 Peachtree Rd\nAtlanta, GA, 30305"
        let lines = (detail.lossAddress ?? "").components(separatedBy: "\n")
        let place = lines.count > 1 ? lines[1].components(separatedBy: ", ") : []
        let names = (detail.prospectName ?? "").split(separator: " ").map(String.init)
        let lead = LeadStaff(
            id: id, name: detail.prospectName, status: detail.prospectStatus, peril: detail.peril,
            lossDate: detail.lossDate, lossDescription: detail.lossDescription,
            street: lines.first.flatMap { $0.isEmpty ? nil : $0 }, city: place.first,
            state: place.count > 1 ? place[1] : nil, postalCode: place.count > 2 ? place[2] : nil,
            insuranceCompanyId: nil, insuranceCompanyName: detail.insuranceCompanyName,
            policyNumber: detail.policyNumber, claimNumber: detail.claimNumber,
            email: detail.email, phone: detail.phone,
            firstName: names.first, lastName: names.dropFirst().joined(separator: " "),
            associatedPartyName: detail.associatedPartyName, associatedPartyCompany: detail.associatedPartyCompany,
            associatedPartyEmail: detail.associatedPartyEmail, associatedPartyPhone: detail.associatedPartyPhone,
            isConverted: detail.prospectStatus == "Converted", convertedClaimId: nil,
            statuses: ["New - Not Contacted", "Working - Contacted", "Nuturing", "Unqualified", "Qualified", "Converted"],
            perils: options.perils, contactRoles: options.contactRoles
        )
        data.staffLeads[id] = lead
        return lead
    }

    public func leadStaff(id: String) async throws -> LeadStaff {
        try await simulate()
        return try staffLead(id)
    }

    public func editLead(id: String, _ edit: LeadEdit) async throws {
        try await simulate()
        var lead = try staffLead(id)
        guard !edit.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PortalAPIError.invalidRequest }
        if edit.status == "Converted" { throw PortalAPIError.rejected("Use Convert to Account to convert a lead.") }
        lead.name = edit.name
        lead.status = edit.status
        lead.peril = edit.peril
        lead.lossDate = edit.lossDate
        lead.lossDescription = edit.lossDescription
        lead.street = edit.street
        lead.city = edit.city
        lead.state = edit.state
        lead.postalCode = edit.postalCode
        lead.policyNumber = edit.policyNumber
        lead.claimNumber = edit.claimNumber
        lead.email = edit.email
        lead.phone = edit.phone
        lead.associatedPartyName = edit.associatedPartyName
        lead.associatedPartyCompany = edit.associatedPartyCompany
        lead.associatedPartyEmail = edit.associatedPartyEmail
        lead.associatedPartyPhone = edit.associatedPartyPhone
        data.staffLeads[id] = lead
        try patchLead(id) { fields in
            fields["prospectName"] = edit.name
            fields["prospectStatus"] = edit.status
            fields["peril"] = edit.peril
            fields["email"] = edit.email
            fields["phone"] = edit.phone
            fields["associatedPartyName"] = edit.associatedPartyName
            fields["claimNumber"] = edit.claimNumber
            fields["policyNumber"] = edit.policyNumber
        }
    }

    public func leadFeed(leadId: String) async throws -> [ChatterPost] {
        try await simulate()
        _ = try staffLead(leadId)
        if let feed = data.leadFeeds[leadId] { return feed }
        let seeded = data.feed.filter { $0.parentId == leadId }.map {
            ChatterPost(id: $0.id, authorName: $0.authorName, text: $0.text, createdDate: $0.createdDate,
                        parentName: nil, replies: [], totalReplies: 0)
        }
        data.leadFeeds[leadId] = seeded
        return seeded
    }

    public func postToLead(leadId: String, text: String, mentions: [Mention], fileIds: [String]) async throws -> ChatterPost {
        let existing = try await leadFeed(leadId: leadId)
        let attachments = try uploadedAttachments(fileIds)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { throw PortalAPIError.invalidRequest }
        let post = ChatterPost(id: makeId(prefix: "0D5"), authorName: "Alex Smith", text: trimmed.isEmpty ? attachments[0].title : text,
                               createdDate: Date(), parentName: nil, replies: [], totalReplies: 0, mentions: mentionNames(text, mentions),
                               attachments: attachments)
        data.leadFeeds[leadId] = [post] + existing
        return post
    }

    /// As the server: the claim is built from the lead, duplicates are refused, and the lead becomes Converted.
    public func convertLead(id: String, account: NewClaimRequest.Account, contact: NewClaimRequest.Contact?) async throws -> String {
        var lead = try staffLead(id)
        if lead.isConverted == true { throw PortalAPIError.alreadyConverted(claimId: lead.convertedClaimId) }
        var claim = NewClaimRequest.Claim(name: lead.name ?? "Claim")
        claim.street = lead.street
        claim.city = lead.city
        claim.state = lead.state.flatMap { (data.newClaimOptions?.states ?? []).contains($0) ? $0 : nil }
        claim.postalCode = lead.postalCode
        claim.lossDate = lead.lossDate
        claim.peril = lead.peril.flatMap { (data.newClaimOptions?.perils ?? []).contains($0) ? $0 : nil }
        claim.lossDescription = lead.lossDescription
        claim.claimNumber = lead.claimNumber
        claim.policyNumber = lead.policyNumber
        claim.email = lead.email
        claim.phone = lead.phone
        let claimId = try await createClaim(NewClaimRequest(account: account, claim: claim, contact: contact))
        lead.isConverted = true
        lead.status = "Converted"
        lead.convertedClaimId = claimId
        data.staffLeads[id] = lead
        try patchLead(id) { $0["prospectStatus"] = "Converted" }
        return claimId
    }

    private func patchLead(_ id: String, _ change: (inout [String: Any]) -> Void) throws {
        guard let detail = data.leadDetails[id] else { return }
        let encoded = try PortalJSON.makeEncoder().encode(detail)
        guard var fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
        change(&fields)
        let json = try JSONSerialization.data(withJSONObject: fields.compactMapValues { $0 is NSNull ? nil : $0 })
        data.leadDetails[id] = try PortalJSON.makeDecoder().decode(LeadDetail.self, from: json)
    }

    /// For tests: what the mock received.
    public func recorded(claimId: String) -> (payments: [PaymentEntry], calls: [CallLog], emails: [OutgoingEmail], contacts: Set<String>) {
        (data.paymentsApplied[claimId] ?? [], data.callsLogged[claimId] ?? [], data.emailsSent[claimId] ?? [], data.claimContacts[claimId] ?? [])
    }

    /// Re-decodes a claim detail with some fields changed (the models are immutable).
    private func patchDetail(_ id: String, _ change: (inout [String: Any]) -> Void) throws {
        guard let detail = data.claimDetails[id] else { return }
        let encoded = try PortalJSON.makeEncoder().encode(detail)
        guard var fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
        change(&fields)
        let json = try JSONSerialization.data(withJSONObject: fields.compactMapValues { $0 is NSNull ? nil : $0 })
        data.claimDetails[id] = try PortalJSON.makeDecoder().decode(ClaimDetail.self, from: json)
    }

    private func recordName(_ record: RecordRef) -> String? {
        switch record {
        case .claim(let id): data.claimDetails[id]?.claimName
        case .lead(let id): data.leadDetails[id]?.prospectName
        }
    }

    private func recordType(_ record: RecordRef) -> RelatedRecordType {
        switch record {
        case .claim: .claim
        case .lead: .prospect
        }
    }

    private func makeId(prefix: String) -> String {
        defer { nextId += 1 }
        return prefix + String(format: "MOCK%011dAAA", nextId)
    }

    private func escapeHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")
        return "<p>\(escaped)</p>"
    }
}

private extension SupportCase {
    func with(status: String) -> SupportCase {
        SupportCase(
            caseId: caseId, caseNumber: caseNumber, subject: subject, description: description,
            status: status, createdDate: createdDate, relatedRecordId: relatedRecordId,
            relatedRecordName: relatedRecordName, relatedRecordType: relatedRecordType,
            relatedRecordStage: relatedRecordStage, accountManager: accountManager
        )
    }
}

private extension SupportCaseDetail {
    func with(status: String) -> SupportCaseDetail {
        SupportCaseDetail(
            caseId: caseId, caseNumber: caseNumber, subject: subject, description: description,
            status: status, createdDate: createdDate, relatedRecordId: relatedRecordId,
            relatedRecordName: relatedRecordName, relatedRecordType: relatedRecordType,
            relatedRecordStage: relatedRecordStage, accountManager: accountManager,
            comments: comments
        )
    }

    func appending(_ comment: CaseComment) -> SupportCaseDetail {
        SupportCaseDetail(
            caseId: caseId, caseNumber: caseNumber, subject: subject, description: description,
            status: status, createdDate: createdDate, relatedRecordId: relatedRecordId,
            relatedRecordName: relatedRecordName, relatedRecordType: relatedRecordType,
            relatedRecordStage: relatedRecordStage, accountManager: accountManager,
            comments: comments + [comment]
        )
    }
}
