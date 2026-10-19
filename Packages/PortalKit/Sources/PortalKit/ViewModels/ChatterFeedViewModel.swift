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

    /// Files attached to a draft, by post id (`newPostId` for a new post). They're uploaded to the
    /// claim or lead as soon as they're picked, so they're also in its Files.
    public private(set) var attachments: [String: [ChatterAttachment]] = [:]
    /// Drafts with an upload in flight.
    public private(set) var uploading: Set<String> = []
    /// Why the last attachment for a draft couldn't be added.
    public private(set) var attachmentErrors: [String: String] = [:]

    private let api: PortalAPI
    /// Where posts and replies written offline wait (claim and lead feeds; nil keeps them unsent).
    private let outbox: Outbox?

    public init(api: PortalAPI, source: Source, outbox: Outbox? = nil) {
        self.api = api
        self.source = source
        self.outbox = outbox
    }

    // MARK: - Offline outbox

    /// Posts on this claim or lead waiting to be sent.
    public var pendingPosts: [Outbox.Item] {
        guard let outbox else { return [] }
        switch source {
        case .claim(let id): return outbox.items.filter { $0.kind == .claimPost && $0.targetId == id }
        case .lead(let id): return outbox.items.filter { $0.kind == .leadPost && $0.targetId == id }
        case .person: return []
        }
    }

    /// Replies to a post waiting to be sent.
    public func pendingReplies(to postId: String) -> [Outbox.Item] {
        outbox?.items.filter { $0.kind == .reply && $0.targetId == postId } ?? []
    }

    /// Drops a waiting post or reply.
    public func discardPending(_ id: UUID) {
        outbox?.remove(id)
    }

    /// When offline, keeps a text-only post or reply in the outbox instead of failing.
    private func queueIfOffline(_ error: Error, kind: Outbox.Item.Kind, targetId: String, draft: MentionDraft, hasFiles: Bool) -> Bool {
        guard let outbox, !hasFiles, PortalAPIError.wrap(error) == .offline else { return false }
        outbox.add(Outbox.Item(kind: kind, targetId: targetId, text: draft.trimmedText, mentions: draft.resolvedMentions))
        return true
    }

    public func load() async {
        let api = self.api
        switch source {
        case .person(let id): await PortalKit.load(self, \.feed) { try await api.personFeed(id: id) }
        case .claim(let id): await PortalKit.load(self, \.feed) { try await api.claimFeed(claimId: id) }
        case .lead(let id): await PortalKit.load(self, \.feed) { try await api.leadFeed(leadId: id) }
        }
    }

    // MARK: - Attachments (claim and lead feeds)

    private var record: RecordRef? {
        switch source {
        case .claim(let id): .claim(id)
        case .lead(let id): .lead(id)
        case .person: nil
        }
    }

    /// Profile feeds have no record to keep files on.
    public var supportsAttachments: Bool { record != nil }

    /// Chatter allows one file per reply and ten per post.
    public func maxFiles(for draftId: String) -> Int { draftId == Self.newPostId ? 10 : 1 }

    public func canAttach(to draftId: String) -> Bool {
        supportsAttachments && !uploading.contains(draftId) && (attachments[draftId]?.count ?? 0) < maxFiles(for: draftId)
    }

    /// Uploads the picked files to the claim or lead and adds them to the draft.
    public func attach(_ uploads: [FileUpload], to draftId: String) async {
        guard let record, !uploads.isEmpty else { return }
        let room = maxFiles(for: draftId) - (attachments[draftId]?.count ?? 0)
        attachmentErrors[draftId] = uploads.count > room
            ? (draftId == Self.newPostId ? "A post can have up to 10 files." : "A reply can have one file.") : nil
        uploading.insert(draftId)
        defer { uploading.remove(draftId) }
        for upload in uploads.prefix(max(room, 0)) {
            do {
                let file = try await api.uploadFile(upload, to: record)
                attachments[draftId, default: []].append(ChatterAttachment(file))
            } catch {
                attachmentErrors[draftId] = "\(upload.title) couldn't be uploaded. Please try again."
            }
        }
    }

    /// Takes a file off the draft. It stays in the record's Files.
    public func removeAttachment(_ fileId: String, from draftId: String) {
        attachments[draftId]?.removeAll { $0.id == fileId }
    }

    /// Clears a reply draft: text, files and errors.
    public func discardDraft(_ draftId: String) {
        drafts[draftId] = nil
        attachments[draftId] = nil
        attachmentErrors[draftId] = nil
        if failedId == draftId { clearFailure() }
    }

    /// An attachment's bytes, for Quick Look.
    public func fileContent(_ fileId: String) async throws -> Data {
        try await api.fileContent(contentDocumentId: fileId)
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
        let fileIds = (attachments[Self.newPostId] ?? []).map(\.id)
        guard !trimmed.isEmpty || !fileIds.isEmpty, !saving.contains(Self.newPostId), !uploading.contains(Self.newPostId) else { return false }
        saving.insert(Self.newPostId)
        clearFailure()
        defer { saving.remove(Self.newPostId) }
        do {
            let post: ChatterPost
            switch source {
            case .claim(let id): post = try await api.postToClaim(claimId: id, text: trimmed, mentions: mentions, fileIds: fileIds)
            case .lead(let id): post = try await api.postToLead(leadId: id, text: trimmed, mentions: mentions, fileIds: fileIds)
            case .person: return false
            }
            let date = feed.loadedAt ?? Date()
            feed = .loaded([post] + (feed.value ?? []), at: date)
            discardDraft(Self.newPostId)
            return true
        } catch {
            let target: (Outbox.Item.Kind, String)? = switch source {
            case .claim(let id): (.claimPost, id)
            case .lead(let id): (.leadPost, id)
            case .person: nil
            }
            if let target, queueIfOffline(error, kind: target.0, targetId: target.1, draft: draft, hasFiles: !fileIds.isEmpty) {
                discardDraft(Self.newPostId)
                return true
            }
            fail(Self.newPostId, error)
            return false
        }
    }

    // MARK: - Replies

    /// Text or a file, and nothing uploading or sending.
    public func canSend(_ postId: String) -> Bool {
        (!(drafts[postId]?.trimmedText ?? "").isEmpty || !(attachments[postId] ?? []).isEmpty)
            && !saving.contains(postId) && !uploading.contains(postId)
    }

    @discardableResult
    public func sendReply(to postId: String) async -> Bool {
        let draft = drafts[postId] ?? MentionDraft()
        let text = draft.trimmedText
        let fileIds = (attachments[postId] ?? []).map(\.id)
        guard canSend(postId) else { return false }
        saving.insert(postId)
        clearFailure()
        defer { saving.remove(postId) }
        do {
            let reply = try await api.addReply(toPost: postId, text: text, mentions: draft.resolvedMentions, fileIds: fileIds)
            updatePost(postId) { post in
                post.replies.append(reply)
                post.totalReplies = (post.totalReplies ?? post.replies.count - 1) + 1
            }
            drafts[postId] = nil
            attachments[postId] = nil
            attachmentErrors[postId] = nil
            return true
        } catch {
            if queueIfOffline(error, kind: .reply, targetId: postId, draft: draft, hasFiles: !fileIds.isEmpty) {
                drafts[postId] = nil
                return true
            }
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
