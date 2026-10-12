import PortalKit
import SwiftUI

/// Submit a Lead (spec §6.8): one scrolling form in 5 numbered sections with a sticky Submit button,
/// then a confirmation and the supporting-files step.
struct SubmitLeadView: View {
    @State private var viewModel: SubmitLeadViewModel
    /// Called from Done with the new lead's id and name.
    let onDone: (_ leadId: String, _ name: String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, userEmail: String, onDone: @escaping (String, String) -> Void) {
        _viewModel = State(initialValue: SubmitLeadViewModel(api: api, userEmail: userEmail))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Group {
                if let leadId = viewModel.createdLeadId {
                    SubmittedLeadView(leadId: leadId, message: viewModel.confirmationMessage) {
                        onDone(leadId, viewModel.submission.leadName)
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Submit a Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.createdLeadId == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isSubmitting || viewModel.createdLeadId != nil)
        }
        .task { await viewModel.loadPerils() }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            claimantSection
            addressSection
            lossSection
            insuranceSection
            referralSection
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { submitBar }
        .toolbar {
            // Number and phone pads have no return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("keyboardDone")
            }
        }
    }

    private var claimantSection: some View {
        Section {
            TextField("Name", text: $viewModel.name)
                .textContentType(.name)
                .accessibilityIdentifier("leadName")
            errorText(.name)
            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("leadEmail")
            errorText(.email)
            TextField("Phone", text: $viewModel.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .accessibilityIdentifier("leadPhone")
            errorText(.contact)
        } header: {
            Text("1. Claimant information")
        } footer: {
            Text("Name is required, plus an email or phone number.")
        }
    }

    private var addressSection: some View {
        Section("2. Property address") {
            TextField("Street", text: $viewModel.street)
                .textContentType(.fullStreetAddress)
            TextField("City", text: $viewModel.city)
                .textContentType(.addressCity)
            Picker("State", selection: $viewModel.stateCode) {
                Text("Select a state").tag(String?.none)
                ForEach(SubmitLeadViewModel.usStates, id: \.code) { state in
                    Text(state.name).tag(String?.some(state.code))
                }
            }
            TextField("ZIP code", text: $viewModel.postalCode)
                .textContentType(.postalCode)
                .keyboardType(.numberPad)
            errorText(.postalCode)
        }
    }

    private var lossSection: some View {
        Section("3. Loss details") {
            perilPicker
            TextField("Loss description", text: $viewModel.lossDescription, axis: .vertical)
                .lineLimit(3...8)
            TextField("Link to photos (optional)", text: $viewModel.fileLink)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            errorText(.fileLink)
        }
    }

    @ViewBuilder
    private var perilPicker: some View {
        switch viewModel.perils {
        case .loaded(let perils, _):
            Picker("Peril", selection: $viewModel.peril) {
                Text("Select a peril").tag(String?.none)
                ForEach(perils, id: \.self) { peril in
                    Text(peril).tag(String?.some(peril))
                }
            }
        case .failed:
            HStack {
                Text("Perils couldn't be loaded.")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Retry") { Task { await viewModel.loadPerils() } }
            }
        case .idle, .loading:
            LabeledContent("Peril") { ProgressView() }
        }
    }

    private var insuranceSection: some View {
        Section("4. Insurance") {
            TextField("Insurance company", text: $viewModel.insuranceQuery)
                .autocorrectionDisabled()
                .accessibilityIdentifier("insuranceCompany")
            insuranceResults
            TextField("Policy number", text: $viewModel.policyNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Picker("Has a claim been filed?", selection: $viewModel.claimFiled) {
                Text("Not sure").tag(SubmitLeadViewModel.ClaimFiled?.none)
                ForEach(SubmitLeadViewModel.ClaimFiled.allCases, id: \.self) { answer in
                    Text(answer.rawValue).tag(SubmitLeadViewModel.ClaimFiled?.some(answer))
                }
            }
            if viewModel.claimFiled == .yes {
                TextField("Claim number", text: $viewModel.claimNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        }
    }

    @ViewBuilder
    private var insuranceResults: some View {
        switch viewModel.insuranceSearch {
        case .idle:
            EmptyView()
        case .searching:
            HStack {
                ProgressView()
                Text("Searching…").foregroundStyle(Color.textSecondary)
            }
        case .noResults:
            Text("No insurance companies found")
                .foregroundStyle(Color.textSecondary)
        case .unavailable:
            Text("Insurance company search is currently unavailable.")
                .foregroundStyle(Color.warning)
        case .results(let companies):
            ForEach(companies) { company in
                Button {
                    viewModel.selectInsuranceCompany(company)
                } label: {
                    Label(company.name, systemImage: "building.columns")
                }
                .accessibilityHint("Selects this insurance company")
            }
        }
    }

    private var referralSection: some View {
        Section {
            TextField("Company", text: $viewModel.referralCompany)
                .textContentType(.organizationName)
            TextField("Name", text: $viewModel.referralName)
                .textContentType(.name)
            TextField("Phone", text: $viewModel.referralPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            LabeledContent("Email") {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(viewModel.referralEmail)
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.textSecondary)
            }
            .accessibilityHint("Read only")
        } header: {
            Text("5. Referral")
        } footer: {
            Text("Your email links this lead to your My Leads list, so it can't be changed.")
        }
    }

    private var submitBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if viewModel.submitError != nil {
                Label("We couldn't submit this lead. Please try again.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.warning)
            } else if viewModel.showErrors && !viewModel.isValid {
                Text("Please fix the highlighted fields.")
                    .font(.footnote)
                    .foregroundStyle(Color.warning)
            }
            Button {
                Task { await viewModel.submit() }
            } label: {
                Group {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit").foregroundStyle(Color.surface)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("submitLeadButton")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    @ViewBuilder
    private func errorText(_ field: SubmitLeadViewModel.Field) -> some View {
        if let message = viewModel.error(for: field) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.warning)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

/// Confirmation and the supporting-files step (spec §6.8).
private struct SubmittedLeadView: View {
    let leadId: String
    let message: String
    let done: () -> Void

    @Environment(UploadQueue.self) private var queue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.success)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("leadConfirmation")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        SectionHeading("Supporting files")
                        Spacer()
                        UploadMenu(record: .lead(leadId))
                    }
                    Text("Add photos of the damage and any documents, such as the policy or an estimate. You can also add them later from the lead's Files.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .cardStyle()

                UploadStatusList(record: .lead(leadId))
            }
            .padding(Theme.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: done) {
                Text("Done")
                    .foregroundStyle(Color.surface)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .background(.bar)
            .accessibilityIdentifier("leadDone")
        }
    }
}

#Preview("Submit a Lead") {
    SubmitLeadView(api: PreviewData.api(), userEmail: "taylor@brooksroofing.example.com") { _, _ in }
}
