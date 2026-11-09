import XCTest

/// iPad: Claims and Leads show the list and the chosen record side by side. Skipped on iPhone.
final class IPadLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// iPad's floating tab bar (iOS 18+) isn't a TabBar element.
    private func tab(_ name: String) -> XCUIElement {
        let button = app.buttons.matching(identifier: name).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        return button
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHomeOnIPad() {
        XCTAssertTrue(app.buttons["quickSubmitLead"].waitForExistence(timeout: 10))
        screenshot("Home")
    }

    func testLeadOpensInDetailColumn() {
        tab("Leads").tap()
        XCTAssertTrue(element(containing: "Choose a lead").waitForExistence(timeout: 10))
        let card = app.buttons["leadCard-a0r000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(element(containing: "Public Adjuster Agreement").waitForExistence(timeout: 5), "The lead opens in the detail column")
        XCTAssertTrue(card.exists, "The list stays beside it")
        XCTAssertTrue(card.isSelected, "The open lead is highlighted in the list")
        screenshot("Lead")

        let other = app.buttons["leadCard-a0r000000000002AAA"]
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        XCTAssertTrue(other.isSelected)
        XCTAssertFalse(card.isSelected, "Choosing another lead replaces the first")
    }

    func testClaimOpensInDetailColumn() {
        tab("Claims").tap()
        let card = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(card.isSelected)
        XCTAssertTrue(element(containing: "Payments").waitForExistence(timeout: 5), "The claim opens in the detail column")
        screenshot("Claim")
    }
}
