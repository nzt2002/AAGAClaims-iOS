import XCTest

/// Milestone 6: aagaclaims:// deep links open the right screen, cold and warm.
final class DeepLinkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testClaimLinkWhileRunning() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
        app.open(URL(string: "aagaclaims://claim/a23000000000002AAA")!)
        XCTAssertTrue(element(containing: "Claim CLM-2210").waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "Opens on top of the current screen")
    }

    func testLeadLinkWhileRunning() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
        app.open(URL(string: "aagaclaims://lead/a0r000000000002AAA")!)
        XCTAssertTrue(element(containing: "Morgan Chen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "Opens on top of the current screen")
    }

    func testCaseLinkLaunchesApp() {
        // Not running yet: the link launches the app and waits for sign-in.
        app.open(URL(string: "aagaclaims://case/500000000000001AAA")!)
        XCTAssertTrue(element(containing: "the inspection is booked for October 9").waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Support"].isSelected)
    }

    func testUnknownRecordShowsNotFound() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
        app.open(URL(string: "aagaclaims://claim/a23999999999999AAA")!)
        XCTAssertTrue(app.staticTexts["Claim not found"].waitForExistence(timeout: 10))
    }
}
