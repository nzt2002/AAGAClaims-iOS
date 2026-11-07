import Foundation

/// `GET /{claims|leads}/{id}/portal-update` (staff): the "Recent Portal Update" draft, written from the
/// last 30 days of activity, and who it can be emailed to.
public struct PortalUpdateDraft: Codable, Hashable, Sendable {
    public let recordName: String?
    /// The draft as plain text: paragraphs, "- " bullets and **bold** (the server turns it back into HTML).
    public let text: String?
    /// False when nothing new happened: the draft is the "no new activity" message.
    public let hasNewActivity: Bool?
    /// Set when the draft couldn't be written: staff write the update themselves.
    public let notice: String?
    public let recipients: [Recipient]?

    public struct Recipient: Codable, Hashable, Identifiable, Sendable {
        public let id: String
        public let name: String?
        public let email: String?

        public init(id: String, name: String?, email: String?) {
            self.id = id
            self.name = name
            self.email = email
        }
    }

    public init(recordName: String?, text: String?, hasNewActivity: Bool?, notice: String?, recipients: [Recipient]?) {
        self.recordName = recordName
        self.text = text
        self.hasNewActivity = hasNewActivity
        self.notice = notice
        self.recipients = recipients
    }
}

/// `POST /{claims|leads}/{id}/portal-update` body.
public struct PortalUpdatePost: Codable, Hashable, Sendable {
    public var text: String
    public var sendEmail: Bool
    /// Who to email, from the draft's recipients.
    public var recipientIds: [String]

    public init(text: String, sendEmail: Bool, recipientIds: [String]) {
        self.text = text
        self.sendEmail = sendEmail
        self.recipientIds = recipientIds
    }
}

/// `POST /{claims|leads}/{id}/portal-update` response.
public struct PortalUpdatePosted: Codable, Hashable, Sendable {
    public let commentId: String?
    /// How many people were emailed.
    public let emailed: Int?

    public init(commentId: String?, emailed: Int?) {
        self.commentId = commentId
        self.emailed = emailed
    }
}
