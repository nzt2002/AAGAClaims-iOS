import PortalKit
import SwiftUI

/// Account → "Notify me about": a switch for each kind of notification (spec §6.11). Saved on the
/// server, which only sends the kinds that are on. Portal users see updates, payments and support;
/// staff also see mentions, tasks, team posts and e-signatures.
struct NotificationPreferencesSection: View {
    let api: PortalAPI
    let isInternal: Bool

    @State private var preferences: NotificationPreferences?
    @State private var saving: NotificationPreferences.Kind?
    @State private var errorMessage: String?
    @State private var loadFailed = false

    var body: some View {
        Section {
            if let preferences {
                ForEach(NotificationPreferences.Kind.kinds(isInternal: isInternal)) { kind in
                    Toggle(isOn: binding(kind, current: preferences)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        } icon: {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                    .disabled(saving != nil)
                    .accessibilityIdentifier("notificationKind-\(kind.rawValue)")
                }
            } else if loadFailed {
                Button("Couldn't load your choices. Try again") { Task { await load() } }
                    .accessibilityIdentifier("notificationKindsRetry")
            } else {
                HStack {
                    ProgressView()
                    Text("Loading…").foregroundStyle(Color.textSecondary)
                }
            }
        } header: {
            Text("Notify me about")
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.warning)
            } else {
                Text("Choose what you're notified about. Changes apply to every device you're signed in on.")
            }
        }
        .task { if preferences == nil { await load() } }
    }

    private func binding(_ kind: NotificationPreferences.Kind, current: NotificationPreferences) -> Binding<Bool> {
        Binding {
            current[kind]
        } set: { isOn in
            Task { await save(kind, isOn) }
        }
    }

    private func load() async {
        loadFailed = false
        do {
            preferences = try await api.notificationPreferences()
        } catch {
            loadFailed = true
        }
    }

    /// Shows the change at once; puts it back if saving fails.
    private func save(_ kind: NotificationPreferences.Kind, _ isOn: Bool) async {
        guard var updated = preferences else { return }
        let previous = updated
        updated[kind] = isOn
        preferences = updated
        saving = kind
        errorMessage = nil
        do {
            preferences = try await api.saveNotificationPreferences(updated)
        } catch {
            preferences = previous
            errorMessage = "Couldn't save that change. Check your connection and try again."
        }
        saving = nil
    }
}
