import Foundation
import Observation

/// How the Claims and Leads lists are ordered.
public enum ListSortOrder: String, CaseIterable, Codable, Sendable {
    case updated = "Recently updated"
    case lossDate = "Loss date"
    case name = "Name A–Z"
}

/// A list's filter and sort choices, saved so the list opens the way the user left it.
public struct ListFilterState: Codable, Equatable, Sendable {
    public var status: String?
    public var peril: String?
    /// PaymentFilter (claims) or AgreementFilter (leads) raw value.
    public var option: String?
    public var openOnly = false
    public var mineOnly = false
    public var sort: ListSortOrder = .updated

    public init() {}
}

enum ListSorting {
    static func sorted<T>(_ items: [T], by order: ListSortOrder,
                          updated: (T) -> Date?, lossDate: (T) -> CalendarDate?, name: (T) -> String?) -> [T] {
        switch order {
        case .updated:
            return items.sorted { (updated($0) ?? .distantPast) > (updated($1) ?? .distantPast) }
        case .lossDate:
            // Most recent loss first; records without a loss date last.
            return items.sorted {
                switch (lossDate($0), lossDate($1)) {
                case let (a?, b?): return a > b
                case (.some, nil): return true
                default: return false
                }
            }
        case .name:
            return items.sorted {
                (name($0) ?? "").localizedStandardCompare(name($1) ?? "") == .orderedAscending
            }
        }
    }

    static func matches(_ name: String?, user: String?) -> Bool {
        guard let name = PortalFormat.nonEmpty(name), let user = PortalFormat.nonEmpty(user) else { return false }
        return name.caseInsensitiveCompare(user) == .orderedSame
    }
}

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
    /// Hides Closed claims. Set from the Home "Open Claims" tile.
    public var openOnly = false
    /// Only claims where the signed-in user is the adjuster or account manager.
    public var mineOnly = false
    public var sortOrder: ListSortOrder = .updated
    /// The signed-in user's name, for "Mine".
    public var currentUserName: String?

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// The filter and sort choices, for saving and restoring.
    public var filterState: ListFilterState {
        get {
            var state = ListFilterState()
            state.status = statusFilter
            state.peril = perilFilter
            state.option = paymentFilter == .any ? nil : paymentFilter.rawValue
            state.openOnly = openOnly
            state.mineOnly = mineOnly
            state.sort = sortOrder
            return state
        }
        set {
            statusFilter = newValue.status
            perilFilter = newValue.peril
            paymentFilter = newValue.option.flatMap(PaymentFilter.init(rawValue:)) ?? .any
            openOnly = newValue.openOnly
            mineOnly = newValue.mineOnly
            sortOrder = newValue.sort
        }
    }

    /// All claims, most recently updated first.
    public var claims: [ClaimSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    /// Claims after search and filters, in the chosen order (spec §6.4).
    public var filteredClaims: [ClaimSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = currentUserName
        let matching = claims.filter { claim in
            if mineOnly, !ListSorting.matches(claim.adjusterName, user: user),
               !ListSorting.matches(claim.accountManagerName, user: user) {
                return false
            }
            if openOnly, claim.claimStatus?.caseInsensitiveCompare("Closed") == .orderedSame {
                return false
            }
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
        return ListSorting.sorted(matching, by: sortOrder, updated: \.lastModifiedDate,
                                  lossDate: \.lossDate, name: \.recordName)
    }

    public var statusOptions: [String] { ClaimLifecycle.stages }

    /// Perils present in the user's claims, sorted (spec: "built from the values in the data").
    public var perilOptions: [String] {
        let values = claims.compactMap { PortalFormat.nonEmpty($0.peril) }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var hasActiveFilters: Bool {
        openOnly || mineOnly || statusFilter != nil || perilFilter != nil || paymentFilter != .any
    }

    /// Clears the filters (not the sort order).
    public func clearFilters() {
        openOnly = false
        mineOnly = false
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
    /// Hides Converted and Unqualified leads. Set from the Home "Open Leads" tile.
    public var openOnly = false
    /// Only leads where the signed-in user is the adjuster or account manager.
    public var mineOnly = false
    public var sortOrder: ListSortOrder = .updated
    /// The signed-in user's name, for "Mine".
    public var currentUserName: String?

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    /// The filter and sort choices, for saving and restoring.
    public var filterState: ListFilterState {
        get {
            var state = ListFilterState()
            state.status = statusFilter
            state.peril = perilFilter
            state.option = agreementFilter == .any ? nil : agreementFilter.rawValue
            state.openOnly = openOnly
            state.mineOnly = mineOnly
            state.sort = sortOrder
            return state
        }
        set {
            statusFilter = newValue.status
            perilFilter = newValue.peril
            agreementFilter = newValue.option.flatMap(AgreementFilter.init(rawValue:)) ?? .any
            openOnly = newValue.openOnly
            mineOnly = newValue.mineOnly
            sortOrder = newValue.sort
        }
    }

    /// All leads, most recently updated first.
    public var leads: [LeadSummary] {
        (state.value ?? []).sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
    }

    /// Leads after search and filters, in the chosen order (spec §6.6).
    public var filteredLeads: [LeadSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = currentUserName
        let matching = leads.filter { lead in
            if mineOnly, !ListSorting.matches(lead.adjusterName, user: user),
               !ListSorting.matches(lead.accountManagerName, user: user) {
                return false
            }
            if openOnly, LeadsListViewModel.isFinished(lead.prospectStatus) {
                return false
            }
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
        return ListSorting.sorted(matching, by: sortOrder, updated: \.lastModifiedDate,
                                  lossDate: \.lossDate, name: \.recordName)
    }

    public var statusOptions: [String] { LeadLifecycle.stages + ["Unqualified"] }

    public var perilOptions: [String] {
        let values = leads.compactMap { PortalFormat.nonEmpty($0.peril) }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var hasActiveFilters: Bool {
        openOnly || mineOnly || statusFilter != nil || perilFilter != nil || agreementFilter != .any
    }

    /// Clears the filters (not the sort order).
    public func clearFilters() {
        openOnly = false
        mineOnly = false
        statusFilter = nil
        perilFilter = nil
        agreementFilter = .any
    }

    /// Converted or Unqualified: not counted as an open lead.
    public nonisolated static func isFinished(_ status: String?) -> Bool {
        guard let status = status?.trimmingCharacters(in: .whitespaces) else { return false }
        return status.caseInsensitiveCompare("Converted") == .orderedSame
            || status.caseInsensitiveCompare("Unqualified") == .orderedSame
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
