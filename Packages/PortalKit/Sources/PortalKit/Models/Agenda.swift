import Foundation

/// `GET /agenda`: upcoming tasks and events for Home.
public struct Agenda: Codable, Hashable, Sendable {
    public let items: [AgendaItem]
    /// Staff and portal adjusters (Edit_Claim_Status) can create tasks.
    public let canCreateTasks: Bool

    public init(items: [AgendaItem], canCreateTasks: Bool) {
        self.items = items
        self.canCreateTasks = canCreateTasks
    }
}

public struct AgendaItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case task
        case event
    }

    public let id: String
    public let kind: Kind
    public let subject: String?
    /// Tasks: due date, no time.
    public let dueDate: CalendarDate?
    /// Events.
    public let startDateTime: Date?
    public let endDateTime: Date?
    public let isAllDay: Bool?
    public let location: String?
    public let status: String?
    public let isOverdue: Bool?
    public let assignedToName: String?
    public let relatedRecordId: String?
    public let relatedRecordName: String?
    public let relatedRecordType: RelatedRecordType?
    /// `GET /claims/{id}/activities` only: the record page's details.
    public var description: String? = nil
    public var priority: String? = nil
    /// Tasks: "Call", "Email" or "Task".
    public var subtype: String? = nil
    /// Completed tasks and past events.
    public var isClosed: Bool? = nil
    public var createdDate: Date? = nil
    public var createdByName: String? = nil

    public var recordRef: RecordRef? {
        guard let relatedRecordId, let relatedRecordType else { return nil }
        switch relatedRecordType {
        case .claim: return .claim(relatedRecordId)
        case .prospect: return .lead(relatedRecordId)
        }
    }
}

/// `GET /task-assignees`.
public struct TaskAssignee: Codable, Hashable, Identifiable, Sendable {
    public let userId: String
    public let name: String
    public var id: String { userId }
}

/// `POST /claims/{id}/tasks` body.
public struct NewTask: Codable, Hashable, Sendable {
    public var subject: String
    public var dueDate: CalendarDate?
    public var assignedToId: String
    public var description: String?

    public init(subject: String, dueDate: CalendarDate?, assignedToId: String, description: String?) {
        self.subject = subject
        self.dueDate = dueDate
        self.assignedToId = assignedToId
        self.description = description
    }
}

/// `GET /activity-subjects`: the Task and Event Subject combobox values, as offered on desktop.
public struct ActivitySubjects: Codable, Hashable, Sendable {
    public let taskSubjects: [String]
    public let eventSubjects: [String]

    public init(taskSubjects: [String], eventSubjects: [String]) {
        self.taskSubjects = taskSubjects
        self.eventSubjects = eventSubjects
    }

    public static let none = ActivitySubjects(taskSubjects: [], eventSubjects: [])

    /// Subjects for the typed text, as desktop's combobox: everything when empty, otherwise the
    /// subjects containing it (those starting with it first). The typed text itself isn't repeated.
    public static func suggestions(for text: String, in subjects: [String]) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return subjects }
        let matches = subjects.filter { $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame }
        let starting = matches.filter { $0.lowercased().hasPrefix(query.lowercased()) }
        return starting + matches.filter { !starting.contains($0) }
    }
}
