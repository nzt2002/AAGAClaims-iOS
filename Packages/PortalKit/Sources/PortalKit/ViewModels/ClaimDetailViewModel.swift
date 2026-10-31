import Foundation
import Observation

/// Claim detail (spec §6.5). The header and each section load independently, so a slow or
/// failing section doesn't block the rest of the screen.
@MainActor
@Observable
public final class ClaimDetailViewModel {
    public enum Section: String, CaseIterable, Sendable {
        case updates = "Updates"
        case details = "Details"
        case insurance = "Insurance"
        case files = "Files"
        case payments = "Payments"
    }

    public let claimId: String
    public private(set) var detail: LoadState<ClaimDetail> = .idle
    public private(set) var updates: LoadState<[PortalUpdate]> = .idle
    public private(set) var files: LoadState<[PortalFile]> = .idle
    /// Support cases on the record, shown under Updates. Loaded only when `includesCases` is set
    /// (servers with `recordCases`).
    public private(set) var cases: LoadState<[SupportCase]> = .idle
    public var includesCases = false
    public private(set) var payments: LoadState<[Payment]> = .idle
    public var section: Section = .updates

    private let api: PortalAPI

    public init(claimId: String, api: PortalAPI) {
        self.claimId = claimId
        self.api = api
    }

    public var record: RecordRef { .claim(claimId) }

    public func load() async {
        async let detail: Void = loadDetail()
        async let updates: Void = loadUpdates()
        async let files: Void = loadFiles()
        async let payments: Void = loadPayments()
        async let cases: Void = includesCases ? loadCases() : ()
        _ = await (detail, updates, files, payments, cases)
    }

    public func loadDetail() async {
        let api = self.api, id = claimId
        await PortalKit.load(self, \.detail) { try await api.claim(id: id) }
    }

    public func loadUpdates() async {
        let api = self.api, record = self.record
        await PortalKit.load(self, \.updates) {
            // Newest first, whatever order the server sends.
            try await api.updates(for: record).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
    }

    /// Newest first.
    public func loadCases() async {
        let api = self.api, record = self.record
        await PortalKit.load(self, \.cases) {
            try await api.cases(for: record).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
    }

    public func loadFiles() async {
        let api = self.api, record = self.record
        await PortalKit.load(self, \.files) { try await api.files(for: record) }
    }

    public func loadPayments() async {
        let api = self.api, id = claimId
        await PortalKit.load(self, \.payments) { try await api.claimPayments(id: id) }
    }
}
