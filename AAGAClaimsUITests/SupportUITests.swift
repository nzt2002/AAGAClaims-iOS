import XCTest

/// Milestone 4: support cases, thread, reply and Request Assistance.
final class SupportUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.tabBars.buttons["Support"].tap()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openRoofCase() {
        let row = app.buttons["caseRow-500000000000001AAA"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element(containing: "the inspection is booked for October 9").waitForExistence(timeout: 5))
    }

    func testReplyAppearsInThread() {
        openRoofCase()
        let reply = app.descendants(matching: .any).matching(identifier: "replyText").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        reply.typeText("Can the adjuster come after 10am?")
        app.buttons["sendReply"].tap()
        XCTAssertTrue(element(containing: "You wrote: Can the adjuster come after 10am?").waitForExistence(timeout: 5))
    }

    func testRelatedRecordOpensClaim() {
        openRoofCase()
        app.buttons["caseRelatedRecord"].tap()
        XCTAssertTrue(app.staticTexts["Claim CLM-1234"].waitForExistence(timeout: 5)
            || element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
    }

    func testRequestAssistanceFromSupport() {
        let button = app.buttons["supportRequestAssistance"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        // Submitting empty shows both errors.
        app.buttons["assistanceSubmit"].tap()
        XCTAssertTrue(element(containing: "Choose the claim or lead you need help with.").waitForExistence(timeout: 5))

        app.buttons["assistanceRecord"].tap()
        app.buttons["Lead: Riley Park (New)"].tap()
        // Wait for the field, whatever element type SwiftUI gives it.
        let comments = app.descendants(matching: .any).matching(identifier: "assistanceComments").firstMatch
        XCTAssertTrue(comments.waitForExistence(timeout: 5))
        comments.tap()
        comments.typeText("Has an adjuster been assigned?")
        app.buttons["assistanceSubmit"].tap()

        // Opens the new case.
        XCTAssertTrue(element(containing: "Assistance Requested - Riley Park").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "No updates have been posted yet.").exists)
    }

    func testSearchAndClosedFilter() {
        XCTAssertTrue(app.buttons["caseRow-500000000000001AAA"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["caseRow-500000000000002AAA"].exists, "Closed cases are hidden by default")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Closed")).firstMatch.tap()
        XCTAssertTrue(app.buttons["caseRow-500000000000002AAA"].waitForExistence(timeout: 5))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All")).firstMatch.tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("signed yet")
        XCTAssertTrue(app.buttons["caseRow-500000000000002AAA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["caseRow-500000000000001AAA"].exists)
    }
}
