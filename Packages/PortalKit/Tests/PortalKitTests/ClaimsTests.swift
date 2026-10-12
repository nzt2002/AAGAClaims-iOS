import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Claims milestone")
struct ClaimsTests {
    private func loadedList() async -> ClaimsListViewModel {
        let viewModel = ClaimsListViewModel(api: MockPortalAPI(fixtures: try! .bundled()))
        await viewModel.load()
        return viewModel
    }

    @Test("Search matches name, number, address, status and peril", arguments: [
        ("roof", ["Smith - Roof"]),
        ("CLM-2210", ["Smith - Kitchen Water"]),
        ("decatur", ["Smith - Fence", "Smith - Garage Fire"]),
        ("negotiations", ["Smith - Kitchen Water"]),
        ("hail", ["Smith - Fence"]),
        ("nothing matches", [])
    ])
    func search(query: String, expected: [String]) async {
        let viewModel = await loadedList()
        viewModel.searchText = query
        #expect(viewModel.filteredClaims.compactMap(\.recordName).sorted() == expected.sorted())
    }

    @Test("Filters combine and clear")
    func filters() async {
        let viewModel = await loadedList()

        viewModel.paymentFilter = .received
        #expect(Set(viewModel.filteredClaims.compactMap(\.recordName)) == ["Smith - Roof", "Smith - Garage Fire"])

        viewModel.statusFilter = "Closed"
        #expect(viewModel.filteredClaims.compactMap(\.recordName) == ["Smith - Garage Fire"])
        #expect(viewModel.hasActiveFilters)

        viewModel.clearFilters()
        #expect(!viewModel.hasActiveFilters)
        #expect(viewModel.filteredClaims.count == 4)

        viewModel.paymentFilter = .none
        #expect(Set(viewModel.filteredClaims.compactMap(\.recordName)) == ["Smith - Kitchen Water", "Smith - Fence"])
    }

    @Test("Peril options come from the data")
    func perilOptions() async {
        let viewModel = await loadedList()
        #expect(viewModel.perilOptions == ["Fire", "Hail", "Water", "Wind"])
    }

    @Test("Detail loads every section; updates newest first")
    func detail() async throws {
        let viewModel = ClaimDetailViewModel(claimId: "a0X000000000001AAA", api: MockPortalAPI(fixtures: try .bundled()))
        await viewModel.load()

        #expect(viewModel.detail.value?.claimName == "Smith - Roof")
        #expect(viewModel.payments.value?.count == 1)
        #expect(viewModel.files.value?.count == 2)
        let dates = try #require(viewModel.updates.value).compactMap(\.createdDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Detail for someone else's claim fails as not found")
    func detailNotFound() async throws {
        let viewModel = ClaimDetailViewModel(claimId: "a0Xnope", api: MockPortalAPI(fixtures: try .bundled()))
        await viewModel.load()
        #expect(viewModel.detail.error == .notFound)
    }

    @Test("Composer enforces blank and length limits")
    func composerLimits() async throws {
        let composer = ComposerViewModel(kind: .comment, record: .claim("a0X000000000001AAA"), api: MockPortalAPI(fixtures: try .bundled()))
        #expect(!composer.canSubmit)
        composer.text = "   "
        #expect(!composer.canSubmit)
        composer.text = String(repeating: "a", count: PortalLimits.commentLength + 1)
        #expect(composer.isOverLimit)
        #expect(!composer.canSubmit)
        composer.text = "When is the inspection?"
        #expect(composer.canSubmit)

        await composer.submit()
        #expect(composer.outcome == .commentSent)
        #expect(composer.successMessage == "Your comment has been submitted. Your account manager has been notified.")
    }

    @Test("Request Assistance returns the new case")
    func composerAssistance() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        let composer = ComposerViewModel(kind: .assistance, record: .claim("a0X000000000002AAA"), api: api)
        composer.text = "Can you call me?"
        await composer.submit()

        guard case .caseCreated(let caseId) = composer.outcome else {
            Issue.record("Expected a case")
            return
        }
        #expect(try await api.supportCase(id: caseId).relatedRecordName == "Smith - Kitchen Water")
    }

    @Test("Composer surfaces errors without an outcome")
    func composerError() async {
        let composer = ComposerViewModel(kind: .comment, record: .claim("x"), api: MockPortalAPI(fixtures: .empty, failure: .server(status: 503)))
        composer.text = "Hello"
        await composer.submit()
        #expect(composer.outcome == nil)
        #expect(composer.error == .server(status: 503))
    }
}
