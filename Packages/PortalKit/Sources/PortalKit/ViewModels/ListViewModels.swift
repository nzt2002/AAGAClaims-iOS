import Foundation
import Observation

@MainActor
@Observable
public final class ClaimsListViewModel {
    public enum PaymentFilter: String, CaseIterable, Sendable {
        case any = "Any"
        case received = "Payment received"
        case none = "No payment yet"
    }

    public private(set) var state: LoadState<[ClaimSummary]> = .idle

    /// Matches claim name, claim number, address, status or peril, on the device (spec §6.4).
    public var searchText = ""
    /// A lifecycle stage name, or nil for all.
    public var statusFilter: String?
    public var paymentFilter: PaymentFilter = .any
    /// A peril value from the data, or nil for all.
    public var perilFilter: String?

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// All claims, most recently updated first.
    public var claims: [ClaimSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    /// Claims after search and filters, most recently updated first (spec §6.4).
    public var filteredClaims: [ClaimSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return claims.filter { claim in
            if let statusFilter, claim.claimStatus?.caseInsensitiveCompare(statusFilter) != .orderedSame {
                return false
            }
            if let perilFilter, claim.peril?.caseInsensitiveCompare(perilFilter) != .orderedSame {
                return false
            }
            let collected = claim.paymentCollected ?? 0
            switch paymentFilter {
            case .any: break
            case .received: if collected <= 0 { return false }
            case .none: if collected > 0 { return false }
            }
            guard !query.isEmpty else { return true }
            return [claim.recordName, claim.claimNumber, claim.lossAddress, claim.claimStatus, claim.peril]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var statusOptions: [String] { ClaimLifecycle.stages }

    /// Perils present in the user's claims, sorted (spec: "built from the values in the data").
    public var perilOptions: [String] {
        let values = claims.compactMap { PortalFormat.nonEmpty($0.peril) }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var hasActiveFilters: Bool {
        statusFilter != nil || perilFilter != nil || paymentFilter != .any
    }

    public func clearFilters() {
        statusFilter = nil
        perilFilter = nil
        paymentFilter = .any
    }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.claims() }
    }
}

@MainActor
@Observable
public final class LeadsListViewModel {
    public enum AgreementFilter: String, CaseIterable, Sendable {
        case any = "Any"
        case sent = "Sent"
        case signed = "Signed"
        case notSent = "Not sent"
    }

    public private(set) var state: LoadState<[LeadSummary]> = .idle

    /// Matches lead name, claim number, address, status or peril, on the device.
    public var searchText = ""
    public var statusFilter: String?
    public var agreementFilter: AgreementFilter = .any
    public var perilFilter: String?

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// All leads, most recently updated first.
    public var leads: [LeadSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    /// Leads after search and filters (spec §6.6).
    public var filteredLeads: [LeadSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return leads.filter { lead in
            if let statusFilter, lead.prospectStatus?.caseInsensitiveCompare(statusFilter) != .orderedSame {
                return false
            }
            if let perilFilter, lead.peril?.caseInsensitiveCompare(perilFilter) != .orderedSame {
                return false
            }
            switch agreementFilter {
            case .any: break
            // "Sent" means sent and not yet signed.
            case .sent: if lead.agreementSentDate == nil || lead.agreementCompletedDate != nil { return false }
            case .signed: if lead.agreementCompletedDate == nil { return false }
            case .notSent: if lead.agreementSentDate != nil || lead.agreementCompletedDate != nil { return false }
            }
            guard !query.isEmpty else { return true }
            return [lead.recordName, lead.claimNumber, lead.lossAddress, lead.prospectStatus, lead.peril]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var statusOptions: [String] { LeadLifecycle.stages + ["Unqualified"] }

    public var perilOptions: [String] {
        let values = leads.compactMap { PortalFormat.nonEmpty($0.peril) }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var hasActiveFilters: Bool {
        statusFilter != nil || perilFilter != nil || agreementFilter != .any
    }

    public func clearFilters() {
        statusFilter = nil
        perilFilter = nil
        agreementFilter = .any
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
    /// Open by default, as on the portal.
    public var filter: Filter = .open
    /// Matches subject, case number, description, status, related record and account manager.
    public var searchText = ""

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// Newest first, after filter and search (spec §6.9).
    public var cases: [SupportCase] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (state.value ?? [])
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            .filter { supportCase in
                switch filter {
                case .all: break
                case .open: if supportCase.isClosed { return false }
                case .closed: if !supportCase.isClosed { return false }
                }
                guard !query.isEmpty else { return true }
                return [
                    supportCase.subject, supportCase.caseNumber, supportCase.description, supportCase.status,
                    supportCase.relatedRecordName, supportCase.relatedRecordType?.displayName, supportCase.accountManager
                ]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
            }
    }

    public func count(for filter: Filter) -> Int {
        let all = state.value ?? []
        switch filter {
        case .all: return all.count
        case .open: return all.filter { !$0.isClosed }.count
        case .closed: return all.filter(\.isClosed).count
        }
    }

    public func load() async {
        await PortalKit.load(self, \.state) { try await api.cases() }
    }
}
