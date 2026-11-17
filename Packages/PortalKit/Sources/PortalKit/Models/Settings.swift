import Foundation

/// `GET /settings/me`: your own name, phone and which alerts also come by email.
public struct MySettings: Codable, Hashable, Sendable {
    public var fullName: String
    public var email: String?
    public var phone: String?
    /// Staff can change their name and phone; policyholders can't here.
    public var canEditProfile: Bool
    public var emailAlerts: [EmailAlert]
}

public struct EmailAlert: Codable, Hashable, Identifiable, Sendable {
    public let kind: String
    public let label: String
    public let hint: String
    public var on: Bool

    public var id: String { kind }
}

/// `GET /settings/company` (staff): the company's everyday settings, and which of them this person may change.
public struct CompanySettings: Codable, Hashable, Sendable {
    public struct WebLeads: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var ownerId: String?
        /// Leads go to a group, which the app shows but the website changes.
        public var ownerIsGroup: Bool
    }

    public struct UploadRules: Codable, Hashable, Sendable {
        public var staffFolderRequired: Bool
        public var portalFolderRequired: Bool
    }

    public struct Message: Codable, Hashable, Identifiable, Sendable {
        public let event: String
        public let label: String
        /// "homeowner" or "team".
        public let audience: String
        public let when: String
        public var enabled: Bool

        public var id: String { event }
        public var isForPolicyholders: Bool { audience == "homeowner" }
    }

    public struct Person: Codable, Hashable, Identifiable, Sendable {
        public let id: String
        public let name: String
    }

    public struct Access: Codable, Hashable, Sendable {
        public let brand: Bool
        public let visibility: Bool
        public let webLeads: Bool
        public let uploadRules: Bool
        public let messages: Bool

        /// Nothing here is theirs to change.
        public var isEmpty: Bool { !(brand || visibility || webLeads || uploadRules || messages) }
    }

    public var name: String
    public var markText: String?
    public var brandColor: String?
    /// "all" or "assigned".
    public var claimVisibility: String
    public var leadVisibility: String
    public var webLeads: WebLeads
    public var uploadRules: UploadRules
    public var messages: [Message]
    public var people: [Person]
    public let can: Access
}

/// One change to the company's settings (`POST /settings/company`).
public enum CompanySettingChange: Sendable, Equatable {
    case brand(markText: String, brandColor: String)
    case visibility(claims: String?, leads: String?)
    case webLeads(enabled: Bool, ownerId: String?, keepGroup: Bool)
    case uploadRules(staff: Bool, portal: Bool)
    case message(event: String, enabled: Bool)
}
