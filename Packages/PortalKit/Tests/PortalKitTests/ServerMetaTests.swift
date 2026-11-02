import Foundation
import Testing
@testable import PortalKit

@Suite("Server meta")
struct ServerMetaTests {
    @Test("Decodes the Alex agent Id when the server sends one")
    func assistantAgent() throws {
        let json = #"{"apiVersion":6,"features":["assistant","staffCases"],"assistantAgentId":"0XxRh0000000HC9KAM"}"#
        let meta = try JSONDecoder().decode(ServerMeta.self, from: Data(json.utf8))
        #expect(meta.supports(.assistant))
        #expect(meta.assistantAgentId == "0XxRh0000000HC9KAM")
    }

    @Test("No agent Id from servers without Alex, or for users without access")
    func noAssistantAgent() throws {
        let older = #"{"apiVersion":6,"features":["staffCases"]}"#
        let noAccess = #"{"apiVersion":6,"features":["assistant"],"assistantAgentId":null}"#
        #expect(try JSONDecoder().decode(ServerMeta.self, from: Data(older.utf8)).assistantAgentId == nil)
        #expect(try JSONDecoder().decode(ServerMeta.self, from: Data(noAccess.utf8)).assistantAgentId == nil)
        #expect(ServerMeta.legacy.assistantAgentId == nil)
    }
}
