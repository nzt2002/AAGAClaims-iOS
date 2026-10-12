import Foundation
import Observation

/// Global search (the magnifying glass next to the bell): records the user can open.
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

    public var query = "" {
        didSet { queryChanged() }
    }
    public private(set) var state: State = .idle

    private let api: PortalAPI
    private let debounce: Duration
    private var task: Task<Void, Never>?

    public init(api: PortalAPI, debounce: Duration = .milliseconds(300)) {
        self.api = api
        self.debounce = debounce
    }

    /// Results grouped by type, in the order claims, leads, cases.
    public var sections: [(kind: SearchResult.Kind, results: [SearchResult])] {
        guard case .results(let results) = state else { return [] }
        return [SearchResult.Kind.claim, .prospect, .supportCase].compactMap { kind in
            let matching = results.filter { $0.type == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    private func queryChanged() {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }
        let api = self.api, debounce = self.debounce
        task = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            self?.state = .searching
            do {
                let results = try await api.search(trimmed)
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
