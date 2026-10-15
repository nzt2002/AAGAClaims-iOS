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

    /// Reply drafts (text and @mentions) by post id.
    public var drafts: [String: MentionDraft] = [:]
    /// The reply being edited, and its text and @mentions.
    public private(set) var editingReplyId: String?
    public var editDraft = MentionDraft()
    public var editText: String {
        get { editDraft.text }
        set { editDraft.text = newValue }
    }
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

    /// People to @mention whose name starts with (or has a word starting with) `query`.
    public func mentionCandidates(_ query: String) async -> [Mention] {
        (try? await api.mentionCandidates(query)) ?? []
    }

    @discardableResult
    public func post(_ text: String) async -> Bool {
        await post(MentionDraft(text: text))
    }

    /// Post: a new post on the claim's or lead's feed, shown at the top, with its @mentions.
    @discardableResult
    public func post(_ draft: MentionDraft) async -> Bool {
        if case .person = source { return false }
        let trimmed = draft.trimmedText
        let mentions = draft.resolvedMentions
        guard !trimmed.isEmpty, !saving.contains(Self.newPostId) else { return false }
        saving.insert(Self.newPostId)
        clearFailure()
        defer { saving.remove(Self.newPostId) }
        do {
            let post: ChatterPost
            switch source {
            case .claim(let id): post = try await api.postToClaim(claimId: id, text: trimmed, mentions: mentions)
            case .lead(let id): post = try await api.postToLead(leadId: id, text: trimmed, mentions: mentions)
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
        !(drafts[postId]?.trimmedText ?? "").isEmpty && !saving.contains(postId)
    }

    @discardableResult
    public func sendReply(to postId: String) async -> Bool {
        let draft = drafts[postId] ?? MentionDraft()
        let text = draft.trimmedText
        guard !text.isEmpty, !saving.contains(postId) else { return false }
        saving.insert(postId)
        clearFailure()
        defer { saving.remove(postId) }
        do {
            let reply = try await api.addReply(toPost: postId, text: text, mentions: draft.resolvedMentions)
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
        editDraft = MentionDraft(text: reply.text ?? "")
        clearFailure()
    }

    public func cancelEditing() {
        editingReplyId = nil
        editDraft = MentionDraft()
    }

    @discardableResult
    public func saveEdit() async -> Bool {
        guard let replyId = editingReplyId else { return false }
        let text = editDraft.trimmedText
        let mentions = editDraft.resolvedMentions
        guard !text.isEmpty, !saving.contains(replyId) else { return false }
        saving.insert(replyId)
        clearFailure()
        defer { saving.remove(replyId) }
        do {
            let saved = try await api.editReply(id: replyId, text: text, mentions: mentions)
            replaceReply(replyId) {
                $0.text = saved.text ?? text
                $0.mentions = saved.mentions
            }
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
