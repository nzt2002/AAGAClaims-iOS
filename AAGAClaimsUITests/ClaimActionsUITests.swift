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

    func testClaimFeedPostsCollapseAndReplyOpensTheReplyBox() {
        let post = "0D5000000000001AAA"
        let toggle = app.buttons["togglePost-\(post)"]
        app.scrollIntoView(toggle)
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(app.descendants(matching: .any)["replyField-\(post)"].exists, "No reply box until Reply")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-'")).firstMatch.exists,
                       "Collapsed posts hide their files")
        XCTAssertTrue(element(containing: "1 file").exists, "…but say they have one")

        toggle.tap()
        let file = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5), "Expanded posts show their files")

        let reply = app.buttons["replyButton-\(post)"]
        app.scrollIntoView(reply)
        reply.tap()
        let field = app.descendants(matching: .any)["replyField-\(post)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(field.frame.height, 60, "Three lines tall")
        XCTAssertTrue(app.buttons["attachReply-\(post)"].exists, "Claim replies can have a file")
        sleep(1)
        app.typeText("Thanks, I'll chase them.")
        app.buttons["sendReply-\(post)"].tap()
        XCTAssertTrue(element(containing: "Thanks, I'll chase them.").waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists, "The box closes once sent")

        toggle.tap()
        XCTAssertFalse(element(containing: "Thanks, I'll chase them.").exists, "Collapsing hides the replies")
        XCTAssertTrue(element(containing: "1 reply").exists)
    }

    func testIdFieldAndEmailQuotesIt() {
        open("email")
        let body = app.textViews["emailBody"].exists ? app.textViews["emailBody"] : app.textFields["emailBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue((body.value as? String ?? "").contains("[ref_ (a23000000000001AAA)]"), String(describing: body.value))
        app.buttons["actionCancel"].tap()

        let details = app.buttons["Details"]
        app.scrollIntoView(details)
        details.tap()
        XCTAssertTrue(element(containing: "ref_ (a23000000000001AAA)").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["copy-Id"].exists)
    }

    func testEditIsATextButtonInTheTopBar() {
        // The visible title is "Edit" (VoiceOver says "Edit Claim").
        let edit = app.navigationBars.buttons["claimAction-edit"]
        XCTAssertTrue(edit.exists)
        XCTAssertEqual(edit.label, "Edit Claim")
    }

    func testTaskPageMarkCompleteEditAndReassign() {
        open("task")
        let subject = app.textFields["newTaskSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        subject.tap()
        subject.typeText("Order roof measurements")
        app.buttons["newTaskSave"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'claimActivity-' AND label CONTAINS 'Order roof measurements'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.scrollIntoView(row)
        row.tap()

        // Reassign to Jane Doe.
        let reassign = app.buttons["activityReassign"]
        XCTAssertTrue(reassign.waitForExistence(timeout: 5))
        reassign.tap()
        app.buttons["Jane Doe"].firstMatch.tap()
        XCTAssertTrue(element(containing: "Jane Doe").waitForExistence(timeout: 5))

        // Edit the subject.
        app.buttons["activityEdit"].tap()
        let field = app.textFields["editActivitySubject"].exists ? app.textFields["editActivitySubject"] : app.textViews["editActivitySubject"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Tap the end of the text so the cursor lands after it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        sleep(1)
        app.typeText(" and gutters")
        app.buttons["actionSave"].tap()
        let header = app.descendants(matching: .any)["activityHeader"]
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'Order roof measurements and gutters'").evaluate(with: header) ||
                      element(containing: "Order roof measurements and gutters").waitForExistence(timeout: 5))

        // Mark Complete.
        let complete = app.buttons["activityComplete"]
        XCTAssertTrue(complete.exists)
        complete.tap()
        XCTAssertTrue(element(containing: "Completed").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activityComplete"].exists, "Done tasks can't be completed again")
    }

    func testEmailsShowInRecentActivity() {
        let email = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'claimActivity-02s'")).firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        app.scrollIntoView(email)
        XCTAssertTrue(email.label.contains("Received"), email.label)
        email.tap()
        XCTAssertTrue(element(containing: "Email details").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Pat Carrier").exists)
        XCTAssertFalse(app.buttons["activityEdit"].exists, "Emails are read-only")
    }

    func testStageGuideAndPaymentProgress() {
        let guide = app.descendants(matching: .any)["stageGuide"].firstMatch
        app.scrollIntoView(guide)
        XCTAssertTrue(guide.exists)
        XCTAssertTrue(element(containing: "What's next").exists)

        let payments = app.buttons["Payments"]
        app.scrollIntoView(payments)
        payments.tap()
        let progress = app.descendants(matching: .any)["paymentProgress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.label.contains("collected of"), progress.label)
    }

    func testRecentActivityOpensTaskRecord() {
        // Open items first, then done ones; three at a time.
        let done = app.buttons["claimActivity-00Thist1AAA1"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        app.scrollIntoView(done)
        XCTAssertTrue(done.label.contains("Documents - Requested from insurance company"), done.label)
        XCTAssertTrue(done.label.contains("Completed"), done.label)
        done.tap()

        let header = app.descendants(matching: .any)["activityHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.label.contains("Documents - Requested from insurance company"), header.label)
        XCTAssertTrue(element(containing: "Assigned to").exists)
        XCTAssertTrue(element(containing: "full policy").exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Claim CLM-1234"].waitForExistence(timeout: 5), "Back on the claim")
    }

    func testNewTaskShowsInRecentActivity() {
        open("task")
        let subject = app.textFields["newTaskSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        subject.tap()
        subject.typeText("Order roof measurements")
        app.buttons["newTaskSave"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'claimActivity-' AND label CONTAINS 'Order roof measurements'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The new task is listed first")
        app.scrollIntoView(row)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activityHeader"].waitForExistence(timeout: 5))
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
