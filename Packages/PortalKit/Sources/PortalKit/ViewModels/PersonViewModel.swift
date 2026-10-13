import Foundation
import Observation

/// A person from search (staff only): their profile and Chatter profile feed, where the user can
/// reply to posts and edit their own replies in place.
@MainActor
@Observable
public final class PersonViewModel {
    public let personId: String
    public private(set) var person: LoadState<Person> = .idle
    public private(set) var feed: LoadState<[ChatterPost]> = .idle

    /// Reply drafts by post id.
    public var drafts: [String: String] = [:]
    /// The reply being edited, and its text.
    public private(set) var editingReplyId: String?
    public var editText = ""
    /// Post or reply ids with a write in flight.
    public private(set) var saving: Set<String> = []
    /// The post or reply whose last write failed, and why.
    public private(set) var failedId: String?
    public private(set) var failure: PortalAPIError?

    private let api: PortalAPI

    public init(api: PortalAPI, personId: String) {
        self.api = api
        self.personId = personId
    }

    public func load() async {
        async let person: Void = loadPerson()
        async let feed: Void = loadFeed()
        _ = await (person, feed)
    }

    private func loadPerson() async {
        let api = self.api, id = personId
        await PortalKit.load(self, \.person) { try await api.person(id: id) }
    }

    public func loadFeed() async {
        let api = self.api, id = personId
        await PortalKit.load(self, \.feed) { try await api.personFeed(id: id) }
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
