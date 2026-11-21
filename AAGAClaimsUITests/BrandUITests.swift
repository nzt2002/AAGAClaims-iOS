import XCTest

/// A company's brand colour is resolved by SwiftUI's renderer off the main thread; the app must not trap there.
final class BrandUITests: XCTestCase {
    func testBrandColourResolvesOffTheMainThread() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "YES", "-PortalDataSource", "mock", "-DemoBrand", "#C2410C", "-BrandSelfTest", "YES"]
        app.launch()
        app.dismissSystemAlerts()
        XCTAssertTrue(app.staticTexts["Welcome back, Alex!"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo Roofing"].exists, "The company name shows in the Home header")
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "The app is still running")
    }
}
