import Foundation
import Observation

/// Where recent searches are kept. Device-only; cleared on sign-out.
public protocol RecentSearchStore: AnyObject, Sendable {
    func load() -> [String]
    func save(_ searches: [String])
}

/// UserDefaults-backed recent searches.
public final class UserDefaultsRecentSearchStore: RecentSearchStore, @unchecked Sendable {
    public static let key = "RecentSearches"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    public func save(_ searches: [String]) {
        defaults.set(searches, forKey: Self.key)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory recent searches for tests and previews.
public final class MemoryRecentSearchStore: RecentSearchStore, @unchecked Sendable {
    private var searches: [String]
    public init(_ searches: [String] = []) { self.searches = searches }
    public func load() -> [String] { searches }
    public func save(_ searches: [String]) { self.searches = searches }
}

/// Global search (the search bar on Home): records the user can open.
@MainActor
@Observable
public final class SearchViewModel {
    public enum State: Equatable, Sendable {
        /// Fewer than 2 characters typed.
        case idle
        case searching
        case results([SearchResult])
        case failed
    }

    /// Narrows results to one kind of record.
    public enum Scope: String, CaseIterable, Sendable {
        case all = "All"
        case claims = "Claims"
        case leads = "Leads"
        case cases = "Cases"
        case people = "People"

        var kind: SearchResult.Kind? {
            switch self {
            case .all: nil
            case .claims: .claim
            case .leads: .prospect
            case .cases: .supportCase
            case .people: .user
            }
        }
    }

    public static let maxRecents = 6

    public var query = "" {
        didSet { queryChanged() }
    }
    public var scope: Scope = .all
    public private(set) var state: State = .idle
    public private(set) var recentSearches: [String]

    private let api: PortalAPI
    private let debounce: Duration
    private let store: RecentSearchStore
    private var task: Task<Void, Never>?

    /// Staff also search internal users.
    public let includePeople: Bool

    public init(api: PortalAPI, store: RecentSearchStore = MemoryRecentSearchStore(),
                debounce: Duration = .milliseconds(300), includePeople: Bool = false) {
        self.api = api
        self.includePeople = includePeople
        self.store = store
        self.debounce = debounce
        self.recentSearches = store.load()
    }

    /// The scope chips to show: People only for staff.
    public var scopes: [Scope] {
        Scope.allCases.filter { $0 != .people || includePeople }
    }

    /// All results of the current search, before the scope is applied.
    public var allResults: [SearchResult] {
        if case .results(let results) = state { return results }
        return []
    }

    /// How many results each scope would show, for the scope chips.
    public func count(for scope: Scope) -> Int {
        guard let kind = scope.kind else { return allResults.count }
        return allResults.filter { $0.type == kind }.count
    }

    /// Results grouped by type (claims, leads, cases), within the chosen scope.
    public var sections: [(kind: SearchResult.Kind, results: [SearchResult])] {
        [SearchResult.Kind.user, .claim, .prospect, .supportCase].compactMap { kind in
            if let only = scope.kind, only != kind { return nil }
            let matching = allResults.filter { $0.type == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    public var hasResultsInScope: Bool {
        !sections.isEmpty
    }

    /// Remembers the current query (most recent first, no duplicates). Called when the user
    /// opens a result or submits the search.
    public func commitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var searches = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        searches.insert(trimmed, at: 0)
        recentSearches = Array(searches.prefix(Self.maxRecents))
        store.save(recentSearches)
    }

    public func clearRecents() {
        recentSearches = []
        store.save([])
    }

    /// The parts of `text` that match the query, for highlighting.
    public func highlightRanges(in text: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            ranges.append(found)
            searchRange = found.upperBound..<text.endIndex
        }
        return ranges
    }

    private func queryChanged() {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }
        let api = self.api, debounce = self.debounce, includePeople = self.includePeople
        task = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            self?.state = .searching
            do {
                let results = try await api.search(trimmed, includePeople: includePeople)
                guard !Task.isCancelled else { return }
                self?.state = .results(results)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
        }
    }

    /// Waits for the current search. For tests.
    public func awaitSearch() async {
        await task?.value
    }
}
