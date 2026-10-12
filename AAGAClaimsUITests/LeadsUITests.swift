import XCTest

/// Milestone 3: leads list, lead detail and Submit a Lead.
final class LeadsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.tabBars.buttons["Leads"].tap()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testLeadDetailShowsAgreementAndLifecycle() {
        let card = app.buttons["leadCard-a0r000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(element(containing: "Public Adjuster Agreement").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Sent").exists)
        XCTAssertTrue(element(containing: "Working").exists)
        XCTAssertTrue(app.staticTexts["Agreement sent"].exists, "Updates section shows the published update")

        app.buttons["Insurance"].tap()
        XCTAssertTrue(element(containing: "USAA").waitForExistence(timeout: 5))
    }

    func testLeadCommentAppearsInUpdates() {
        let card = app.buttons["leadCard-a0r000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        app.buttons["addComment"].tap()
        let editor = app.textViews["composerText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Homeowner will sign tonight.")
        app.buttons["composerSubmit"].tap()
        app.alerts.buttons["OK"].tap()

        XCTAssertTrue(element(containing: "Homeowner will sign tonight.").waitForExistence(timeout: 5))
    }

    func testSubmitLeadValidatesThenOpensNewLead() {
        let add = app.buttons["submitLead"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let submit = app.buttons["submitLeadButton"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        XCTAssertTrue(element(containing: "Enter at least one contact method: email or phone.").waitForExistence(timeout: 5))

        let name = app.textFields["leadName"]
        name.tap()
        name.typeText("Casey Morgan")
        let phone = app.textFields["leadPhone"]
        phone.tap()
        phone.typeText("4045550188")

        // Close the phone pad, then scroll: the form is lazy, so the insurance section
        // doesn't exist until it's on screen.
        app.buttons["keyboardDone"].tap()
        let insurance = app.textFields["insuranceCompany"]
        let form = app.collectionViews.firstMatch
        for _ in 0..<8 where !(insurance.exists && insurance.isHittable) {
            form.swipeUp()
        }
        insurance.tap()
        insurance.typeText("trav")
        let travelers = app.buttons["Travelers"]
        XCTAssertTrue(travelers.waitForExistence(timeout: 5))
        travelers.tap()

        submit.tap()
        XCTAssertTrue(element(containing: "Thank you, Casey Morgan.").waitForExistence(timeout: 5))
        app.buttons["leadDone"].tap()

        // Done opens the new lead's detail.
        XCTAssertTrue(element(containing: "Casey Morgan").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Visible once an agreement has been sent.").exists)
    }

    func testAgreementFilterViaSearch() {
        XCTAssertTrue(app.buttons["leadCard-a0r000000000001AAA"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Marietta")
        XCTAssertTrue(app.buttons["leadCard-a0r000000000002AAA"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["leadCard-a0r000000000001AAA"].exists)
    }
}
