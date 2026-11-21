import Foundation
import Observation

/// Jobs for a company with the Contractor add-on: the list, with search and a stage filter.
@MainActor
@Observable
public final class JobsListViewModel {
    public private(set) var state: LoadState<[JobSummary]> = .idle
    public var searchText = ""
    /// A stage name, or nil for all.
    public var stageFilter: String?
    /// Hides finished jobs.
    public var openOnly = true

    private let api: PortalAPI
    public init(api: PortalAPI) { self.api = api }

    /// Every job, most recently moved first.
    public var jobs: [JobSummary] {
        (state.value ?? []).sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) }
    }

    /// Stage names present in the data, for the filter.
    public var stageOptions: [String] {
        var seen = Set<String>(), out: [String] = []
        for j in (state.value ?? []).sorted(by: { $0.stageNumber < $1.stageNumber }) where seen.insert(j.stage).inserted { out.append(j.stage) }
        return out
    }

    /// After search and filters: matches the name, number, trade, address, customer or stage.
    public var filteredJobs: [JobSummary] {
        let words = searchText.lowercased().split(separator: " ").map(String.init)
        return jobs.filter { j in
            if openOnly, j.isComplete { return false }
            if let stageFilter, j.stage != stageFilter { return false }
            let hay = [j.name, j.number, j.trade, j.address, j.customerName, j.stage].compactMap { $0 }.joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    public var hasActiveFilters: Bool { stageFilter != nil || !openOnly }
    public func clearFilters() { stageFilter = nil; openOnly = true }

    public func load() async { await PortalKit.load(self, \.state) { try await api.jobs() } }
}

/// One job: everything on its screen, and moving it to another stage.
@MainActor
@Observable
public final class JobDetailViewModel {
    public private(set) var state: LoadState<JobDetail> = .idle
    public private(set) var updates: LoadState<[PortalUpdate]> = .idle
    public private(set) var files: LoadState<[PortalFile]> = .idle
    public private(set) var moveError: PortalAPIError?
    public private(set) var isMoving = false

    public let jobId: String
    private let api: PortalAPI
    public init(jobId: String, api: PortalAPI) { self.jobId = jobId; self.api = api }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.job(id: jobId) }
    }
    public func loadUpdates() async { await PortalKit.load(self, \.updates) { try await api.jobUpdates(id: jobId) } }
    public func loadFiles() async { await PortalKit.load(self, \.files) { try await api.jobFiles(id: jobId) } }

    /// Moves the job to a stage of its board, then reloads. Returns whether it worked.
    @discardableResult
    public func move(to stage: String) async -> Bool {
        isMoving = true
        moveError = nil
        defer { isMoving = false }
        do {
            try await api.moveJob(id: jobId, to: stage)
            await load()
            return true
        } catch {
            moveError = .wrap(error)
            return false
        }
    }
}
