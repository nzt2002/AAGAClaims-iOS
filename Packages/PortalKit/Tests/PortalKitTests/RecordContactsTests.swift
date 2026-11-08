import Foundation
import Testing
@testable import PortalKit

@Suite("Record contacts and lead progress")
struct RecordContactsTests {
    @Test("Contacts decode from GET /{record}/contacts, with the homeowner's null id")
    func decodesContacts() throws {
        let json = """
        [{"id":"003A","name":"Sam Roofer","role":"Contractor","email":"sam@example.com","phone":"404","mobilePhone":"405","kind":"Contact"},
         {"id":null,"name":"Jordan","role":"Homeowner","email":"j@example.com","phone":null,"mobilePhone":null,"kind":"Lead"}]
        """
        let contacts = try JSONDecoder().decode([RecordContact].self, from: Data(json.utf8))
        #expect(contacts.count == 2)
        #expect(contacts[0].id == "003A")
        #expect(contacts[0].mobilePhone == "405")
        #expect(contacts[1].contactId == nil)
        #expect(contacts[1].id != contacts[0].id)
    }

    @Test("Lead percent: 25/50/75/100, none when Unqualified or unknown")
    func leadPercent() {
        #expect(LeadLifecycle.position(for: "New").percentComplete == 25)
        #expect(LeadLifecycle.position(for: "Working").percentComplete == 50)
        #expect(LeadLifecycle.position(for: "Qualified").percentComplete == 75)
        #expect(LeadLifecycle.position(for: "Converted").percentComplete == 100)
        #expect(LeadLifecycle.position(for: "Converted").stageNumber == 4)
        #expect(LeadLifecycle.position(for: "Unqualified").percentComplete == nil)
        #expect(LeadLifecycle.position(for: "Something else").percentComplete == nil)
    }

    @Test("Claim detail loads contacts only when asked")
    @MainActor
    func claimContactsLoadWhenIncluded() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        let claims = try await api.claims()
        let model = ClaimDetailViewModel(claimId: try #require(claims.first).id, api: api)
        await model.load()
        #expect(model.contacts.value == nil)
        model.includesContacts = true
        await model.load()
        #expect(model.contacts.value?.isEmpty == false)
    }
}
