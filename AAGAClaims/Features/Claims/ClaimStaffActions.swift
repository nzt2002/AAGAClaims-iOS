import PortalKit
import SwiftUI

/// Staff actions on a claim's page: quick actions and communication.
enum ClaimAction: String, Identifiable, CaseIterable {
    case payments, addContact, edit, address, owner, proofOfLoss, post, email, task, event
    var id: String { rawValue }

    var title: String {
        switch self {
        case .payments: "Apply Payments"
        case .addContact: "Add Contact"
        case .edit: "Edit Claim"
        case .address: "Update Address"
        case .owner: "Change Owner"
        case .proofOfLoss: "Proof of Loss"
        case .post: "Add a Post"
        case .email: "Send an Email"
        case .task: "New Task"
        case .event: "New Event"
        }
    }

    var icon: String {
        switch self {
        case .payments: "dollarsign.circle"
        case .addContact: "person.badge.plus"
        case .edit: "square.and.pencil"
        case .address: "mappin.and.ellipse"
        case .owner: "person.crop.circle.badge.checkmark"
        case .proofOfLoss: "doc.text.magnifyingglass"
        case .post: "text.bubble"
        case .email: "envelope"
        case .task: "checklist"
        case .event: "calendar.badge.plus"
        }
    }

    /// In the More menu; the rest are on the action strip (and Edit Claim in the top bar).
    static let more: [ClaimAction] = [.addContact, .email, .address, .owner, .proofOfLoss]

    /// The label under a round action button.
    var shortTitle: String {
        switch self {
        case .payments: "Payments"
        case .post: "Post"
        case .email: "Email"
        case .addContact: "Contact"
        case .task: "Task"
        case .event: "Event"
        default: title
        }
    }
}

/// The claim's action strip (staff only): Apply Payments, Add a Post, New Task, New Event and More
/// (Add Contact, Send an Email, Update Address, Change Owner, Proof of Loss), as round icon buttons with labels on one card. Edit Claim is in the top bar.
struct ClaimQuickActions: View {
    /// In-house e-sign (pilot users only); shown in More when set.
    var onESign: (() -> Void)? = nil
    let open: (ClaimAction) -> Void
    @Environment(\.isOffline) private var isOffline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let strip: [ClaimAction] = [.payments, .post, .task, .event]

    var body: some View {
        // Five across; two across at accessibility text sizes, so labels never break mid-word.
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs, alignment: .top),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 5)
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(Self.strip) { action in
                Button { open(action) } label: {
                    ActionCircle(title: action.shortTitle, icon: action.icon)
                }
                .buttonStyle(ActionCirclePressStyle())
                .disabledWhenOffline(isOffline)
                .accessibilityLabel(action.title)
                .accessibilityIdentifier("claimAction-\(action.rawValue)")
            }
            Menu {
                ForEach(ClaimAction.more) { action in
                    Button { open(action) } label: { Label(action.title, systemImage: action.icon) }
                        .accessibilityIdentifier("claimAction-\(action.rawValue)")
                }
                if let onESign {
                    Button(action: onESign) { Label("E-Sign", systemImage: "signature") }
                        .accessibilityIdentifier("claimAction-eSign")
                }
            } label: {
                ActionCircle(title: "More", icon: "ellipsis")
            }
            .buttonStyle(ActionCirclePressStyle())
            .disabledWhenOffline(isOffline)
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("claimActionMore")
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

/// A round gradient icon with a short label under it, in the style of the system's contact actions.
struct ActionCircle: View {
    let title: String
    let icon: String
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 48
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isLeadRecord) private var isLead

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(BrandGradient.record(isLead: isLead, colorScheme), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1).padding(1))
                .opacity(isEnabled ? 1 : 0.4)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.textPrimary : Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// A gentle press: the circle shrinks a touch.
struct ActionCirclePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The sheet for one action. `saved` refreshes the claim afterwards.
struct ClaimActionSheet: View {
    let action: ClaimAction
    let actions: ClaimActionsViewModel
    let feed: ChatterFeedViewModel
    let api: PortalAPI
    /// The claim's Reference_ID__c, put in new emails.
    var referenceId: String?
    let saved: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch action {
                case .payments: ApplyPaymentsForm(api: api, claimId: actions.claimId, saved: saved)
                case .addContact: AddContactForm(api: api, claimId: actions.claimId, roles: actions.staff.value?.contactRoles ?? [], saved: saved)
                case .post: AddPostForm(feed: feed)
                default:
                    switch actions.staff {
                    case .loaded(let staff, _): form(staff)
                    case .failed: ErrorStateView(subject: "this claim") { Task { await actions.load() } }
                    case .idle, .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if actions.staff.value == nil { await actions.load() }
        }
        .onAppear { actions.clearError() }
    }

    @ViewBuilder
    private func form(_ staff: StaffClaim) -> some View {
        switch action {
        case .edit: EditClaimForm(staff: staff, actions: actions, api: api, saved: saved)
        case .address: UpdateAddressForm(staff: staff, actions: actions, saved: saved)
        case .owner: ChangeOwnerForm(staff: staff, actions: actions, saved: saved)
        case .proofOfLoss: ProofOfLossForm(staff: staff, actions: actions, saved: saved)
        case .email: EmailForm(api: api, staff: staff, referenceId: referenceId, saved: saved)
        case .payments, .addContact, .post, .task, .event: EmptyView()
        }
    }
}

// MARK: - Shared form pieces

/// Cancel and a Save button (or a spinner) for action forms.
struct FormToolbar: ToolbarContent {
    var saveTitle = "Save"
    let isSaving: Bool
    var canSave = true
    let save: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("actionCancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button(saveTitle) { Task { await save() } }
                    .bold()
                    .disabled(!canSave)
                    .accessibilityIdentifier("actionSave")
            }
        }
    }
}

struct ErrorRow: View {
    let message: String?
    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.warning)
                    .accessibilityIdentifier("actionError")
            }
        }
    }
}

/// A currency or number field for an optional Decimal.
private struct DecimalField: View {
    let title: String
    @Binding var value: Decimal?
    var prefix = "$"
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                if !prefix.isEmpty { Text(prefix).foregroundStyle(Color.textSecondary) }
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: text) { _, new in
                        let cleaned = new.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                        value = cleaned.isEmpty ? nil : Decimal(string: cleaned)
                    }
            }
        }
        .onAppear {
            if text.isEmpty, let value { text = NSDecimalNumber(decimal: value).stringValue }
        }
    }
}

/// An optional date with a switch, stored as a CalendarDate.
struct OptionalDateRow: View {
    let title: String
    @Binding var value: CalendarDate?

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { value != nil },
            set: { value = $0 ? (value ?? CalendarDate(Date())) : nil }
        ).animation())
        if let current = value {
            DatePicker("Date", selection: Binding(
                get: { current.date },
                set: { value = CalendarDate($0) }
            ), displayedComponents: .date)
        }
    }
}

extension CalendarDate {
    /// Midnight, local time.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    init(_ date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

func optional(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Edit Claim

private struct EditClaimForm: View {
    let actions: ClaimActionsViewModel
    let api: PortalAPI
    let saved: () -> Void
    @State private var edit: ClaimEdit
    @State private var insuranceQuery: String
    @State private var insuranceResults: [InsuranceCompany] = []
    let staff: StaffClaim
    @Environment(\.dismiss) private var dismiss

    init(staff: StaffClaim, actions: ClaimActionsViewModel, api: PortalAPI, saved: @escaping () -> Void) {
        self.staff = staff
        self.actions = actions
        self.api = api
        self.saved = saved
        var edit = ClaimEdit(name: staff.name ?? "")
        edit.status = staff.status
        edit.peril = staff.peril
        edit.lossDate = staff.lossDate
        edit.lossDescription = staff.lossDescription
        edit.claimNumber = staff.claimNumber
        edit.policyNumber = staff.policyNumber
        edit.insuranceCompanyId = staff.insuranceCompanyId
        edit.deductible = staff.deductible
        edit.adjusterFees = staff.adjusterFees
        edit.accountManagerId = staff.accountManagerId
        _edit = State(initialValue: edit)
        _insuranceQuery = State(initialValue: staff.insuranceCompanyName ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Claim name", text: $edit.name)
                    .accessibilityIdentifier("editClaimName")
                Picker("Stage", selection: $edit.status) {
                    ForEach(staff.statuses, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("editClaimStatus")
                Picker("Peril", selection: $edit.peril) {
                    Text("Not set").tag(String?.none)
                    ForEach(staff.perils, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
            }
            Section("Loss") {
                OptionalDateRow(title: "Loss date", value: $edit.lossDate)
                TextField("Loss description", text: Binding(get: { edit.lossDescription ?? "" }, set: { edit.lossDescription = optional($0) }), axis: .vertical)
                    .lineLimit(2...8)
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
                TextField("Claim number", text: Binding(get: { edit.claimNumber ?? "" }, set: { edit.claimNumber = optional($0) }))
                    .textInputAutocapitalization(.characters)
                TextField("Policy number", text: Binding(get: { edit.policyNumber ?? "" }, set: { edit.policyNumber = optional($0) }))
                    .textInputAutocapitalization(.characters)
            }
            Section("Money and team") {
                DecimalField(title: "Deductible", value: $edit.deductible)
                DecimalField(title: "Adjuster fees (%)", value: $edit.adjusterFees, prefix: "")
                Picker("Account manager", selection: $edit.accountManagerId) {
                    Text("None").tag(String?.none)
                    ForEach(staff.users) { Text($0.name).tag(String?.some($0.userId)) }
                }
                .pickerStyle(.menu)
            }
            ErrorRow(message: actions.errorMessage)
        }
        .toolbar {
            FormToolbar(isSaving: actions.isSaving) {
                if await actions.saveEdit(edit) {
                    saved()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Update Address

private struct UpdateAddressForm: View {
    let staff: StaffClaim
    let actions: ClaimActionsViewModel
    let saved: () -> Void
    @State private var street: String
    @State private var city: String
    @State private var state: String?
    @State private var postalCode: String
    @Environment(\.dismiss) private var dismiss

    init(staff: StaffClaim, actions: ClaimActionsViewModel, saved: @escaping () -> Void) {
        self.staff = staff
        self.actions = actions
        self.saved = saved
        _street = State(initialValue: staff.street ?? "")
        _city = State(initialValue: staff.city ?? "")
        _state = State(initialValue: staff.state)
        _postalCode = State(initialValue: staff.postalCode ?? "")
    }

    var body: some View {
        Form {
            Section("Loss address") {
                StreetAddressField(street: $street) { address in
                    street = address.street
                    city = address.city
                    state = staff.states.contains(address.state) ? address.state : nil
                    postalCode = address.postalCode
                }
                TextField("City", text: $city)
                Picker("State", selection: $state) {
                    Text("Not set").tag(String?.none)
                    ForEach(staff.states, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                TextField("ZIP code", text: $postalCode)
                    .keyboardType(.numberPad)
            }
            ErrorRow(message: actions.errorMessage)
        }
        .toolbar {
            FormToolbar(isSaving: actions.isSaving) {
                let address = ClaimAddress(street: optional(street), city: optional(city), state: state, postalCode: optional(postalCode))
                if await actions.saveAddress(address) {
                    saved()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Change Owner

private struct ChangeOwnerForm: View {
    let staff: StaffClaim
    let actions: ClaimActionsViewModel
    let saved: () -> Void
    @State private var selection: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    init(staff: StaffClaim, actions: ClaimActionsViewModel, saved: @escaping () -> Void) {
        self.staff = staff
        self.actions = actions
        self.saved = saved
        _selection = State(initialValue: staff.ownerId)
    }

    private var users: [TaskAssignee] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? staff.users : staff.users.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Current owner", value: staff.ownerName ?? "—")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
                    TextField("Search people", text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ownerSearch")
                }
            }
            Section("New owner") {
                ForEach(users) { user in
                    Button { selection = user.userId } label: {
                        HStack {
                            Text(user.name).foregroundStyle(Color.textPrimary)
                            Spacer()
                            if selection == user.userId {
                                Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary)
                            }
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == user.userId ? .isSelected : [])
                    .accessibilityIdentifier("owner-\(user.userId)")
                }
            }
            ErrorRow(message: actions.errorMessage)
        }
        .toolbar {
            FormToolbar(isSaving: actions.isSaving, canSave: selection != nil && selection != staff.ownerId) {
                guard let selection else { return }
                if await actions.changeOwner(to: selection) {
                    saved()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Proof of Loss

private struct ProofOfLossForm: View {
    let staff: StaffClaim
    let actions: ClaimActionsViewModel
    let saved: () -> Void
    @State private var pol: ProofOfLoss
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var generatorURL: URL?
    @State private var openingGenerator = false
    @Environment(\.salesforcePage) private var salesforcePage

    /// The document is made by a Salesforce page (DocMerge), as from the quick action.
    private static let documentSolutionKey = "384d10eb-635a-4b6d-8b5b-578e06ed9643"

    init(staff: StaffClaim, actions: ClaimActionsViewModel, saved: @escaping () -> Void) {
        self.staff = staff
        self.actions = actions
        self.saved = saved
        _pol = State(initialValue: staff.proofOfLoss)
        let parts = (staff.proofOfLoss.timeOfLoss ?? "").split(separator: ":").compactMap { Int($0) }
        _hasTime = State(initialValue: parts.count >= 2)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: parts.first ?? 12, minute: parts.count > 1 ? parts[1] : 0)) ?? Date())
    }

    private var current: ProofOfLoss {
        var value = pol
        if hasTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            value.timeOfLoss = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        } else {
            value.timeOfLoss = nil
        }
        return value
    }

    /// The DocMerge page, opened signed in.
    private var generatorPath: String {
        SalesforcePageLink.path("/apex/hic_docmerge__Composer", query: [
            URLQueryItem(name: "advancemergefields", value: "true"),
            URLQueryItem(name: "id", value: staff.id),
            URLQueryItem(name: "documentSolutionKey", value: Self.documentSolutionKey)
        ])
    }

    var body: some View {
        Form {
            Section {
                let missing = current.missingCount
                Label(missing == 0 ? "All 13 fields are complete." : "\(13 - missing) of 13 fields complete.",
                      systemImage: missing == 0 ? "checkmark.seal.fill" : "list.bullet.clipboard")
                    .foregroundStyle(missing == 0 ? Color.success : Color.textSecondary)
                    .accessibilityIdentifier("polProgress")
            } footer: {
                Text("Every field is needed before the Proof of Loss document can be generated.")
            }
            Section("Amounts") {
                DecimalField(title: "Total loss & damage", value: $pol.totalLossDamage)
                DecimalField(title: "Total actual cash value", value: $pol.totalActualCashValue)
                DecimalField(title: "Total amount claimed", value: $pol.totalAmountClaimed)
            }
            Section("Loss") {
                OptionalDateRow(title: "Loss date", value: $pol.lossDate)
                Toggle("Time of loss", isOn: $hasTime.animation())
                if hasTime {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            Section("Policy") {
                TextField("Policy number", text: Binding(get: { pol.policyNumber ?? "" }, set: { pol.policyNumber = optional($0) }))
                    .textInputAutocapitalization(.characters)
                OptionalDateRow(title: "Effective date", value: $pol.policyEffectiveDate)
                OptionalDateRow(title: "Expiration date", value: $pol.policyExpirationDate)
                DecimalField(title: "Coverage amount", value: $pol.policyCoverageAmount)
            }
            Section("Property") {
                TextField("Other persons", text: Binding(get: { pol.otherPersons ?? "" }, set: { pol.otherPersons = optional($0) }))
                TextField("Changes affecting the property", text: Binding(get: { pol.changesAffectingProperty ?? "" }, set: { pol.changesAffectingProperty = optional($0) }), axis: .vertical)
                Picker("Primary home or rental", selection: $pol.primaryHomeOrRental) {
                    Text("Not set").tag(String?.none)
                    ForEach(staff.primaryHomeValues, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                Picker("Occupancy", selection: $pol.occupancy) {
                    Text("Not set").tag(String?.none)
                    ForEach(staff.occupancyValues, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
            }
            ErrorRow(message: actions.errorMessage)
            Section {
                Button {
                    guard let salesforcePage else { return }
                    openingGenerator = true
                    Task {
                        generatorURL = await salesforcePage.url(for: generatorPath)
                        openingGenerator = false
                    }
                } label: {
                    HStack {
                        Label("Generate Proof of Loss Document", systemImage: "doc.richtext")
                        if openingGenerator { Spacer(); ProgressView() }
                    }
                }
                .disabled(!staff.proofOfLoss.isComplete || salesforcePage == nil || openingGenerator)
                .accessibilityIdentifier("polGenerate")
            } footer: {
                Text(salesforcePage == nil
                     ? "Document generation opens in Salesforce, which isn't available in demo mode."
                     : staff.proofOfLoss.isComplete
                        ? "Opens Salesforce's document generator, already signed in."
                        : "Save all 13 fields first.")
            }
        }
        .toolbar {
            FormToolbar(isSaving: actions.isSaving) {
                if await actions.saveProofOfLoss(current) {
                    saved()
                }
            }
        }
        .sheet(item: Binding(get: { generatorURL.map(SafariLink.init) }, set: { generatorURL = $0?.url })) {
            SafariView(url: $0.url).ignoresSafeArea()
        }
    }
}

// MARK: - Apply Payments

private struct ApplyPaymentsForm: View {
    @State private var model: PaymentCalculatorViewModel
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, claimId: String, saved: @escaping () -> Void) {
        _model = State(initialValue: PaymentCalculatorViewModel(api: api, claimId: claimId))
        self.saved = saved
    }

    var body: some View {
        Group {
            switch model.setup {
            case .idle, .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed: ErrorStateView(subject: "the payment calculator") { Task { await model.load() } }
            case .loaded: form
            }
        }
        .task { if model.setup.value == nil { await model.load() } }
    }

    private var form: some View {
        Form {
            if model.isBlocked {
                Section {
                    Label("Please add the Deductible on this claim before using the payment calculator.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                        .accessibilityIdentifier("paymentsBlocked")
                }
            }
            Section {
                DatePicker("Date collected", selection: $model.dateCollected, in: ...Date(), displayedComponents: .date)
                Toggle(isOn: Binding(get: { model.applyDeductible }, set: { model.setApplyDeductible($0) })) {
                    VStack(alignment: .leading) {
                        Text("Apply deductible")
                        Text(PortalFormat.currency(model.deductible)).font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityIdentifier("applyDeductible")
            }
            Section("Payments") {
                ForEach($model.rows) { $row in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Picker("Type", selection: Binding(get: { row.rowType }, set: { model.setType($0, for: row.id) })) {
                            Text("Choose a type").tag(String?.none)
                            ForEach(model.paymentTypes, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("paymentType")
                        DecimalField(title: "Amount", value: $row.amount)
                            .accessibilityIdentifier("paymentAmount")
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { model.removeRow(row.id) }
                    }
                }
                Button { model.addRow() } label: { Label("Add payment", systemImage: "plus.circle") }
                    .accessibilityIdentifier("addPaymentRow")
            }
            Section {
                LabeledContent("RCV", value: PortalFormat.currency(model.totalRCV))
                LabeledContent("Payments received", value: PortalFormat.currency(model.received))
                if model.systemDeductible > 0 {
                    LabeledContent("Deductible", value: PortalFormat.currency(model.systemDeductible))
                }
                LabeledContent("Adjuster fee (\(percent(model.feeRate)))", value: PortalFormat.currency(model.adjusterFee))
                LabeledContent("Insured payment", value: PortalFormat.currency(model.insuredPayment))
                    .bold()
                    .accessibilityIdentifier("insuredPayment")
            } header: {
                Text("This entry")
            } footer: {
                if model.systemDeductible > 0 { Text("The adjuster fee includes the deductible.") }
            }
            Section("Notes") {
                TextField("Optional", text: $model.notes, axis: .vertical).lineLimit(2...6)
            }
            ErrorRow(message: model.errorMessage)
        }
        .toolbar {
            FormToolbar(isSaving: model.isSaving, canSave: !model.isBlocked) {
                if await model.save() {
                    saved()
                    dismiss()
                }
            }
        }
    }

    private func percent(_ rate: Decimal) -> String {
        (rate * 100).formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}

// MARK: - Add Contact

private struct AddContactForm: View {
    @State private var model: AddClaimContactViewModel
    let roles: [String]
    let saved: () -> Void
    @State private var query = ""
    @State private var partnerQuery = ""
    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, claimId: String, roles: [String], saved: @escaping () -> Void) {
        _model = State(initialValue: AddClaimContactViewModel(api: api, claimId: claimId))
        self.roles = roles.isEmpty ? ["Property Contact", "Sub-Contractor", "Adjuster", "Other"] : roles
        self.saved = saved
    }

    var body: some View {
        Form {
            switch model.step {
            case .form: details
            case .matches: matches
            case .partner: partner
            case .duplicate: duplicate
            case .done: EmptyView()
            }
            ErrorRow(message: model.errorMessage)
        }
        .onChange(of: model.step) { _, step in
            if step == .done {
                saved()
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if model.isWorking {
                    ProgressView()
                } else if model.step == .form {
                    Button(model.mode == .existing ? "Add" : "Next") { Task { await model.continueFromForm() } }
                        .bold()
                        .accessibilityIdentifier("actionSave")
                } else if model.step == .partner {
                    Button("Add") { Task { await model.continueFromPartner() } }.bold()
                }
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        Section {
            Picker("Contact", selection: $model.mode.animation()) {
                ForEach(AddClaimContactViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("addContactMode")
            Picker("Role", selection: $model.role) {
                Text("Choose…").tag(String?.none)
                ForEach(roles, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("addContactRole")
        }
        switch model.mode {
        case .existing:
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
                    TextField("Name or email", text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addContactSearch")
                }
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await model.search(query)
                }
                ForEach(model.searchResults) { contact in
                    Button { model.selectedContact = contact } label: {
                        contactRow(contact, selected: model.selectedContact?.id == contact.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addContactResult-\(contact.id)")
                }
            }
        case .new:
            Section {
                TextField("First name", text: $model.firstName)
                TextField("Last name", text: $model.lastName).accessibilityIdentifier("addContactLastName")
                TextField("Email", text: $model.email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Mobile phone", text: $model.mobile).keyboardType(.phonePad)
                TextField(model.isSubcontractor ? "Company" : "Company (optional)", text: $model.company)
            } footer: {
                Text("We check for a contact with the same email, mobile phone or name first.")
            }
        }
    }

    private var matches: some View {
        Group {
            Section {
                Text("We found contacts that may be the same person. Choose one to add it, so it isn't added twice.")
            }
            Section("Possible matching contacts") {
                ForEach(model.matches) { contact in
                    Button { Task { await model.useMatch(contact) } } label: { contactRow(contact, selected: false) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("addContactMatch-\(contact.id)")
                }
            }
            Section {
                Button("None of these are a match") { Task { await model.noMatch() } }
                    .accessibilityIdentifier("addContactNoMatch")
            }
        }
    }

    private var partner: some View {
        Group {
            Section { Text("Subcontractor contacts belong to a company (Commercial) account.") }
            if !model.partnerMatches.isEmpty {
                Section {
                    ForEach(model.partnerMatches) { account in
                        Button { model.selectedPartner = account } label: {
                            HStack {
                                Text(account.name ?? "Account").foregroundStyle(Color.textPrimary)
                                Spacer()
                                if model.selectedPartner?.id == account.id { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary) }
                            }
                            .frame(minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Matching company accounts")
                } footer: {
                    Text("A company account with this name already exists. Choose it, so the company isn't added twice.")
                }
            } else {
                Section {
                    Picker("Company account", selection: $model.partnerMode) {
                        ForEach(NewClaimViewModel.PartnerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if model.partnerMode == .existing {
                        TextField("Company name", text: $partnerQuery)
                            .task(id: partnerQuery) {
                                try? await Task.sleep(for: .milliseconds(300))
                                guard !Task.isCancelled else { return }
                                await model.searchPartners(partnerQuery)
                            }
                        ForEach(model.partnerResults) { account in
                            Button { model.selectedPartner = account } label: {
                                HStack {
                                    Text(account.name ?? "Account").foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if model.selectedPartner?.id == account.id { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary) }
                                }
                                .frame(minHeight: Theme.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        TextField("Company name", text: $model.partnerName)
                    }
                }
            }
        }
    }

    private var duplicate: some View {
        Group {
            Section {
                Text("Salesforce found a matching contact already on file. Add the existing contact, or don't add one.")
            }
            Section("Existing contacts") {
                ForEach(model.duplicates) { contact in
                    Button { Task { await model.resolveDuplicate(contact) } } label: { contactRow(contact, selected: false) }
                        .buttonStyle(.plain)
                }
            }
            Section {
                Button("Don't add a contact") { Task { await model.resolveDuplicate(nil) } }
            }
        }
    }

    private func contactRow(_ contact: ContactMatch, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name ?? "Contact").font(.body.weight(.semibold)).foregroundStyle(Color.textPrimary)
                if !contact.details.isEmpty {
                    Text(contact.details).font(.subheadline).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary) }
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Add a Post, Send an Email

struct AddPostForm: View {
    let feed: ChatterFeedViewModel
    @Environment(\.serverMeta) private var serverMeta
    @State private var draft = MentionDraft()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                MentionField(prompt: "Share an update with the team. Type @ to mention someone.", draft: $draft,
                             search: feed.mentionCandidates, lineLimit: 4...12, autofocus: true, boxed: false,
                             identifier: "postText")
            } footer: {
                Text("Posts to the Chatter feed. Staff only; homeowners don't see it.")
            }
            if feed.supportsAttachments && serverMeta.supports(.chatterAttachments) {
                Section {
                    let id = ChatterFeedViewModel.newPostId
                    let files = feed.attachments[id] ?? []
                    if !files.isEmpty || feed.uploading.contains(id) {
                        DraftAttachments(files: files, isUploading: feed.uploading.contains(id)) { file in
                            feed.removeAttachment(file.id, from: id)
                        }
                    }
                    FileSourceMenu(maxCount: feed.maxFiles(for: id) - files.count, onPicked: { uploads in
                        Task { await feed.attach(uploads, to: id) }
                    }) {
                        Label("Attach Files", systemImage: "paperclip")
                            .frame(minHeight: Theme.minTapTarget)
                    }
                    .disabled(!feed.canAttach(to: id))
                    .accessibilityIdentifier("attachPost")
                    if let error = feed.attachmentErrors[id] {
                        Text(error).font(.footnote).foregroundStyle(Color.warning)
                    }
                } footer: {
                    Text("Files are also added to the record's Files.")
                }
            }
            if feed.failedId == ChatterFeedViewModel.newPostId {
                ErrorRow(message: "We couldn't post that. Please try again.")
            }
        }
        .toolbar {
            let id = ChatterFeedViewModel.newPostId
            FormToolbar(saveTitle: "Post", isSaving: feed.saving.contains(id),
                        canSave: (!draft.trimmedText.isEmpty || !(feed.attachments[id] ?? []).isEmpty) && !feed.uploading.contains(id)) {
                if await feed.post(draft) { dismiss() }
            }
        }
        // Files picked for a post that wasn't sent stay in the record's Files, but not on the next draft.
        .onDisappear { feed.discardDraft(ChatterFeedViewModel.newPostId) }
    }
}

private struct EmailForm: View {
    @State private var model: EmailComposerViewModel
    let staff: StaffClaim
    let saved: () -> Void
    @State private var toText = ""
    @State private var ccText = ""
    @State private var showingCc = false
    @State private var addressError: String?
    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, staff: StaffClaim, referenceId: String?, saved: @escaping () -> Void) {
        _model = State(initialValue: EmailComposerViewModel(api: api, claimId: staff.id, defaultRecipient: staff.emailRecipients.first?.value,
                                                            referenceId: referenceId))
        self.staff = staff
        self.saved = saved
    }

    var body: some View {
        Form {
            Section {
                if staff.fromAddresses.count > 1 {
                    Picker("From", selection: $model.fromAddressId) {
                        ForEach(staff.fromAddresses) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.menu)
                }
                recipients("To", addresses: model.to, remove: { _, address in model.to.removeAll { $0 == address } })
                addressField("Add recipient", text: $toText, field: \.to, id: "emailTo")
                let suggestions = staff.emailRecipients.filter { option in !model.to.contains { $0 == option.value } }
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions) { option in
                                Button { if let value = option.value { model.to.append(value) } } label: {
                                    Label(option.label, systemImage: "plus").font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                if showingCc {
                    recipients("Cc", addresses: model.cc, remove: { _, address in model.cc.removeAll { $0 == address } })
                    addressField("Add Cc", text: $ccText, field: \.cc, id: "emailCc")
                } else {
                    Button("Add Cc") { showingCc = true }
                }
                if let addressError {
                    Text(addressError).font(.footnote).foregroundStyle(Color.warning)
                }
            }
            Section {
                TextField("Subject", text: $model.subject).accessibilityIdentifier("emailSubject")
                TextField("Message", text: $model.body, axis: .vertical)
                    .lineLimit(6...20)
                    .accessibilityIdentifier("emailBody")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let footer = model.footer {
                        // Added below the message, so replies CC'd to the tracking mailbox are filed on the claim.
                        Text(footer)
                            .font(.footnote.monospaced())
                            .accessibilityIdentifier("emailFooter")
                    }
                    Text("Sent through Salesforce and saved to the claim's activity. The email ID is added at the bottom.")
                }
            }
            ErrorRow(message: model.errorMessage)
        }
        .toolbar {
            FormToolbar(saveTitle: "Send", isSaving: model.isSending, canSave: model.canSend) {
                if await model.send() {
                    saved()
                    dismiss()
                }
            }
        }
    }

    private func recipients(_ title: String, addresses: [String], remove: @escaping (String, String) -> Void) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                if addresses.isEmpty {
                    Text("None").foregroundStyle(Color.textSecondary)
                }
                ForEach(addresses, id: \.self) { address in
                    HStack(spacing: 4) {
                        Text(address).lineLimit(1)
                        Button { remove(address, address) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityLabel("Remove \(address)")
                    }
                }
            }
        }
    }

    private func addressField(_ prompt: String, text: Binding<String>, field: WritableKeyPath<EmailComposerViewModel, [String]>, id: String) -> some View {
        TextField(prompt, text: text)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit {
                addressError = nil
                guard !text.wrappedValue.isEmpty else { return }
                if model.add(text.wrappedValue, to: field) {
                    text.wrappedValue = ""
                } else {
                    addressError = "Enter a valid email address."
                }
            }
            .accessibilityIdentifier(id)
    }
}
