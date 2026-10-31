import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Support milestone")
struct SupportTests {
    private func mock() -> MockPortalAPI {
        MockPortalAPI(fixtures: try! .bundled())
    }

    @Test("List defaults to open cases, like the portal")
    func defaultFilter() async {
        let viewModel = CasesListViewModel(api: mock())
        await viewModel.load()
        #expect(viewModel.filter == .open)
        #expect(viewModel.cases.map(\.caseNumber) == ["00012345"])
        #expect(viewModel.count(for: .all) == 2)
        #expect(viewModel.count(for: .closed) == 1)
    }

    @Test("Search covers subject, number, description, related record and manager", arguments: [
        ("inspection", ["00012345"]),
        ("00012001", ["00012001"]),
        ("signed yet", ["00012001"]),
        ("Jordan", ["00012001"]),
        ("lead", ["00012001"]),
        ("sam lee", ["00012001", "00012345"]),
        ("nothing", [])
    ])
    func search(query: String, expected: [String]) async {
        let viewModel = CasesListViewModel(api: mock())
        await viewModel.load()
        viewModel.filter = .all
        viewModel.searchText = query
        #expect(viewModel.cases.compactMap(\.caseNumber).sorted() == expected)
    }

    @Test("A record's Updates list its cases")
    func recordCases() async throws {
        let api = mock()
        #expect(try await api.cases(for: .claim("a23000000000001AAA")).map(\.caseNumber) == ["00012345"])
        #expect(try await api.cases(for: .lead("a0r000000000001AAA")).map(\.caseNumber) == ["00012001"])
    }

    @Test("The homeowner can mark an open case completed, once")
    func completeCase() async throws {
        let api = mock()
        let viewModel = CaseDetailViewModel(caseId: "500000000000001AAA", api: api)
        #expect(!viewModel.canComplete) // Not loaded yet.
        await viewModel.load()
        #expect(viewModel.canComplete)
        #expect(await viewModel.complete())
        #expect(viewModel.state.value?.status == "Completed")
        #expect(!viewModel.canComplete)
        #expect(try await api.cases().first { $0.caseId == "500000000000001AAA" }?.isClosed == true)

        let closed = CaseDetailViewModel(caseId: "500000000000002AAA", api: api)
        await closed.load()
        #expect(!closed.canComplete)
    }

    @Test("Resolved counts as closed")
    func resolved() {
        #expect(SupportCase.isClosedStatus("Resolved"))
        #expect(SupportCase.isClosedStatus(" closed "))
        #expect(SupportCase.isClosedStatus("Completed"))
        #expect(SupportCase.isClosedStatus("Canceled"))
        #expect(!SupportCase.isClosedStatus("Working"))
        #expect(!SupportCase.isClosedStatus(nil))
    }

    @Test("Thread is oldest first; replying appends an own message")
    func reply() async {
        let viewModel = CaseDetailViewModel(caseId: "500000000000001AAA", api: mock())
        await viewModel.load()
        let dates = viewModel.comments.compactMap(\.createdDate)
        #expect(dates == dates.sorted())
        let before = viewModel.comments.count

        #expect(!viewModel.canSendReply)
        viewModel.replyText = String(repeating: "x", count: PortalLimits.caseReplyLength + 1)
        #expect(!viewModel.canSendReply)
        viewModel.replyText = "  Thanks, see you then.  "
        #expect(await viewModel.sendReply())

        #expect(viewModel.replyText.isEmpty)
        #expect(viewModel.comments.count == before + 1)
        #expect(viewModel.comments.last?.isOwn == true)
        #expect(viewModel.comments.last?.body == "Thanks, see you then.")
    }

    @Test("Someone else's case is not found")
    func notFound() async {
        let viewModel = CaseDetailViewModel(caseId: "500nope", api: mock())
        await viewModel.load()
        #expect(viewModel.state.error == .notFound)
    }

    @Test("Request Assistance lists claims then leads and validates")
    func requestAssistance() async throws {
        let api = mock()
        let viewModel = RequestAssistanceViewModel(api: api)
        await viewModel.loadOptions()
        let options = try #require(viewModel.options.value)
        #expect(options.count == 7)
        #expect(options.prefix(4).allSatisfy { if case .claim = $0.record { true } else { false } })

        #expect(!(await viewModel.submit()))
        #expect(viewModel.error(for: .record) != nil)
        #expect(viewModel.error(for: .comments) == "Enter your questions or comments.")

        viewModel.selectedRecordId = "a0r000000000003AAA"
        viewModel.comments = "Has an adjuster been assigned?"
        #expect(await viewModel.submit())
        let caseId = try #require(viewModel.createdCaseId)
        #expect(try await api.supportCase(id: caseId).relatedRecordName == "Riley Park")
    }

    @Test("Preselected record")
    func preselected() {
        let viewModel = RequestAssistanceViewModel(api: mock(), preselected: "a23000000000001AAA")
        #expect(viewModel.selectedRecordId == "a23000000000001AAA")
    }
}
