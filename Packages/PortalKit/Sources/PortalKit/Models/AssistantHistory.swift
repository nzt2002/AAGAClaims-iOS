import Foundation

/// Why a chat with Alex didn't help: one tap after "Did Alex help?" → No (Feedback_Reason__c).
public enum AssistantFeedbackReason: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case wrongClaim = "Wrong claim"
    case wrongInfo = "Wrong info"
    case missingInfo = "Missing info"
    case tooLong = "Too long"
    case tooSlow = "Too slow"
    case other = "Other"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wrongClaim: "Wrong claim"
        case .wrongInfo: "Wrong or made-up info"
        case .missingInfo: "Couldn't find what I needed"
        case .tooLong: "Too long or unclear"
        case .tooSlow: "Too slow"
        case .other: "Something else"
        }
    }

    public var systemImage: String {
        switch self {
        case .wrongClaim: "doc.questionmark"
        case .wrongInfo: "exclamationmark.triangle"
        case .missingInfo: "magnifyingglass"
        case .tooLong: "text.alignleft"
        case .tooSlow: "tortoise"
        case .other: "ellipsis.bubble"
        }
    }
}

/// One saved chat with Alex, as listed on a claim, a lead or "Past chats".
public struct AssistantChatSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    /// e.g. "ALEX-00012".
    public let name: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let userName: String?
    public let isMine: Bool
    public let messageCount: Int
    /// The user's first question; nil when they only opened Alex on a record.
    public let firstQuestion: String?
    public let recordId: String?
    public let recordName: String?
    /// "claim", "lead" or nil.
    public let recordType: String?
    /// Did Alex help? nil when not answered.
    public let helpful: Bool?
    public let feedbackReason: AssistantFeedbackReason?

    public init(id: String, name: String? = nil, startedAt: Date?, endedAt: Date? = nil, userName: String?,
                isMine: Bool, messageCount: Int, firstQuestion: String?, recordId: String? = nil,
                recordName: String? = nil, recordType: String? = nil, helpful: Bool? = nil,
                feedbackReason: AssistantFeedbackReason? = nil) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.userName = userName
        self.isMine = isMine
        self.messageCount = messageCount
        self.firstQuestion = firstQuestion
        self.recordId = recordId
        self.recordName = recordName
        self.recordType = recordType
        self.helpful = helpful
        self.feedbackReason = feedbackReason
    }

    /// Whether the user can still answer "Did Alex help?".
    public var canRate: Bool { isMine && helpful == nil }
}

/// `GET /assistant/conversations/{id}`: the chat and its messages.
public struct AssistantChatDetail: Codable, Hashable, Sendable {
    public let conversation: AssistantChatSummary
    public let messages: [AssistantConversation.Message]

    public init(conversation: AssistantChatSummary, messages: [AssistantConversation.Message]) {
        self.conversation = conversation
        self.messages = messages
    }
}
