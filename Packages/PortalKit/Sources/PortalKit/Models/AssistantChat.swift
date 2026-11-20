import Foundation

/// One turn of a chat with Alex, as `POST /assistant/chat` takes it. The server keeps no chat: the app sends the whole
/// conversation so far as plain text, and Alex looks things up fresh each time.
public struct AssistantChatTurn: Codable, Hashable, Sendable {
    /// "user" or "assistant".
    public let role: String
    public let text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }

    public static func user(_ text: String) -> AssistantChatTurn { .init(role: "user", text: text) }
    public static func assistant(_ text: String) -> AssistantChatTurn { .init(role: "assistant", text: text) }
}

/// `POST /assistant/chat` body.
struct AssistantChatRequest: Encodable, Sendable {
    let messages: [AssistantChatTurn]
    /// The claim on screen, if any (a claim's Id; the server ignores anything that isn't one).
    let recordId: String?
}

/// `POST /assistant/chat` reply.
struct AssistantChatReply: Decodable, Sendable {
    let reply: String
}
