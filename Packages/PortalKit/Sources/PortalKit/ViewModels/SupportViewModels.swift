import Foundation
import Observation

/// Case detail with its thread and reply composer (spec §6.9).
@MainActor
@Observable
public final class CaseDetailViewModel {
    public let caseId: String
    public private(set) var state: LoadState<SupportCaseDetail> = .idle
    public var replyText = ""
    public private(set) var isSending = false
    public private(set) var replyError: PortalAPIError?

    private let api: PortalAPI

    public init(caseId: String, api: PortalAPI) {
        self.caseId = caseId
        self.api = api
    }

    /// Oldest first, like a chat.
    public var comments: [CaseComment] {
        (state.value?.comments ?? []).sorted { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
    }

    public var replyLimit: Int { PortalLimits.caseReplyLength }
    public var isReplyOverLimit: Bool { replyText.count > replyLimit }

    public var canSendReply: Bool {
        !isSending && !isReplyOverLimit && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func load() async {
        let api = self.api, id = caseId
        await PortalKit.load(self, \.state) { try await api.supportCase(id: id) }
    }

    /// Sends the reply, clears the composer and reloads the thread.
    @discardableResult
    public func sendReply() async -> Bool {
        guard canSendReply else { return false }
        isSending = true
        replyError = nil
        defer { isSending = false }

        do {
            try await api.replyToCase(id: caseId, body: replyText.trimmingCharacters(in: .whitespacesAndNewlines))
            replyText = ""
            await load()
            return true
        } catch {
            replyError = .wrap(error)
            return false
        }
    }
}

/// Request Assistance from the Support tab: pick a claim or lead, then write the request (spec §6.9).
@MainActor
@Observable
public final class RequestAssistanceViewModel {
    public struct Option: Identifiable, Hashable, Sendable {
        public let record: RecordRef
        public let name: String
        public let detail: String?
        public var id: String { record.id }
    }

    public enum Field: Hashable, Sendable {
        case record, comments
    }

    public private(set) var options: LoadState<[Option]> = .idle
    public var selectedRecordId: String?
    public var comments = ""
    public private(set) var showErrors = false
    public private(set) var isSubmitting = false
    public private(set) var submitError: PortalAPIError?
    public private(set) var createdCaseId: String?

    private let api: PortalAPI

    public init(api: PortalAPI, preselected: String? = nil) {
        self.api = api
        self.selectedRecordId = preselected
    }

    /// Claims then leads, each sorted by name.
    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) {
            async let claims = api.claims()
            async let leads = api.leads()
            let claimOptions = try await claims.map {
                Option(record: .claim($0.recordId), name: $0.recordName ?? "Claim", detail: $0.claimNumber)
            }
            let leadOptions = try await leads.map {
                Option(record: .lead($0.recordId), name: $0.recordName ?? "Lead", detail: $0.prospectStatus)
            }
            let byName: (Option, Option) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return claimOptions.sorted(by: byName) + leadOptions.sorted(by: byName)
        }
    }

    public var limit: Int { PortalLimits.assistanceLength }

    public var errors: [Field: String] {
        var errors: [Field: String] = [:]
        if selectedRecordId == nil {
            errors[.record] = "Choose the claim or lead you need help with."
        }
        let text = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            errors[.comments] = "Enter your questions or comments."
        } else if comments.count > limit {
            errors[.comments] = "Keep your message under \(limit.formatted()) characters."
        }
        return errors
    }

    public func error(for field: Field) -> String? {
        showErrors ? errors[field] : nil
    }

    @discardableResult
    public func submit() async -> Bool {
        showErrors = true
        guard errors.isEmpty, !isSubmitting, let recordId = selectedRecordId else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            createdCaseId = try await api.requestAssistance(
                recordId: recordId,
                comments: comments.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }
}
