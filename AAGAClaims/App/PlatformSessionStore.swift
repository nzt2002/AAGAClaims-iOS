import Foundation
import PortalKit
import Security

/// Keeps the platform sign-in in the keychain between launches. Readable after the first unlock (so a refresh can happen
/// when the app wakes in the background), only on this device, never synced or backed up.
nonisolated struct KeychainPlatformSessionStore: PlatformSessionStore {
    private static let service = "com.accurateadjustmentsga.claims.platformSession"
    private static let account = "session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
    }

    func load() -> PlatformSession? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PlatformSession.self, from: data)
    }

    func save(_ session: PlatformSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update = [kSecValueData as String: data] as CFDictionary
        if SecItemUpdate(query as CFDictionary, update) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The last profile, so the app can open without a connection (the offline cache holds the data).
enum PlatformProfileCache {
    private static let key = "platformProfile"

    static func save(_ profile: PlatformProfile) {
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: key)
    }

    static func load() -> PlatformProfile? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(PlatformProfile.self, from: $0) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension CurrentUser {
    init(_ profile: PlatformProfile) {
        self.init(firstName: profile.firstName, fullName: profile.fullName, email: profile.email, isInternal: profile.isInternal)
        company = profile.company
    }
}
