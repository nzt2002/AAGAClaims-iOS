import Foundation
import Observation

/// The "Regarding {record}" sheet used for Add Comment and Request Assistance (spec §6.5).
@MainActor
@Observable
public final class ComposerViewModel {
    public enum Kind: Sendable, Equatable {
        /// Private comment to the account manager.
        case comment
        /// Opens a support case.
        case assistance
    }

    public enum Outcome: Equatable, Sendable {
        case commentSent
        case caseCreated(caseId: String)
    }

    public let kind: Kind
    public let record: RecordRef
    public var text = ""
    public private(set) var isSubmitting = false
    public private(set) var error: PortalAPIError?
    public private(set) var outcome: Outcome?

    private let api: PortalAPI

    public init(kind: Kind, record: RecordRef, api: PortalAPI) {
        self.kind = kind
        self.record = record
        self.api = api
    }

    public var limit: Int {
        switch kind {
        case .comment: PortalLimits.commentLength
        case .assistance: PortalLimits.assistanceLength
        }
    }

    public var count: Int { text.count }
    public var isOverLimit: Bool { count > limit }

    public var canSubmit: Bool {
        !isSubmitting && !isOverLimit && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var successMessage: String {
        switch kind {
        case .comment: "Your comment has been submitted. Your account manager has been notified."
        case .assistance: "Your request has been submitted. We will follow up with you shortly."
        }
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch kind {
            case .comment:
                try await api.addComment(to: record, text: body)
                outcome = .commentSent
            case .assistance:
                let caseId = try await api.requestAssistance(recordId: record.id, comments: body)
                outcome = .caseCreated(caseId: caseId)
            }
        } catch {
            self.error = .wrap(error)
        }
    }
}
