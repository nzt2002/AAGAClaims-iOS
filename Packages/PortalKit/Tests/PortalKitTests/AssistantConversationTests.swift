import Foundation
import Testing
@testable import PortalKit

@Suite("Alex conversation history")
struct AssistantConversationTests {
    private let conversation = AssistantConversation(
        recordId: "a23Rh000004HiwnIAC",
        startedAt: Date(timeIntervalSince1970: 1_793_000_000),
        endedAt: Date(timeIntervalSince1970: 1_793_000_300),
        source: "iOS app 2.3.0 (47)",
        messages: [
            .init(role: "user", text: "What's the deductible?", at: Date(timeIntervalSince1970: 1_793_000_000)),
            .init(role: "alex", text: "**$500.00**", at: Date(timeIntervalSince1970: 1_793_000_005)),
        ]
    )

    @Test("Encodes the fields POST /assistant/conversations reads, with ISO 8601 dates")
    func encoding() throws {
        let data = try PortalJSON.makeEncoder().encode(conversation)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["recordId"] as? String == "a23Rh000004HiwnIAC")
        #expect(json["source"] as? String == "iOS app 2.3.0 (47)")
        #expect((json["startedAt"] as? String)?.hasSuffix("Z") == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "alex"])
        #expect(messages[1]["text"] as? String == "**$500.00**")
    }

    @Test("The mock keeps saved conversations")
    func mockSaves() async throws {
        let api = MockPortalAPI.standard(latency: .zero)
        try await api.saveAssistantConversation(conversation)
        #expect(await api.assistantConversations == [conversation])
    }
}
