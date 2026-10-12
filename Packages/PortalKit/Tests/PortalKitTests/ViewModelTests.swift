import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("View models")
struct ViewModelTests {
    private func mock() -> MockPortalAPI {
        MockPortalAPI(fixtures: try! .bundled())
    }

    @Test("Home summary counts")
    func homeSummary() async throws {
        let viewModel = HomeViewModel(api: mock())
        await viewModel.load()

        let summary = try #require(viewModel.summary)
        // 4 claims, 1 Closed. 3 leads, 1 Converted.
        #expect(summary.openClaims == 3)
        #expect(summary.openLeads == 2)
        #expect(summary.completed == 2)
        #expect(summary.unreadUpdates == 2)
        #expect(summary.claimsByStage.count == 7)
        #expect(summary.claimsByStage.first { $0.stage == "Inspection" }?.count == 1)
    }

    @Test("Recent activity is newest first and capped at 5")
    func recentActivity() async {
        let viewModel = HomeViewModel(api: mock())
        await viewModel.load()
        let dates = viewModel.recentActivity.compactMap(\.createdDate)
        #expect(dates == dates.sorted(by: >))
        #expect(viewModel.recentActivity.count <= 5)
    }

    @Test("Mark all read clears the unread count")
    func markAllRead() async {
        let api = mock()
        let viewModel = HomeViewModel(api: api)
        await viewModel.load()
        #expect(viewModel.unreadCount == 2)

        await viewModel.markAllRead()
        #expect(viewModel.unreadCount == 0)

        // And the server side agrees on the next load.
        await viewModel.load()
        #expect(viewModel.unreadCount == 0)
    }

    @Test("Claims sort by most recently updated")
    func claimsSorted() async {
        let viewModel = ClaimsListViewModel(api: mock())
        await viewModel.load()
        #expect(viewModel.claims.first?.recordName == "Smith - Kitchen Water")
    }

    @Test("Errors surface as a failed state")
    func failure() async {
        let viewModel = ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty, failure: .server(status: 500)))
        await viewModel.load()
        #expect(viewModel.state.error == .server(status: 500))
    }

    @Test("A failed refresh doesn't need a previous value")
    func emptyState() async {
        let viewModel = LeadsListViewModel(api: MockPortalAPI(fixtures: .empty))
        await viewModel.load()
        #expect(viewModel.leads.isEmpty)
        #expect(viewModel.state.value != nil)
    }

    @Test("Case filter")
    func caseFilter() async {
        let viewModel = CasesListViewModel(api: mock())
        await viewModel.load()
        viewModel.filter = .all
        #expect(viewModel.cases.count == 2)
        viewModel.filter = .open
        #expect(viewModel.cases.map(\.caseNumber) == ["00012345"])
        viewModel.filter = .closed
        #expect(viewModel.cases.map(\.caseNumber) == ["00012001"])
    }
}

@Suite("Mock API")
struct MockAPITests {
    @Test("Lead comments appear in the lead's updates; claim comments don't")
    func commentVisibility() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())

        let leadBefore = try await api.updates(for: .lead("a0P000000000001AAA")).count
        try await api.addComment(to: .lead("a0P000000000001AAA"), text: "Any news?")
        let leadUpdates = try await api.updates(for: .lead("a0P000000000001AAA"))
        #expect(leadUpdates.count == leadBefore + 1)
        #expect(leadUpdates.first?.title == "Customer Comment")

        let claimBefore = try await api.updates(for: .claim("a0X000000000001AAA")).count
        try await api.addComment(to: .claim("a0X000000000001AAA"), text: "Any news?")
        #expect(try await api.updates(for: .claim("a0X000000000001AAA")).count == claimBefore)
    }

    @Test("Unknown records are 404")
    func notFound() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        await #expect(throws: PortalAPIError.notFound) {
            _ = try await api.claim(id: "a0Xnope")
        }
    }

    @Test("createLead requires email or phone")
    func leadValidation() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        await #expect(throws: PortalAPIError.invalidRequest) {
            _ = try await api.createLead(LeadSubmission(leadName: "No contact"))
        }

        var submission = LeadSubmission(leadName: "Has phone")
        submission.phone = "555-0100"
        let id = try await api.createLead(submission)
        #expect(try await api.lead(id: id).prospectName == "Has phone")
    }

    @Test("Request Assistance creates a case linked to the record")
    func requestAssistance() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        let caseId = try await api.requestAssistance(recordId: "a0P000000000001AAA", comments: "Help")
        let detail = try await api.supportCase(id: caseId)
        #expect(detail.relatedRecordType == .prospect)
        #expect(detail.relatedRecordId == "a0P000000000001AAA")

        try await api.replyToCase(id: caseId, body: "Thanks")
        #expect(try await api.supportCase(id: caseId).comments.last?.isOwn == true)
    }

    @Test("Formatting")
    func formatting() {
        let us = Locale(identifier: "en_US")
        #expect(PortalFormat.currency(Decimal(12_500), locale: us) == "$12,500.00")
        #expect(PortalFormat.percent(Decimal(10), locale: us) == "10%")
        #expect(PortalFormat.percent(Decimal(string: "12.5"), locale: us) == "12.5%")
        #expect(PortalFormat.currency(nil) == "—")
    }
}
