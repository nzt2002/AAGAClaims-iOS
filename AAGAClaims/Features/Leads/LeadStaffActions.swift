import PortalKit
import SwiftUI

/// Staff actions on a lead's page, in the claim page's style.
enum LeadAction: String, Identifiable {
    case convert, post, agreement, edit
    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert to Account"
        case .post: "Add a Post"
        case .agreement: "Generate Agreement Preview E-Sign"
        case .edit: "Edit Lead"
        }
    }

    var shortTitle: String {
        switch self {
        case .convert: "Convert"
        case .post: "Post"
        case .agreement: "E-Sign"
        case .edit: "Edit"
        }
    }

    var icon: String {
        switch self {
        case .convert: "arrow.triangle.turn.up.right.circle"
        case .post: "text.bubble"
        case .agreement: "signature"
        case .edit: "square.and.pencil"
        }
    }
}

/// The lead's action strip (staff only): Convert to Account, Post, and the agreement e-sign preview.
/// Edit and Ask Question are in the top bar.
struct LeadQuickActions: View {
    let isConverted: Bool
    let open: (LeadAction) -> Void
    @Environment(\.isOffline) private var isOffline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs, alignment: .top),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach([LeadAction.convert, .post, .agreement]) { action in
                Button { open(action) } label: {
                    ActionCircle(title: action == .convert && isConverted ? "View Claim" : action.shortTitle,
                                 icon: action == .convert && isConverted ? "doc.text" : action.icon)
                }
                .buttonStyle(ActionCirclePressStyle())
                .disabledWhenOffline(isOffline)
                .accessibilityLabel(action == .convert && isConverted ? "View the converted claim" : action.title)
                .accessibilityIdentifier("leadAction-\(action.rawValue)")
            }
        }
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.surface)
                .shadow(color: Color.brandPrimary.opacity(0.10), radius: 14, x: 0, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.border.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Edit Lead

/// Edit: the core lead fields.
struct EditLeadForm: View {
    let staff: LeadStaff
    let actions: LeadActionsViewModel
    let api: PortalAPI
    let saved: () -> Void
    @State private var edit: LeadEdit
    @State private var insuranceQuery: String
    @State private var insuranceResults: [InsuranceCompany] = []
    @Environment(\.dismiss) private var dismiss

    init(staff: LeadStaff, actions: LeadActionsViewModel, api: PortalAPI, saved: @escaping () -> Void) {
        self.staff = staff
        self.actions = actions
        self.api = api
        self.saved = saved
        _edit = State(initialValue: LeadEdit(staff))
        _insuranceQuery = State(initialValue: staff.insuranceCompanyName ?? "")
    }

    private func text(_ keyPath: WritableKeyPath<LeadEdit, String?>) -> Binding<String> {
        Binding(get: { edit[keyPath: keyPath] ?? "" }, set: { edit[keyPath: keyPath] = optional($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                        .accessibilityIdentifier("editLeadName")
                    Picker("Status", selection: $edit.status) {
                        // Converted is set by Convert to Account.
                        ForEach(staff.statuses.filter { $0 != "Converted" || edit.status == "Converted" }, id: \.self) {
                            Text($0).tag(String?.some($0))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(staff.isConverted == true)
                    Picker("Peril", selection: $edit.peril) {
                        Text("Not set").tag(String?.none)
                        ForEach(staff.perils, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.menu)
                }
                Section("Homeowner") {
                    TextField("Email", text: text(\.email))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Phone", text: text(\.phone)).keyboardType(.phonePad)
                }
                Section("Loss") {
                    OptionalDateRow(title: "Loss date", value: $edit.lossDate)
                    TextField("Loss description", text: text(\.lossDescription), axis: .vertical).lineLimit(2...8)
                }
                Section("Loss address") {
                    StreetAddressField(street: text(\.street)) { address in
                        edit.street = address.street
                        edit.city = address.city
                        edit.state = address.state.isEmpty ? nil : address.state
                        edit.postalCode = address.postalCode
                    }
                    TextField("City", text: text(\.city))
                    Picker("State", selection: $edit.state) {
                        Text("Not set").tag(String?.none)
                        ForEach(SubmitLeadViewModel.usStates, id: \.code) { Text($0.name).tag(String?.some($0.code)) }
                    }
                    .pickerStyle(.menu)
                    TextField("ZIP code", text: text(\.postalCode)).keyboardType(.numberPad)
                }
                Section("Insurance") {
                    TextField("Insurance company", text: $insuranceQuery)
                        .autocorrectionDisabled()
                        .task(id: insuranceQuery) {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            let q = insuranceQuery.trimmingCharacters(in: .whitespaces)
                            if q.isEmpty { edit.insuranceCompanyId = nil }
                            insuranceResults = q.count >= 2 && q != staff.insuranceCompanyName
                                ? (try? await api.insuranceCompanies(matching: q)) ?? [] : []
                        }
                    ForEach(insuranceResults) { company in
                        Button(company.name) {
                            edit.insuranceCompanyId = company.id
                            insuranceQuery = company.name
                            insuranceResults = []
                        }
                    }
                    TextField("Policy number", text: text(\.policyNumber)).textInputAutocapitalization(.characters)
                    TextField("Claim number", text: text(\.claimNumber)).textInputAutocapitalization(.characters)
                }
                Section("Associated party") {
                    TextField("Name", text: text(\.associatedPartyName))
                    TextField("Company", text: text(\.associatedPartyCompany))
                    TextField("Email", text: text(\.associatedPartyEmail))
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Phone", text: text(\.associatedPartyPhone)).keyboardType(.phonePad)
                }
                ErrorRow(message: actions.errorMessage)
            }
            .navigationTitle("Edit Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FormToolbar(isSaving: actions.isSaving) {
                    if await actions.saveEdit(edit) {
                        saved()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { actions.clearError() }
    }
}
