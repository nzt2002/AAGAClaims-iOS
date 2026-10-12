import Foundation
import Observation

@MainActor
@Observable
public final class ClaimsListViewModel {
    public private(set) var state: LoadState<[ClaimSummary]> = .idle

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// Most recently updated first (spec §6.4).
    public var claims: [ClaimSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.claims() }
    }
}

@MainActor
@Observable
public final class LeadsListViewModel {
    public private(set) var state: LoadState<[LeadSummary]> = .idle

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    public var leads: [LeadSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.leads() }
    }
}

@MainActor
@Observable
public final class CasesListViewModel {
    public enum Filter: String, CaseIterable, Sendable {
        case all = "All"
        case open = "Open"
        case closed = "Closed"
    }

    public private(set) var state: LoadState<[SupportCase]> = .idle
    public var filter: Filter = .all

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    public var cases: [SupportCase] {
        let all = (state.value ?? []).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        switch filter {
        case .all: return all
        case .open: return all.filter { !$0.isClosed }
        case .closed: return all.filter(\.isClosed)
        }
    }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.cases() }
    }
}
