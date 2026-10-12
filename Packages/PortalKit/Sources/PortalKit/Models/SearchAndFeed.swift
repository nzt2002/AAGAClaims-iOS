import Foundation

/// `GET /search?q=`: one record the user can open.
public struct SearchResult: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case claim = "Claim"
        case prospect = "Prospect"
        case supportCase = "Case"

        public var displayName: String {
            switch self {
            case .claim: "Claims"
            case .prospect: "Leads"
            case .supportCase: "Support cases"
            }
        }
    }

    public let type: Kind
    public let id: String
    public let title: String?
    public let subtitle: String?
}

/// `GET /feed`: a Chatter post from a staff member's news feed. Empty for portal users.
public struct FeedPost: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let authorName: String?
    /// Plain text.
    public let text: String?
    public let createdDate: Date?
    public let parentId: String?
    public let parentName: String?
    /// "Claim", "Prospect" or null.
    public let parentType: RelatedRecordType?

    public var recordRef: RecordRef? {
        guard let parentId, let parentType else { return nil }
        switch parentType {
        case .claim: return .claim(parentId)
        case .prospect: return .lead(parentId)
        }
    }
}

/// `POST /claims/{id}/events` body. All-day events send `date`; others send start and end.
public struct NewEvent: Codable, Hashable, Sendable {
    public var subject: String
    public var isAllDay: Bool
    public var date: CalendarDate?
    public var startDateTime: Date?
    public var endDateTime: Date?
    public var location: String?
    public var assignedToId: String
    public var description: String?

    public init(subject: String, isAllDay: Bool, date: CalendarDate?, startDateTime: Date?, endDateTime: Date?,
                location: String?, assignedToId: String, description: String?) {
        self.subject = subject
        self.isAllDay = isAllDay
        self.date = date
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.location = location
        self.assignedToId = assignedToId
        self.description = description
    }
}
