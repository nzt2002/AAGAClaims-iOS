import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Leads milestone")
struct LeadsTests {
    private func mock() -> MockPortalAPI {
        MockPortalAPI(fixtures: try! .bundled())
    }

    private func loadedList() async -> LeadsListViewModel {
        let viewModel = LeadsListViewModel(api: mock())
        await viewModel.load()
        return viewModel
    }

    // MARK: List

    @Test("Agreement filter", arguments: [
        (LeadsListViewModel.AgreementFilter.any, ["Jordan Reyes", "Morgan Chen", "Riley Park"]),
        (.sent, ["Jordan Reyes"]),
        (.signed, ["Morgan Chen"]),
        (.notSent, ["Riley Park"])
    ])
    func agreementFilter(filter: LeadsListViewModel.AgreementFilter, expected: [String]) async {
        let viewModel = await loadedList()
        viewModel.agreementFilter = filter
        #expect(viewModel.filteredLeads.compactMap(\.recordName).sorted() == expected)
    }

    @Test("Status, peril and search")
    func statusPerilSearch() async {
        let viewModel = await loadedList()
        viewModel.statusFilter = "Converted"
        #expect(viewModel.filteredLeads.compactMap(\.recordName) == ["Morgan Chen"])
        viewModel.clearFilters()

        viewModel.perilFilter = "Hail"
        #expect(viewModel.filteredLeads.compactMap(\.recordName) == ["Jordan Reyes"])
        viewModel.clearFilters()

        viewModel.searchText = "marietta"
        #expect(viewModel.filteredLeads.compactMap(\.recordName) == ["Morgan Chen"])
        #expect(viewModel.statusOptions == ["New", "Working", "Qualified", "Converted", "Unqualified"])
    }

    // MARK: Detail

    @Test("Detail loads; lead comments show up in updates after refresh")
    func detailAndComment() async throws {
        let api = mock()
        let viewModel = LeadDetailViewModel(leadId: "a0r000000000001AAA", api: api)
        await viewModel.load()
        #expect(viewModel.detail.value?.prospectName == "Jordan Reyes")
        let before = try #require(viewModel.updates.value).count

        try await api.addComment(to: viewModel.record, text: "Any news?")
        await viewModel.loadUpdates()
        #expect(viewModel.updates.value?.count == before + 1)
        #expect(viewModel.updates.value?.first?.title == "Customer Comment")
    }

    @Test("Agreement steps")
    func agreementSteps() throws {
        let fixtures = try MockPortalAPI.Fixtures.bundled()

        let sent = try #require(LeadDetailViewModel.agreementSteps(for: fixtures.leadDetails["a0r000000000001AAA"]?.agreement))
        #expect(sent.map(\.title) == ["Sent", "Signed"])
        #expect(sent.map(\.state) == [.current, .upcoming])
        #expect(sent[1].date == nil)

        let signed = try #require(LeadDetailViewModel.agreementSteps(for: fixtures.leadDetails["a0r000000000002AAA"]?.agreement))
        #expect(signed.map(\.state) == [.complete, .current])
        #expect(signed[1].date != nil)

        #expect(LeadDetailViewModel.agreementSteps(for: fixtures.leadDetails["a0r000000000003AAA"]?.agreement) == nil)
        #expect(LeadDetailViewModel.agreementSteps(for: nil) == nil)
    }

    // MARK: Submit a Lead

    @Test("Name and a contact method are required")
    func requiredFields() async {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "taylor@example.com", debounce: .zero)
        #expect(form.error(for: .name) == nil, "No errors before the first submit")

        let submitted = await form.submit()
        #expect(!submitted)
        #expect(form.error(for: .name) == "Enter the claimant's name.")
        #expect(form.error(for: .contact) == "Enter at least one contact method: email or phone.")

        form.name = "Jane Smith"
        form.phone = "404-555-0100"
        #expect(form.isValid)
    }

    @Test("Field formats", arguments: [
        ("email", "not-an-email", SubmitLeadViewModel.Field.email),
        ("zip", "3030", .postalCode),
        ("zip", "30301-1234", .postalCode),
        ("link", "dropbox folder", .fileLink),
        ("link", "ftp://example.com", .fileLink)
    ])
    func formats(kind: String, value: String, field: SubmitLeadViewModel.Field) {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "taylor@example.com", debounce: .zero)
        form.name = "Jane"
        form.phone = "555"
        switch kind {
        case "email": form.email = value
        case "zip": form.postalCode = value
        default: form.fileLink = value
        }
        #expect(form.errors[field] != nil)
    }

    @Test("Valid formats pass")
    func validFormats() {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "taylor@example.com", debounce: .zero)
        form.name = "Jane"
        form.email = "jane@example.com"
        form.postalCode = "30301"
        form.fileLink = "https://drive.example.com/folder"
        #expect(form.isValid)
    }

    @Test("Submission maps fields and forces the referral email")
    func submission() async throws {
        let api = mock()
        let form = SubmitLeadViewModel(api: api, userEmail: "taylor@brooksroofing.example.com", debounce: .zero)
        form.name = "  Jane Smith "
        form.email = "jane@example.com"
        form.stateCode = "GA"
        form.claimFiled = .no
        form.claimNumber = "CLM-should-be-dropped"
        form.referralCompany = "Brooks Roofing"

        let submission = form.submission
        #expect(submission.leadName == "Jane Smith")
        #expect(submission.phone == nil)
        #expect(submission.didFileClaim == "No")
        #expect(submission.claimNumber == nil)
        #expect(submission.associatedPartyEmail == "taylor@brooksroofing.example.com")

        #expect(await form.submit())
        let id = try #require(form.createdLeadId)
        #expect(try await api.lead(id: id).prospectName == "Jane Smith")
        #expect(form.confirmationMessage == "Thank you, Jane Smith. We have received your information and our team will review it promptly.")
    }

    @Test("Claim number is sent only when a claim was filed")
    func claimNumber() {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "t@example.com", debounce: .zero)
        form.name = "Jane"
        form.claimFiled = .yes
        form.claimNumber = "CLM-9"
        #expect(form.submission.claimNumber == "CLM-9")
    }

    @Test("Insurance typeahead starts at 2 characters and handles no results")
    func typeahead() async {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "t@example.com", debounce: .zero)

        form.insuranceQuery = "s"
        #expect(form.insuranceSearch == .idle)

        form.insuranceQuery = "st"
        await form.awaitInsuranceSearch()
        guard case .results(let results) = form.insuranceSearch else {
            Issue.record("Expected results, got \(form.insuranceSearch)")
            return
        }
        // Contains-match, like the server's LIKE '%term%': "Allstate" matches too.
        #expect(results.map(\.name) == ["Allstate", "State Farm"])

        form.selectInsuranceCompany(results[1])
        #expect(form.insuranceQuery == "State Farm")
        #expect(form.insuranceSearch == .idle)
        #expect(form.submission.insuranceCompanyId == "a0I000000000004AAA")

        form.insuranceQuery = "zzz"
        await form.awaitInsuranceSearch()
        #expect(form.insuranceSearch == .noResults)
        #expect(form.submission.insuranceCompanyId == nil, "Editing the text clears the selection")
    }

    @Test("Typeahead errors say search is unavailable")
    func typeaheadUnavailable() async {
        let form = SubmitLeadViewModel(api: MockPortalAPI(fixtures: .empty, failure: .server(status: 500)), userEmail: "t@example.com", debounce: .zero)
        form.insuranceQuery = "state"
        await form.awaitInsuranceSearch()
        #expect(form.insuranceSearch == .unavailable)
    }

    @Test("Typing quickly only searches once (debounce)")
    func debounce() async {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "t@example.com", debounce: .milliseconds(150))
        for prefix in ["st", "sta", "stat", "state"] {
            form.insuranceQuery = prefix
        }
        #expect(form.insuranceSearch == .idle, "Nothing runs until the debounce passes")
        await form.awaitInsuranceSearch()
        #expect(form.insuranceSearch == .results([
            InsuranceCompany(id: "a0I000000000001AAA", name: "Allstate"),
            InsuranceCompany(id: "a0I000000000004AAA", name: "State Farm")
        ]))
    }

    @Test("Perils come from the API")
    func perils() async {
        let form = SubmitLeadViewModel(api: mock(), userEmail: "t@example.com", debounce: .zero)
        await form.loadPerils()
        #expect(form.perils.value?.first == "Wind")
    }
}
