import XCTest

/// Home: hero search, quick actions, agenda, activity, Update sheet and notifications.
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

    private func element(containingCaseInsensitive text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private var bell: XCUIElement { app.buttons["notificationsBell"] }

    func testHomeLayout() {
        let welcome = app.staticTexts["Welcome back, Alex!"]
        let submit = app.buttons["quickSubmitLead"]
        let newEvent = app.buttons["quickNewEvent"]
        let newTask = app.buttons["quickNewTask"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5))
        XCTAssertLessThan(welcome.frame.maxY, submit.frame.minY, "Quick actions sit under the welcome message")
        XCTAssertTrue(app.buttons["quickMyClaims"].label.contains("My Claims"))
        XCTAssertEqual(newEvent.frame.midX, newTask.frame.midX, accuracy: 2, "New Event is in the same column as New Task")
        XCTAssertLessThan(newEvent.frame.maxY, newTask.frame.minY, "New Event is above New Task")

        // Top bar has only the bell; search is the bar in the hero.
        XCTAssertFalse(app.buttons["quickAskQuestion"].exists)
        XCTAssertFalse(app.buttons["askQuestion"].exists)
        XCTAssertFalse(app.buttons["search"].exists)
        XCTAssertTrue(bell.exists)
        let search = app.buttons["homeSearch"]
        XCTAssertTrue(search.exists)
        XCTAssertLessThan(welcome.frame.maxY, search.frame.minY, "Search sits under the welcome message")
        XCTAssertLessThan(search.frame.maxY, submit.frame.minY, "Search sits above the quick actions")
        XCTAssertFalse(app.buttons["heroNextUp"].exists, "Next up was removed")
        XCTAssertFalse(app.buttons["heroUnread"].exists, "Unread pill was removed")

        XCTAssertFalse(app.staticTexts["Status overview"].exists, "Status overview was removed")
        XCTAssertFalse(app.buttons["tileOpenClaims"].exists, "KPI tiles are gone")
    }

    func testSearchOpensRecord() {
        app.buttons["homeSearch"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Jordan")
        let lead = app.buttons["searchResult-a0r000000000001AAA"]
        XCTAssertTrue(lead.waitForExistence(timeout: 5))
        lead.tap()
        XCTAssertTrue(app.tabBars.buttons["Leads"].isSelected)
        XCTAssertTrue(element(containing: "Jordan Reyes").waitForExistence(timeout: 5))
    }

    func testChatterPostInRecentActivityOpensItsClaim() {
        let post = app.buttons["post-0D5000000000001AAA"]
        XCTAssertTrue(post.waitForExistence(timeout: 5))
        XCTAssertTrue(post.label.contains("Carrier called back"))
        app.scrollIntoView(post)
        post.tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
    }

    func testNewEventAppearsInUpcoming() {
        app.buttons["quickNewEvent"].tap()
        let save = app.buttons["newEventSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["newEventClaim"].tap()
        app.buttons["Smith - Roof"].tap()
        let subject = app.textFields["newEventSubject"]
        subject.tap()
        subject.typeText("Re-inspection")
        save.tap()
        XCTAssertTrue(element(containing: "Re-inspection").waitForExistence(timeout: 5))
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

    func testRecentActivityFilterAndHeaders() {
        let post = app.buttons["post-0D5000000000001AAA"]
        XCTAssertTrue(post.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activityFilter-Chatter"].isSelected, "Staff start on Chatter")
        XCTAssertFalse(app.buttons["activity-a1Y000000000002AAA"].exists)
        XCTAssertTrue(post.label.hasPrefix("Claim · Smith - Roof"), "The record is the header: \(post.label)")

        let all = app.buttons["activityFilter-All"]
        app.scrollIntoView(all)
        all.tap()
        let update = app.buttons["activity-a1Y000000000002AAA"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        XCTAssertTrue(update.label.hasPrefix("Claim · Smith - Roof"), update.label)
        XCTAssertTrue(post.exists)
    }

    func testNewTaskOnLead() {
        app.buttons["quickNewTask"].tap()
        let save = app.buttons["newTaskSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.segmentedControls["newTaskRelatedKind"].buttons["Lead"].tap()
        app.buttons["newTaskLead"].tap()
        app.buttons["Jordan Reyes"].tap()
        let subject = app.textFields["newTaskSubject"]
        subject.tap()
        subject.typeText("Resend the agreement")
        save.tap()
        XCTAssertTrue(element(containing: "Lead · Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Resend the agreement").exists)
    }

    func testSearchCloses() {
        app.buttons["homeSearch"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Smith")
        app.buttons["searchClose"].tap()
        XCTAssertTrue(app.buttons["homeSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["searchField"].exists, "The sheet closed, not just the search field")
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

    func testActivityOpensUpdateSheetMarksReadAndOpensClaim() {
        XCTAssertEqual(bell.label, "Notifications, 2 unread")

        // Staff (the demo user) start on Chatter; portal updates are one filter away.
        let updatesFilter = app.buttons["activityFilter-Portal updates"]
        app.scrollIntoView(updatesFilter)
        updatesFilter.tap()
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
        app.buttons["quickMyClaims"].tap()
        XCTAssertTrue(app.tabBars.buttons["Claims"].isSelected)
    }

    func testSearchScopesRecentsAndEmptyState() {
        app.buttons["homeSearch"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find anything"].exists, "Tips show before the first search")

        field.typeText("Smith")
        let claimsScope = app.buttons["searchScope-Claims"]
        XCTAssertTrue(element(containingCaseInsensitive: "Claims · ").waitForExistence(timeout: 5))
        XCTAssertTrue(claimsScope.label.contains("4 results"))

        app.buttons["searchScope-Leads"].tap()
        XCTAssertTrue(element(containing: "No leads match").waitForExistence(timeout: 5))
        app.buttons["Show all 5 results"].tap()
        XCTAssertTrue(element(containingCaseInsensitive: "Claims · 4").waitForExistence(timeout: 5))

        // Submitting saves the search; it's offered again when the field is cleared.
        app.keyboards.buttons["search"].tap()
        app.buttons["searchClear"].tap()
        let recent = app.buttons["recentSearch-Smith"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(element(containingCaseInsensitive: "Claims · 4").waitForExistence(timeout: 5))

        app.buttons["searchClear"].tap()
        app.buttons["Clear recent searches"].tap()
        XCTAssertTrue(app.staticTexts["Find anything"].waitForExistence(timeout: 5))
    }
}
