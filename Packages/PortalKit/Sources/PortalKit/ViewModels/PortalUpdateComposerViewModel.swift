import Foundation
import Observation

/// "Create Recent Portal Update" for staff on a claim or lead: loads the AI draft (the last 30 days of
/// activity), lets staff edit it and pick who to email, then posts it to the portal and the app.
@MainActor
@Observable
public final class PortalUpdateComposerViewModel {
    public var text = ""
    public var sendEmail = false
    public var selectedRecipientIds: Set<String> = []
    public private(set) var recipients: [PortalUpdateDraft.Recipient] = []
    public private(set) var notice: String?
    public private(set) var hasNewActivity = true
    public private(set) var isLoading = false
    public private(set) var isPosting = false
    public private(set) var errorMessage: String?
    private let api: PortalAPI
    public let record: RecordRef

    public init(api: PortalAPI, record: RecordRef) {
        self.api = api
        self.record = record
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let draft = try await api.portalUpdateDraft(for: record)
            text = draft.text ?? ""
            notice = draft.notice
            hasNewActivity = draft.hasNewActivity ?? true
            recipients = draft.recipients ?? []
            selectedRecipientIds = Set(recipients.map(\.id))
            sendEmail = !recipients.isEmpty
        } catch {
            notice = "Couldn't write a draft (\(ClaimActionsViewModel.message(for: error))). Write the update below."
        }
    }

    public var canPost: Bool {
        !isLoading && !isPosting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The people who'll be emailed: none when email is off.
    public var emailRecipientIds: [String] {
        sendEmail ? recipients.map(\.id).filter(selectedRecipientIds.contains) : []
    }

    /// Nil when it failed (see `errorMessage`).
    public func post() async -> PortalUpdatePosted? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Write the update before posting."
            return nil
        }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        let ids = emailRecipientIds
        do {
            return try await api.postPortalUpdate(to: record, PortalUpdatePost(text: trimmed, sendEmail: !ids.isEmpty, recipientIds: ids))
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
            return nil
        }
    }
}
