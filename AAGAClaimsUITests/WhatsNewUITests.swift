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
        XCTAssertEqual(items.count, 8)
        XCTAssertTrue(items.element(boundBy: 0).label.contains("A Cases tab"), items.element(boundBy: 0).label)
        continueButton.tap()
        XCTAssertFalse(continueButton.waitForExistence(timeout: 2))

        app.buttons["accountButton"].firstMatch.tap()
        let again = app.buttons["whatsNewButton"]
        // Below Sign Out and Delete Account: scroll to it.
        app.scrollIntoView(again)
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(app.buttons["whatsNewContinue"].waitForExistence(timeout: 5))
        app.buttons["whatsNewContinue"].tap()

        // Every version's notes, the installed one marked.
        let notes = app.buttons["releaseNotesLink"]
        app.scrollIntoView(notes)
        notes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["currentVersionBadge"].firstMatch.waitForExistence(timeout: 5))
        let older = app.descendants(matching: .any)["release-0.2.3"].firstMatch
        app.scrollIntoView(older)
        XCTAssertTrue(older.exists, "Older versions are kept")
    }

    func testDeleteAccountRequestsDeletionThenSignsOut() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.dismissSystemAlerts()
        app.buttons["accountButton"].firstMatch.tap()
        let delete = app.buttons["deleteAccount"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        app.scrollIntoView(delete)
        delete.tap()
        let confirm = app.buttons["confirmDeleteAccount"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.alerts["Request received"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["accountButton"].waitForExistence(timeout: 3), "Signed out")
    }

    /// Account: once notifications are allowed, a switch for each kind; changes are saved.
    func testNotificationKindsCanBeSwitchedOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
        app.buttons["accountButton"].firstMatch.tap()
        let toggle = app.switches["notificationsToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.waitForExistence(timeout: 5) { alert.buttons["Allow"].tap() }
        }
        let payments = app.switches["notificationKind-payments"].firstMatch
        if !payments.waitForExistence(timeout: 10) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-501/acct.png"))
        }
        XCTAssertTrue(payments.exists, "The list appears once notifications are allowed")
        // Staff (the demo user) also see the staff kinds (the full list is checked in PortalKit's tests).
        XCTAssertTrue(app.switches["notificationKind-mentions"].firstMatch.exists)
        XCTAssertEqual(payments.value as? String, "1")
        // Tap the switch itself (the row's label area doesn't toggle it).
        payments.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        sleep(2)
        XCTAssertEqual(payments.value as? String, "0")
        // Reopen Account: the choice was saved.
        app.buttons["accountDone"].tap()
        app.buttons["accountButton"].firstMatch.tap()
        let again = app.switches["notificationKind-payments"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(again.value as? String, "0")
    }
}
