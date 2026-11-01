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
        /// `GET …/activities?include=emails` only.
        case email
    }

    public let id: String
    public let kind: Kind
    public var subject: String?
    /// Tasks: due date, no time.
    public var dueDate: CalendarDate?
    /// Events; for emails, when it was sent.
    public var startDateTime: Date?
    public var endDateTime: Date?
    public let isAllDay: Bool?
    public var location: String?
    public var status: String?
    public var isOverdue: Bool?
    public var assignedToName: String?
    public let relatedRecordId: String?
    public let relatedRecordName: String?
    public let relatedRecordType: RelatedRecordType?
    /// `GET …/activities` only: the record page's details.
    public var description: String? = nil
    public var priority: String? = nil
    /// Tasks: "Call", "Email" or "Task".
    public var subtype: String? = nil
    /// Completed tasks, past events and emails.
    public var isClosed: Bool? = nil
    public var createdDate: Date? = nil
    public var createdByName: String? = nil
    /// The owner's user id, for Reassign.
    public var assignedToId: String? = nil
    /// Emails.
    public var fromName: String? = nil
    public var fromAddress: String? = nil
    public var toAddress: String? = nil
    public var ccAddress: String? = nil
    public var isIncoming: Bool? = nil
    public var hasAttachment: Bool? = nil

    public var recordRef: RecordRef? {
        guard let relatedRecordId, let relatedRecordType else { return nil }
        switch relatedRecordType {
        case .claim: return .claim(relatedRecordId)
        case .prospect: return .lead(relatedRecordId)
        }
    }
}

/// `POST /activities/{id}`: only the fields set are changed.
public struct ActivityEdit: Encodable, Hashable, Sendable {
    public var subject: String?
    public var status: String?
    public var priority: String?
    /// Set `changesDueDate` to send it; nil then clears the due date.
    public var dueDate: CalendarDate?
    public var changesDueDate = false
    public var description: String?
    public var assignedToId: String?
    public var location: String?
    public var startDateTime: Date?
    public var endDateTime: Date?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case subject, status, priority, dueDate, description, assignedToId, location, startDateTime, endDateTime
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(subject, forKey: .subject)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(priority, forKey: .priority)
        if changesDueDate {
            if let dueDate { try c.encode(dueDate, forKey: .dueDate) } else { try c.encode("", forKey: .dueDate) }
        }
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(assignedToId, forKey: .assignedToId)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(startDateTime, forKey: .startDateTime)
        try c.encodeIfPresent(endDateTime, forKey: .endDateTime)
    }
}

/// `GET /activity-options`: task statuses and priorities for Edit.
public struct ActivityOptions: Codable, Hashable, Sendable {
    public let taskStatuses: [String]
    public let taskPriorities: [String]

    public init(taskStatuses: [String], taskPriorities: [String]) {
        self.taskStatuses = taskStatuses
        self.taskPriorities = taskPriorities
    }
}

/// `GET /meta`: what the server supports. A build hides features its server doesn't have yet,
/// so the app and the server can be released in either order.
public struct ServerMeta: Codable, Hashable, Sendable {
    public let apiVersion: Int
    public let features: Set<String>

    public init(apiVersion: Int, features: Set<String>) {
        self.apiVersion = apiVersion
        self.features = features
    }

    /// A server from before `/meta`: the features it already had are assumed.
    public static let legacy = ServerMeta(apiVersion: 4, features: ["claimActivities", "chatterAttachments", "claimReferenceId"])

    /// Every feature, for demo mode and previews.
    public static let all = ServerMeta(apiVersion: .max, features: Set(Feature.allCases.map(\.rawValue)))

    public func supports(_ feature: Feature) -> Bool { features.contains(feature.rawValue) }

    /// Server features the app checks for.
    public enum Feature: String, CaseIterable, Sendable {
        case claimActivities, chatterAttachments, claimReferenceId
        case leadActivities, activityEmails, activityEdit, push
        case largeFiles, accountDeletion, diagnostics
        /// `GET /{record}/cases` and `POST /cases/{id}/complete`.
        case recordCases
        /// Staff can open and reply to cases in the app (`GET /cases/{id}`, replies).
        case staffCases
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
