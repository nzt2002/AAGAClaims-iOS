import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("List sort and Mine")
struct ListSortingTests {
    private func loadedClaims() async -> ClaimsListViewModel {
        let viewModel = ClaimsListViewModel(api: MockPortalAPI(fixtures: try! .bundled()))
        await viewModel.load()
        return viewModel
    }

    @Test("Name A–Z sorts by record name")
    func sortByName() async {
        let viewModel = await loadedClaims()
        viewModel.sortOrder = .name
        let names = viewModel.filteredClaims.compactMap(\.recordName)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("Loss date puts the most recent loss first")
    func sortByLossDate() async {
        let viewModel = await loadedClaims()
        viewModel.sortOrder = .lossDate
        let dates = viewModel.filteredClaims.compactMap(\.lossDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Mine matches the adjuster or account manager, case-insensitively")
    func mine() async {
        let viewModel = await loadedClaims()
        let someone = viewModel.claims.compactMap { PortalFormat.nonEmpty($0.adjusterName) }.first
        try? #require(someone != nil)
        viewModel.currentUserName = someone?.uppercased()
        viewModel.mineOnly = true
        #expect(!viewModel.filteredClaims.isEmpty)
        #expect(viewModel.filteredClaims.allSatisfy {
            $0.adjusterName?.caseInsensitiveCompare(someone!) == .orderedSame
                || $0.accountManagerName?.caseInsensitiveCompare(someone!) == .orderedSame
        })
        #expect(viewModel.hasActiveFilters)
        viewModel.clearFilters()
        #expect(!viewModel.mineOnly)
    }

    @Test("Filter state round-trips, and clearing keeps the sort")
    func filterState() async {
        let viewModel = await loadedClaims()
        viewModel.statusFilter = "Inspection"
        viewModel.paymentFilter = .received
        viewModel.sortOrder = .name
        let saved = viewModel.filterState
        let other = ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty))
        other.filterState = saved
        #expect(other.statusFilter == "Inspection")
        #expect(other.paymentFilter == .received)
        #expect(other.sortOrder == .name)
        other.clearFilters()
        #expect(other.sortOrder == .name)
        #expect(!other.hasActiveFilters)
    }
}
