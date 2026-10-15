import Foundation
import Observation

/// New Task (Home quick action): a task on one of the user's claims or leads, assigned to a team member.
/// Staff and portal adjusters only, as in the portal.
@MainActor
@Observable
public final class NewTaskViewModel {
    public enum Field: Hashable, Sendable {
        case record, subject, assignee
    }

    /// What a new task or event is attached to.
    public enum RelatedKind: String, CaseIterable, Hashable, Sendable {
        case claim = "Claim"
        case lead = "Lead"
    }

    public struct Options: Sendable {
        public let claims: [ClaimSummary]
        public let leads: [LeadSummary]
        public let assignees: [TaskAssignee]
        /// Subject suggestions (empty if they couldn't be loaded; the subject is still free text).
        public var subjects: ActivitySubjects = .none

        /// Claims and leads sorted by name, and the assignee list. Shared with New Event.
        static func load(_ api: PortalAPI) async throws -> Options {
            async let claims = api.claims()
            async let leads = api.leads()
            async let assignees = api.taskAssignees()
            async let subjects = try? api.activitySubjects()
            var options = try await Options(
                claims: claims.sorted { ($0.recordName ?? "").localizedCaseInsensitiveCompare($1.recordName ?? "") == .orderedAscending },
                leads: leads.sorted { ($0.recordName ?? "").localizedCaseInsensitiveCompare($1.recordName ?? "") == .orderedAscending },
                assignees: assignees
            )
            options.subjects = await subjects ?? .none
            return options
        }
    }

    public private(set) var options: LoadState<Options> = .idle
    public var relatedKind: RelatedKind = .claim
    public var claimId: String?
    public var leadId: String?
    public var subject = ""
    public var hasDueDate = false
    public var dueDate = Date()
    public var assigneeId: String?
    public var details = ""
    public private(set) var showErrors = false
    public private(set) var isSubmitting = false
    public private(set) var submitError: PortalAPIError?
    public private(set) var createdTaskId: String?

    private let api: PortalAPI
    /// The signed-in user's name, to pick them as the default assignee when they're in the list.
    private let currentUserName: String?

    /// Opened from a claim or lead page: the task belongs to that record, which can't be changed.
    public let lockedRecord: RecordRef?

    public init(api: PortalAPI, currentUserName: String?, claimId: String? = nil, record: RecordRef? = nil) {
        self.api = api
        self.currentUserName = currentUserName
        self.claimId = claimId
        self.lockedRecord = record
        switch record {
        case .claim(let id): relatedKind = .claim; self.claimId = id
        case .lead(let id): relatedKind = .lead; leadId = id
        case nil: break
        }
    }

    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) { try await Options.load(api) }
        if assigneeId == nil, let me = options.value?.assignees.first(where: { $0.name == currentUserName }) {
            assigneeId = me.userId
        }
    }

    public var errors: [Field: String] {
        var errors: [Field: String] = [:]
        if record == nil { errors[.record] = "Choose the \(relatedKind.rawValue.lowercased()) this task is for." }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors[.subject] = "Enter a subject."
        } else if trimmed.count > 255 {
            errors[.subject] = "Keep the subject under 255 characters."
        }
        if assigneeId == nil { errors[.assignee] = "Choose who the task is for." }
        return errors
    }

    /// Subject suggestions for what's typed so far.
    public var subjectSuggestions: [String] {
        ActivitySubjects.suggestions(for: subject, in: options.value?.subjects.taskSubjects ?? [])
    }

    /// The chosen claim or lead.
    public var record: RecordRef? {
        switch relatedKind {
        case .claim: claimId.map(RecordRef.claim)
        case .lead: leadId.map(RecordRef.lead)
        }
    }

    public func error(for field: Field) -> String? {
        showErrors ? errors[field] : nil
    }

    public var newTask: NewTask? {
        guard let assigneeId else { return nil }
        let calendar = Calendar.current
        let due = hasDueDate ? CalendarDate(
            year: calendar.component(.year, from: dueDate),
            month: calendar.component(.month, from: dueDate),
            day: calendar.component(.day, from: dueDate)
        ) : nil
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewTask(
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: due,
            assignedToId: assigneeId,
            description: trimmedDetails.isEmpty ? nil : trimmedDetails
        )
    }

    @discardableResult
    public func submit() async -> Bool {
        showErrors = true
        guard errors.isEmpty, !isSubmitting, let record, let task = newTask else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            createdTaskId = try await api.createTask(task, on: record)
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }
}
