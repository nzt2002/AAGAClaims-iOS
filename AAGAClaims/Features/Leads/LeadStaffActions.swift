import PortalKit
import SwiftUI

/// Staff actions on a lead's page, in the claim page's style.
enum LeadAction: String, Identifiable {
    case convert, post, agreement, edit, status, task, event, portalUpdate
    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert to Account"
        case .post: "Add a Post"
        case .agreement: "Documents"
        case .edit: "Edit Lead"
        case .status: "Change Status"
        case .task: "New Task"
        case .event: "New Event"
        case .portalUpdate: "Write Portal Update"
        }
    }

    var shortTitle: String {
        switch self {
        case .convert: "Convert"
        case .post: "Post"
        case .agreement: "Documents"
        case .edit: "Edit"
        case .status: "Status"
        case .task: "Task"
        case .event: "Event"
        case .portalUpdate: "Portal Update"
        }
    }

    var icon: String {
        switch self {
        case .convert: "arrow.triangle.turn.up.right.circle"
        case .post: "text.bubble"
        case .agreement: "doc.text"
        case .edit: "square.and.pencil"
        case .status: "circle.dotted"
        case .task: "checklist"
        case .event: "calendar.badge.plus"
        case .portalUpdate: "megaphone"
        }
    }
}

/// The lead's action row (staff only): Convert, Post, Event, Status, Task and More (the agreement e-sign preview and
/// Write Portal Update), as icon tiles on the page like a claim's. Edit is the pencil in the header.
struct LeadQuickActions: View {
    let isConverted: Bool
    /// Actions the server doesn't support yet (e.g. Write Portal Update).
    var hidden: Set<LeadAction> = []
    let open: (LeadAction) -> Void

    static let row: [LeadAction] = [.event, .post, .status, .convert, .task, .agreement, .portalUpdate]

    var body: some View {
        // Converted: no new event or status; "Open the claim" leads the row.
        // Documents is for open leads only, as on the website.
        let order = isConverted ? [LeadAction.convert, .post, .task, .portalUpdate] : Self.row
        let items = order.filter { !hidden.contains($0) }.map { action in
            let viewClaim = action == .convert && isConverted
            return RecordActionItem(
                id: action.rawValue,
                title: viewClaim ? "View Claim" : action.shortTitle,
                menuTitle: viewClaim ? "View the converted claim" : action.title,
                icon: viewClaim ? "doc.text" : action.icon) { open(action) }
        }
        return RecordActionRow(items: items, idPrefix: "leadAction")
    }
}

/// Change Status: every status to pick from. Picking one saves it. (Converted is set by Convert.)
struct ChangeLeadStatusForm: View {
    let staff: LeadStaff
    let actions: LeadActionsViewModel
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving: String?

    var body: some View {
        List {
            Section {
                ForEach(staff.statuses.filter { $0 != "Converted" || staff.status == "Converted" }, id: \.self) { status in
                    Button {
                        Task { await choose(status) }
                    } label: {
                        HStack {
                            Text(status).foregroundStyle(Color.textPrimary)
                            Spacer()
                            if saving == status { ProgressView() }
                            else if staff.status == status { Image(systemName: "checkmark").foregroundStyle(Color.leadAccent) }
                        }
                        .frame(minHeight: Theme.minTapTarget)
                    }
                    .disabled(saving != nil || staff.isConverted == true)
                }
            } header: {
                Text("Now: \(staff.status ?? "Not set")")
            }
            ErrorRow(message: actions.errorMessage)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func choose(_ status: String) async {
        guard status != staff.status else { dismiss(); return }
        saving = status
        var edit = LeadEdit(staff)
        edit.status = status
        let ok = await actions.saveEdit(edit)
        saving = nil
        if ok {
            saved()
            dismiss()
        }
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
