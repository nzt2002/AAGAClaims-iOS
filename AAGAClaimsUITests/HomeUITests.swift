import XCTest

/// Milestone 5: Home tiles, status overview, activity, Update sheet, notifications and quick actions.
final class HomeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private var bell: XCUIElement { app.buttons["notificationsBell"] }

    /// Scrolls in small steps until the element sits in the middle of the screen, clear of the
    /// navigation bar and the floating tab bar, so a tap lands on it. Full swipes overshoot.
    private func scrollIntoView(_ element: XCUIElement) {
        let height = app.frame.height
        for _ in 0..<15 {
            if element.exists, element.frame.minY > height * 0.25, element.frame.maxY < height * 0.7 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let dy = element.exists && element.frame.minY < height * 0.25 ? 0.15 : -0.15
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6 + dy)))
        }
    }

    func testOpenClaimsTileFiltersList() {
        app.buttons["tileOpenClaims"].tap()
        XCTAssertTrue(app.buttons["claimCard-a0X000000000001AAA"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Open claims").exists)
        XCTAssertFalse(app.buttons["claimCard-a0X000000000003AAA"].exists, "The closed claim is hidden")
    }

    func testStatusOverviewRowFiltersByStage() {
        let row = app.buttons["stage-Negotiations"]
        scrollIntoView(row)
        row.tap()
        XCTAssertTrue(app.buttons["claimCard-a0X000000000002AAA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["claimCard-a0X000000000001AAA"].exists)
    }

    func testActivityOpensUpdateSheetMarksReadAndOpensClaim() {
        XCTAssertEqual(bell.label, "Notifications, 2 unread")

        let item = app.buttons["activity-a1Y000000000002AAA"]
        scrollIntoView(item)
        item.tap()
        XCTAssertTrue(element(containing: "Inspection is booked for October 9.").waitForExistence(timeout: 5))

        app.buttons["openUpdateRecord"].tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Claims"].isSelected)

        // Opening the update marked it read.
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertEqual(bell.label, "Notifications, 1 unread")
    }

    func testNotificationsOpenUpdateAndMarkAllRead() {
        bell.tap()
        let item = app.buttons["notification-a1Y000000000010AAA"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons["Open Lead"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        app.buttons["markAllRead"].tap()
        XCTAssertTrue(app.staticTexts["No unread notifications"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(bell.label, "Notifications")
    }

    func testQuickActions() {
        app.buttons["quickSubmitLead"].tap()
        XCTAssertTrue(app.buttons["submitLeadButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Leads"].isSelected)
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Home"].tap()
        app.buttons["quickRequestAssistance"].tap()
        XCTAssertTrue(app.buttons["assistanceSubmit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Support"].isSelected)
    }
}
