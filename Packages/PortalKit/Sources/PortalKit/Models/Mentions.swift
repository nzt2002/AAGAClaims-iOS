import Foundation

/// Someone @mentioned in a Chatter post or reply (an active internal user).
public struct Mention: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public var title: String?

    public init(id: String, name: String, title: String? = nil) {
        self.id = id
        self.name = name
        self.title = title
    }
}

/// Text being written with @mentions: finds the "@…" being typed, inserts a chosen person, and
/// keeps only the mentions whose "@Name" is still in the text when it's sent.
public struct MentionDraft: Hashable, Sendable {
    public var text: String
    public private(set) var mentions: [Mention]

    public init(text: String = "", mentions: [Mention] = []) {
        self.text = text
        self.mentions = mentions
    }

    /// What follows the last "@" being typed, e.g. "Ja" in "Thanks @Ja". Nil when not mentioning.
    /// A mention may contain one space ("@Jane D"), so first and last names can be typed.
    public var activeQuery: String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        // "@" must start a word.
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = String(text[text.index(after: at)...])
        if query.contains("\n") || query.count > 40 { return nil }
        if query.filter({ $0 == " " }).count > 1 || query.hasPrefix(" ") { return nil }
        // Already a chosen mention: nothing to suggest.
        if mentions.contains(where: { query.hasPrefix($0.name) }) { return nil }
        return query
    }

    /// Replaces the "@…" being typed with "@Full Name " and remembers who it is.
    public mutating func insert(_ person: Mention) {
        guard let at = text.lastIndex(of: "@") else { return }
        text = String(text[..<at]) + "@" + person.name + " "
        if !mentions.contains(where: { $0.id == person.id }) {
            mentions.append(person)
        }
    }

    /// The mentions still in the text.
    public var resolvedMentions: [Mention] {
        mentions.filter { text.contains("@" + $0.name) }
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
