import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("New Claim")
struct NewClaimTests {
    private func mock() throws -> MockPortalAPI {
        MockPortalAPI(fixtures: try .bundled(), latency: .zero)
    }

    @Test("A new account that matches an existing one must use the match")
    func newAccountMatches() async throws {
        let api = try mock()
        let form = NewClaimViewModel(api: api)
        await form.loadOptions()
        #expect(form.ownerId == "005000000000001AAA", "The adjuster defaults to me")
        #expect(form.source == "Web Lead")

        #expect(await form.continueWithNewAccount() == nil)
        #expect(form.error(.accountLastName, on: .newAccount) == "Enter a last name.")

        form.accountFirstName = "Someone"
        form.accountLastName = "Else"
        form.accountEmail = "JORDAN.REYES@example.com"
        #expect(await form.continueWithNewAccount() == .accountMatches, "Same email, different name")
        #expect(form.accountMatches.map(\.id) == ["001000000000002AAA"])

        form.accountEmail = ""
        form.accountFirstName = "alex"
        form.accountLastName = "smith"
        #expect(await form.continueWithNewAccount() == .accountMatches, "Same first and last name")

        #expect(form.chooseAccount(form.accountMatches[0]) == .claimDetails)
        #expect(!form.isNewAccount)
        #expect(form.claimName == "Alex Smith")
        #expect(form.claimEmail == "alex.smith@example.com")
    }

    @Test("A new account with no match goes straight to the claim, and the claim is created")
    func newAccountCreates() async throws {
        let api = try mock()
        let form = NewClaimViewModel(api: api)
        await form.loadOptions()
        form.accountFirstName = "Taylor"
        form.accountLastName = "Nguyen"
        form.accountEmail = "taylor@example.com"
        #expect(await form.continueWithNewAccount() == .claimDetails)
        #expect(form.isNewAccount)
        #expect(form.claimName == "Taylor Nguyen")

        form.claimName = "Nguyen - Water"
        form.adjusterFees = "150"
        #expect(form.continueFromClaimDetails() == nil)
        form.adjusterFees = "10"
        form.peril = "Water Damage"
        #expect(form.continueFromClaimDetails() == .contact)
        #expect(await form.continueFromContact() == .review, "Contact is optional")

        #expect(await form.submit() == nil)
        let id = try #require(form.createdClaimId)
        #expect(try await api.claim(id: id).claimName == "Nguyen - Water")

        // The server-side check: the same new account a second time is refused.
        let again = NewClaimViewModel(api: api)
        again.accountFirstName = "Taylor"
        again.accountLastName = "Nguyen"
        #expect(await again.continueWithNewAccount() == .accountMatches)
    }

    @Test("The server refuses a duplicate account even if the app didn't catch it")
    func serverDuplicate() async throws {
        let api = try mock()
        let form = NewClaimViewModel(api: api)
        form.accountLastName = "Smith"
        form.accountFirstName = "Alex"
        form.claimName = "Smith - Fence"
        #expect(await form.submit() == .accountMatches)
        #expect(form.accountMatches.first?.id == "001000000000001AAA")
        #expect(form.createdClaimId == nil)
    }

    @Test("A new contact: matches first, then the partner account for subcontractors")
    func contactAndPartner() async throws {
        let api = try mock()
        let form = NewClaimViewModel(api: api)
        _ = form.chooseAccount(AccountMatch(id: "001000000000001AAA", name: "Alex Smith"))
        form.claimName = "Smith - Roof 2"
        form.contactMode = .new
        #expect(await form.continueFromContact() == nil)
        #expect(form.error(.contactRole, on: .contact) != nil)
        #expect(form.error(.contactLastName, on: .contact) != nil)

        form.contactRole = NewClaimViewModel.subcontractorRole
        form.contactFirstName = "Chris"
        form.contactLastName = "Builder"
        form.contactCompany = "Peachtree Roofing LLC"
        #expect(await form.continueFromContact() == .contactMatches)
        #expect(form.contactMatches.map(\.id) == ["003000000000002AAA"])

        // None of these: carry on with the new contact; the company already exists, so pick it.
        #expect(await form.noContactMatches() == .partner)
        #expect(form.partnerMatches.map(\.id) == ["001000000000003AAA"])
        #expect(form.continueFromPartner() == nil, "A matching partner account must be chosen")
        form.selectedPartner = form.partnerMatches[0]
        #expect(form.continueFromPartner() == .review)
        guard case .new(_, let role, let partner) = form.request.contact else {
            Issue.record("Expected a new contact")
            return
        }
        #expect(role == "Sub-Contractor")
        #expect(partner == .existing(id: "001000000000003AAA"))
        #expect(await form.submit() == nil)
        #expect(form.createdClaimId != nil)
    }

    @Test("A duplicate contact from the server: use the existing one or skip")
    func duplicateContact() async throws {
        let api = try mock()
        let form = NewClaimViewModel(api: api)
        _ = form.chooseAccount(AccountMatch(id: "001000000000001AAA", name: "Alex Smith"))
        form.claimName = "Smith - Garage"
        form.contactMode = .new
        form.contactRole = "Property Contact"
        form.contactLastName = "Fieldstone"
        form.contactEmail = "morgan.field@example.com"
        #expect(await form.submit() == .duplicateContact)
        #expect(form.duplicateContacts.map(\.id) == ["003000000000001AAA"])
        #expect(await form.resolveDuplicateContact(using: form.duplicateContacts[0]) == nil)
        #expect(form.createdClaimId != nil)
        #expect(form.request.contact == .existing(id: "003000000000001AAA", role: "Property Contact"))
    }

    @Test("The request JSON matches the server's shape")
    func requestJSON() throws {
        var claim = NewClaimRequest.Claim(name: "Smith - Roof")
        claim.lossDate = CalendarDate(year: 2026, month: 10, day: 1)
        claim.adjusterFees = 10
        let request = NewClaimRequest(
            account: .new(.init(firstName: "Pat", lastName: "Q", email: nil, phone: nil)),
            claim: claim,
            contact: .new(.init(firstName: nil, lastName: "B", email: nil, phone: nil, company: "Co"),
                          role: "Sub-Contractor", partner: .new(name: "Co"))
        )
        let data = try PortalJSON.makeEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let account = try #require(json["account"] as? [String: Any])
        #expect((account["new"] as? [String: Any])?["lastName"] as? String == "Q")
        let claimJSON = try #require(json["claim"] as? [String: Any])
        #expect(claimJSON["lossDate"] as? String == "2026-10-01")
        let contact = try #require(json["contact"] as? [String: Any])
        #expect(contact["role"] as? String == "Sub-Contractor")
        #expect((contact["partnerAccount"] as? [String: Any])?["name"] as? String == "Co")
    }

    @Test("409 bodies decode into the matches")
    func duplicateDecoding() {
        let body = Data(#"{"error":"duplicate_contact","matches":[{"id":"003X","name":"Morgan"}]}"#.utf8)
        let duplicate = HTTPPortalAPI.duplicateMatches(body)
        #expect(duplicate.kind == .contact)
        #expect(duplicate.contacts.first?.id == "003X")
        let accounts = HTTPPortalAPI.duplicateMatches(Data(#"{"error":"duplicate_account","matches":[{"id":"001X","name":"Pat"}]}"#.utf8))
        #expect(accounts.kind == .account)
        #expect(accounts.accounts.first?.id == "001X")
    }
}
