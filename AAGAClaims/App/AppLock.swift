import LocalAuthentication
import Observation
import PortalKit
import SwiftUI

/// Optional Face ID / Touch ID app lock with device passcode fallback (spec §8).
@MainActor
@Observable
final class AppLock {
    private enum Keys {
        static let enabled = "AppLockEnabled"
        static let offered = "AppLockOffered"
    }

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    /// Shown on the lock screen when unlocking fails.
    private(set) var message: String?
    private var backgroundedAt: Date?
    /// True while Face ID / passcode is on screen. iOS makes the app inactive for it, which must
    /// not put up the privacy shield (that left the app covered after turning the lock on).
    private(set) var isAuthenticating = false
    private var authenticationEndedAt: Date?

    /// Face ID is up, or has just closed (its inactive/active notifications can arrive late).
    var isInAuthentication: Bool {
        if isAuthenticating { return true }
        guard let authenticationEndedAt else { return false }
        return Date().timeIntervalSince(authenticationEndedAt) < 2
    }

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        isEnabled = enabled
        // Ask on launch (spec §8).
        isLocked = enabled
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode".
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Whether the device has Face ID, Touch ID or a passcode to lock with.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Offer the lock once, after the first successful sign-in (spec §6.1).
    var shouldOffer: Bool {
        !isEnabled && !UserDefaults.standard.bool(forKey: Keys.offered) && isAvailable
            && !UserDefaults.standard.bool(forKey: "UITestDemo")
    }

    func markOffered() {
        UserDefaults.standard.set(true, forKey: Keys.offered)
    }

    /// Turns the lock on after confirming the user can unlock, so they can't lock themselves out.
    func enable() async -> Bool {
        markOffered()
        guard await authenticate(reason: "Turn on \(methodName) for AAGA Claims") else { return false }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Keys.enabled)
        return true
    }

    func disable() {
        isEnabled = false
        isLocked = false
        UserDefaults.standard.set(false, forKey: Keys.enabled)
    }

    /// Clears the setting on sign-out.
    func reset() {
        disable()
        UserDefaults.standard.removeObject(forKey: Keys.offered)
    }

    // MARK: - Scene lifecycle

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func willEnterForeground() {
        if AppLockPolicy.shouldLock(isEnabled: isEnabled, backgroundedAt: backgroundedAt) {
            isLocked = true
        }
        backgroundedAt = nil
    }

    // MARK: - Unlocking

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        message = nil

        // If the device no longer has a passcode, the lock can't work: turn it off rather than
        // locking the user out.
        var error: NSError?
        if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error),
           (error as? LAError)?.code == .passcodeNotSet {
            disable()
            return
        }

        if await authenticate(reason: "Unlock AAGA Claims") {
            isLocked = false
        } else {
            message = "AAGA Claims is still locked. Try again."
        }
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer {
            isAuthenticating = false
            authenticationEndedAt = Date()
        }
        // .deviceOwnerAuthentication falls back to the device passcode.
        return (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Covers the app while it's locked.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text("AAGA Claims is locked")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            if let message = lock.message {
                Text(message)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Text("Unlock with \(lock.methodName)")
                    .foregroundStyle(Color.surface)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("unlockButton")
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .task { await lock.unlock() }
        .accessibilityIdentifier("lockScreen")
    }
}

/// Hides app content in the app switcher snapshot when the lock is on (spec §10).
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Color.appBackground
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandPrimary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
