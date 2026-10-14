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
