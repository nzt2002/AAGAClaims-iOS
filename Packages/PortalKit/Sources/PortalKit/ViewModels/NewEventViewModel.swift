import Foundation
import Observation

/// New Event (Home quick action): an event on a claim, assigned to a team member. Staff and
/// portal adjusters only, like New Task.
@MainActor
@Observable
public final class NewEventViewModel {
    public enum Field: Hashable, Sendable {
        case claim, subject, assignee, end
    }

    public private(set) var options: LoadState<NewTaskViewModel.Options> = .idle
    public var claimId: String?
    public var subject = ""
    public var isAllDay = false
    public var start: Date
    public var end: Date
    public var location = ""
    public var assigneeId: String?
    public var details = ""
    public private(set) var showErrors = false
    public private(set) var isSubmitting = false
    public private(set) var submitError: PortalAPIError?
    public private(set) var createdEventId: String?

    private let api: PortalAPI
    private let currentUserName: String?

    /// Starts at the next whole hour, for an hour.
    public init(api: PortalAPI, currentUserName: String?, now: Date = Date()) {
        self.api = api
        self.currentUserName = currentUserName
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        self.start = nextHour
        self.end = nextHour.addingTimeInterval(3_600)
    }

    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) {
            async let claims = api.claims()
            async let assignees = api.taskAssignees()
            let sortedClaims = try await claims.sorted {
                ($0.recordName ?? "").localizedCaseInsensitiveCompare($1.recordName ?? "") == .orderedAscending
            }
            return try await NewTaskViewModel.Options(claims: sortedClaims, assignees: assignees)
        }
        if assigneeId == nil, let me = options.value?.assignees.first(where: { $0.name == currentUserName }) {
            assigneeId = me.userId
        }
    }

    /// Keeps the event the same length when the start moves.
    public func startChanged(from oldStart: Date) {
        let length = max(end.timeIntervalSince(oldStart), 15 * 60)
        end = start.addingTimeInterval(length)
    }

    public var errors: [Field: String] {
        var errors: [Field: String] = [:]
        if claimId == nil { errors[.claim] = "Choose the claim this event is for." }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors[.subject] = "Enter a subject."
        } else if trimmed.count > 255 {
            errors[.subject] = "Keep the subject under 255 characters."
        }
        if assigneeId == nil { errors[.assignee] = "Choose who the event is for." }
        if !isAllDay && end < start { errors[.end] = "The end must be after the start." }
        return errors
    }

    public func error(for field: Field) -> String? {
        showErrors ? errors[field] : nil
    }

    public var newEvent: NewEvent? {
        guard let assigneeId else { return nil }
        let calendar = Calendar.current
        let day = CalendarDate(
            year: calendar.component(.year, from: start),
            month: calendar.component(.month, from: start),
            day: calendar.component(.day, from: start)
        )
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewEvent(
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            isAllDay: isAllDay,
            date: isAllDay ? day : nil,
            startDateTime: isAllDay ? nil : start,
            endDateTime: isAllDay ? nil : end,
            location: trimmedLocation.isEmpty ? nil : trimmedLocation,
            assignedToId: assigneeId,
            description: trimmedDetails.isEmpty ? nil : trimmedDetails
        )
    }

    @discardableResult
    public func submit() async -> Bool {
        showErrors = true
        guard errors.isEmpty, !isSubmitting, let claimId, let event = newEvent else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            createdEventId = try await api.createEvent(event, onClaim: claimId)
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }
}
