import Foundation
import Observation

/// A Chatter feed with inline replies and editing of your own replies: a person's profile feed
/// or a claim's record feed (staff only).
@MainActor
@Observable
public final class ChatterFeedViewModel {
    public enum Source: Hashable, Sendable {
        case person(String)
        case claim(String)
        case lead(String)
    }

    public let source: Source
    public private(set) var feed: LoadState<[ChatterPost]> = .idle

    /// Reply drafts by post id.
    public var drafts: [String: String] = [:]
    /// The reply being edited, and its text.
    public private(set) var editingReplyId: String?
    public var editText = ""
    /// Post or reply ids with a write in flight ("new-post" for a new post).
    public private(set) var saving: Set<String> = []
    /// The post or reply whose last write failed.
    public private(set) var failedId: String?
    public private(set) var failure: PortalAPIError?

    public static let newPostId = "new-post"

    private let api: PortalAPI

    public init(api: PortalAPI, source: Source) {
        self.api = api
        self.source = source
    }

    public func load() async {
        let api = self.api
        switch source {
        case .person(let id): await PortalKit.load(self, \.feed) { try await api.personFeed(id: id) }
        case .claim(let id): await PortalKit.load(self, \.feed) { try await api.claimFeed(claimId: id) }
        case .lead(let id): await PortalKit.load(self, \.feed) { try await api.leadFeed(leadId: id) }
        }
    }

    // MARK: - Posts (claims)

    /// Post: a new post on the claim's or lead's feed, shown at the top.
    @discardableResult
    public func post(_ text: String) async -> Bool {
        if case .person = source { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !saving.contains(Self.newPostId) else { return false }
        saving.insert(Self.newPostId)
        clearFailure()
        defer { saving.remove(Self.newPostId) }
        do {
            let post: ChatterPost
            switch source {
            case .claim(let id): post = try await api.postToClaim(claimId: id, text: trimmed)
            case .lead(let id): post = try await api.postToLead(leadId: id, text: trimmed)
            case .person: return false
            }
            let date = feed.loadedAt ?? Date()
            feed = .loaded([post] + (feed.value ?? []), at: date)
            return true
        } catch {
            fail(Self.newPostId, error)
            return false
        }
    }

    // MARK: - Replies

    public func canSend(_ postId: String) -> Bool {
        !(drafts[postId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving.contains(postId)
    }

    @discardableResult
    public func sendReply(to postId: String) async -> Bool {
        let text = (drafts[postId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !saving.contains(postId) else { return false }
        saving.insert(postId)
        clearFailure()
        defer { saving.remove(postId) }
        do {
            let reply = try await api.addReply(toPost: postId, text: text)
            updatePost(postId) { post in
                post.replies.append(reply)
                post.totalReplies = (post.totalReplies ?? post.replies.count - 1) + 1
            }
            drafts[postId] = nil
            return true
        } catch {
            fail(postId, error)
            return false
        }
    }

    public func startEditing(_ reply: ChatterReply) {
        guard reply.isMine == true else { return }
        editingReplyId = reply.id
        editText = reply.text ?? ""
        clearFailure()
    }

    public func cancelEditing() {
        editingReplyId = nil
        editText = ""
    }

    @discardableResult
    public func saveEdit() async -> Bool {
        guard let replyId = editingReplyId else { return false }
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !saving.contains(replyId) else { return false }
        saving.insert(replyId)
        clearFailure()
        defer { saving.remove(replyId) }
        do {
            let saved = try await api.editReply(id: replyId, text: text)
            replaceReply(replyId) { $0.text = saved.text ?? text }
            cancelEditing()
            return true
        } catch {
            fail(replyId, error)
            return false
        }
    }

    // MARK: - Helpers

    private func updatePost(_ postId: String, _ change: (inout ChatterPost) -> Void) {
        guard case .loaded(var posts, let date) = feed, let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        change(&posts[index])
        feed = .loaded(posts, at: date)
    }

    private func replaceReply(_ replyId: String, _ change: (inout ChatterReply) -> Void) {
        guard case .loaded(var posts, let date) = feed else { return }
        for p in posts.indices {
            if let r = posts[p].replies.firstIndex(where: { $0.id == replyId }) {
                change(&posts[p].replies[r])
            }
        }
        feed = .loaded(posts, at: date)
    }

    private func fail(_ id: String, _ error: Error) {
        failedId = id
        failure = .wrap(error)
    }

    private func clearFailure() {
        failedId = nil
        failure = nil
    }
}
