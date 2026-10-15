import Foundation

/// `GET /people/{id}`: an internal user's profile (staff only).
public struct Person: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let title: String?
    public let department: String?
    public let email: String?
    public let phone: String?
    public let mobilePhone: String?
    public let aboutMe: String?
    public let city: String?
    public let state: String?
    public let managerName: String?
    public let isMe: Bool?

    /// "AS" for Alex Smith, for the avatar.
    public var initials: String {
        (name ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// A reply (Chatter comment) on a post.
public struct ChatterReply: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let authorName: String?
    public var text: String?
    public let createdDate: Date?
    /// The signed-in user wrote it, so it can be edited.
    public let isMine: Bool?
    /// Names @mentioned in the text.
    public var mentions: [String]?

    public init(id: String, authorName: String?, text: String?, createdDate: Date?, isMine: Bool?, mentions: [String]? = nil) {
        self.id = id
        self.authorName = authorName
        self.text = text
        self.createdDate = createdDate
        self.isMine = isMine
        self.mentions = mentions
    }
}

/// `GET /people/{id}/feed`: a post on someone's Chatter profile feed, with its latest replies.
public struct ChatterPost: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let authorName: String?
    public let text: String?
    public let createdDate: Date?
    /// Where it was posted, when not on the person's own profile.
    public let parentName: String?
    public var replies: [ChatterReply]
    public var totalReplies: Int?
    public var mentions: [String]?

    public init(id: String, authorName: String?, text: String?, createdDate: Date?, parentName: String?,
                replies: [ChatterReply], totalReplies: Int?, mentions: [String]? = nil) {
        self.mentions = mentions
        self.id = id
        self.authorName = authorName
        self.text = text
        self.createdDate = createdDate
        self.parentName = parentName
        self.replies = replies
        self.totalReplies = totalReplies
    }
}

/// Mock data: profiles and feeds by user id.
public struct PeopleFixture: Codable, Sendable {
    public var person: Person
    public var feed: [ChatterPost]
}
