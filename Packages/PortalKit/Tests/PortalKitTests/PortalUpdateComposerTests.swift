import Foundation
import Testing
@testable import PortalKit

@Suite("Portal update composer")
@MainActor
struct PortalUpdateComposerTests {
    private func mock() throws -> MockPortalAPI {
        MockPortalAPI(fixtures: try .bundled(), latency: .zero)
    }

    @Test("Draft loads with everyone selected; posting adds the update and emails who's picked")
    func draftAndPost() async throws {
        let api = try mock()
        let model = PortalUpdateComposerViewModel(api: api, record: .claim("a23000000000001AAA"))
        await model.load()
        #expect(model.text.contains("Current update"))
        #expect(model.sendEmail)
        #expect(model.emailRecipientIds == model.recipients.map(\.id))

        model.sendEmail = false
        #expect(model.emailRecipientIds.isEmpty)
        model.sendEmail = true
        model.text = "**Current update**\nInspection is Friday."
        let posted = await model.post()
        #expect(posted?.emailed == 1)
        let updates = try await api.updates(for: .claim("a23000000000001AAA"))
        #expect(updates.first?.title == "Recent Portal Update")
    }

    @Test("Blank updates aren't posted")
    func blank() async throws {
        let model = PortalUpdateComposerViewModel(api: try mock(), record: .lead("a0r000000000001AAA"))
        model.text = "  \n "
        #expect(!model.canPost)
        #expect(await model.post() == nil)
        #expect(model.errorMessage != nil)
    }
}
