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

@MainActor
@Suite("People")
struct PeopleTests {
    private func mock() throws -> MockPortalAPI {
        MockPortalAPI(fixtures: try .bundled(), latency: .zero)
    }

    @Test("Staff search finds people; others don't, and don't get the People scope")
    func search() async throws {
        let api = try mock()
        let staff = SearchViewModel(api: api, debounce: .zero, includePeople: true)
        #expect(staff.scopes.contains(.people))
        staff.query = "Jane"
        await staff.awaitSearch()
        #expect(staff.allResults.contains { $0.type == .user && $0.id == "005000000000002AAA" })
        #expect(staff.sections.first?.kind == .user, "People come first")
        staff.scope = .people
        #expect(staff.sections.map(\.kind) == [.user])

        let portal = SearchViewModel(api: api, debounce: .zero)
        #expect(!portal.scopes.contains(.people))
        portal.query = "Jane"
        await portal.awaitSearch()
        #expect(!portal.allResults.contains { $0.type == .user })
    }

    @Test("Profile and feed load; replies are added and own replies edited in place")
    func profileAndReplies() async throws {
        let api = try mock()
        let model = PersonViewModel(api: api, personId: "005000000000002AAA")
        await model.load()
        #expect(model.person.value?.name == "Jane Doe")
        #expect(model.person.value?.initials == "JD")
        let post = try #require(model.feed.value?.first)
        #expect(post.replies.count == 2)

        #expect(!model.canSend(post.id))
        model.drafts[post.id] = "  Photos are in the claim now.  "
        #expect(await model.sendReply(to: post.id))
        #expect(model.feed.value?.first?.replies.last?.text == "Photos are in the claim now.")
        #expect(model.feed.value?.first?.totalReplies == 3)
        #expect(model.drafts[post.id] == nil)

        // Someone else's reply can't be edited.
        let theirs = post.replies[0]
        model.startEditing(theirs)
        #expect(model.editingReplyId == nil)

        let mine = post.replies[1]
        model.startEditing(mine)
        #expect(model.editingReplyId == mine.id)
        #expect(model.editText == "I'll update the claim after.")
        model.editText = "Claim updated."
        #expect(await model.saveEdit())
        #expect(model.editingReplyId == nil)
        #expect(model.feed.value?.first?.replies.first { $0.id == mine.id }?.text == "Claim updated.")
        let reloaded = try await api.personFeed(id: "005000000000002AAA")
        #expect(reloaded.first?.replies.first { $0.id == mine.id }?.text == "Claim updated.")
    }

    @Test("Search asks the server for people only when allowed")
    func httpQuery() async throws {
        actor Recorder: PortalTransport {
            var request: TransportRequest?
            func send(_ request: TransportRequest) async throws -> TransportResponse {
                self.request = request
                return TransportResponse(statusCode: 200, body: Data("[]".utf8))
            }
        }
        let recorder = Recorder()
        _ = try await HTTPPortalAPI(transport: recorder).search("Jane", includePeople: true)
        #expect(await recorder.request?.queryItems.contains(URLQueryItem(name: "includeUsers", value: "true")) == true)
        _ = try await HTTPPortalAPI(transport: recorder).search("Jane", includePeople: false)
        #expect(await recorder.request?.queryItems.contains { $0.name == "includeUsers" } == false)
    }
}
