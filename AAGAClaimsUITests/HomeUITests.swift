import XCTest

/// Home: hero search, quick actions, agenda, activity, Update sheet and notifications.
final class HomeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.dismissSystemAlerts()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func element(containingCaseInsensitive text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private var bell: XCUIElement { app.buttons["notificationsBell"] }

    /// Opens a Claim/Lead lookup, searches by name and picks the record (its row shows the loss address).
    private func chooseRecord(_ lookup: String, search: String, option id: String) {
        app.buttons[lookup].tap()
        let field = app.textFields["recordSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(search)
        let option = app.buttons["recordOption-\(id)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(app.buttons[lookup].waitForExistence(timeout: 5), "Back on the form")
    }

    func testHomeLayout() {
        let welcome = app.staticTexts["Welcome back, Alex!"]
        let submit = app.buttons["quickSubmitLead"]
        let newEvent = app.buttons["quickNewEvent"]
        let newTask = app.buttons["quickNewTask"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5))
        XCTAssertLessThan(welcome.frame.maxY, submit.frame.minY, "Quick actions sit under the welcome message")
        XCTAssertTrue(submit.label.contains("New Lead"))
        // The demo user is staff: New Claim instead of My Claims.
        XCTAssertTrue(app.buttons["quickNewClaim"].label.contains("New Claim"))
        XCTAssertFalse(app.buttons["quickMyClaims"].exists)
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
        XCTAssertTrue(element(containing: "Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "Opened on top of Home")
    }

    /// The Search tab: results open inside it, and Back returns to the results.
    func testSearchTabOpensRecordInPlace() {
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["searchClose"].exists, "Nothing to close in a tab")
        field.tap()
        field.typeText("Jordan")
        let lead = app.buttons["searchResult-a0r000000000001AAA"]
        XCTAssertTrue(lead.waitForExistence(timeout: 5))
        lead.tap()
        XCTAssertTrue(element(containing: "Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Search"].isSelected, "Opened inside the Search tab")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(lead.waitForExistence(timeout: 5), "Back returns to the results")
    }

    /// Account opens from the profile button and closes with Done.
    func testProfileButtonOpensAccount() {
        app.buttons["accountButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 5))
        app.buttons["accountDone"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 5))
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
        chooseRecord("newEventClaim", search: "Roof", option: "a23000000000001AAA")
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
        // Opened on top of Home, so Back returns there.
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 5), "Back returns to Home")
    }

    func testSearchOpensTheChosenClaimNotTheOneAlreadyOpen() {
        app.tabBars.buttons["Claims"].tap()
        let card = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))

        app.tabBars.buttons["Home"].tap()
        app.buttons["homeSearch"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("CLM-2210")
        let result = app.buttons["searchResult-a23000000000002AAA"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(element(containing: "Claim CLM-2210").waitForExistence(timeout: 5), "The chosen claim opens")
        XCTAssertFalse(element(containing: "Claim CLM-1234").exists)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 5), "Back returns to Home")
        app.tabBars.buttons["Claims"].tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5), "The Claims tab is where it was")
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
        chooseRecord("newTaskLead", search: "Jordan", option: "a0r000000000001AAA")
        let subject = app.textFields["newTaskSubject"]
        subject.tap()
        subject.typeText("Resend the agreement")
        save.tap()
        XCTAssertTrue(element(containing: "Lead · Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Resend the agreement").exists)
    }

    func testClaimLookupShowsLossAddress() {
        app.buttons["quickNewTask"].tap()
        let lookup = app.buttons["newTaskClaim"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 5))
        lookup.tap()
        let field = app.textFields["recordSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Kitchen")
        let kitchen = app.buttons["recordOption-a23000000000002AAA"]
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5))
        XCTAssertTrue(kitchen.label.contains("Smith - Kitchen Water"), kitchen.label)
        XCTAssertFalse(app.buttons["recordOption-a23000000000001AAA"].exists, "Filtered by name")
        kitchen.tap()
        XCTAssertTrue(app.buttons["newTaskClaim"].label.contains("Smith - Kitchen Water"))
    }

    func testSearchPersonReplyAndEdit() {
        app.buttons["homeSearch"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["searchScope-People"].exists, "Staff can search people")
        field.typeText("Jane")
        let jane = app.buttons["searchResult-005000000000002AAA"]
        XCTAssertTrue(jane.waitForExistence(timeout: 5))
        jane.tap()

        XCTAssertTrue(element(containing: "Senior Field Adjuster").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Heading to the Smith roof inspection").exists)

        // Reply opens the reply box (and expands the post).
        let replyButton = app.buttons["replyButton-0D5000000000011AAA"]
        app.scrollIntoView(replyButton)
        replyButton.tap()
        let reply = app.descendants(matching: .any)["replyField-0D5000000000011AAA"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["attachReply-0D5000000000011AAA"].exists, "No files on profile feeds")
        reply.tap()
        reply.typeText("Photos are uploaded.")
        app.buttons["sendReply-0D5000000000011AAA"].tap()
        XCTAssertTrue(element(containing: "Photos are uploaded.").waitForExistence(timeout: 5))

        // Edit my own reply inline; others' replies have no Edit.
        XCTAssertFalse(app.buttons["editReply-0D7000000000011AAA"].exists)
        let edit = app.buttons["editReply-0D7000000000012AAA"]
        app.scrollIntoView(edit)
        edit.tap()
        let editField = app.descendants(matching: .any)["editReplyField"]
        XCTAssertTrue(editField.waitForExistence(timeout: 5))
        // Edit focuses the field with the cursor at the end.
        sleep(1)
        app.typeText(" Done.")
        app.buttons["saveReply"].tap()
        XCTAssertTrue(element(containing: "I'll update the claim after. Done.").waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["editReplyField"].exists)
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

        chooseRecord("newTaskClaim", search: "Roof", option: "a23000000000001AAA")
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
        // The list animates when the filter changes; wait until the row settles.
        let deadline = Date().addingTimeInterval(5)
        while !item.isHittable && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        item.tap()
        XCTAssertTrue(element(containing: "Inspection is booked for October 9.").waitForExistence(timeout: 5))

        app.buttons["openUpdateRecord"].tap()
        XCTAssertTrue(element(containing: "Claim CLM-1234").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)

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
        app.buttons["quickNewClaim"].tap()
        XCTAssertTrue(app.buttons["newClaimNewAccount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newClaimExistingAccount"].exists)
        app.buttons["newClaimClose"].tap()
        XCTAssertTrue(app.buttons["quickNewClaim"].waitForExistence(timeout: 5))
    }

    private func next() {
        let next = app.buttons["newClaimNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
    }

    func testNewClaimNewAccountMustUseExistingMatch() {
        app.buttons["quickNewClaim"].tap()
        app.buttons["newClaimNewAccount"].tap()
        let last = app.textFields["newAccountLastName"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        app.textFields["First name"].tap()
        app.textFields["First name"].typeText("Alex")
        last.tap()
        last.typeText("Smith")
        next()

        // Alex Smith already exists: it must be used, and no new account is offered.
        let match = app.buttons["accountMatch-001000000000001AAA"]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "To avoid a duplicate").exists)
        match.tap()

        let name = app.textFields["claimName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Alex Smith", "Prefilled from the account")
        name.tap()
        name.typeText(" - Fence")
        next()
        XCTAssertTrue(app.segmentedControls["contactMode"].waitForExistence(timeout: 5))
        next()
        let create = app.buttons["newClaimCreate"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Existing account").exists)
        create.tap()

        XCTAssertTrue(app.tabBars.buttons["Claims"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Alex Smith - Fence").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
    }

    func testNewClaimExistingAccountWithMatchingContact() {
        app.buttons["quickNewClaim"].tap()
        app.buttons["newClaimExistingAccount"].tap()
        let search = app.textFields["accountSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Jordan")
        let account = app.buttons["account-001000000000002AAA"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()

        let name = app.textFields["claimName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        next()

        app.segmentedControls["contactMode"].buttons["New"].tap()
        app.buttons["contactRole"].tap()
        app.buttons["Property Contact"].tap()
        app.textFields["First name"].tap()
        app.textFields["First name"].typeText("Morgan")
        let last = app.textFields["contactLastName"]
        last.tap()
        last.typeText("Field")
        next()

        // Morgan Field is already a contact: use it rather than adding a duplicate.
        let match = app.buttons["contactMatch-003000000000001AAA"]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["noContactMatch"].exists)
        match.tap()
        let create = app.buttons["newClaimCreate"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Morgan Field").exists)
        create.tap()
        XCTAssertTrue(element(containing: "Jordan Reyes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
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
