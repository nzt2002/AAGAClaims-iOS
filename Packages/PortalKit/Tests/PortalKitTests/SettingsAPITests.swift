import Foundation
import Testing
@testable import PortalKit

private actor Recorder: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    private let status: Int
    private let body: String
    init(status: Int = 200, body: String = #"{"ok":true}"#) { self.status = status; self.body = body }
    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: status, body: Data(body.utf8))
    }
}

@Suite("Settings API")
struct SettingsAPITests {
    private func sentBody(_ t: Recorder) async throws -> [String: Any] {
        let request = try #require(await t.requests.last)
        let data = try #require(request.jsonBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func companyChangesSendTheActionAndOnlyItsFields() async throws {
        let t = Recorder()
        let api = HTTPPortalAPI(transport: t)
        try await api.saveCompanySetting(.message(event: "payment", enabled: false))
        let body = try await sentBody(t)
        #expect(body["action"] as? String == "message")
        #expect(body["event"] as? String == "payment")
        #expect(body["enabled"] as? Bool == false)
        #expect(body["markText"] == nil)
        let path = try #require(await t.requests.last).path
        #expect(path.hasSuffix("/settings/company"))
    }

    @Test func clearingTheLeadOwnerOmitsItSoTheServerClearsIt() async throws {
        let t = Recorder()
        try await HTTPPortalAPI(transport: t).saveCompanySetting(.webLeads(enabled: true, ownerId: nil, keepGroup: false))
        let body = try await sentBody(t)
        #expect(body["action"] as? String == "webLeads")
        #expect(body["ownerId"] == nil)
        #expect(body["keepGroup"] as? Bool == false)
    }

    @Test func passwordGoesWithTheCurrentOne() async throws {
        let t = Recorder()
        try await HTTPPortalAPI(transport: t).changePassword(current: "old-pass", new: "new-password")
        let body = try await sentBody(t)
        #expect(body["currentPassword"] as? String == "old-pass")
        #expect(body["password"] as? String == "new-password")
        #expect(try #require(await t.requests.last).path.hasSuffix("/settings/me/password"))
    }

    @Test func aRefusedPasswordShowsTheServersWords() async throws {
        let t = Recorder(status: 400, body: #"{"error":"wrong_password","message":"That isn't your current password."}"#)
        await #expect(throws: PortalAPIError.rejected("That isn't your current password.")) {
            try await HTTPPortalAPI(transport: t).changePassword(current: "x", new: "long-enough-1")
        }
    }

    @Test func readsYourSettingsAndTheCompanys() async throws {
        let me = #"{"fullName":"Alex","email":"a@x.test","phone":null,"canEditProfile":true,"emailAlerts":[{"kind":"task","label":"A task","hint":"h","on":true}]}"#
        let mine = try await HTTPPortalAPI(transport: Recorder(body: me)).mySettings()
        #expect(mine.emailAlerts.first?.on == true)
        #expect(mine.phone == nil)

        let co = ##"{"name":"Acme","markText":null,"brandColor":"#0B5CAB","claimVisibility":"all","leadVisibility":"assigned","webLeads":{"enabled":true,"ownerId":null,"ownerIsGroup":false},"uploadRules":{"staffFolderRequired":true,"portalFolderRequired":false},"messages":[{"event":"payment","label":"A payment","audience":"homeowner","when":"w","enabled":false}],"people":[{"id":"m1","name":"Amy"}],"can":{"brand":true,"visibility":false,"webLeads":false,"uploadRules":false,"messages":true}}"##
        let company = try await HTTPPortalAPI(transport: Recorder(body: co)).companySettings()
        #expect(company.leadVisibility == "assigned")
        #expect(company.messages.first?.isForPolicyholders == true)
        #expect(company.can.visibility == false)
        #expect(company.can.isEmpty == false)
    }
}
