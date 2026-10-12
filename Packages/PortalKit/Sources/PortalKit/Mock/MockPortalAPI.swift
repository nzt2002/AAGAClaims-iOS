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

        /// The fixtures bundled with PortalKit.
        public static func bundled() throws -> Fixtures {
            Fixtures(
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
                perils: try load("peril")
            )
        }

        /// No claims, leads, activity or cases: for empty-state previews and tests.
        public static let empty = Fixtures(
            claims: [], claimDetails: [:], payments: [:], updates: [:], files: [:],
            leads: [], leadDetails: [:], activity: [], cases: [], caseDetails: [:],
            insuranceCompanies: [], perils: []
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

        let id = makeId(prefix: "a0P")
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
