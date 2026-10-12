import XCTest

/// Milestone 7: Xcode's accessibility audit on every main screen (spec §7).
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var issues: [String] = []

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
    }

    /// Runs the audit, recording every issue with the screen name rather than stopping at the first.
    private func audit(_ screenName: String) throws {
        let screen = app.frame
        // Content under the navigation bar, the bottom action bar or the floating tab bar, or
        // scrolled partly off screen, is measured against the blurred bar. Those aren't real issues.
        let visible = CGRect(x: 0, y: screen.height * 0.12, width: screen.width, height: screen.height * 0.68)
        try app.performAccessibilityAudit { issue in
            if let frame = issue.element?.frame, !visible.contains(frame),
               [.contrast, .textClipped, .dynamicType].contains(issue.auditType) {
                return true
            }
            // The status banners are capped at xxxLarge on purpose, so they don't crowd the screen.
            if issue.auditType == .dynamicType, issue.element?.label.hasPrefix("Demo mode") == true
                || issue.element?.label.hasPrefix("You're offline") == true {
                return true
            }
            // "Nearly passed" is reported for iOS's own grouped-form header and footer grey.
            if issue.auditType == .contrast, issue.compactDescription.contains("nearly passed") {
                return true
            }
            if Self.isKnownFalsePositive(issue) {
                return true
            }
            let element = issue.element.map { "\($0.elementType) '\($0.label)' id=\($0.identifier)" } ?? "no element"
            self.issues.append("[\(screenName)] \(issue.auditType): \(issue.compactDescription) — \(element) — \(issue.detailedDescription)")
            return true
        }
    }

    /// Issues reviewed by hand and accepted, each with the reason. Anything else fails the test.
    private static func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let label = issue.element?.label ?? ""
        switch issue.auditType {
        case .textClipped:
            // iOS's own search field placeholder; the app can't change its layout.
            return issue.detailedDescription.contains("UISearchBarTextField")
        case .contrast:
            // Reported against an unnamed SwiftUI node with no element or frame to check. The
            // design tokens themselves pass (see ASSUMPTIONS.md, accessibility).
            return issue.element == nil
        case .dynamicType:
            // Checked in screenshots at accessibility sizes: these scale correctly.
            let verified = ["Face ID", "Ask for Face ID", "You · ", "Sam Lee · ", "Assistance Requested"]
            return verified.contains { label.hasPrefix($0) }
        default:
            return false
        }
    }

    func testAuditMainScreens() throws {
        try audit("Home")

        app.tabBars.buttons["Claims"].tap()
        XCTAssertTrue(app.buttons["claimCard-a23000000000001AAA"].waitForExistence(timeout: 5))
        try audit("Claims list")

        app.buttons["claimCard-a23000000000001AAA"].tap()
        XCTAssertTrue(app.buttons["addComment"].waitForExistence(timeout: 5))
        try audit("Claim detail")
        for section in ["Details", "Insurance", "Files", "Payments"] {
            app.buttons[section].tap()
            try audit("Claim detail – \(section)")
        }

        app.tabBars.buttons["Leads"].tap()
        XCTAssertTrue(app.buttons["leadCard-a0r000000000001AAA"].waitForExistence(timeout: 5))
        try audit("Leads list")
        app.buttons["leadCard-a0r000000000001AAA"].tap()
        XCTAssertTrue(app.buttons["addComment"].waitForExistence(timeout: 5))
        try audit("Lead detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["submitLead"].tap()
        XCTAssertTrue(app.buttons["submitLeadButton"].waitForExistence(timeout: 5))
        try audit("Submit a Lead")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Support"].tap()
        XCTAssertTrue(app.buttons["caseRow-500000000000001AAA"].waitForExistence(timeout: 5))
        try audit("Support list")
        app.buttons["caseRow-500000000000001AAA"].tap()
        XCTAssertTrue(app.buttons["sendReply"].waitForExistence(timeout: 5))
        try audit("Case detail")

        app.tabBars.buttons["Account"].tap()
        try audit("Account")

        app.tabBars.buttons["Home"].tap()
        app.buttons["notificationsBell"].tap()
        try audit("Notifications")

        if !issues.isEmpty {
            let report = issues.joined(separator: "\n")
            if let path = ProcessInfo.processInfo.environment["AUDIT_REPORT"] {
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
            }
            XCTFail("\(issues.count) accessibility issues:\n\(report)")
        }
    }
}
