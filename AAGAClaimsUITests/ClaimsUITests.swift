import XCTest

/// Milestone 2: claims list, detail, comments and Request Assistance.
final class ClaimsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.tabBars.buttons["Claims"].tap()
    }

    private func openRoofClaim() {
        let card = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.staticTexts["Claim CLM-1234"].waitForExistence(timeout: 5))
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Filter chips and sort: a stage chip narrows the list and shows its value; Clear resets.
    func testFilterChipsAndSort() {
        let roof = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(roof.waitForExistence(timeout: 10))
        let cardCount = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'claimCard-'")).count

        app.buttons["filterChip-payments"].tap()
        app.buttons["No payment yet"].tap()
        XCTAssertTrue(element(containing: "Payments, No payment yet").waitForExistence(timeout: 5))
        let filtered = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'claimCard-'")).count
        XCTAssertLessThan(filtered, cardCount)

        app.buttons["filterChip-clear"].tap()
        XCTAssertTrue(roof.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filterChip-clear"].exists)

        app.buttons["sortMenu"].tap()
        app.buttons["Name A–Z"].tap()
        XCTAssertTrue(element(containing: "Sort, Name A–Z").waitForExistence(timeout: 5))
    }

    /// Spec §3 testing: login → claim detail.
    func testClaimDetailShowsLifecycleAndSections() {
        openRoofClaim()
        XCTAssertTrue(element(containing: "29 percent complete").exists)
        // Staff (the demo user) see the Claim Feed first; published updates are one tap away.
        let filter = app.segmentedControls["updatesFilter"]
        app.scrollIntoView(filter)
        filter.buttons["Portal Updates"].tap()
        XCTAssertTrue(element(containing: "Carrier review update").waitForExistence(timeout: 5))

        app.buttons["Payments"].tap()
        XCTAssertTrue(app.staticTexts["PMT-0001"].waitForExistence(timeout: 5))

        app.buttons["Insurance"].tap()
        XCTAssertTrue(element(containing: "State Farm").waitForExistence(timeout: 5))

        app.buttons["Files"].tap()
        XCTAssertTrue(element(containing: "Roof photo 1").waitForExistence(timeout: 5))
    }

    func testClaimHasNoAddCommentAndAskQuestionIsInTheTopBar() {
        openRoofClaim()
        XCTAssertFalse(app.buttons["addComment"].exists, "Add Comment was removed from claims")
        let ask = app.buttons["requestAssistance"]
        XCTAssertTrue(ask.exists)
        XCTAssertLessThan(ask.frame.maxY, app.staticTexts["Claim CLM-1234"].frame.minY, "Ask Question is a top-bar icon")
        XCTAssertTrue(app.buttons["claimAction-edit"].exists, "Edit Claim is a top-bar icon for staff")
    }

    func testRequestAssistanceOpensSupport() {
        openRoofClaim()
        app.buttons["requestAssistance"].tap()
        let editor = app.textViews["composerText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Please call me about the estimate.")
        app.buttons["composerSubmit"].tap()

        XCTAssertTrue(element(containing: "We will follow up with you shortly").waitForExistence(timeout: 5))
        app.alerts.buttons["View case"].tap()

        // The Support tab opens and lists the new case. The mock numbers it 00013002 in a fresh launch.
        XCTAssertTrue(app.tabBars.buttons["Support"].isSelected)
        XCTAssertTrue(element(containing: "Case 00013002").waitForExistence(timeout: 5))
    }

    func testSearchFiltersList() {
        XCTAssertTrue(app.buttons["claimCard-a23000000000001AAA"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Kitchen")
        XCTAssertTrue(app.buttons["claimCard-a23000000000002AAA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["claimCard-a23000000000001AAA"].exists)
    }
}
