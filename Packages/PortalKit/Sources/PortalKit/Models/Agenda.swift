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
