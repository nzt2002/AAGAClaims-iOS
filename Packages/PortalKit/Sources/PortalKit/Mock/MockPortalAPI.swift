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

    public func addReply(toPost postId: String, text: String) async throws -> ChatterReply {
        try await simulate()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PortalAPIError.invalidRequest }
        let reply = ChatterReply(id: makeId(prefix: "0D7"), authorName: "Alex Smith", text: text, createdDate: Date(), isMine: true)
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

    public func editReply(id: String, text: String) async throws -> ChatterReply {
        try await simulate()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PortalAPIError.invalidRequest }
        for (userId, var fixture) in data.people {
            for p in fixture.feed.indices {
                if let r = fixture.feed[p].replies.firstIndex(where: { $0.id == id }) {
                    // As in Chatter: only your own replies.
                    guard fixture.feed[p].replies[r].isMine == true else { throw PortalAPIError.invalidRequest }
                    fixture.feed[p].replies[r].text = text
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

private extension SupportCaseDetail {
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
