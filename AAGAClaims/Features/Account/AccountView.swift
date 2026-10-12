import PortalKit
import SwiftUI

/// Account (spec §6.11). Notification and Face ID toggles come in milestone 6; privacy policy
/// and terms links are waiting on URLs (see ASSUMPTIONS.md).
struct AccountView: View {
    let session: AppSession
    let user: CurrentUser
    let openSupport: () -> Void

    @State private var confirmingSignOut = false

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: user.fullName)
                LabeledContent("Email", value: user.email)
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
        .confirmationDialog("Sign out of AAGA Claims?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: signOut)
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
