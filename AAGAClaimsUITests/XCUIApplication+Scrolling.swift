import XCTest

extension XCUIApplication {
    /// Scrolls in small steps until the element sits in the middle of the screen, clear of the
    /// navigation bar, the bottom action bar and the floating tab bar, so a tap lands on it.
    /// Full swipes overshoot.
    func scrollIntoView(_ element: XCUIElement) {
        let height = frame.height
        for _ in 0..<15 {
            if element.exists, element.frame.minY > height * 0.25, element.frame.maxY < height * 0.65 { return }
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let dy = element.exists && element.frame.minY < height * 0.25 ? 0.15 : -0.15
            start.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6 + dy)))
        }
    }
}

extension XCUIApplication {
    /// Accepts a system permission alert (e.g. notifications after a fresh install), which
    /// otherwise covers the app and makes elements unhittable.
    func dismissSystemAlerts() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        let allow = alert.buttons["Allow"]
        if allow.exists { allow.tap() } else { alert.buttons.firstMatch.tap() }
    }
}
