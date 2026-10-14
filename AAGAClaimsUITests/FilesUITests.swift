import XCTest

/// Milestone 6: Quick Look preview and photo upload (spec §6.10).
final class FilesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        app.launch()
        app.dismissSystemAlerts()
        app.tabBars.buttons["Claims"].tap()
        let card = app.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let files = app.buttons["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        // Staff quick actions sit above the sections, so bring the tab into view first.
        app.scrollIntoView(files)
        files.tap()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testFileOpensInQuickLook() {
        let file = app.buttons["file-069000000000002AAA"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        app.scrollIntoView(file)
        file.tap()
        // Quick Look shows the file name in its title.
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", "Estimate")).firstMatch.waitForExistence(timeout: 10)
            || element(containing: "Estimate").waitForExistence(timeout: 10))
    }

    func testPhotoLibraryUpload() {
        let upload = app.buttons["uploadMenu"]
        app.scrollIntoView(upload)
        upload.tap()
        app.buttons["Photo Library"].tap()

        // The system photo picker: pick the first photo, then Add.
        // The picker runs out of process; its grid is one element, so tap the first cell by position.
        let grid = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,"))
            .firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.2)).tap()
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 3) { add.tap() }

        // It uploads and appears in the file list, titled like a camera photo.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo 20")).firstMatch.waitForExistence(timeout: 15))
    }
}
