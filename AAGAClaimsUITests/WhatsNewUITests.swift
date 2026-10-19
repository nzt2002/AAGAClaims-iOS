import XCTest

/// Release notes after sign-in, once per version, and again from Account.
final class WhatsNewUITests: XCTestCase {
    func testShownAfterSignInThenFromAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // "none": as if this version's notes haven't been seen yet.
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock", "-ShowWhatsNew", "YES", "-WhatsNewSeenVersion", "none"]
        app.launch()
        app.dismissSystemAlerts()

        let continueButton = app.buttons["whatsNewContinue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["What's New"].exists || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS \"What's New\"")).firstMatch.exists)
        let items = app.descendants(matching: .any).matching(identifier: "whatsNewItem")
        // The current version's notes; staff see the staff items too.
        XCTAssertEqual(items.count, 4, "Staff see the staff features too")
        XCTAssertTrue(items.element(boundBy: 0).label.contains("Back takes you back"), items.element(boundBy: 0).label)
        continueButton.tap()
        XCTAssertFalse(continueButton.waitForExistence(timeout: 2))

        app.tabBars.buttons["Account"].tap()
        let again = app.buttons["whatsNewButton"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        app.scrollIntoView(again)
        again.tap()
        XCTAssertTrue(app.buttons["whatsNewContinue"].waitForExistence(timeout: 5))
    }
}
