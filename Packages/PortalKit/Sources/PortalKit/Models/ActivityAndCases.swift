import Foundation

/// `relatedRecordType` values. The server says "Prospect" for a lead.
public enum RelatedRecordType: String, Codable, Hashable, Sendable {
    case claim = "Claim"
    case prospect = "Prospect"

    /// The word shown in the UI.
    public var displayName: String {
        switch self {
        case .claim: "Claim"
        case .prospect: "Lead"
        }
    }
}

/// `GET /activity` row: the latest published update for one claim or lead.
public struct ActivityItem: Codable, Hashable, Identifiable, Sendable {
    public let commentId: String
    public let relatedRecordId: String
    public let relatedRecordName: String?
    public let relatedRecordType: RelatedRecordType
    public let createdDate: Date?
    public let title: String?
    /// HTML.
    public let text: String?
    public var isRead: Bool

    public var id: String { commentId }

    public var recordRef: RecordRef {
        switch relatedRecordType {
        case .claim: .claim(relatedRecordId)
        case .prospect: .lead(relatedRecordId)
        }
    }
}

/// `GET /cases` row.
public struct SupportCase: Codable, Hashable, Identifiable, Sendable {
    public let caseId: String
    public let caseNumber: String?
    public let subject: String?
    /// Plain text.
    public let description: String?
    public let status: String?
    public let createdDate: Date?
    public let relatedRecordId: String?
    public let relatedRecordName: String?
    public let relatedRecordType: RelatedRecordType?
    public let relatedRecordStage: String?
    public let accountManager: String?

    public var id: String { caseId }

    /// Closed, Resolved, Completed or Canceled.
    public var isClosed: Bool {
        SupportCase.isClosedStatus(status)
    }

    /// The Case status a homeowner sets with Mark as Completed (a closed status in the org).
    public static let completedStatus = "Completed"

    public static func isClosedStatus(_ status: String?) -> Bool {
        guard let status = status?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return ["closed", "resolved", "completed", "canceled", "cancelled"].contains(status)
    }

    public var recordRef: RecordRef? {
        guard let relatedRecordId, let relatedRecordType else { return nil }
        switch relatedRecordType {
        case .claim: return .claim(relatedRecordId)
        case .prospect: return .lead(relatedRecordId)
        }
    }
}

/// `GET /cases/{id}`.
public struct SupportCaseDetail: Codable, Hashable, Sendable {
    public let caseId: String
    public let caseNumber: String?
    public let subject: String?
    public let description: String?
    public let status: String?
    public let createdDate: Date?
    public let relatedRecordId: String?
    public let relatedRecordName: String?
    public let relatedRecordType: RelatedRecordType?
    public let relatedRecordStage: String?
    public let accountManager: String?
    public let comments: [CaseComment]
}

public struct CaseComment: Codable, Hashable, Identifiable, Sendable {
    public let commentId: String
    /// Plain text.
    public let body: String?
    public let authorName: String?
    public let createdDate: Date?
    public let isOwn: Bool

    public var id: String { commentId }
}

/// A claim or lead, for the endpoints that exist for both.
public enum RecordRef: Hashable, Sendable {
    case claim(String)
    case lead(String)

    public var id: String {
        switch self {
        case .claim(let id), .lead(let id): id
        }
    }

    /// Path segment under `/portal/v1/`.
    var collectionPath: String {
        switch self {
        case .claim: "claims"
        case .lead: "leads"
        }
    }
}
