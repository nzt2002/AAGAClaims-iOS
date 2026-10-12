import Foundation

/// When the optional Face ID / Touch ID lock asks again (spec §8): on launch, and after
/// 5 minutes in the background.
public enum AppLockPolicy {
    public static let backgroundGrace: TimeInterval = 5 * 60

    /// Whether returning to the foreground should lock the app.
    public static func shouldLock(isEnabled: Bool, backgroundedAt: Date?, now: Date = Date()) -> Bool {
        guard isEnabled, let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= backgroundGrace
    }
}
