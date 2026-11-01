import Foundation

/// Which kinds of push notification the user wants (`GET`/`POST /notification-preferences`).
/// Everything is on until the user turns something off. Unknown keys from a newer server are ignored.
public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var updates = true
    public var payments = true
    public var mentions = true
    public var tasks = true
    public var posts = true
    public var support = true
    public var esign = true

    public init() {}

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case updates, payments, support, mentions, tasks, posts, esign

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .updates: "Claim and lead updates"
            case .payments: "Payments"
            case .support: "Support replies"
            case .mentions: "Mentions"
            case .tasks: "Tasks assigned to me"
            case .posts: "Team posts"
            case .esign: "E-signatures"
            }
        }

        public var detail: String {
            switch self {
            case .updates: "New updates on your claims and leads"
            case .payments: "When a payment is recorded on your claim"
            case .support: "Replies and status changes on your support requests"
            case .mentions: "When someone @mentions you"
            case .tasks: "When a task is assigned to you"
            case .posts: "Chatter posts on claims and leads you work on"
            case .esign: "When a document you sent is viewed, signed or declined"
            }
        }

        public var systemImage: String {
            switch self {
            case .updates: "bell.badge"
            case .payments: "dollarsign.circle"
            case .support: "questionmark.bubble"
            case .mentions: "at"
            case .tasks: "checklist"
            case .posts: "text.bubble"
            case .esign: "signature"
            }
        }

        /// Portal users only get these kinds; staff see every switch.
        public var isForEveryone: Bool {
            switch self {
            case .updates, .payments, .support: true
            default: false
            }
        }

        public static func kinds(isInternal: Bool) -> [Kind] {
            allCases.filter { isInternal || $0.isForEveryone }
        }
    }

    public subscript(kind: Kind) -> Bool {
        get {
            switch kind {
            case .updates: updates
            case .payments: payments
            case .support: support
            case .mentions: mentions
            case .tasks: tasks
            case .posts: posts
            case .esign: esign
            }
        }
        set {
            switch kind {
            case .updates: updates = newValue
            case .payments: payments = newValue
            case .support: support = newValue
            case .mentions: mentions = newValue
            case .tasks: tasks = newValue
            case .posts: posts = newValue
            case .esign: esign = newValue
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updates = try c.decodeIfPresent(Bool.self, forKey: .updates) ?? true
        payments = try c.decodeIfPresent(Bool.self, forKey: .payments) ?? true
        mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? true
        tasks = try c.decodeIfPresent(Bool.self, forKey: .tasks) ?? true
        posts = try c.decodeIfPresent(Bool.self, forKey: .posts) ?? true
        support = try c.decodeIfPresent(Bool.self, forKey: .support) ?? true
        esign = try c.decodeIfPresent(Bool.self, forKey: .esign) ?? true
    }
}
