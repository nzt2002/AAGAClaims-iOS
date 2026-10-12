import PortalKit
import SwiftUI

/// Account (spec §6.11). Notification and Face ID toggles come in milestone 6; privacy policy
/// and terms links are waiting on URLs (see ASSUMPTIONS.md).
struct AccountView: View {
    let session: AppSession
    let user: CurrentUser
    let openSupport: () -> Void

    @State private var confirmingSignOut = false
    @State private var notificationStatus: PushNotifications.Status = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: user.fullName)
                LabeledContent("Email", value: user.email)
            }

            Section {
                Toggle("Notifications", isOn: notificationsBinding)
                    .accessibilityIdentifier("notificationsToggle")
            } footer: {
                Text(notificationFooter)
            }

            Section {
                Button("Contact support", action: openSupport)
            }

            Section {
                Button("Sign out", role: .destructive) {
                    confirmingSignOut = true
                }
                .accessibilityIdentifier("signOut")
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            // Re-check when returning from Settings.
            notificationStatus = await PushNotifications.status()
        }
        .confirmationDialog("Sign out of AAGA Claims?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: signOut)
        }
    }

    /// On when allowed. Turning it on asks for permission the first time; after that iOS only lets
    /// the user change it in Settings, so the toggle opens Settings (spec §6.11).
    private var notificationsBinding: Binding<Bool> {
        Binding {
            notificationStatus == .allowed
        } set: { wantsOn in
            if wantsOn, notificationStatus == .notDetermined {
                Task {
                    _ = await PushNotifications.requestPermission(registerWithSalesforce: !session.isDemo)
                    notificationStatus = await PushNotifications.status()
                }
            } else {
                PushNotifications.openSettings()
            }
        }
    }

    private var notificationFooter: String {
        switch notificationStatus {
        case .allowed: "We'll let you know when there's an update on your claim or lead, or a reply on a support case."
        case .denied: "Notifications are off for AAGA Claims. Turn them on in Settings."
        case .notDetermined: "Get notified about updates on your claims and leads, and replies on support cases."
        }
    }

    private func signOut() {
        if session.isDemo {
            session.didSignOut()
        } else {
            SalesforceSession.signOut()
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        AccountView(session: AppSession(environment: .current), user: .demo, openSupport: {})
    }
}
