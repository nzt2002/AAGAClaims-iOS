import Foundation
import Observation

/// Chatter posts and replies written while offline, saved on the device and sent, in order, once
/// the app is back online. Text and @mentions only: files need a connection to upload.
/// Cleared at sign-out. The file is protected until the device is first unlocked.
@MainActor
@Observable
public final class Outbox {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case claimPost, leadPost, reply
        }

        public let id: UUID
        public let kind: Kind
        /// The claim or lead for posts; the post for replies.
        public let targetId: String
        public let text: String
        public let mentions: [Mention]
        public let createdAt: Date
        /// Set when the server refused it (e.g. the post was deleted); it isn't retried.
        public var failed = false

        public init(kind: Kind, targetId: String, text: String, mentions: [Mention], createdAt: Date = Date()) {
            id = UUID()
            self.kind = kind
            self.targetId = targetId
            self.text = text
            self.mentions = mentions
            self.createdAt = createdAt
        }
    }

    public private(set) var items: [Item] = []
    /// When the last send finished, so feeds can reload.
    public private(set) var lastSent: Date?
    public private(set) var isSending = false

    private let fileURL: URL?

    /// `fileURL` nil keeps items in memory only (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? PortalJSON.makeDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    public static let shared = Outbox(fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appending(path: "Outbox.json"))

    public var pendingCount: Int { items.filter { !$0.failed }.count }

    public func add(_ item: Item) {
        items.append(item)
        save()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        items = []
        save()
    }

    /// Sends everything waiting, oldest first. Stops at the first offline error and tries again
    /// next time; anything the server refuses is marked failed. Returns how many were sent.
    @discardableResult
    public func send(using api: PortalAPI) async -> Int {
        guard !isSending else { return 0 }
        isSending = true
        defer { isSending = false }
        var sent = 0
        for item in items where !item.failed {
            do {
                switch item.kind {
                case .claimPost: _ = try await api.postToClaim(claimId: item.targetId, text: item.text, mentions: item.mentions, fileIds: [])
                case .leadPost: _ = try await api.postToLead(leadId: item.targetId, text: item.text, mentions: item.mentions, fileIds: [])
                case .reply: _ = try await api.addReply(toPost: item.targetId, text: item.text, mentions: item.mentions, fileIds: [])
                }
                items.removeAll { $0.id == item.id }
                sent += 1
            } catch {
                switch PortalAPIError.wrap(error) {
                case .offline, .sessionExpired, .server:
                    save()
                    if sent > 0 { lastSent = Date() }
                    return sent
                default:
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].failed = true }
                }
            }
        }
        save()
        if sent > 0 { lastSent = Date() }
        return sent
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PortalJSON.makeEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Losing the outbox file only loses unsent drafts; nothing to show the user.
        }
    }
}
