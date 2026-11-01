import Foundation
import Testing
@testable import PortalKit

@Suite("Notification preferences")
struct NotificationPreferencesTests {
    @Test("Missing or unknown keys mean on; saved values round-trip")
    func decoding() throws {
        let json = Data(#"{"payments": false, "somethingNew": false}"#.utf8)
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        #expect(prefs.payments == false)
        #expect(prefs.updates && prefs.support && prefs.mentions && prefs.tasks && prefs.posts && prefs.esign)
        let again = try JSONDecoder().decode(NotificationPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(again == prefs)
    }

    @Test("Portal users see updates, payments and support; staff see everything")
    func kinds() {
        #expect(NotificationPreferences.Kind.kinds(isInternal: false) == [.updates, .payments, .support])
        #expect(NotificationPreferences.Kind.kinds(isInternal: true).count == NotificationPreferences.Kind.allCases.count)
    }

    @Test("Subscript reads and writes every kind")
    func subscripts() {
        var prefs = NotificationPreferences()
        for kind in NotificationPreferences.Kind.allCases {
            prefs[kind] = false
            #expect(prefs[kind] == false)
        }
        #expect(prefs == {
            var p = NotificationPreferences()
            p.updates = false; p.payments = false; p.mentions = false; p.tasks = false
            p.posts = false; p.support = false; p.esign = false
            return p
        }())
    }

    @Test("The demo API keeps what was saved")
    func mock() async throws {
        let api = MockPortalAPI(fixtures: .empty)
        var prefs = try await api.notificationPreferences()
        #expect(prefs == NotificationPreferences())
        prefs.tasks = false
        _ = try await api.saveNotificationPreferences(prefs)
        #expect(try await api.notificationPreferences().tasks == false)
    }
}
