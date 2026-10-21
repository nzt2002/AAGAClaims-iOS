import PortalKit
import SwiftUI

/// Account (spec §6.11). Notification and Face ID toggles come in milestone 6; privacy policy
/// and terms links are waiting on URLs (see ASSUMPTIONS.md).
struct AccountView: View {
    let session: AppSession
    let user: CurrentUser
    let openSupport: () -> Void

    @State private var confirmingSignOut = false
    @State private var whatsNew: WhatsNew.Release?
    @State private var deletingAccount = false
    @Environment(\.serverMeta) private var serverMeta
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

            if session.lock.isAvailable || session.lock.isEnabled {
                Section {
                    Toggle(session.lock.methodName, isOn: lockBinding)
                        .accessibilityIdentifier("appLockToggle")
                } footer: {
                    Text("Ask for \(session.lock.methodName) when you open the app and after 5 minutes away.")
                }
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

            if serverMeta.supports(.accountDeletion) {
                Section {
                    Button("Delete Account", role: .destructive) { deletingAccount = true }
                        .accessibilityIdentifier("deleteAccount")
                } footer: {
                    Text("Ask us to delete your account and personal information.")
                }
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                if let release = WhatsNew.current(isInternal: user.isInternal) {
                    Button("What's New in \(release.version)") { whatsNew = release }
                        .accessibilityIdentifier("whatsNewButton")
                }
                NavigationLink("Release Notes") {
                    ReleaseNotesView(isInternal: user.isInternal)
                }
                .accessibilityIdentifier("releaseNotesLink")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Account")
        .sheet(item: $whatsNew) { release in
            WhatsNewSheet(release: release, isInternal: user.isInternal)
        }
        .sheet(isPresented: $deletingAccount) {
            DeleteAccountSheet(api: session.api, signOut: {
                // Forget the Face ID sign-in too.
                session.lock.disable()
                signOut()
            })
        }
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

    private var lockBinding: Binding<Bool> {
        Binding {
            session.lock.isEnabled
        } set: { wantsOn in
            if wantsOn {
                Task { _ = await session.lock.enable() }
            } else {
                session.lock.disable()
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

/// Account deletion (App Store 5.1.1(v)): explains what happens, takes an optional reason, sends
/// the request (a support case for the team), then signs out.
struct DeleteAccountSheet: View {
    let api: PortalAPI
    let signOut: () -> Void
    @State private var reason = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var result: AccountDeletionRequest?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isOffline) private var isOffline

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your account and personal information will be deleted within 30 days. We'll email you when it's done.",
                          systemImage: "person.crop.circle.badge.xmark")
                    Label("Records we must keep by law for your claims are kept only as long as required.", systemImage: "doc.text")
                    Label("You'll be signed out now. You can't undo this once it's done.", systemImage: "exclamationmark.triangle")
                }
                .font(.subheadline)
                Section("Why are you leaving? (optional)") {
                    TextField("Reason", text: $reason, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("deleteAccountReason")
                }
                ErrorRow(message: errorMessage)
                Section {
                    Button(role: .destructive) {
                        Task { await send() }
                    } label: {
                        HStack {
                            Text("Delete My Account")
                            Spacer()
                            if isSending { ProgressView() }
                        }
                    }
                    .disabled(isSending)
                    .disabledWhenOffline(isOffline)
                    .accessibilityIdentifier("confirmDeleteAccount")
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(result?.alreadyRequested == true ? "Already requested" : "Request received",
                   isPresented: Binding(get: { result != nil }, set: { _ in })) {
                Button("OK") {
                    dismiss()
                    signOut()
                }
            } message: {
                Text(result?.alreadyRequested == true
                     ? "We're already working on deleting your account. We'll email you when it's done. You'll now be signed out."
                     : "We'll delete your account within 30 days and email you when it's done. You'll now be signed out.")
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            result = try await api.requestAccountDeletion(reason: trimmed.isEmpty ? nil : trimmed)
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
        }
    }
}
