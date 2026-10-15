import Foundation
import Observation

/// New Event (Home quick action): an event on a claim or lead, assigned to a team member. Staff and
/// portal adjusters only, like New Task.
@MainActor
@Observable
public final class NewEventViewModel {
    public enum Field: Hashable, Sendable {
        case record, subject, assignee, end
    }

    public private(set) var options: LoadState<NewTaskViewModel.Options> = .idle
    public var relatedKind: NewTaskViewModel.RelatedKind = .claim
    public var claimId: String?
    public var leadId: String?
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
    /// Opened from a claim or lead page: the event belongs to that record, which can't be changed.
    public let lockedRecord: RecordRef?

    public init(api: PortalAPI, currentUserName: String?, now: Date = Date(), record: RecordRef? = nil) {
        self.api = api
        self.currentUserName = currentUserName
        self.lockedRecord = record
        switch record {
        case .claim(let id): relatedKind = .claim; claimId = id
        case .lead(let id): relatedKind = .lead; leadId = id
        case nil: break
        }
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        self.start = nextHour
        self.end = nextHour.addingTimeInterval(3_600)
    }

    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) { try await NewTaskViewModel.Options.load(api) }
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
        if record == nil { errors[.record] = "Choose the \(relatedKind.rawValue.lowercased()) this event is for." }
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

    /// Subject suggestions for what's typed so far.
    public var subjectSuggestions: [String] {
        ActivitySubjects.suggestions(for: subject, in: options.value?.subjects.eventSubjects ?? [])
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
        guard errors.isEmpty, !isSubmitting, let record, let event = newEvent else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            createdEventId = try await api.createEvent(event, on: record)
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }
}
