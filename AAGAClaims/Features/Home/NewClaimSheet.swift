import PortalKit
import SwiftUI

/// New Claim (staff): the Prospect Conversion Guided Process without a Prospect. Opens on the
/// account choice; each later step pushes onto the stack, so Back always works.
struct NewClaimSheet: View {
    @State private var viewModel: NewClaimViewModel
    @State private var path: [NewClaimViewModel.Step] = []
    let close: () -> Void
    let created: (_ claimId: String, _ name: String) -> Void

    init(api: PortalAPI, conversion: LeadConversion? = nil, close: @escaping () -> Void,
         created: @escaping (_ claimId: String, _ name: String) -> Void) {
        _viewModel = State(initialValue: NewClaimViewModel(api: api, conversion: conversion))
        self.close = close
        self.created = created
    }

    var body: some View {
        NavigationStack(path: $path) {
            start
                .navigationDestination(for: NewClaimViewModel.Step.self) { step in
                    screen(for: step)
                        .toolbar { closeButton }
                }
                .toolbar { closeButton }
        }
        .interactiveDismissDisabled(viewModel.isWorking || !path.isEmpty)
        .task {
            if viewModel.options.value == nil { await viewModel.loadOptions() }
        }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark", action: close)
                .accessibilityIdentifier("newClaimClose")
        }
    }

    private func go(_ step: NewClaimViewModel.Step?) {
        if let step { path.append(step) }
    }

    @ViewBuilder
    private func screen(for step: NewClaimViewModel.Step) -> some View {
        switch step {
        case .accountSearch: AccountSearchStep(viewModel: viewModel, go: go)
        case .newAccount: NewAccountStep(viewModel: viewModel, go: go)
        case .accountMatches: AccountMatchesStep(viewModel: viewModel, go: go)
        case .claimDetails: ClaimDetailsStep(viewModel: viewModel, go: go)
        case .contact: ContactStep(viewModel: viewModel, go: go)
        case .contactMatches: ContactMatchesStep(viewModel: viewModel, go: go)
        case .partner: PartnerStep(viewModel: viewModel, go: go)
        case .review: ReviewStep(viewModel: viewModel, go: go, finish: finish)
        case .duplicateContact: DuplicateContactStep(viewModel: viewModel, go: go, finish: finish)
        }
    }

    private func finish() {
        guard let id = viewModel.createdClaimId else { return }
        created(id, viewModel.claimName)
    }

    // MARK: - Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(viewModel.conversion == nil ? "Who is this claim for?" : "Which account is this lead for?")
                    .font(.title2.bold())
                Text(viewModel.conversion == nil
                     ? "Choose an existing account, or create a new one. We always check for an existing account first, so customers aren't added twice."
                     : "Converting \(viewModel.conversion?.leadName ?? "this lead") creates its claim. Choose an existing account, or create one from the lead's details. We always check for an existing account first.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                choiceCard(
                    title: "Existing account",
                    detail: "Search by name, then add the claim.",
                    icon: "magnifyingglass",
                    id: "newClaimExistingAccount"
                ) { go(.accountSearch) }
                choiceCard(
                    title: "New account",
                    detail: viewModel.conversion == nil ? "Create the account, claim contact and claim." : "Create the account from the lead's details.",
                    icon: "plus",
                    id: "newClaimNewAccount"
                ) { go(.newAccount) }
                if case .failed = viewModel.options {
                    Label("We couldn't load the claim form. Check your connection and try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.appBackground)
        .navigationTitle(viewModel.conversion == nil ? "New Claim" : "Convert to Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choiceCard(title: String, detail: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemName: icon, size: 44, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.textSecondary)
            }
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickActionPressStyle())
        .accessibilityIdentifier(id)
    }
}

// MARK: - Shared pieces

/// "Next" in the top bar, or a spinner while a lookup runs.
private struct NextButton: ToolbarContent {
    let viewModel: NewClaimViewModel
    var title = "Next"
    let action: () async -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isWorking {
                ProgressView()
            } else {
                Button(title) { Task { await action() } }
                    .accessibilityIdentifier("newClaimNext")
            }
        }
    }
}

private struct FieldError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.warning)
        }
    }
}

private struct LoadError: View {
    let viewModel: NewClaimViewModel

    var body: some View {
        if viewModel.error != nil {
            Section {
                Label("Something went wrong. Check your connection and try again.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.warning)
            }
        }
    }
}

/// A tappable account or contact row with an optional checkmark.
private struct MatchRow: View {
    let title: String
    let detail: String
    var badge: String?
    var selected = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(selected ? Color.brandPrimary : Color.textSecondary)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A search box that runs `search` 300 ms after typing stops.
private struct DebouncedSearchField: View {
    let prompt: String
    @Binding var text: String
    let id: String
    let search: (String) async -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier(id)
        }
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(text)
        }
    }
}

// MARK: - 1. Account

private struct AccountSearchStep: View {
    let viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                DebouncedSearchField(prompt: "Account name", text: $query, id: "accountSearchField") {
                    await viewModel.searchAccounts($0)
                }
            } footer: {
                Text("Type at least 2 letters of the account name.")
            }
            if !viewModel.accountResults.isEmpty {
                Section("Accounts") {
                    ForEach(viewModel.accountResults) { account in
                        Button { go(viewModel.chooseAccount(account)) } label: {
                            MatchRow(title: account.name ?? "Account", detail: account.details, badge: account.kind)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("account-\(account.id)")
                    }
                }
            } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                Section {
                    Text("No accounts found. Go back and choose New account to create one.")
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .navigationTitle("Existing Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NewAccountStep: View {
    @Bindable var viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $viewModel.accountFirstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $viewModel.accountLastName)
                    .textContentType(.familyName)
                    .accessibilityIdentifier("newAccountLastName")
                FieldError(message: viewModel.error(.accountLastName, on: .newAccount))
                TextField("Email", text: $viewModel.accountEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldError(message: viewModel.error(.accountEmail, on: .newAccount))
                TextField("Phone", text: $viewModel.accountPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("Account holder")
            } footer: {
                Text("Before anything is created we check for an account with the same email, or the same first and last name.")
            }
            LoadError(viewModel: viewModel)
        }
        .navigationTitle("New Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { NextButton(viewModel: viewModel) { go(await viewModel.continueWithNewAccount()) } }
    }
}

private struct AccountMatchesStep: View {
    let viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void

    var body: some View {
        Form {
            Section {
                Label {
                    Text("This person may already have an account. To avoid a duplicate, choose the account to use for this claim.")
                } icon: {
                    Image(systemName: "person.2.badge.gearshape")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            Section("Possible matching accounts") {
                ForEach(viewModel.accountMatches) { account in
                    Button { go(viewModel.chooseAccount(account)) } label: {
                        MatchRow(title: account.name ?? "Account", detail: account.details, badge: account.kind)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountMatch-\(account.id)")
                }
            }
            Section {
                Text("Not the right person? Go back and check the name and email.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle("Matching Accounts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. Claim

private struct ClaimDetailsStep: View {
    @Bindable var viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Account", value: viewModel.accountDisplayName)
                TextField("Claim name", text: $viewModel.claimName)
                    .accessibilityIdentifier("claimName")
                FieldError(message: viewModel.error(.claimName, on: .claimDetails))
            } footer: {
                Text("Usually the last name and the damage, like \"Smith - Roof\".")
            }

            if let options = viewModel.options.value {
                Section("Loss") {
                    Picker("Peril", selection: $viewModel.peril) {
                        Text("Not set").tag(String?.none)
                        ForEach(options.perils, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    Toggle("Loss date", isOn: $viewModel.hasLossDate.animation())
                    if viewModel.hasLossDate {
                        DatePicker("Date", selection: $viewModel.lossDate, in: ...Date(), displayedComponents: .date)
                    }
                    TextField("What happened?", text: $viewModel.lossDescription, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Loss address") {
                    StreetAddressField(street: $viewModel.street) { address in
                        viewModel.street = address.street
                        viewModel.city = address.city
                        // Claims only take the states in the picklist (GA, SC).
                        viewModel.state = options.states.contains(address.state) ? address.state : nil
                        viewModel.postalCode = address.postalCode
                    }
                    TextField("City", text: $viewModel.city)
                        .textContentType(.addressCity)
                    Picker("State", selection: $viewModel.state) {
                        Text("Not set").tag(String?.none)
                        ForEach(options.states, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    TextField("ZIP code", text: $viewModel.postalCode)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                }

                insurance

                Section("Homeowner contact details") {
                    TextField("Email", text: $viewModel.claimEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    FieldError(message: viewModel.error(.claimEmail, on: .claimDetails))
                    TextField("Phone", text: $viewModel.claimPhone)
                        .keyboardType(.phonePad)
                }

                Section("Assignment") {
                    Picker("Adjuster", selection: $viewModel.ownerId) {
                        ForEach(options.users) { Text($0.name).tag(String?.some($0.userId)) }
                    }
                    .pickerStyle(.menu)
                    Picker("Account manager", selection: $viewModel.accountManagerId) {
                        Text("None").tag(String?.none)
                        ForEach(options.users) { Text($0.name).tag(String?.some($0.userId)) }
                    }
                    .pickerStyle(.menu)
                    Picker("Source", selection: $viewModel.source) {
                        ForEach(options.sources, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    TextField("Adjuster fees (%)", text: $viewModel.adjusterFees)
                        .keyboardType(.decimalPad)
                    FieldError(message: viewModel.error(.adjusterFees, on: .claimDetails))
                }
            } else {
                Section { ProgressView() }
            }
        }
        .navigationTitle("Claim Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { NextButton(viewModel: viewModel) { go(viewModel.continueFromClaimDetails()) } }
    }

    private var insurance: some View {
        Section("Insurance") {
            TextField("Insurance company", text: $viewModel.insuranceQuery)
                .autocorrectionDisabled()
                .task(id: viewModel.insuranceQuery) {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await viewModel.searchInsurance(viewModel.insuranceQuery)
                }
            ForEach(viewModel.insuranceResults) { company in
                Button(company.name) { viewModel.chooseInsurance(company) }
            }
            TextField("Policy number", text: $viewModel.policyNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Claim number", text: $viewModel.claimNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - 3. Contact

private struct ContactStep: View {
    @Bindable var viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                Picker("Claim contact", selection: $viewModel.contactMode.animation()) {
                    ForEach(NewClaimViewModel.ContactMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("contactMode")
            } header: {
                Text("Claim contact")
            } footer: {
                Text("Optional. Someone else involved in the claim, like a property contact or subcontractor.")
            }

            if viewModel.contactMode != .skip, let options = viewModel.options.value {
                Section {
                    Picker("Role", selection: $viewModel.contactRole) {
                        Text("Choose…").tag(String?.none)
                        ForEach(options.contactRoles, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("contactRole")
                    FieldError(message: viewModel.error(.contactRole, on: .contact))
                }
            }

            switch viewModel.contactMode {
            case .skip:
                EmptyView()
            case .existing:
                Section {
                    DebouncedSearchField(prompt: "Name or email", text: $query, id: "contactSearchField") {
                        await viewModel.searchContacts($0)
                    }
                    FieldError(message: viewModel.error(.contact, on: .contact))
                    ForEach(viewModel.contactResults) { contact in
                        Button { viewModel.selectedContact = contact } label: {
                            MatchRow(title: contact.name ?? "Contact", detail: contact.details,
                                     selected: viewModel.selectedContact?.id == contact.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("contact-\(contact.id)")
                    }
                }
            case .new:
                Section {
                    TextField("First name", text: $viewModel.contactFirstName)
                    TextField("Last name", text: $viewModel.contactLastName)
                        .accessibilityIdentifier("contactLastName")
                    FieldError(message: viewModel.error(.contactLastName, on: .contact))
                    TextField("Email", text: $viewModel.contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    FieldError(message: viewModel.error(.contactEmail, on: .contact))
                    TextField("Phone", text: $viewModel.contactPhone)
                        .keyboardType(.phonePad)
                    TextField(viewModel.isSubcontractor ? "Company" : "Company (optional)", text: $viewModel.contactCompany)
                        .accessibilityIdentifier("contactCompany")
                } footer: {
                    Text("We check for an existing contact with the same email or name first.")
                }
            }
            LoadError(viewModel: viewModel)
        }
        .navigationTitle("Claim Contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { NextButton(viewModel: viewModel) { go(await viewModel.continueFromContact()) } }
    }
}

private struct ContactMatchesStep: View {
    let viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void

    var body: some View {
        Form {
            Section {
                Text("We found contacts that may be the same person. Choose one to use it, so it isn't added twice.")
            }
            Section("Possible matching contacts") {
                ForEach(viewModel.contactMatches) { contact in
                    Button { go(viewModel.useMatchingContact(contact)) } label: {
                        MatchRow(title: contact.name ?? "Contact", detail: contact.details)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("contactMatch-\(contact.id)")
                }
            }
            Section {
                Button("None of these are a match") { Task { go(await viewModel.noContactMatches()) } }
                    .accessibilityIdentifier("noContactMatch")
            } footer: {
                Text("Creates the new contact you entered.")
            }
            LoadError(viewModel: viewModel)
        }
        .navigationTitle("Matching Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PartnerStep: View {
    @Bindable var viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                Text("Subcontractor contacts belong to a company (Commercial) account.")
            }
            if !viewModel.partnerMatches.isEmpty {
                Section {
                    ForEach(viewModel.partnerMatches) { account in
                        Button { viewModel.selectedPartner = account } label: {
                            MatchRow(title: account.name ?? "Account", detail: account.details,
                                     selected: viewModel.selectedPartner?.id == account.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("partnerMatch-\(account.id)")
                    }
                    FieldError(message: viewModel.error(.partner, on: .partner))
                } header: {
                    Text("Matching company accounts")
                } footer: {
                    Text("A company account with this name already exists. Choose it, so the company isn't added twice.")
                }
            } else {
                Section {
                    Picker("Company account", selection: $viewModel.partnerMode.animation()) {
                        ForEach(NewClaimViewModel.PartnerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch viewModel.partnerMode {
                    case .existing:
                        DebouncedSearchField(prompt: "Company name", text: $query, id: "partnerSearchField") {
                            await viewModel.searchPartners($0)
                        }
                        ForEach(viewModel.partnerResults) { account in
                            Button { viewModel.selectedPartner = account } label: {
                                MatchRow(title: account.name ?? "Account", detail: account.details,
                                         selected: viewModel.selectedPartner?.id == account.id)
                            }
                            .buttonStyle(.plain)
                        }
                    case .new:
                        TextField("Company name", text: $viewModel.partnerName)
                            .accessibilityIdentifier("partnerName")
                    }
                    FieldError(message: viewModel.error(.partner, on: .partner))
                }
            }
        }
        .navigationTitle("Company Account")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.partnerMode) { viewModel.selectedPartner = nil }
        .toolbar { NextButton(viewModel: viewModel) { go(viewModel.continueFromPartner()) } }
    }
}

// MARK: - 4. Review

private struct ReviewStep: View {
    let viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void
    let finish: () -> Void

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent(viewModel.isNewAccount ? "New account" : "Existing account", value: viewModel.accountDisplayName)
            }
            Section("Claim") {
                LabeledContent("Name", value: viewModel.claimName)
                if viewModel.conversion != nil {
                    Text("The loss details, address, insurance and team come from the lead, and the lead's files are linked to the claim. The lead is marked Converted.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                if let peril = viewModel.peril { LabeledContent("Peril", value: peril) }
                if viewModel.hasLossDate {
                    LabeledContent("Loss date", value: viewModel.lossDate.formatted(date: .abbreviated, time: .omitted))
                }
                let address = [viewModel.street, viewModel.city, viewModel.state ?? "", viewModel.postalCode]
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !address.isEmpty { LabeledContent("Loss address", value: address) }
                if let company = viewModel.insuranceCompany { LabeledContent("Insurance", value: company.name) }
                if let adjuster = viewModel.options.value?.users.first(where: { $0.userId == viewModel.ownerId }) {
                    LabeledContent("Adjuster", value: adjuster.name)
                }
            }
            Section("Claim contact") {
                switch viewModel.contactMode {
                case .skip:
                    Text("None").foregroundStyle(Color.textSecondary)
                case .existing:
                    LabeledContent(viewModel.contactRole ?? "Contact", value: viewModel.selectedContact?.name ?? "")
                case .new:
                    LabeledContent(viewModel.contactRole ?? "Contact", value: "New: \(viewModel.contactFirstName) \(viewModel.contactLastName)")
                    if viewModel.isSubcontractor {
                        LabeledContent("Company", value: viewModel.selectedPartner?.name ?? "New: \(viewModel.partnerName)")
                    }
                }
            }
            if let error = viewModel.error {
                Section {
                    Label(ClaimActionsViewModel.message(for: error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                }
            }
            Section {
                Button {
                    Task {
                        let next = await viewModel.submit()
                        if viewModel.createdClaimId != nil { finish() } else { go(next) }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isWorking { ProgressView() } else { Text(viewModel.conversion == nil ? "Create Claim" : "Convert").bold() }
                        Spacer()
                    }
                }
                .disabled(viewModel.isWorking)
                .accessibilityIdentifier("newClaimCreate")
            } footer: {
                Text(createSummary)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var createSummary: String {
        let parts = (viewModel.isNewAccount ? ["the account"] : []) + ["the claim"]
            + (viewModel.contactMode == .skip ? [] : ["the claim contact"])
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "Creates \(list) together. If anything fails, nothing is created."
    }
}

private struct DuplicateContactStep: View {
    let viewModel: NewClaimViewModel
    let go: (NewClaimViewModel.Step?) -> Void
    let finish: () -> Void

    var body: some View {
        Form {
            Section {
                Text("Salesforce found a matching contact already on file. Use the existing contact, or create the claim without a contact.")
            }
            Section("Existing contacts") {
                ForEach(viewModel.duplicateContacts) { contact in
                    Button { resolve(contact) } label: {
                        MatchRow(title: contact.name ?? "Contact", detail: contact.details)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("duplicateContact-\(contact.id)")
                }
            }
            Section {
                Button("Skip the claim contact") { resolve(nil) }
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("skipContact")
            }
            if viewModel.isWorking {
                Section { ProgressView() }
            }
        }
        .navigationTitle("Duplicate Contact")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolve(_ contact: ContactMatch?) {
        Task {
            let next = await viewModel.resolveDuplicateContact(using: contact)
            if viewModel.createdClaimId != nil { finish() } else { go(next) }
        }
    }
}
