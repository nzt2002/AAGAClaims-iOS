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

    func testQuickActionsAreUnderTheWelcomeAndRenamed() {
        let welcome = app.staticTexts["Welcome back, Alex!"]
        let ask = app.buttons["quickAskQuestion"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        XCTAssertTrue(ask.label.contains("Ask Question"))
        XCTAssertTrue(app.buttons["quickMyClaims"].label.contains("My Claims"))
        XCTAssertTrue(app.buttons["quickNewTask"].exists, "Demo user can create tasks")
        XCTAssertLessThan(welcome.frame.maxY, ask.frame.minY, "Quick actions sit under the welcome message")
        XCTAssertFalse(app.buttons["tileOpenClaims"].exists, "KPI tiles are gone")
    }

    func testRecentClaimOpensClaim() {
        let row = app.buttons["recentClaim-a23000000000001AAA"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.scrollIntoView(row)
        row.tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Claims"].isSelected)
    }

    func testUpcomingEventOpensItsClaim() {
        let event = app.buttons["agenda-00U000000000001AAA"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(event.label.contains("Roof inspection"))
        app.scrollIntoView(event)
        event.tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
    }

    func testNewTaskAppearsInUpcoming() {
        app.buttons["quickNewTask"].tap()
        let save = app.buttons["newTaskSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        // Saving empty shows the errors.
        save.tap()
        XCTAssertTrue(element(containing: "Enter a subject.").waitForExistence(timeout: 5))

        app.buttons["newTaskClaim"].tap()
        app.buttons["Smith - Roof"].tap()
        let subject = app.textFields["newTaskSubject"]
        subject.tap()
        subject.typeText("Call the carrier")
        save.tap()

        XCTAssertTrue(element(containing: "Call the carrier").waitForExistence(timeout: 5))
    }

    func testStatusOverviewRowFiltersByStage() {
        let row = app.buttons["stage-Negotiations"]
        app.scrollIntoView(row)
        row.tap()
        XCTAssertTrue(app.buttons["claimCard-a23000000000002AAA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["claimCard-a23000000000001AAA"].exists)
    }

    func testActivityOpensUpdateSheetMarksReadAndOpensClaim() {
        XCTAssertEqual(bell.label, "Notifications, 2 unread")

        let item = app.buttons["activity-a1Y000000000002AAA"]
        app.scrollIntoView(item)
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
        app.buttons["quickAskQuestion"].tap()
        XCTAssertTrue(app.buttons["assistanceSubmit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Support"].isSelected)
    }
}
