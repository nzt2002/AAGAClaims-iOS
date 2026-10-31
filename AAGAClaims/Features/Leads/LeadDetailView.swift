import PortalKit
import SwiftUI

/// Lead detail (spec §6.7).
struct LeadDetailView: View {
    @State private var viewModel: LeadDetailViewModel
    /// Staff only: Convert, Post, the agreement e-sign preview, Edit and the Lead Feed.
    @State private var leadActions: LeadActionsViewModel
    @State private var leadFeed: ChatterFeedViewModel
    @State private var activity: RecordActivityViewModel
    @State private var openAction: LeadAction?
    @State private var showingConvert = false
    @State private var convertedClaim: (id: String, name: String)?
    @State private var showingESign = false
    @State private var eSignAvailable = false
    @State private var updatesFilter: UpdatesFilter = .leadFeed
    @Environment(\.isInternalUser) private var isInternal
    @Environment(\.openRecord) private var openRecord
    @Environment(\.currentUserName) private var currentUserName
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.serverMeta) private var serverMeta

    enum UpdatesFilter: String, CaseIterable {
        case leadFeed = "Lead Feed"
        case portalUpdates = "Portal Updates"
    }

    /// Generate Agreement - GA - Preview Esign (the lead page's DocMerge button).
    let fallbackName: String?
    let api: PortalAPI

    init(leadId: String, fallbackName: String?, api: PortalAPI) {
        _viewModel = State(initialValue: LeadDetailViewModel(leadId: leadId, api: api))
        _leadActions = State(initialValue: LeadActionsViewModel(api: api, leadId: leadId))
        _leadFeed = State(initialValue: ChatterFeedViewModel(api: api, source: .lead(leadId), outbox: .shared))
        _activity = State(initialValue: RecordActivityViewModel(api: api, record: .lead(leadId), includeEmails: false))
        self.fallbackName = fallbackName
        self.api = api
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.detail.value == nil {
                    viewModel.includesCases = serverMeta.supports(.recordCases)
                    await viewModel.load()
                }
                if isInternal, leadFeed.feed.value == nil {
                    async let staff: Void = leadActions.load()
                    async let feed: Void = leadFeed.load()
                    async let activity: Void = loadActivity()
                    _ = await (staff, feed, activity)
                }
            }
            .sheet(item: $openAction) { action in
                switch action {
                case .task:
                    NewTaskSheet(api: api, currentUserName: currentUserName, record: .lead(viewModel.leadId)) {
                        Task { await loadActivity() }
                    }
                case .event:
                    NewEventSheet(api: api, currentUserName: currentUserName, record: .lead(viewModel.leadId)) {
                        Task { await loadActivity() }
                    }
                case .edit:
                    if let staff = leadActions.staff.value {
                        EditLeadForm(staff: staff, actions: leadActions, api: api) {
                            Task { await viewModel.load() }
                        }
                    }
                default:
                    NavigationStack {
                        AddPostForm(feed: leadFeed)
                            .navigationTitle("Add a Post")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            // The new claim opens once the sheet has closed.
            .sheet(isPresented: $showingConvert, onDismiss: openConvertedClaim) {
                if let staff = leadActions.staff.value {
                    NewClaimSheet(api: api, conversion: LeadConversion(staff), close: { showingConvert = false }) { id, name in
                        convertedClaim = (id, name)
                        showingConvert = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Back in the foreground with data more than 5 minutes old (spec §7).
                if phase == .active, viewModel.detail.isStale() {
                    Task { await viewModel.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.detail {
        case .idle, .loading:
            ScrollView { SkeletonList(rows: 3).padding(Theme.Spacing.l) }
        case .failed(.notFound):
            ContentUnavailableView(
                "Lead not found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This lead isn't connected to your email address. Contact support if you think this is a mistake.")
            )
        case .failed:
            ErrorStateView(subject: "this lead") { Task { await viewModel.load() } }
        case .loaded(let detail, _):
            loaded(detail)
        }
    }

    private var recordName: String {
        viewModel.detail.value?.prospectName ?? fallbackName ?? "Lead"
    }

    private func loaded(_ detail: LeadDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(detail)
                LossAddressCard(address: detail.lossAddress)
                if isInternal {
                    LeadQuickActions(isConverted: isConverted(detail)) { handle($0, detail) }
                }
                LeadLifecycleCard(position: detail.lifecycle, status: detail.prospectStatus)
                if isInternal && serverMeta.supports(.leadActivities) {
                    RecordActivitySection(model: activity, api: api, noun: "lead")
                }
                AgreementCard(agreement: detail.agreement)
                SectionBar(selection: $viewModel.section)
                sectionContent(detail)
                TeamCard(
                    adjuster: .init(name: detail.adjusterName, phone: detail.adjusterPhone, email: detail.adjusterEmail),
                    deskAdjuster: .init(name: detail.deskAdjusterName, phone: nil, email: detail.deskAdjusterEmail),
                    accountManager: .init(name: detail.accountManagerName, phone: detail.accountManagerPhone, email: detail.accountManagerEmail),
                    adjusterFees: detail.adjusterFees
                )
            }
            .padding(Theme.Spacing.l)
        }
        .refreshable {
            await viewModel.load()
            if isInternal {
                await leadActions.load()
                await leadFeed.load()
                await loadActivity()
            }
        }
        .toolbar {
            if isInternal {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { openAction = .edit }
                        .disabled(leadActions.staff.value == nil)
                        .accessibilityLabel("Edit Lead")
                        .accessibilityIdentifier("leadAction-edit")
                }
            }
        }
        .environment(\.emailReference, EmailReference.reference(forRecordId: viewModel.leadId))
        // Ask Question is a top-bar icon; there's no Add Comment, as on claims.
        .recordActions(record: viewModel.record, recordName: recordName, api: api, placement: .toolbarIcon)
        .documentGeneration(record: viewModel.record, recordName: recordName, api: api,
                            isPresented: $showingESign, isAvailable: $eSignAvailable)
    }

    private func isConverted(_ detail: LeadDetail) -> Bool {
        leadActions.staff.value?.isConverted == true || detail.prospectStatus == "Converted"
    }

    private func handle(_ action: LeadAction, _ detail: LeadDetail) {
        switch action {
        case .convert:
            if isConverted(detail) {
                if let claimId = leadActions.staff.value?.convertedClaimId {
                    openRecord(.claim(claimId), name: detail.prospectName)
                }
            } else if leadActions.staff.value != nil {
                showingConvert = true
            }
        case .post, .edit, .task, .event:
            openAction = action
        case .agreement:
            // In-house e-sign (Docs Made Easy is no longer used from the app).
            showingESign = true
        }
    }

    private func openConvertedClaim() {
        guard let claim = convertedClaim else { return }
        convertedClaim = nil
        Task {
            await viewModel.load()
            await leadActions.load()
        }
        openRecord(.claim(claim.id), name: claim.name)
    }

    /// The lead's hero: status, name and numbers on the green lead gradient. The address is its own
    /// card below, so it can be tapped to open Maps.
    private func header(_ detail: LeadDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let status = PortalFormat.nonEmpty(detail.prospectStatus) {
                Text(status.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail.prospectName ?? "Lead")
                .font(.heroTitle)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
            // One fact per line, so numbers never split.
            VStack(alignment: .leading, spacing: 2) {
                if let number = PortalFormat.nonEmpty(detail.claimNumber) {
                    Text("Claim \(number)")
                }
                if let policy = PortalFormat.nonEmpty(detail.policyNumber) {
                    Text("Policy \(policy)")
                }
                if detail.lossDate != nil {
                    Text("Loss date \(PortalFormat.date(detail.lossDate))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandGradient.leadHero, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Emails are included once the server has them.
    private func loadActivity() async {
        guard isInternal, serverMeta.supports(.leadActivities) else { return }
        activity.includeEmails = serverMeta.supports(.activityEmails)
        await activity.load()
    }

    @ViewBuilder
    private func sectionContent(_ detail: LeadDetail) -> some View {
        switch viewModel.section {
        case .updates:
            if isInternal {
                Picker("Show", selection: $updatesFilter) {
                    ForEach(UpdatesFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("leadUpdatesFilter")
            }
            if isInternal && updatesFilter == .leadFeed {
                ChatterFeedSection(model: leadFeed, emptyMessage: "No posts on this lead yet. Use Post to start one.", visibleCount: 3)
            } else {
                SectionLoader(state: viewModel.updates, subject: "updates", retry: { await viewModel.loadUpdates() }) { updates in
                    UpdatesList(updates: updates, emptyMessage: "No updates have been published for this lead yet.", visibleCount: 3)
                }
            }
            if viewModel.includesCases {
                RecordCasesSection(state: viewModel.cases, noun: "lead") { await viewModel.loadCases() }
            }
        case .details:
            LeadDetailsSection(detail: detail)
        case .referredBy:
            ReferralCard(detail: detail)
        case .insurance:
            LeadInsuranceSection(detail: detail)
        case .files:
            FilesSection(record: viewModel.record, state: viewModel.files, api: api) { await viewModel.loadFiles() }
        }
    }
}

// MARK: - Cards

/// Collapsible, like the claim's: the status always shows; tap to see every stage.
private struct LeadLifecycleCard: View {
    let position: LeadLifecycle.Position
    let status: String?
    @State private var expanded = false

    private var hasStages: Bool {
        if case .stage = position { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Lead progress")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(PortalFormat.nonEmpty(status) ?? "Status not set")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer(minLength: 0)
                    if hasStages {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandPrimary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasStages)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the stages" : "Shows every stage")
            .accessibilityIdentifier("leadProgressToggle")

            if expanded, case .stage(_, let isUnqualified) = position {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(position.stages.enumerated()), id: \.offset) { index, stage in
                        StepRow(
                            title: stage,
                            state: position.state(ofStageAt: index),
                            isLast: index == position.stages.count - 1,
                            // Unqualified is shown in a warning style (spec §6.7).
                            currentTint: isUnqualified ? .warning : .brandPrimary
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
}

private struct AgreementCard: View {
    let agreement: Agreement?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeading(PortalFormat.nonEmpty(agreement?.agreementName) ?? "Agreement")
            if let steps = LeadDetailViewModel.agreementSteps(for: agreement) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        StepRow(
                            title: step.title,
                            state: step.state,
                            isLast: index == steps.count - 1,
                            detail: step.date.map { PortalFormat.date($0) },
                            currentTint: step.title == "Signed" ? .success : .brandPrimary
                        )
                    }
                }
            } else {
                Text("Visible once an agreement has been sent.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }
}

private struct ReferralCard: View {
    let detail: LeadDetail
    @Environment(\.emailReference) private var emailReference

    var body: some View {
        if [detail.associatedPartyName, detail.associatedPartyCompany, detail.associatedPartyEmail, detail.associatedPartyPhone]
            .allSatisfy({ PortalFormat.nonEmpty($0) == nil }) {
            Text("No one is recorded as referring this lead.")
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                FieldRow(label: "Name", value: detail.associatedPartyName, systemImage: "person")
                FieldRow(label: "Company", value: detail.associatedPartyCompany, systemImage: "building.2")
                LinkRow(label: "Phone", value: detail.associatedPartyPhone, url: ContactURL.phone(detail.associatedPartyPhone),
                        systemImage: "phone", actionName: "Call")
                LinkRow(label: "Email", value: detail.associatedPartyEmail, url: ContactURL.email(detail.associatedPartyEmail, reference: emailReference),
                        systemImage: "envelope", actionName: "Email")
            }
            .cardStyle()
        }
    }
}

private struct LeadDetailsSection: View {
    let detail: LeadDetail
    @Environment(\.emailReference) private var emailReference

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Lead name", value: detail.prospectName, systemImage: "person")
            FieldRow(label: "Peril", value: detail.peril, systemImage: "cloud.bolt")
            FieldRow(label: "Loss date", value: detail.lossDate == nil ? nil : PortalFormat.date(detail.lossDate), systemImage: "calendar")
            LinkRow(label: "Loss address", value: detail.lossAddress, url: ContactURL.map(detail.lossAddress),
                    systemImage: "mappin.and.ellipse", actionName: "Open in Maps")
            LinkRow(label: "Phone", value: detail.phone, url: ContactURL.phone(detail.phone), systemImage: "phone", actionName: "Call")
            LinkRow(label: "Mobile", value: detail.mobile, url: ContactURL.phone(detail.mobile), systemImage: "iphone", actionName: "Call")
            LinkRow(label: "Email", value: detail.email, url: ContactURL.email(detail.email, reference: emailReference), systemImage: "envelope", actionName: "Email")
            if let description = PortalFormat.nonEmpty(detail.lossDescription) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loss description")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(description)
                        .font(.subheadline)
                }
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityElement(children: .combine)
            }
            FieldRow(label: "Created", value: detail.createdDate == nil ? nil : PortalFormat.date(detail.createdDate), systemImage: "calendar.badge.plus")
            FieldRow(label: "Last updated", value: detail.lastModifiedDate == nil ? nil : PortalFormat.date(detail.lastModifiedDate), systemImage: "clock")
            LinkRow(label: "Supporting documents", value: ContactURL.web(detail.documentsUrl) == nil ? nil : "Open link",
                    url: ContactURL.web(detail.documentsUrl), systemImage: "folder", actionName: "Open")
        }
        .cardStyle()
    }
}

private struct LeadInsuranceSection: View {
    let detail: LeadDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Insurance company", value: detail.insuranceCompanyName, systemImage: "building.columns")
            FieldRow(label: "Claim filed?", value: detail.didFileClaim, systemImage: "questionmark.circle")
            FieldRow(label: "Claim number", value: detail.claimNumber, systemImage: "number")
            FieldRow(label: "Policy number", value: detail.policyNumber, systemImage: "doc.plaintext")
            if [detail.insuranceCompanyName, detail.didFileClaim, detail.claimNumber, detail.policyNumber]
                .allSatisfy({ PortalFormat.nonEmpty($0) == nil }) {
                Text("We haven't added insurance details to this lead yet.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }
}

#Preview("Lead detail") {
    NavigationStack {
        LeadDetailView(leadId: "a0r000000000001AAA", fallbackName: nil, api: PreviewData.api())
    }
}
