import Foundation
import Testing
@testable import PortalKit

@Suite("Alex conversation history")
struct AssistantConversationTests {
    private let conversation = AssistantConversation(
        recordId: "a23Rh000004HiwnIAC",
        startedAt: Date(timeIntervalSince1970: 1_793_000_000),
        endedAt: Date(timeIntervalSince1970: 1_793_000_300),
        source: "iOS app 2.4.0 (48)",
        messages: [
            .init(role: "user", text: "I'm viewing the claim \"Harper\" (claim # 123).", at: Date(timeIntervalSince1970: 1_793_000_000)),
            .init(role: "user", text: "What's the deductible?", at: Date(timeIntervalSince1970: 1_793_000_010)),
            .init(role: "alex", text: "**$500.00**", at: Date(timeIntervalSince1970: 1_793_000_015)),
        ]
    )

    @Test("Encodes the fields POST /assistant/conversations reads; feedback only when answered")
    func encoding() throws {
        let data = try PortalJSON.makeEncoder().encode(conversation)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["recordId"] as? String == "a23Rh000004HiwnIAC")
        #expect((json["startedAt"] as? String)?.hasSuffix("Z") == true)
        #expect(json["helpful"] == nil)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "user", "alex"])

        var rated = conversation
        rated.helpful = false
        rated.reason = .wrongClaim
        let ratedJSON = try #require(try JSONSerialization.jsonObject(with: PortalJSON.makeEncoder().encode(rated)) as? [String: Any])
        #expect(ratedJSON["helpful"] as? Bool == false)
        #expect(ratedJSON["reason"] as? String == "Wrong claim")
    }

    @Test("Decodes the server's history list and detail (Salesforce date format)")
    func decoding() throws {
        let list = Data("""
        [{"id":"a5XRh0000001AAA","name":"ALEX-00001","startedAt":"2026-11-02T16:00:00.000Z","userName":"Jody-Ann Anyanwu",
          "isMine":true,"messageCount":2,"firstQuestion":"What is the deductible?","recordId":"a23Rh000004HiwnIAC",
          "recordName":"Harper","recordType":"claim","helpful":false,"feedbackReason":"Too long"}]
        """.utf8)
        let summaries = try PortalJSON.makeDecoder().decode([AssistantChatSummary].self, from: list)
        #expect(summaries.first?.feedbackReason == .tooLong)
        #expect(summaries.first?.canRate == false)
        #expect(summaries.first?.startedAt != nil)

        let detail = Data("""
        {"conversation":{"id":"a5X1","isMine":true,"messageCount":1,"helpful":null},
         "messages":[{"role":"alex","text":"**$500.00**","at":"2026-11-02T16:00:04.000Z"},{"role":"user","text":"hi","at":null}]}
        """.utf8)
        let decoded = try PortalJSON.makeDecoder().decode(AssistantChatDetail.self, from: detail)
        #expect(decoded.conversation.canRate)
        #expect(decoded.messages.first?.isAlex == true)
        #expect(decoded.messages.last?.at == nil)
    }

    @Test("Mock saves, lists newest first, opens and rates chats")
    func mockHistory() async throws {
        let api = MockPortalAPI.standard(latency: .zero)
        let first = try await api.saveAssistantConversation(conversation)
        let second = try await api.saveAssistantConversation(AssistantConversation(
            recordId: nil, startedAt: Date(), endedAt: Date(), source: "test",
            messages: [.init(role: "user", text: "Stalled claims?", at: Date())]))

        let mine = try await api.assistantConversations(recordId: nil)
        #expect(mine.map(\.id) == [second, first])
        let onClaim = try await api.assistantConversations(recordId: "a23Rh000004HiwnIAC")
        #expect(onClaim.map(\.id) == [first])
        #expect(onClaim.first?.firstQuestion == "What's the deductible?")

        let rated = try await api.rateAssistantConversation(id: first, helpful: false, reason: .wrongInfo)
        #expect(rated.helpful == false && rated.feedbackReason == .wrongInfo && !rated.canRate)
        let detail = try await api.assistantConversation(id: first)
        #expect(detail.messages.count == 3)
    }
}
