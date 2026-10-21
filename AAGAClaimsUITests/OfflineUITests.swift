import XCTest

/// Milestone 6: offline cache, banner and disabled writes (spec §7, §8).
final class OfflineUITests: XCTestCase {
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testCachedDataShowsOfflineWithWritesDisabled() {
        // 1. Online: visit the claim so it's cached.
        let online = XCUIApplication()
        online.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock"]
        online.launch()
        online.tabBars.buttons["Claims"].tap()
        let card = online.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertFalse(online.descendants(matching: .any)["offlineBanner"].exists)
        card.tap()
        XCTAssertTrue(element(online, containing: "Claim CLM-1234").waitForExistence(timeout: 5))
        online.terminate()

        // 2. Offline: the same screens come from the cache.
        let offline = XCUIApplication()
        offline.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock", "-SimulateOffline", "YES"]
        offline.launch()
        offline.tabBars.buttons["Claims"].tap()
        let cachedCard = offline.buttons["claimCard-a23000000000001AAA"]
        XCTAssertTrue(cachedCard.waitForExistence(timeout: 10))
        XCTAssertTrue(element(offline, containing: "You're offline. Showing data from").exists)

        cachedCard.tap()
        XCTAssertTrue(element(offline, containing: "Claim CLM-1234").waitForExistence(timeout: 5))
        XCTAssertFalse(offline.buttons["addComment"].exists, "Claims have no Add Comment")
        XCTAssertFalse(offline.buttons["requestAssistance"].isEnabled)
        XCTAssertTrue(element(offline, containing: "Available when you're back online.").exists)
    }

    func testUncachedScreenShowsErrorOffline() {
        let offline = XCUIApplication()
        offline.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock", "-SimulateOffline", "YES"]
        offline.launch()
        // Sign out clears the cache, so start from nothing.
        offline.buttons["accountButton"].firstMatch.tap()
        offline.buttons["signOut"].tap()
        offline.sheets.buttons["Sign out"].firstMatch.tap()
        offline.buttons["continueDemo"].tap()

        offline.tabBars.buttons["Leads"].tap()
        XCTAssertTrue(offline.buttons["Retry"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(offline, containing: "Unable to load leads").exists)
    }
}
