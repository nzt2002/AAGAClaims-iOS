import XCTest

/// Staff claim page: quick actions, collapsible progress, Claim Feed and communication actions.
final class ClaimActionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.dismissSystemAlerts()
        app.tabBars.buttons["Claims"].tap()
        let card = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(app.staticTexts["Claim CLM-1234"].waitForExistence(timeout: 5))
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private static let inMoreMenu: Set<String> = ["addContact", "email", "address", "owner", "proofOfLoss"]

    private func open(_ action: String) {
        if Self.inMoreMenu.contains(action) {
            let more = app.buttons["claimActionMore"]
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            app.scrollIntoView(more)
            more.tap()
        }
        let button = app.buttons["claimAction-\(action)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        app.scrollIntoView(button)
        button.tap()
    }

    private func save() {
        let save = app.buttons["actionSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    func testPageLayout() {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "headerLossAddress").firstMatch.label.contains("123 Main St"), "Loss address under the name")
        XCTAssertFalse(app.buttons["claimAction-call"].exists, "Log a Call was removed")
        for action in ["payments", "edit", "post", "task", "event"] {
            XCTAssertTrue(app.buttons["claimAction-\(action)"].exists, action)
        }
        let more = app.buttons["claimActionMore"]
        XCTAssertTrue(more.exists)
        // One action strip under the header: Payments, Post, Log Call, Contact and More side by side.
        let payments = app.buttons["claimAction-payments"]
        XCTAssertLessThan(app.staticTexts["Claim CLM-1234"].frame.maxY, payments.frame.minY)
        XCTAssertEqual(payments.frame.midY, more.frame.midY, accuracy: 2)
        XCTAssertFalse(app.buttons["claimAction-email"].exists, "The rest are in More")
        more.tap()
        for action in ["addContact", "email", "address", "owner", "proofOfLoss"] {
            XCTAssertTrue(app.buttons["claimAction-\(action)"].waitForExistence(timeout: 5), action)
        }
        // Choosing an item opens its sheet (and closes the menu).
        app.buttons["claimAction-owner"].tap()
        XCTAssertTrue(app.buttons["actionCancel"].waitForExistence(timeout: 5))
        app.buttons["actionCancel"].tap()

        // Progress is collapsed; the status stays visible and prominent.
        let toggle = app.buttons["claimProgressToggle"]
        app.scrollIntoView(toggle)
        XCTAssertTrue(toggle.label.contains("Inspection"), toggle.label)
        XCTAssertFalse(app.staticTexts["Restoration"].exists)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Restoration"].waitForExistence(timeout: 5))
        toggle.tap()

        // Updates default to the Claim Feed for staff.
        let filter = app.segmentedControls["updatesFilter"]
        app.scrollIntoView(filter)
        XCTAssertTrue(filter.buttons["Claim Feed"].isSelected)
        XCTAssertTrue(element(containing: "Carrier called back").exists)

        let contactUs = app.staticTexts["Contact Us"]
        app.scrollIntoView(contactUs)
        XCTAssertTrue(contactUs.exists)
    }

    func testAddPostAppearsInClaimFeed() {
        open("post")
        let text = app.descendants(matching: .any)["postText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.typeText("Carrier approved the supplement.")
        save()
        XCTAssertTrue(element(containing: "Carrier approved the supplement.").waitForExistence(timeout: 5))
    }

    func testPostWithMention() {
        open("post")
        let text = app.descendants(matching: .any)["postText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.typeText("Thanks @Ja")
        let jane = app.buttons["mention-005000000000002AAA"]
        XCTAssertTrue(jane.waitForExistence(timeout: 5), "Typing @ suggests people")
        jane.tap()
        app.typeText("please check the estimate.")
        save()
        XCTAssertTrue(element(containing: "Thanks @Jane Doe please check the estimate.").waitForExistence(timeout: 5))
    }

    func testNewTaskFromClaimWithSuggestedSubject() {
        open("task")
        let locked = app.descendants(matching: .any)["newTaskLockedRecord"]
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        XCTAssertTrue(locked.label.contains("Smith - Roof"), "The task belongs to this claim: \(locked.label)")
        XCTAssertFalse(app.buttons["newTaskClaim"].exists, "The claim can't be changed")
        let subject = app.textFields["newTaskSubject"]
        subject.tap()
        subject.typeText("check")
        let suggestion = app.buttons["subjectSuggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(suggestion.label.contains("Check - Received from Insurer"))
        suggestion.tap()
        XCTAssertEqual(subject.value as? String, "Check - Received from Insurer")
        app.buttons["newTaskSave"].tap()
        XCTAssertTrue(app.buttons["claimActionMore"].waitForExistence(timeout: 5), "Back on the claim")
        XCTAssertFalse(app.buttons["newTaskSave"].exists)
    }

    func testEditClaimShowsValidationAndSaves() {
        open("edit")
        let name = app.textFields["editClaimName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" and Gutters")
        save()
        XCTAssertTrue(app.staticTexts["Smith - Roof and Gutters"].waitForExistence(timeout: 5))
    }

    func testMoreMenuOpensAddress() {
        open("address")
        XCTAssertTrue(app.textFields["streetAddress"].waitForExistence(timeout: 5))
    }

    func testApplyPayments() {
        open("payments")
        let type = app.buttons["paymentType"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.tap()
        app.buttons["NET Payment (ACV)"].tap()
        let amount = app.textFields.matching(NSPredicate(format: "placeholderValue == '0'")).firstMatch
        amount.tap()
        amount.typeText("9000")
        app.switches["applyDeductible"].switches.firstMatch.tap()
        let insured = app.descendants(matching: .any)["insuredPayment"]
        app.scrollIntoView(insured)
        XCTAssertTrue(insured.label.contains("$8,000.00"), insured.label)
        save()
        XCTAssertFalse(app.buttons["actionSave"].waitForExistence(timeout: 2), "The sheet closed")
    }

    func testSendEmail() {
        open("email")
        let emailSubject = app.textFields["emailSubject"]
        XCTAssertTrue(emailSubject.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "alex.smith@example.com").exists, "The claim's email is the default recipient")
        emailSubject.tap()
        emailSubject.typeText("Inspection booked")
        let body = app.descendants(matching: .any)["emailBody"]
        body.tap()
        app.typeText("See you Friday at 9.")
        save()
        XCTAssertTrue(app.buttons["claimActionMore"].waitForExistence(timeout: 5), "Back on the claim")
    }
}
