import XCTest

/// Milestone 1: every tab shows mock data, and sign-out works.
final class MilestoneOneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Demo auth and the mock API with no artificial latency.
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
    }

    func testEveryTabShowsMockData() {
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Claims"].tap()
        XCTAssertTrue(app.staticTexts["Smith - Roof"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["29% complete"].exists)

        app.tabBars.buttons["Leads"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Reyes"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Support"].tap()
        XCTAssertTrue(app.staticTexts["Assistance Requested - Smith - Roof"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Account"].tap()
        // LabeledContent combines the label and value into one accessibility element.
        let email = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "alex.smith@example.com"))
            .firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5))
    }

    func testNotificationsSheet() {
        let bell = app.buttons["notificationsBell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        let update = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Carrier review update"))
            .firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 5))
    }

    func testSignOutReturnsToSplash() {
        app.tabBars.buttons["Account"].tap()
        app.buttons["signOut"].tap()
        app.sheets.buttons["Sign out"].firstMatch.tap()
        XCTAssertTrue(app.buttons["continueDemo"].waitForExistence(timeout: 5))
    }
}
