import Foundation
import Testing
@testable import PortalKit

@Suite("Deep links and push payloads")
struct DeepLinkTests {
    private let claimId = "a23000000000001AAA"
    private let leadId = "a0r000000000001AAA"
    private let caseId = "500000000000001AAA"

    @Test("App scheme links")
    func appScheme() {
        #expect(DeepLink(url: URL(string: "aagaclaims://claim/\(claimId)")!) == .claim(id: claimId))
        #expect(DeepLink(url: URL(string: "aagaclaims://lead/\(leadId)")!) == .lead(id: leadId))
        #expect(DeepLink(url: URL(string: "aagaclaims://case/\(caseId)")!) == .supportCase(id: caseId))
        #expect(DeepLink(url: URL(string: "AAGACLAIMS://Claim/\(claimId)")!) == .claim(id: claimId))
    }

    @Test("Portal universal links")
    func universalLinks() {
        let base = "https://portal.accurateadjustmentsga.com"
        #expect(DeepLink(url: URL(string: "\(base)/s/detail/\(claimId)")!) == .claim(id: claimId))
        #expect(DeepLink(url: URL(string: "\(base)/s/detail/\(leadId)")!) == .lead(id: leadId))
        #expect(DeepLink(url: URL(string: "\(base)/s/my-case-detail?recordId=\(caseId)")!) == .supportCase(id: caseId))
    }

    @Test("Rejected links", arguments: [
        "aagaclaims://claim/",
        "aagaclaims://claim/not-an-id",
        "aagaclaims://claim/a23000000000001AAA/extra%20junk%27",
        "aagaclaims://payments/a23000000000001AAA",
        "https://evil.example.com/s/detail/a23000000000001AAA",
        "http://portal.accurateadjustmentsga.com/s/detail/a23000000000001AAA",
        "https://portal.accurateadjustmentsga.com/s/detail/001000000000001AAA",
        "https://portal.accurateadjustmentsga.com/s/my-case-detail?recordId=a23000000000001AAA",
        "https://portal.accurateadjustmentsga.com/s/my-case-detail"
    ])
    func rejected(url: String) {
        #expect(DeepLink(url: URL(string: url)!) == nil)
    }

    @Test("15-character ids are accepted")
    func shortIds() {
        #expect(DeepLink(url: URL(string: "aagaclaims://claim/a23000000000001")!) == .claim(id: "a23000000000001"))
    }

    @Test("Push payloads")
    func push() {
        #expect(DeepLink(pushPayload: ["type": "update", "recordId": claimId, "commentId": "a1Y1"])
                == .update(record: .claim(claimId), commentId: "a1Y1"))
        #expect(DeepLink(pushPayload: ["type": "update", "recordId": leadId])
                == .update(record: .lead(leadId), commentId: nil))
        #expect(DeepLink(pushPayload: ["type": "caseReply", "recordId": caseId, "commentId": "00a1"])
                == .supportCase(id: caseId))
    }

    @Test("Bad push payloads are ignored")
    func badPush() {
        #expect(DeepLink(pushPayload: [:]) == nil)
        #expect(DeepLink(pushPayload: ["type": "update", "recordId": caseId]) == nil)
        #expect(DeepLink(pushPayload: ["type": "caseReply", "recordId": claimId]) == nil)
        // Chatter posts, e-sign and case updates (case id for homeowners, the record for staff).
        #expect(DeepLink(pushPayload: ["type": "post", "recordId": claimId]) == .claim(id: claimId))
        #expect(DeepLink(pushPayload: ["type": "esign", "recordId": claimId]) == .claim(id: claimId))
        #expect(DeepLink(pushPayload: ["type": "case", "recordId": caseId]) == .supportCase(id: caseId))
        #expect(DeepLink(pushPayload: ["type": "case", "recordId": claimId]) == .claim(id: claimId))
        #expect(DeepLink(pushPayload: ["type": "marketing", "recordId": claimId]) == nil)
        #expect(DeepLink(pushPayload: ["type": "update", "recordId": 42]) == nil)
    }

    @Test("Universal links on the app link domain use the portal's paths")
    func appLinkDomain() {
        #expect(DeepLink(url: URL(string: "https://app.accurateadjustmentsga.com/s/detail/a23000000000001AAA")!) == .claim(id: "a23000000000001AAA"))
        #expect(DeepLink(url: URL(string: "https://app.accurateadjustmentsga.com/s/my-case-detail?recordId=500000000000001AAA")!) == .supportCase(id: "500000000000001AAA"))
        #expect(DeepLink(url: URL(string: "https://evil.example.com/s/detail/a23000000000001AAA")!) == nil)
    }

    @Test("Payment, mention and task pushes open the record")
    func newPushTypes() {
        #expect(DeepLink(pushPayload: ["type": "payment", "recordId": "a23000000000001AAA"]) == .claim(id: "a23000000000001AAA"))
        #expect(DeepLink(pushPayload: ["type": "mention", "recordId": "a0r000000000001AAA"]) == .lead(id: "a0r000000000001AAA"))
        #expect(DeepLink(pushPayload: ["type": "task"]) == nil)
    }
}
