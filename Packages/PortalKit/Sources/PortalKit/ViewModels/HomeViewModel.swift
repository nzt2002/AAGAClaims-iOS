import Foundation
import Observation

/// Home dashboard (spec §6.2) and the bell badge count.
@MainActor
@Observable
public final class HomeViewModel {
    public struct Summary: Equatable, Sendable {
        public let openClaims: Int
        public let openLeads: Int
        /// Claims with status Closed plus leads with status Converted.
        public let completed: Int
        public let unreadUpdates: Int
        /// Claim count for each lifecycle stage, in lifecycle order. Stages with no claims are included.
        public let claimsByStage: [(stage: String, count: Int)]

        public static func == (lhs: Summary, rhs: Summary) -> Bool {
            lhs.openClaims == rhs.openClaims && lhs.openLeads == rhs.openLeads
                && lhs.completed == rhs.completed && lhs.unreadUpdates == rhs.unreadUpdates
                && lhs.claimsByStage.map(\.stage) == rhs.claimsByStage.map(\.stage)
                && lhs.claimsByStage.map(\.count) == rhs.claimsByStage.map(\.count)
        }
    }

    public struct Content: Sendable {
        public let claims: [ClaimSummary]
        public let leads: [LeadSummary]
        public let activity: [ActivityItem]
    }

    public private(set) var state: LoadState<Content> = .idle
    /// Loaded separately, so a failing agenda doesn't take down the rest of Home.
    public private(set) var agenda: LoadState<Agenda> = .idle
    /// Staff's Chatter posts. Loaded separately; empty for portal users.
    public private(set) var feed: LoadState<[FeedPost]> = .idle

    /// One entry in Recent activity: a published update, or (for staff) a Chatter post.
    public enum ActivityEntry: Identifiable, Hashable, Sendable {
        case update(ActivityItem)
        case post(FeedPost)

        public var id: String {
            switch self {
            case .update(let item): "u-" + item.commentId
            case .post(let post): "p-" + post.id
            }
        }

        public var date: Date? {
            switch self {
            case .update(let item): item.createdDate
            case .post(let post): post.createdDate
            }
        }
    }

    /// Which entries Recent activity shows. Staff choose; portal users only have portal updates.
    public enum ActivityFilter: String, CaseIterable, Hashable, Sendable {
        case chatter = "Chatter"
        case updates = "Portal updates"
        case all = "All"
    }

    /// Staff see the filter and start on their Chatter feed; portal users see portal updates only.
    public let isInternalUser: Bool
    public var activityFilter: ActivityFilter

    private let api: PortalAPI

    public init(api: PortalAPI, isInternalUser: Bool = false) {
        self.api = api
        self.isInternalUser = isInternalUser
        self.activityFilter = isInternalUser ? .chatter : .updates
    }

    public func load() async {
        async let content: Void = loadContent()
        async let agenda: Void = loadAgenda()
        // Portal users have no Chatter feed.
        async let feed: Void = isInternalUser ? loadFeed() : ()
        _ = await (content, agenda, feed)
    }

    private func loadContent() async {
        let api = self.api
        await PortalKit.load(self, \.state) {
            async let claims = api.claims()
            async let leads = api.leads()
            async let activity = api.activity()
            return try await Content(claims: claims, leads: leads, activity: activity)
        }
    }

    public func loadFeed() async {
        let api = self.api
        await PortalKit.load(self, \.feed) { try await api.feed() }
    }

    /// Entries for the current filter, newest first (20 at most; Home shows 3 at a time and scrolls). A failed feed just leaves posts out.
    public var recentEntries: [ActivityEntry] {
        let filter = isInternalUser ? activityFilter : .updates
        let updates = filter == .chatter ? [] : sortedActivity.map(ActivityEntry.update)
        let posts = filter == .updates ? [] : (feed.value ?? []).map(ActivityEntry.post)
        return Array((updates + posts)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(20))
    }

    public func loadAgenda() async {
        let api = self.api
        await PortalKit.load(self, \.agenda) { try await api.agenda() }
    }

    /// Upcoming tasks and events, earliest first (the server orders them; undated tasks last).
    public var upcoming: [AgendaItem] {
        Array((agenda.value?.items ?? []).prefix(5))
    }

    public var canCreateTasks: Bool {
        agenda.value?.canCreateTasks ?? false
    }

    /// The 3 most recently updated claims.
    public var recentClaims: [ClaimSummary] {
        Array((state.value?.claims ?? [])
            .sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
            .prefix(3))
    }

    public var summary: Summary? {
        state.value.map(Self.summarise)
    }

    /// Latest 5 activity items, newest first.
    public var recentActivity: [ActivityItem] {
        Array(sortedActivity.prefix(5))
    }

    public var sortedActivity: [ActivityItem] {
        (state.value?.activity ?? []).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    public var unreadCount: Int {
        state.value?.activity.filter { !$0.isRead }.count ?? 0
    }

    public var hasClaims: Bool { !(state.value?.claims.isEmpty ?? true) }
    public var hasLeads: Bool { !(state.value?.leads.isEmpty ?? true) }

    /// Marks items read on the server, then locally. Failures are ignored: the call is
    /// idempotent and the next refresh will retry.
    public func markRead(_ commentIds: [String]) async {
        guard !commentIds.isEmpty else { return }
        try? await api.markActivityRead(commentIds: commentIds)
        guard case .loaded(let content, let date) = state else { return }
        let ids = Set(commentIds)
        let activity = content.activity.map { item -> ActivityItem in
            var item = item
            if ids.contains(item.commentId) { item.isRead = true }
            return item
        }
        state = .loaded(Content(claims: content.claims, leads: content.leads, activity: activity), at: date)
    }

    public func markAllRead() async {
        await markRead(sortedActivity.filter { !$0.isRead }.map(\.commentId))
    }

    nonisolated static func summarise(_ content: Content) -> Summary {
        let closedClaims = content.claims.filter { isStatus($0.claimStatus, "Closed") }.count
        let convertedLeads = content.leads.filter { isStatus($0.prospectStatus, "Converted") }.count
        let finishedLeads = content.leads.filter { LeadsListViewModel.isFinished($0.prospectStatus) }.count

        var counts = Dictionary(uniqueKeysWithValues: ClaimLifecycle.stages.map { ($0, 0) })
        for claim in content.claims {
            if case .stage(let index) = claim.lifecycle {
                counts[ClaimLifecycle.stages[index], default: 0] += 1
            }
        }

        return Summary(
            openClaims: content.claims.count - closedClaims,
            openLeads: content.leads.count - finishedLeads,
            completed: closedClaims + convertedLeads,
            unreadUpdates: content.activity.filter { !$0.isRead }.count,
            claimsByStage: ClaimLifecycle.stages.map { ($0, counts[$0] ?? 0) }
        )
    }

    nonisolated private static func isStatus(_ status: String?, _ expected: String) -> Bool {
        status?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(expected) == .orderedSame
    }
}
