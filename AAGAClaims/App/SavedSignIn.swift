import Foundation
import LocalAuthentication
import Security

/// "Sign in with Face ID": with the app's Face ID lock on, the portal username and password are kept
/// in the keychain, readable only after Face ID (or Touch ID) on this device. Signing out keeps them,
/// so the next sign-in is a Face ID glance instead of typing. They're removed when the lock is
/// turned off, the password stops working, the account is deleted, or Face ID enrolment changes
/// (`.biometryCurrentSet`). Never synced to iCloud or included in backups.
enum SavedSignIn {
    struct Credentials: Sendable {
        let username: String
        let password: String
    }

    nonisolated private static let service = "com.accurateadjustmentsga.claims.savedSignIn"
    nonisolated private static let account = "portal"

    /// The last password sign-in, held in memory until the user turns Face ID on (it's offered
    /// right after sign-in). Cleared on sign-out.
    @MainActor static var pending: Credentials?

    /// Whether credentials are saved (checked without showing Face ID).
    static var exists: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // "Interaction not allowed" means the item is there but needs Face ID to read.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Saves (or replaces) the credentials behind Face ID. False if the device can't protect them.
    @discardableResult
    static func save(_ credentials: Credentials) -> Bool {
        delete()
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil
        ), let data = try? JSONEncoder().encode(["u": credentials.username, "p": credentials.password]) else {
            return false
        }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Shows Face ID and returns the credentials, or nil if cancelled, failed or not saved.
    static func load(reason: String) async -> Credentials? {
        await Task.detached(priority: .userInitiated) { () -> Credentials? in
            let context = LAContext()
            context.localizedReason = reason
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: context,
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data,
                  let fields = try? JSONDecoder().decode([String: String].self, from: data),
                  let username = fields["u"], let password = fields["p"] else { return nil }
            return Credentials(username: username, password: password)
        }.value
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
