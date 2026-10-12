import Foundation
import Observation

/// New Task (Home quick action): a task on one of the user's claims, assigned to a team member.
/// Staff and portal adjusters only, as in the portal.
@MainActor
@Observable
public final class NewTaskViewModel {
    public enum Field: Hashable, Sendable {
        case claim, subject, assignee
    }

    public struct Options: Sendable {
        public let claims: [ClaimSummary]
        public let assignees: [TaskAssignee]
    }

    public private(set) var options: LoadState<Options> = .idle
    public var claimId: String?
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

    public init(api: PortalAPI, currentUserName: String?, claimId: String? = nil) {
        self.api = api
        self.currentUserName = currentUserName
        self.claimId = claimId
    }

    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) {
            async let claims = api.claims()
            async let assignees = api.taskAssignees()
            let sortedClaims = try await claims.sorted {
                ($0.recordName ?? "").localizedCaseInsensitiveCompare($1.recordName ?? "") == .orderedAscending
            }
            return try await Options(claims: sortedClaims, assignees: assignees)
        }
        if assigneeId == nil, let me = options.value?.assignees.first(where: { $0.name == currentUserName }) {
            assigneeId = me.userId
        }
    }

    public var errors: [Field: String] {
        var errors: [Field: String] = [:]
        if claimId == nil { errors[.claim] = "Choose the claim this task is for." }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors[.subject] = "Enter a subject."
        } else if trimmed.count > 255 {
            errors[.subject] = "Keep the subject under 255 characters."
        }
        if assigneeId == nil { errors[.assignee] = "Choose who the task is for." }
        return errors
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
        guard errors.isEmpty, !isSubmitting, let claimId, let task = newTask else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            createdTaskId = try await api.createTask(task, onClaim: claimId)
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }
}
