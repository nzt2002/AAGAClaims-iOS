import Testing
@testable import PortalKit

@Suite("Lifecycle")
struct LifecycleTests {
    @Test(
        "Claim percentages match the portal (spec §6.5)",
        arguments: [
            ("Preparation", 14), ("Inspection", 29), ("Negotiations", 43), ("Restoration", 57),
            ("Litigation", 71), ("Settlement", 86), ("Closed", 100)
        ]
    )
    func claimPercent(status: String, expected: Int) {
        #expect(ClaimLifecycle.position(for: status).percentComplete == expected)
    }

    @Test("Unknown claim status hides progress")
    func unknownClaimStatus() {
        let position = ClaimLifecycle.position(for: "On Hold")
        #expect(position == .unknown("On Hold"))
        #expect(position.percentComplete == nil)
    }

    @Test("Status matching ignores case and whitespace")
    func lenientMatching() {
        #expect(ClaimLifecycle.position(for: " negotiations ") == .stage(index: 2))
    }

    @Test("Claim step states")
    func claimSteps() {
        let position = ClaimLifecycle.position(for: "Negotiations")
        #expect(position.state(ofStageAt: 1) == .complete)
        #expect(position.state(ofStageAt: 2) == .current)
        #expect(position.state(ofStageAt: 3) == .upcoming)
    }

    @Test("Unqualified leads use the short track")
    func unqualifiedLead() {
        let position = LeadLifecycle.position(for: "Unqualified")
        #expect(position.stages == ["New", "Working", "Unqualified"])
        #expect(position.state(ofStageAt: 2) == .current)
        #expect(LeadLifecycle.position(for: "Qualified").stages == LeadLifecycle.stages)
    }
}
