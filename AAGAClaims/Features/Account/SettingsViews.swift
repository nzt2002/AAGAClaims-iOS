import PortalKit
import SwiftUI
import UIKit

/// What an error from a settings call says to the person.
private func settingsMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case PortalAPIError.rejected(let text): text
    case PortalAPIError.offline: "You're offline. Try again when you're back online."
    case PortalAPIError.server(status: 403): "You don't have permission to change this."
    default: fallback
    }
}

// MARK: - Your settings

/// Account → Your settings: name and phone (staff), which alerts also come by email, and your password.
/// Read only when it opens; each switch saves as you flip it.
struct YourSettingsView: View {
    let api: PortalAPI

    @State private var settings: MySettings?
    @State private var loadFailed = false
    @State private var name = ""
    @State private var phone = ""
    @State private var savingProfile = false
    @State private var errorMessage: String?
    @State private var savedNote: String?

    var body: some View {
        List {
            if let settings {
                Section("Profile") {
                    if settings.canEditProfile {
                        LabeledContent("Name") {
                            TextField("Your name", text: $name).textContentType(.name).multilineTextAlignment(.trailing).accessibilityIdentifier("settingsName")
                        }
                        LabeledContent("Phone") {
                            TextField("Optional", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).multilineTextAlignment(.trailing).accessibilityIdentifier("settingsPhone")
                        }
                        Button {
                            Task { await saveProfile() }
                        } label: {
                            HStack { Text("Save"); if savingProfile { ProgressView() } }
                        }
                        .disabled(savingProfile || name.trimmingCharacters(in: .whitespaces).isEmpty || (name == settings.fullName && phone == (settings.phone ?? "")))
                        .accessibilityIdentifier("settingsSaveProfile")
                    } else {
                        LabeledContent("Name", value: settings.fullName)
                    }
                    if let email = settings.email { LabeledContent("Email", value: email) }
                }

                Section {
                    ForEach(settings.emailAlerts) { alert in
                        Toggle(isOn: binding(alert)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.label)
                                Text(alert.hint).font(.caption).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("emailAlert-\(alert.kind)")
                    }
                } header: {
                    Text("Also email me when")
                } footer: {
                    Text("You always get these in the app. This only adds an email.")
                }

                Section {
                    NavigationLink("Change password") { ChangePasswordView(api: api) }
                        .accessibilityIdentifier("changePasswordLink")
                }
            } else if loadFailed {
                Section { Button("Couldn't load your settings. Try again") { Task { await load() } } }
            } else {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(Color.textSecondary) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Your Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .overlay(alignment: .bottom) {
            if let savedNote {
                Text(savedNote).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule()).padding(.bottom, 24).transition(.opacity)
            }
        }
    }

    private func binding(_ alert: EmailAlert) -> Binding<Bool> {
        Binding(get: { alert.on }, set: { newValue in Task { await setAlert(alert.kind, newValue) } })
    }

    private func load() async {
        loadFailed = false
        do {
            let loaded = try await api.mySettings()
            settings = loaded
            name = loaded.fullName
            phone = loaded.phone ?? ""
        } catch { loadFailed = true }
    }

    private func saveProfile() async {
        savingProfile = true
        defer { savingProfile = false }
        do {
            try await api.saveMySettings(fullName: name.trimmingCharacters(in: .whitespaces), phone: phone.trimmingCharacters(in: .whitespaces))
            settings?.fullName = name.trimmingCharacters(in: .whitespaces)
            settings?.phone = phone.trimmingCharacters(in: .whitespaces)
            flash("Saved")
        } catch { errorMessage = settingsMessage(error, fallback: "Couldn't save. Try again.") }
    }

    private func setAlert(_ kind: String, _ on: Bool) async {
        guard let index = settings?.emailAlerts.firstIndex(where: { $0.kind == kind }) else { return }
        let before = settings?.emailAlerts[index].on ?? false
        settings?.emailAlerts[index].on = on
        do { try await api.saveEmailAlerts([kind: on]) } catch {
            settings?.emailAlerts[index].on = before
            errorMessage = settingsMessage(error, fallback: "Couldn't save. Try again.")
        }
    }

    private func flash(_ text: String) {
        withAnimation { savedNote = text }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { savedNote = nil } }
    }
}

/// Needs the current password, then a new one of at least 8 characters.
struct ChangePasswordView: View {
    let api: PortalAPI
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var done = false

    private var mismatch: Bool { !confirm.isEmpty && new != confirm }
    private var canSave: Bool { !current.isEmpty && new.count >= 8 && new == confirm && !saving }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current).textContentType(.password).accessibilityIdentifier("currentPassword")
            }
            Section {
                SecureField("New password", text: $new).textContentType(.newPassword).accessibilityIdentifier("newPassword")
                SecureField("Confirm new password", text: $confirm).textContentType(.newPassword).accessibilityIdentifier("confirmPassword")
            } footer: {
                if mismatch { Text("The passwords don't match.").foregroundStyle(Color.warning) } else { Text("Use at least 8 characters.") }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.warning) } }
            Section {
                Button {
                    Task { await save() }
                } label: { HStack { Text("Save password"); if saving { ProgressView() } } }
                .disabled(!canSave)
                .accessibilityIdentifier("savePassword")
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password saved", isPresented: $done) { Button("OK") { dismiss() } }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await api.changePassword(current: current, new: new)
            done = true
        } catch { errorMessage = settingsMessage(error, fallback: "Couldn't save your password. Try again.") }
    }
}

// MARK: - Company settings

/// Account → Company settings (staff): the everyday ones. Each section is changeable only with the same permission as
/// on the website. Read only when it opens; each change saves as you make it.
struct CompanySettingsView: View {
    let api: PortalAPI

    @State private var settings: CompanySettings?
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var badge = ""
    @State private var color = Color(hex: "#0B5CAB") ?? .blue
    @State private var hasColor = false
    @State private var savingBrand = false

    var body: some View {
        List {
            if let settings {
                if settings.can.isEmpty {
                    Section { Text("Only owners and managers can change these. You can see how they're set.").foregroundStyle(Color.textSecondary) }
                }
                brand(settings)
                visibility(settings)
                webForm(settings)
                uploads(settings)
                messages(settings, forPolicyholders: true)
                messages(settings, forPolicyholders: false)
                Section { Text("Templates, permissions, custom fields, folder templates, licences and the logo are on the website.").font(.footnote).foregroundStyle(Color.textSecondary) }
            } else if loadFailed {
                Section { Button("Couldn't load the settings. Try again") { Task { await load() } } }
            } else {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(Color.textSecondary) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(settings?.name ?? "Company Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Sections

    private func brand(_ s: CompanySettings) -> some View {
        Section {
            LabeledContent("Badge letters") {
                TextField("Up to 3", text: $badge)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    .onChange(of: badge) { _, new in badge = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(3)) }
                    .accessibilityIdentifier("brandBadge")
            }
            ColorPicker("Brand colour", selection: Binding(get: { color }, set: { color = $0; hasColor = true }), supportsOpacity: false)
                .accessibilityIdentifier("brandColor")
            Button {
                Task { await saveBrand() }
            } label: { HStack { Text("Save colour and badge"); if savingBrand { ProgressView() } } }
            .disabled(savingBrand || (badge == (s.markText ?? "") && (!hasColor || color.hexString == (s.brandColor ?? "").uppercased())))
            .accessibilityIdentifier("saveBrand")
        } header: { Text("Colour and badge") } footer: { Text("Your colour runs through the whole app. The letters show when there's no logo.") }
        .disabled(!s.can.brand)
    }

    private func visibility(_ s: CompanySettings) -> some View {
        Section {
            Picker("Claims", selection: Binding(get: { s.claimVisibility }, set: { v in
                Task { await change(.visibility(claims: v, leads: nil)) { $0.claimVisibility = v } }
            })) {
                Text("Everyone sees every claim").tag("all")
                Text("People see only theirs").tag("assigned")
            }
            Picker("Leads", selection: Binding(get: { s.leadVisibility }, set: { v in
                Task { await change(.visibility(claims: nil, leads: v)) { $0.leadVisibility = v } }
            })) {
                Text("Everyone sees every lead").tag("all")
                Text("People see only theirs").tag("assigned")
            }
        } header: { Text("Who sees what") } footer: { Text("\"Theirs\" means the claims and leads someone is on.") }
        .disabled(!s.can.visibility)
    }

    private func webForm(_ s: CompanySettings) -> some View {
        Section {
            Toggle("Accept requests from your website", isOn: Binding(get: { s.webLeads.enabled }, set: { v in
                Task { await change(.webLeads(enabled: v, ownerId: s.webLeads.ownerId, keepGroup: s.webLeads.ownerIsGroup)) { $0.webLeads.enabled = v } }
            }))
            .accessibilityIdentifier("webLeadsToggle")
            if s.webLeads.ownerIsGroup {
                LabeledContent("New leads go to", value: "A group")
            } else {
                Picker("New leads go to", selection: Binding(get: { s.webLeads.ownerId ?? "" }, set: { v in
                    let owner = v.isEmpty ? nil : v
                    Task { await change(.webLeads(enabled: s.webLeads.enabled, ownerId: owner, keepGroup: false)) { $0.webLeads.ownerId = owner } }
                })) {
                    Text("No one in particular").tag("")
                    ForEach(s.people) { Text($0.name).tag($0.id) }
                }
            }
        } header: { Text("Website form") } footer: { if s.webLeads.ownerIsGroup { Text("Change the group on the website.") } }
        .disabled(!s.can.webLeads)
    }

    private func uploads(_ s: CompanySettings) -> some View {
        Section {
            Toggle("Staff choose a folder for each upload", isOn: Binding(get: { s.uploadRules.staffFolderRequired }, set: { v in
                Task { await change(.uploadRules(staff: v, portal: s.uploadRules.portalFolderRequired)) { $0.uploadRules.staffFolderRequired = v } }
            }))
            Toggle("Policyholders choose a folder", isOn: Binding(get: { s.uploadRules.portalFolderRequired }, set: { v in
                Task { await change(.uploadRules(staff: s.uploadRules.staffFolderRequired, portal: v)) { $0.uploadRules.portalFolderRequired = v } }
            }))
        } header: { Text("Uploads") } footer: { Text("Off means files go to the top level unless someone picks a folder.") }
        .disabled(!s.can.uploadRules)
    }

    @ViewBuilder
    private func messages(_ s: CompanySettings, forPolicyholders: Bool) -> some View {
        let list = s.messages.filter { $0.isForPolicyholders == forPolicyholders }
        if !list.isEmpty {
            Section {
                ForEach(list) { message in
                    Toggle(isOn: Binding(get: { message.enabled }, set: { v in
                        Task { await change(.message(event: message.event, enabled: v)) { settings in
                            if let i = settings.messages.firstIndex(where: { $0.event == message.event }) { settings.messages[i].enabled = v }
                        } }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.label)
                            Text(message.when).font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("message-\(message.event)")
                }
            } header: {
                Text(forPolicyholders ? "Messages to policyholders" : "Team alerts")
            } footer: {
                Text(forPolicyholders ? "Switch one off to stop sending it. You change what it says on the website." : "Off stops that email for everyone. The alert still shows in the app.")
            }
            .disabled(!s.can.messages)
        }
    }

    // MARK: Actions

    private func load() async {
        loadFailed = false
        do {
            let loaded = try await api.companySettings()
            settings = loaded
            badge = loaded.markText ?? ""
            if let hex = loaded.brandColor, let c = Color(hex: hex) { color = c }
            hasColor = false
        } catch { loadFailed = true }
    }

    /// Shows the change at once and puts it back if the server refuses.
    private func change(_ change: CompanySettingChange, apply: (inout CompanySettings) -> Void) async {
        guard let before = settings else { return }
        var after = before
        apply(&after)
        settings = after
        do { try await api.saveCompanySetting(change) } catch {
            settings = before
            errorMessage = settingsMessage(error, fallback: "Couldn't save. Try again.")
        }
    }

    private func saveBrand() async {
        guard settings != nil else { return }
        savingBrand = true
        defer { savingBrand = false }
        let hex = hasColor ? color.hexString : (settings?.brandColor ?? "")
        do {
            try await api.saveCompanySetting(.brand(markText: badge, brandColor: hex))
            settings?.markText = badge.isEmpty ? nil : badge
            settings?.brandColor = hex.isEmpty ? nil : hex
            hasColor = false
        } catch { errorMessage = settingsMessage(error, fallback: "Couldn't save. Try again.") }
    }
}

// MARK: - Colour helpers

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// "#RRGGBB", upper case.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
