import Foundation
import Observation

/// Recent activity on a claim or lead (staff): its tasks and events, open first, and its emails
/// when the server has them.
@MainActor
@Observable
public final class RecordActivityViewModel {
    public let record: RecordRef
    public private(set) var activities: LoadState<[AgendaItem]> = .idle
    /// Emails are listed only when the server supports them (`ServerMeta.Feature.activityEmails`).
    public var includeEmails: Bool

    private let api: PortalAPI

    public init(api: PortalAPI, record: RecordRef, includeEmails: Bool) {
        self.api = api
        self.record = record
        self.includeEmails = includeEmails
    }

    public func load() async {
        let api = self.api, record = self.record, emails = includeEmails
        await PortalKit.load(self, \.activities) { try await api.activities(on: record, includeEmails: emails) }
    }

    /// Puts an edited activity back in the list, keeping open items first.
    public func replace(_ item: AgendaItem) {
        guard case .loaded(var items, let date) = activities, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        activities = .loaded(items.filter { $0.isClosed != true } + items.filter { $0.isClosed == true }, at: date)
    }
}

/// A task, event or email page. Tasks: Mark Complete, Edit and Reassign; events: Edit and
/// Reassign; emails are read-only.
@MainActor
@Observable
public final class ActivityDetailViewModel {
    public private(set) var item: AgendaItem
    public private(set) var options: ActivityOptions?
    public private(set) var assignees: [TaskAssignee] = []
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Whether the server can edit activities (`ServerMeta.Feature.activityEdit`).
    public let canChange: Bool
    /// Called with the saved activity, so the list can update.
    public var onChange: ((AgendaItem) -> Void)?

    private let api: PortalAPI

    public init(api: PortalAPI, item: AgendaItem, canChange: Bool) {
        self.api = api
        self.item = item
        self.canChange = canChange
    }

    public var canComplete: Bool { canChange && item.kind == .task && item.isClosed != true }
    public var canEdit: Bool { canChange && item.kind != .email }

    /// Statuses, priorities and the people tasks can be assigned to.
    public func loadOptions() async {
        guard canEdit, options == nil else { return }
        let api = self.api
        async let options = try? api.activityOptions()
        async let assignees = try? api.taskAssignees()
        self.options = await options
        self.assignees = await assignees ?? []
    }

    public func clearError() { errorMessage = nil }

    @discardableResult
    public func complete() async -> Bool {
        let api = self.api, id = item.id
        return await run { try await api.completeTask(id: id) }
    }

    @discardableResult
    public func save(_ edit: ActivityEdit) async -> Bool {
        if let subject = edit.subject, subject.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Enter a subject."
            return false
        }
        if let start = edit.startDateTime ?? item.startDateTime, let end = edit.endDateTime ?? item.endDateTime,
           item.kind == .event, end < start {
            errorMessage = "The end must be after the start."
            return false
        }
        let api = self.api, id = item.id
        return await run { try await api.editActivity(id: id, edit) }
    }

    @discardableResult
    public func reassign(to userId: String) async -> Bool {
        var edit = ActivityEdit()
        edit.assignedToId = userId
        return await save(edit)
    }

    private func run(_ operation: @Sendable () async throws -> AgendaItem) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            item = try await operation()
            onChange?(item)
            return true
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
            return false
        }
    }
}
