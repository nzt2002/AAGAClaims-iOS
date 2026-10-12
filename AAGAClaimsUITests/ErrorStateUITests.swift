import XCTest

/// Milestone 7: every screen shows a friendly error with Retry when loading fails (spec §7).
final class ErrorStateUITests: XCTestCase {
    func testEveryScreenShowsErrorWithRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock", "-MockFailure", "YES"]
        app.launch()

        func expectError(_ subject: String, file: StaticString = #filePath, line: UInt = #line) {
            let message = app.staticTexts["Unable to load \(subject). Pull to refresh or contact support."]
            XCTAssertTrue(message.waitForExistence(timeout: 10), "No error for \(subject)", file: file, line: line)
            XCTAssertTrue(app.buttons["Retry"].exists, "No Retry for \(subject)", file: file, line: line)
            // Never show raw server errors.
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "500")).firstMatch.exists)
        }

        expectError("your dashboard")
        app.tabBars.buttons["Claims"].tap()
        expectError("claims")
        app.tabBars.buttons["Leads"].tap()
        expectError("leads")
        app.tabBars.buttons["Support"].tap()
        expectError("your support cases")

        // Detail screens, via deep links.
        app.open(URL(string: "aagaclaims://claim/a23000000000001AAA")!)
        expectError("this claim")
        app.open(URL(string: "aagaclaims://lead/a0r000000000001AAA")!)
        expectError("this lead")
        app.open(URL(string: "aagaclaims://case/500000000000001AAA")!)
        expectError("this case")

        // Retry tries again (and fails again here, without crashing).
        app.buttons["Retry"].tap()
        expectError("this case")
    }
}
