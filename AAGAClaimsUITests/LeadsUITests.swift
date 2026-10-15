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
        // Staff (the demo user) start on the Lead Feed; published updates are one tap away.
        let filter = app.segmentedControls["leadUpdatesFilter"]
        app.scrollIntoView(filter)
        filter.buttons["Portal Updates"].tap()
        XCTAssertTrue(element(containing: "Agreement sent").waitForExistence(timeout: 5), "Updates section shows the published update")

        app.scrollIntoView(app.buttons["Insurance"])
        app.buttons["Insurance"].tap()
        XCTAssertTrue(element(containing: "USAA").waitForExistence(timeout: 5))
    }

    private func openJordan() {
        let card = app.buttons["leadCard-a0r000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["leadAction-convert"].waitForExistence(timeout: 5))
    }

    func testLeadActionsAndPostToLeadFeed() {
        openJordan()
        XCTAssertFalse(app.buttons["addComment"].exists, "Add Comment was removed, as on claims")
        XCTAssertTrue(app.buttons["leadAction-edit"].label.contains("Edit"))
        XCTAssertTrue(app.buttons["requestAssistance"].exists)
        XCTAssertTrue(app.buttons["leadAction-post"].exists)
        XCTAssertTrue(app.buttons["leadAction-agreement"].exists)

        app.buttons["leadAction-post"].tap()
        let text = app.descendants(matching: .any)["postText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.typeText("Homeowner will sign tonight.")
        app.buttons["actionSave"].tap()
        let filter = app.segmentedControls["leadUpdatesFilter"]
        app.scrollIntoView(filter)
        XCTAssertTrue(filter.buttons["Lead Feed"].isSelected)
        XCTAssertTrue(element(containing: "Homeowner will sign tonight.").waitForExistence(timeout: 5))
    }

    func testNewEventFromLead() {
        openJordan()
        app.buttons["leadAction-event"].tap()
        let locked = app.descendants(matching: .any)["newEventLockedRecord"]
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        XCTAssertTrue(locked.label.contains("Jordan Reyes"), locked.label)
        let subject = app.textFields["newEventSubject"]
        subject.tap()
        subject.typeText("Mee")
        let suggestion = app.buttons["subjectSuggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertEqual(subject.value as? String, "Meeting")
        app.buttons["newEventSave"].tap()
        XCTAssertTrue(app.buttons["leadAction-convert"].waitForExistence(timeout: 5), "Back on the lead")
    }

    func testEditLead() {
        openJordan()
        app.buttons["leadAction-edit"].tap()
        let name = app.textFields["editLeadName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" Jr")
        app.buttons["actionSave"].tap()
        XCTAssertTrue(element(containing: "Jordan Reyes Jr").waitForExistence(timeout: 5))
    }

    func testConvertToAccountUsesExistingAccountAndOpensClaim() {
        openJordan()
        app.buttons["leadAction-convert"].tap()
        let newAccount = app.buttons["newClaimNewAccount"]
        XCTAssertTrue(newAccount.waitForExistence(timeout: 5))
        newAccount.tap()
        // Prefilled from the lead; Jordan Reyes already has an account, which must be used.
        let last = app.textFields["newAccountLastName"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertEqual(last.value as? String, "Reyes")
        app.buttons["newClaimNext"].tap()
        let match = app.buttons["accountMatch-001000000000002AAA"]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        match.tap()

        // No claim-details step: the contact comes next, prefilled with the associated party.
        let mode = app.segmentedControls["contactMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.buttons["New"].isSelected)
        mode.buttons["None"].tap()
        app.buttons["newClaimNext"].tap()
        let convert = app.buttons["newClaimCreate"]
        XCTAssertTrue(convert.waitForExistence(timeout: 5))
        XCTAssertTrue(convert.label.contains("Convert"))
        convert.tap()

        XCTAssertTrue(app.tabBars.buttons["Claims"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Claims"].isSelected, "The new claim opens")
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
