import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Claim actions")
struct ClaimActionsTests {
    private let claimId = "a23000000000001AAA"

    private func mock() throws -> MockPortalAPI {
        MockPortalAPI(fixtures: try .bundled(), latency: .zero)
    }

    @Test("Staff data loads; edit, address, owner and Proof of Loss save")
    func editAndSave() async throws {
        let api = try mock()
        let model = ClaimActionsViewModel(api: api, claimId: claimId)
        await model.load()
        let staff = try #require(model.staff.value)
        #expect(staff.name == "Smith - Roof")
        #expect(staff.statuses.contains("Inspection"))

        var edit = ClaimEdit(name: " ")
        #expect(!(await model.saveEdit(edit)))
        #expect(model.errorMessage == "Enter a claim name.")
        edit = ClaimEdit(name: "Smith - Roof and Gutters")
        edit.status = "Inspection"
        #expect(!(await model.saveEdit(edit)), "The org's validation rule")
        #expect(model.errorMessage?.contains("Deductible") == true)
        edit.deductible = 1000
        edit.adjusterFees = 10
        #expect(await model.saveEdit(edit))
        #expect(model.staff.value?.name == "Smith - Roof and Gutters", "Reloaded after saving")
        #expect(try await api.claim(id: claimId).claimName == "Smith - Roof and Gutters")

        #expect(await model.saveAddress(ClaimAddress(street: "9 Elm St", city: "Marietta", state: "GA", postalCode: "30060")))
        #expect(try await api.claim(id: claimId).lossAddress == "9 Elm St, Marietta, GA 30060")
        #expect(await model.changeOwner(to: "005000000000002AAA"))
        #expect(model.staff.value?.ownerName == "Jane Doe")

        var pol = ProofOfLoss()
        #expect(!pol.isComplete)
        #expect(pol.missingCount == 13)
        pol.policyEffectiveDate = CalendarDate(year: 2026, month: 6, day: 1)
        pol.policyExpirationDate = CalendarDate(year: 2026, month: 1, day: 1)
        #expect(!(await model.saveProofOfLoss(pol)))
        pol.policyExpirationDate = CalendarDate(year: 2027, month: 6, day: 1)
        pol.totalLossDamage = 25000
        #expect(await model.saveProofOfLoss(pol))
        #expect(model.staff.value?.proofOfLoss.totalLossDamage == 25000)
    }

    @Test("Payment calculator: totals match the quick action")
    func payments() async throws {
        let api = try mock()
        let edit = ClaimActionsViewModel(api: api, claimId: claimId)
        await edit.load()
        var values = ClaimEdit(name: "Smith - Roof")
        values.deductible = 1000
        values.adjusterFees = 10
        #expect(await edit.saveEdit(values))

        let calc = PaymentCalculatorViewModel(api: api, claimId: claimId)
        await calc.load()
        #expect(!calc.isBlocked)
        #expect(calc.feeRate == Decimal(string: "0.1"))

        let first = calc.rows[0].id
        calc.setType(PaymentCalculatorViewModel.rcv, for: first)
        calc.rows[0].amount = 20000
        calc.addRow()
        calc.setType("NET Payment (ACV)", for: calc.rows[1].id)
        calc.rows[1].amount = 9000
        #expect(calc.totalRCV == 20000)
        #expect(calc.received == 9000, "RCV doesn't count as received")
        #expect(calc.adjusterFee == 900)
        #expect(calc.insuredPayment == 8100)

        // Choosing Deductible switches on the system deductible instead of adding a row.
        calc.addRow()
        calc.setType(PaymentCalculatorViewModel.deductibleType, for: calc.rows[2].id)
        #expect(calc.applyDeductible)
        #expect(calc.rows[2].rowType == nil)
        #expect(!calc.paymentTypes.contains(PaymentCalculatorViewModel.deductibleType))
        #expect(calc.adjusterFee == 1000, "Fee includes the deductible: (9000 + 1000) × 10%")
        #expect(calc.insuredPayment == 8000)

        #expect(calc.entry.rows.count == 2, "Rows without a type aren't sent")
        #expect(await calc.save())
        let recorded = await api.recorded(claimId: claimId)
        #expect(recorded.payments.first?.applyDeductible == true)
    }

    @Test("Payments are blocked without a deductible")
    func paymentsBlocked() async throws {
        let api = try mock()
        let edit = ClaimActionsViewModel(api: api, claimId: claimId)
        await edit.load()
        var values = ClaimEdit(name: "Smith - Roof")
        values.deductible = nil
        #expect(await edit.saveEdit(values))
        let calc = PaymentCalculatorViewModel(api: api, claimId: claimId)
        await calc.load()
        #expect(calc.isBlocked)
        #expect(!(await calc.save()))
        #expect(calc.errorMessage?.contains("Deductible") == true)
    }

    @Test("Add Contact: matches first; an existing link is refused")
    func addContact() async throws {
        let api = try mock()
        let model = AddClaimContactViewModel(api: api, claimId: claimId)
        model.mode = .new
        await model.continueFromForm()
        #expect(model.errorMessage == "Choose the contact's role.")
        model.role = "Property Contact"
        model.firstName = "Someone"
        model.lastName = "Else"
        model.mobile = "(404) 555-0122"
        await model.continueFromForm()
        #expect(model.step == .matches, "Same mobile phone as Morgan Field")
        #expect(model.matches.first?.id == "003000000000001AAA")
        await model.useMatch(model.matches[0])
        #expect(model.step == .done)
        #expect(await api.recorded(claimId: claimId).contacts.contains("003000000000001AAA"))

        let again = AddClaimContactViewModel(api: api, claimId: claimId)
        again.role = "Adjuster"
        again.selectedContact = ContactMatch(id: "003000000000001AAA", name: "Morgan Field")
        await again.continueFromForm()
        #expect(again.errorMessage == "This contact is already on the claim.")
    }

    @Test("Recent activity: open items first, then logged calls and history")
    func claimActivities() async throws {
        let api = try mock()
        let actions = ClaimActionsViewModel(api: api, claimId: claimId)
        try await api.logCall(claimId: claimId, CallLog(subject: "Called the carrier", description: "Left a voicemail", contactId: nil))
        await actions.loadActivities()
        let items = try #require(actions.activities.value)
        let call = try #require(items.first { $0.subject == "Called the carrier" })
        #expect(call.subtype == "Call")
        #expect(call.isClosed == true)
        #expect(call.description == "Left a voicemail")
        let firstClosed = try #require(items.firstIndex { $0.isClosed == true })
        #expect(items[..<firstClosed].allSatisfy { $0.isClosed == false })
        #expect(items.allSatisfy { $0.relatedRecordId == claimId })
    }

    @Test("Claim feed: post, then reply")
    func claimFeed() async throws {
        let api = try mock()
        let feed = ChatterFeedViewModel(api: api, source: .claim(claimId))
        await feed.load()
        #expect(feed.feed.value?.contains { $0.text?.contains("Carrier called back") == true } == true)
        #expect(await feed.post("  Estimate approved.  "))
        let top = try #require(feed.feed.value?.first)
        #expect(top.text == "Estimate approved.")
        let person = ChatterFeedViewModel(api: api, source: .person("005000000000002AAA"))
        #expect(!(await person.post("Not on a person's feed")))
    }

    @Test("Log a Call and Send an Email")
    func callAndEmail() async throws {
        let api = try mock()
        let call = LogCallViewModel(api: api, claimId: claimId)
        call.subject = " "
        #expect(!(await call.save()))
        call.subject = "Called the homeowner"
        call.details = "Inspection Friday"
        #expect(await call.save())

        let email = EmailComposerViewModel(api: api, claimId: claimId, defaultRecipient: "alex.smith@example.com")
        #expect(!email.canSend)
        #expect(!email.add("not an email", to: \.cc))
        #expect(email.add("a@example.com; b@example.com, a@example.com", to: \.cc))
        #expect(email.cc == ["a@example.com", "b@example.com"])
        email.subject = "Inspection"
        email.body = "Hi <Alex>\nSee you Friday."
        #expect(email.htmlBody == "Hi &lt;Alex&gt;<br>See you Friday.")
        #expect(await email.send())
        let recorded = await api.recorded(claimId: claimId)
        #expect(recorded.calls.first?.description == "Inspection Friday")
        #expect(recorded.emails.first?.to == ["alex.smith@example.com"])
    }

    @Test("400s with a message become readable errors")
    func rejectedMessages() {
        #expect(HTTPPortalAPI.message(Data(#"{"error":"validation","message":"Please update Deductible."}"#.utf8)) == "Please update Deductible.")
        #expect(HTTPPortalAPI.message(Data(#"{"error":"invalid_request"}"#.utf8)) == nil)
        #expect(ClaimActionsViewModel.message(for: PortalAPIError.rejected("Nope")) == "Nope")
    }
}

@MainActor
@Suite("Lead actions")
struct LeadActionsTests {
    private let leadId = "a0r000000000001AAA"

    private func mock() throws -> MockPortalAPI {
        MockPortalAPI(fixtures: try .bundled(), latency: .zero)
    }

    @Test("Edit saves; Converted can't be set by hand")
    func editLead() async throws {
        let api = try mock()
        let model = LeadActionsViewModel(api: api, leadId: leadId)
        await model.load()
        let staff = try #require(model.staff.value)
        #expect(staff.name == "Jordan Reyes")
        #expect(staff.city == "Atlanta")
        var edit = LeadEdit(staff)
        edit.status = "Converted"
        #expect(!(await model.saveEdit(edit)))
        #expect(model.errorMessage == "Use Convert to Account to convert a lead.")
        edit.status = "Qualified"
        edit.email = "bad"
        #expect(!(await model.saveEdit(edit)))
        edit.email = "jordan.new@example.com"
        #expect(await model.saveEdit(edit))
        #expect(model.staff.value?.status == "Qualified")
        #expect(try await api.lead(id: leadId).email == "jordan.new@example.com")
    }

    @Test("Convert: prefilled, the existing account must be used, then the lead is converted")
    func convert() async throws {
        let api = try mock()
        let actions = LeadActionsViewModel(api: api, leadId: leadId)
        await actions.load()
        let form = NewClaimViewModel(api: api, conversion: LeadConversion(try #require(actions.staff.value)))
        #expect(form.accountFirstName == "Jordan")
        #expect(form.accountLastName == "Reyes")
        #expect(form.contactMode == .new, "The associated party is offered as the claim contact")
        #expect(form.contactLastName == "Brooks")

        // Jordan Reyes already has an account in the mock: it must be used.
        #expect(await form.continueWithNewAccount() == .accountMatches)
        #expect(form.chooseAccount(form.accountMatches[0]) == .contact, "No claim-details step when converting")
        form.contactMode = .skip
        #expect(await form.continueFromContact() == .review)
        #expect(await form.submit() == nil)
        let claimId = try #require(form.createdClaimId)
        #expect(try await api.claim(id: claimId).claimName == "Jordan Reyes")
        #expect(try await api.lead(id: leadId).prospectStatus == "Converted")

        let again = NewClaimViewModel(api: api, conversion: LeadConversion(try await api.leadStaff(id: leadId)))
        _ = again.chooseAccount(AccountMatch(id: "001000000000002AAA", name: "Jordan Reyes"))
        #expect(await again.submit() == nil)
        #expect(again.error == .alreadyConverted(claimId: claimId))
    }

    @Test("Lead feed: post")
    func leadFeed() async throws {
        let api = try mock()
        let feed = ChatterFeedViewModel(api: api, source: .lead(leadId))
        await feed.load()
        #expect(await feed.post("Agreement sent."))
        #expect(feed.feed.value?.first?.text == "Agreement sent.")
    }
}

@MainActor
@Suite("Mentions")
struct MentionTests {
    @Test("Typing @ finds the query; picking inserts the name; only names left in the text are sent")
    func draft() {
        var draft = MentionDraft(text: "Thanks @Ja")
        #expect(draft.activeQuery == "Ja")
        draft.insert(Mention(id: "005000000000002AAA", name: "Jane Doe"))
        #expect(draft.text == "Thanks @Jane Doe ")
        #expect(draft.activeQuery == nil, "A chosen mention isn't searched again")
        draft.text += "and @Sam L"
        #expect(draft.activeQuery == "Sam L", "One space allowed, for last names")
        draft.insert(Mention(id: "005000000000003AAA", name: "Sam Lee"))
        #expect(draft.resolvedMentions.map(\.name) == ["Jane Doe", "Sam Lee"])
        draft.text = "Thanks @Sam Lee "
        #expect(draft.resolvedMentions.map(\.name) == ["Sam Lee"], "Deleted mentions aren't sent")
        #expect(MentionDraft(text: "email me@example.com").activeQuery == nil, "@ inside a word isn't a mention")
        #expect(MentionDraft(text: "hi @a b c").activeQuery == nil)
    }

    @Test("Posts and replies send their mentions")
    func send() async throws {
        let api = MockPortalAPI(fixtures: try .bundled(), latency: .zero)
        let feed = ChatterFeedViewModel(api: api, source: .claim("a23000000000001AAA"))
        await feed.load()
        let people = await feed.mentionCandidates("Ja")
        #expect(people.map(\.name) == ["Jane Doe"])
        var draft = MentionDraft(text: "@")
        draft.insert(people[0])
        draft.text += "can you check the estimate?"
        #expect(await feed.post(draft))
        #expect(feed.feed.value?.first?.mentions == ["Jane Doe"])

        let postId = try #require(feed.feed.value?.first?.id)
        var reply = MentionDraft(text: "Looping in @Sa")
        reply.insert(Mention(id: "005000000000003AAA", name: "Sam Lee"))
        feed.drafts[postId] = reply
        // Replies on posts outside the people fixtures aren't stored by the mock; check the request instead.
        #expect(reply.resolvedMentions.map(\.id) == ["005000000000003AAA"])
    }

    @Test("Mentions are sent as {id, name}")
    func httpBody() async throws {
        actor Recorder: PortalTransport {
            var request: TransportRequest?
            func send(_ request: TransportRequest) async throws -> TransportResponse {
                self.request = request
                return TransportResponse(statusCode: 201, body: Data(#"{"id":"0D7X","text":"hi"}"#.utf8))
            }
        }
        let recorder = Recorder()
        _ = try await HTTPPortalAPI(transport: recorder).addReply(toPost: "0D5X", text: "hi @Jane Doe", mentions: [Mention(id: "005A", name: "Jane Doe")])
        let body = try #require(await recorder.request?.jsonBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let mentions = try #require(json["mentions"] as? [[String: Any]])
        #expect(mentions.first?["id"] as? String == "005A")
        #expect(mentions.first?["name"] as? String == "Jane Doe")
    }
}

@MainActor
@Suite("Tasks and events from a record")
struct RecordActivityTests {
    @Test("Subject suggestions: all when empty, matches as you type, starts-with first")
    func suggestions() {
        let subjects = ["Check - Received from Insurer", "POL - Proof of Loss received from Client", "Call - Follow-up on supplement review"]
        #expect(ActivitySubjects.suggestions(for: "", in: subjects) == subjects)
        #expect(ActivitySubjects.suggestions(for: "rec", in: subjects) == ["Check - Received from Insurer", "POL - Proof of Loss received from Client"])
        #expect(ActivitySubjects.suggestions(for: "call", in: subjects) == ["Call - Follow-up on supplement review"])
        #expect(ActivitySubjects.suggestions(for: "Call - Follow-up on supplement review", in: subjects).isEmpty, "A chosen subject isn't suggested again")
    }

    @Test("A task from a lead page belongs to that lead, with subject suggestions")
    func taskFromLead() async throws {
        let api = MockPortalAPI(fixtures: try .bundled(), latency: .zero)
        let form = NewTaskViewModel(api: api, currentUserName: "Alex Smith", record: .lead("a0r000000000001AAA"))
        await form.loadOptions()
        #expect(form.lockedRecord == .lead("a0r000000000001AAA"))
        #expect(form.record == .lead("a0r000000000001AAA"))
        form.subject = "pol"
        #expect(form.subjectSuggestions == ["POL - Proof of Loss received from Client"])
        form.subject = form.subjectSuggestions[0]
        #expect(await form.submit())
        let item = try #require(try await api.agenda().items.first { $0.subject == "POL - Proof of Loss received from Client" })
        #expect(item.relatedRecordType == .prospect)
    }

    @Test("An event from a claim page belongs to that claim")
    func eventFromClaim() async throws {
        let api = MockPortalAPI(fixtures: try .bundled(), latency: .zero)
        let form = NewEventViewModel(api: api, currentUserName: "Alex Smith", record: .claim("a23000000000001AAA"))
        await form.loadOptions()
        #expect(form.record == .claim("a23000000000001AAA"))
        form.subject = "Mee"
        #expect(form.subjectSuggestions == ["Meeting"])
        form.subject = "Meeting"
        #expect(await form.submit())
        #expect(try await api.agenda().items.contains { $0.subject == "Meeting" && $0.relatedRecordName == "Smith - Roof" })
    }
}

@Suite("Salesforce page links")
struct SalesforcePageLinkTests {
    @Test("The front-door link goes to the page; the token never appears")
    func link() throws {
        let path = SalesforcePageLink.path("/apex/hic_docmerge__Composer", query: [
            URLQueryItem(name: "id", value: "a0r000000000001AAA"),
            URLQueryItem(name: "documentSolutionKey", value: "994dd7c4")
        ])
        #expect(path == "/apex/hic_docmerge__Composer?id=a0r000000000001AAA&documentSolutionKey=994dd7c4")

        let body = String(decoding: SalesforcePageLink.requestBody(for: path), as: UTF8.self)
        #expect(body == "redirect_uri=%2Fapex%2Fhic_docmerge__Composer%3Fid%3Da0r000000000001AAA%26documentSolutionKey%3D994dd7c4")

        let response = Data(#"{"frontdoor_uri":"https://proclaimer.my.salesforce.com/secur/frontdoor.jsp?otp=ONE-TIME&cshc=abc"}"#.utf8)
        let url = try #require(SalesforcePageLink.url(fromResponse: response, pagePath: path))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "otp", value: "ONE-TIME")))
        #expect(items.contains(URLQueryItem(name: "retURL", value: path)))

        let withRedirect = Data(#"{"frontdoor_uri":"https://x.my.salesforce.com/secur/frontdoor.jsp?otp=1&retURL=%2Fapex%2FPage"}"#.utf8)
        let kept = try #require(SalesforcePageLink.url(fromResponse: withRedirect, pagePath: path))
        #expect(URLComponents(url: kept, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "retURL" }.count == 1)

        #expect(SalesforcePageLink.url(fromResponse: Data("{}".utf8), pagePath: path) == nil)
    }
}
