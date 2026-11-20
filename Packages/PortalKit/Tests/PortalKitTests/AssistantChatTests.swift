import Foundation
import Testing
@testable import PortalKit

private actor OneReplyTransport: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    private let status: Int
    private let body: String

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: status, body: Data(body.utf8))
    }
}

@Suite("Alex chat on the platform")
struct AssistantChatTests {
    private let turns: [AssistantChatTurn] = [.user("Where is the Brooks claim?"), .assistant("It is in Negotiations."), .user("Who owns it?")]

    @Test("Sends the chat so far and the claim on screen, and returns the reply")
    func sendsChat() async throws {
        let transport = OneReplyTransport(status: 200, body: #"{"reply":"Jody-Ann owns it."}"#)
        let api = HTTPPortalAPI(transport: transport)
        let reply = try await api.assistantChat(messages: turns, recordId: "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(reply == "Jody-Ann owns it.")

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/assistant/chat")
        let sent = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(json["recordId"] as? String == "0f8fad5b-d9cb-469f-a165-70867728950e")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect(messages.last?["text"] as? String == "Who owns it?")
    }

    @Test("Leaves recordId out when no claim is open")
    func noRecord() async throws {
        let transport = OneReplyTransport(status: 200, body: #"{"reply":"ok"}"#)
        _ = try await HTTPPortalAPI(transport: transport).assistantChat(messages: [.user("hi")], recordId: nil)
        let body = try #require(await transport.requests.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["recordId"] == nil)
    }

    @Test("A server refusal surfaces as an error, with the status so the screen can explain it")
    func refusal() async {
        let api = HTTPPortalAPI(transport: OneReplyTransport(status: 403, body: #"{"error":"Alex isn't turned on for your company."}"#))
        await #expect(throws: (any Error).self) {
            _ = try await api.assistantChat(messages: [.user("hi")], recordId: nil)
        }
    }

    @Test("The mock answers, so demo mode and previews work")
    func mock() async throws {
        let reply = try await MockPortalAPI(fixtures: try .bundled()).assistantChat(messages: [.user("hi")], recordId: nil)
        #expect(!reply.isEmpty)
    }

    @Test("The feature is announced by name and is part of the full set")
    func feature() {
        #expect(ServerMeta(apiVersion: 6, features: ["assistantChat"]).supports(.assistantChat))
        #expect(!ServerMeta.legacy.supports(.assistantChat))
        #expect(ServerMeta.all.supports(.assistantChat))
    }
}
