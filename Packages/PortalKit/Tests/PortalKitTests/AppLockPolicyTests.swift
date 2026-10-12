import Foundation
import Testing
@testable import PortalKit

@Suite("App lock policy")
struct AppLockPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Locks after 5 minutes in the background, not before")
    func grace() {
        #expect(!AppLockPolicy.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-299), now: now))
        #expect(AppLockPolicy.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-300), now: now))
        #expect(AppLockPolicy.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-3600), now: now))
    }

    @Test("Never locks when the lock is off or there was no background")
    func disabled() {
        #expect(!AppLockPolicy.shouldLock(isEnabled: false, backgroundedAt: now.addingTimeInterval(-3600), now: now))
        #expect(!AppLockPolicy.shouldLock(isEnabled: true, backgroundedAt: nil, now: now))
    }
}
