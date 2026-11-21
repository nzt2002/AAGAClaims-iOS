import Charts
import PortalKit
import SwiftUI

/// Claim detail (spec §6.5).
struct ClaimDetailView: View {
    @State private var viewModel: ClaimDetailViewModel
    /// Staff only: quick actions, communication and the Feed.
    @State private var actions: ClaimActionsViewModel
    @State private var claimFeed: ChatterFeedViewModel
    @State private var activity: RecordActivityViewModel
    @State private var openAction: ClaimAction?
    @State private var showingESign = false
    @State private var eSignAvailable = false
    @State private var updatesFilter: UpdatesFilter = .feed
    /// iPad, with room for two columns.
    @State private var isWide = false
    @Environment(\.isInternalUser) private var isInternal
    @Environment(\.isOffline) private var isOffline
    @Environment(\.currentUserName) private var currentUserName
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.serverMeta) private var serverMeta

    enum UpdatesFilter: String, CaseIterable {
        case feed = "Feed"
        /// Tasks, events and emails (staff, once the server has them).
        case activities = "Activities"
        case portalUpdates = "Portal Updates"
    }
    /// The list row, for fields only `GET /claims` returns (loss reason).
    let summary: ClaimSummary?
    let api: PortalAPI

    init(claimId: String, summary: ClaimSummary?, api: PortalAPI) {
        _viewModel = State(initialValue: ClaimDetailViewModel(claimId: claimId, api: api))
        _actions = State(initialValue: ClaimActionsViewModel(api: api, claimId: claimId))
        _claimFeed = State(initialValue: ChatterFeedViewModel(api: api, source: .claim(claimId), outbox: .shared))
        _activity = State(initialValue: RecordActivityViewModel(api: api, record: .claim(claimId), includeEmails: false))
        self.summary = summary
        self.api = api
    }

    /// How Alex can find this claim without a Salesforce Id: the carrier claim number, else the address.
    private var alexHint: String? {
        let detail = viewModel.detail.value
        if let number = detail?.claimNumber ?? summary?.claimNumber, !number.isEmpty { return "claim # \(number)" }
        if let address = detail?.lossAddress, !address.isEmpty { return "at \(address)" }
        return nil
    }

    var body: some View {
        content
            .background(Color.appBackground)
            // The header shows the name; repeating it in the bar wastes space.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .reportsViewedRecord(.claim(viewModel.claimId),
                                 name: viewModel.detail.value?.claimName ?? summary?.recordName,
                                 hint: alexHint)
            .task {
                if viewModel.detail.value == nil {
                    viewModel.includesCases = serverMeta.supports(.recordCases)
                    viewModel.includesContacts = showsContacts
                    await viewModel.load()
                }
                if isInternal, claimFeed.feed.value == nil {
                    async let staff: Void = actions.load()
                    async let feed: Void = claimFeed.load()
                    async let activity: Void = loadActivity()
                    _ = await (staff, feed, activity)
                }
            }
            .sheet(item: $openAction) { action in
                switch action {
                case .task:
                    NewTaskSheet(api: api, currentUserName: currentUserName, record: .claim(viewModel.claimId)) {
                        Task { await showActivities() }
                    }
                case .event:
                    NewEventSheet(api: api, currentUserName: currentUserName, record: .claim(viewModel.claimId)) {
                        Task { await showActivities() }
                    }
                case .portalUpdate:
                    PortalUpdateComposer(api: api, record: viewModel.record) { await showPostedPortalUpdate() }
                default:
                ClaimActionSheet(action: action, actions: actions, feed: claimFeed, api: api,
                                 referenceId: viewModel.detail.value?.referenceId) {
                    Task {
                        await viewModel.load()
                        if action == .post || action == .email { await claimFeed.load() }
                    }
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
                "Claim not found",
                systemImage: "doc.questionmark",
                description: Text("This claim isn't available on your account. Contact support if you think this is a mistake.")
            )
        case .failed:
            ErrorStateView(subject: "this claim") { Task { await viewModel.load() } }
        case .loaded(let detail, _):
            loaded(detail)
        }
    }

    private var recordName: String {
        viewModel.detail.value?.claimName ?? summary?.recordName ?? "Claim"
    }

    private func loaded(_ detail: ClaimDetail) -> some View {
        ScrollView {
            Group {
                if isWide {
                    // iPad: the hero across the top; the work (actions, stage, tabs) on the left and
                    // reference facts (address, money, people, activity) in a rail on the right.
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header(detail)
                        TwoColumns {
                            quickActions
                            progress(detail)
                            SectionBar(selection: $viewModel.section, hidden: hiddenSections)
                            sectionContent(detail)
                        } rail: {
                            teamCard(detail)
                            staffExtras
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header(detail)
                        quickActions
                        progress(detail)
                        staffExtras
                        SectionBar(selection: $viewModel.section, hidden: hiddenSections)
                        sectionContent(detail)
                        teamCard(detail)
                    }
                }
            }
            .padding(isWide ? Theme.Spacing.xl : Theme.Spacing.l)
        }
        .readsWideLayout($isWide)
        .refreshable {
            await viewModel.load()
            if isInternal {
                async let feed: Void = claimFeed.load()
                async let activity: Void = loadActivity()
                _ = await (feed, activity)
            }
        }
        .environment(\.emailReference, detail.referenceId ?? EmailReference.reference(forRecordId: viewModel.claimId))
        .businessLineCalls(recordId: viewModel.claimId, recordName: recordName)
        // Ask Question is a top-bar icon on claims; there's no Add Comment here.
        .recordActions(record: viewModel.record, recordName: recordName, api: api, placement: .toolbarIcon)
        .documentGeneration(record: viewModel.record, recordName: recordName, api: api,
                            isPresented: $showingESign, isAvailable: $eSignAvailable)
    }

    /// Staff get the website's header card; homeowners keep the progress ring.
    @ViewBuilder
    private func header(_ detail: ClaimDetail) -> some View {
        if isInternal {
            RecordCardHeader(
                isLead: false, chip: detail.claimStatus, name: detail.claimName ?? "Claim",
                facts: [("Claim no.", detail.claimNumber), ("Policy no.", detail.policyNumber)]
                    .compactMap { label, value in PortalFormat.nonEmpty(value).map { (label: label, value: $0) } },
                address: detail.lossAddress,
                onEdit: { openAction = .edit }, editLabel: "Edit Claim", editIdentifier: "claimAction-edit")
        } else {
            ClaimHeader(detail: detail, position: detail.lifecycle)
        }
    }

    /// Staff: the stage track, which only shows where the claim is. Homeowners: the progress card with what's happening.
    @ViewBuilder
    private func progress(_ detail: ClaimDetail) -> some View {
        if isInternal {
            StageTrackCard(stages: ClaimLifecycle.stages, current: { if case .stage(let i) = detail.lifecycle { i } else { nil } }(),
                           fallbackLabel: detail.claimStatus, isLead: false)
        } else {
            LifecycleCard(position: detail.lifecycle, status: detail.claimStatus)
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        if isInternal {
            ClaimQuickActions(onESign: { showingESign = true },
                              hidden: serverMeta.supports(.portalUpdate) ? [] : [.portalUpdate]) { openAction = $0 }
        }
    }

    /// Staff only: Alex chats about this claim. (Tasks, events and emails are in Updates → Activities.)
    @ViewBuilder
    private var staffExtras: some View {
        if isInternal && serverMeta.supports(.assistantHistory) {
            AlexChatsLink(api: api, recordId: viewModel.claimId)
        }
    }

    /// The Updates tab's segments: Activities once the server has them.
    private var updatesFilters: [UpdatesFilter] {
        UpdatesFilter.allCases.filter { $0 != .activities || serverMeta.supports(.claimActivities) }
    }

    /// After a task or event is added: show it in Updates → Activities.
    private func showActivities() async {
        if serverMeta.supports(.claimActivities) {
            viewModel.section = .updates
            updatesFilter = .activities
        }
        await loadActivity()
    }

    /// The Contact Us card shows on the Contacts tab only. A homeowner has no Contacts tab, so for them it stays on the page.
    @ViewBuilder
    private func teamCard(_ detail: ClaimDetail) -> some View {
        if viewModel.section == .contacts || hiddenSections.contains(.contacts) {
            teamCardBody(detail)
        }
    }

    private func teamCardBody(_ detail: ClaimDetail) -> some View {
        TeamCard(
            adjuster: .init(name: detail.adjusterName, phone: detail.adjusterPhone, email: detail.adjusterEmail),
            deskAdjuster: .init(name: detail.deskAdjusterName, phone: nil, email: detail.deskAdjusterEmail),
            accountManager: .init(name: detail.accountManagerName, phone: detail.accountManagerPhone, email: detail.accountManagerEmail),
            adjusterFees: detail.adjusterFees
        )
    }

    /// Contacts are staff-only; Cases and Contacts wait for the server to support them.
    private var showsContacts: Bool { isInternal && serverMeta.supports(.recordContacts) }

    private var hiddenSections: Set<ClaimDetailViewModel.Section> {
        var hidden: Set<ClaimDetailViewModel.Section> = []
        if !viewModel.includesCases { hidden.insert(.cases) }
        if !showsContacts { hidden.insert(.contacts) }
        return hidden
    }

    /// After a Portal Update is posted (from the tab or More): show it in Updates → Portal Updates.
    private func showPostedPortalUpdate() async {
        viewModel.section = .updates
        updatesFilter = .portalUpdates
        await viewModel.loadUpdates()
    }

    /// Emails are included once the server has them.
    private func loadActivity() async {
        guard serverMeta.supports(.claimActivities) else { return }
        activity.includeEmails = serverMeta.supports(.activityEmails)
        await activity.load()
    }

    @ViewBuilder
    private func sectionContent(_ detail: ClaimDetail) -> some View {
        switch viewModel.section {
        case .updates:
            if isInternal {
                // Staff: the claim's Chatter feed (default), its tasks, events and emails, or the
                // published portal updates.
                Picker("Show", selection: $updatesFilter) {
                    ForEach(updatesFilters, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("updatesFilter")
            }
            if isInternal && updatesFilter == .feed {
                // Four posts at a time; the rest scroll inside the section.
                ChatterFeedSection(model: claimFeed, emptyMessage: "No posts on this claim yet. Use Post to start one.", visibleCount: 4)
            } else if isInternal && updatesFilter == .activities {
                RecordActivitySection(model: activity, api: api, noun: "claim",
                                      onTask: { openAction = .task }, onEvent: { openAction = .event })
            } else {
                SectionLoader(state: viewModel.updates, subject: "updates", retry: { await viewModel.loadUpdates() }) { updates in
                    UpdatesList(updates: updates, emptyMessage: "No updates have been published for this claim yet.", visibleCount: 3)
                }
            }
        case .details:
            ClaimDetailsSection(detail: detail, lossReason: summary?.lossReason)
        case .contacts:
            RecordContactsSection(state: viewModel.contacts, noun: "claim") { await viewModel.loadContacts() }
        case .insurance:
            ClaimInsuranceSection(detail: detail)
        case .files:
            FilesSection(record: viewModel.record, state: viewModel.files, api: api) { await viewModel.loadFiles() }
        case .cases:
            RecordCasesSection(state: viewModel.cases, noun: "claim") { await viewModel.loadCases() }
        case .payments:
            // As on the mobile website: collected toward the Total RCV, where the money goes, and the checks over time.
            SectionLoader(state: viewModel.payments, subject: "payments", retry: { await viewModel.loadPayments() }) { payments in
                PaymentsAtAGlance(summary: PaymentsSummary(payments: payments, totalRcv: detail.totalRcv, collected: detail.paymentCollected),
                                  onRecord: isInternal ? { openAction = .payments } : nil)
            }
        }
    }
}

// MARK: - Header, highlights, lifecycle

/// The claim's hero: name, status, numbers and loss date on the brand gradient, with
/// the progress ring. The step-by-step lifecycle stays in the card below.
private struct ClaimHeader: View {
    let detail: ClaimDetail
    let position: ClaimLifecycle.Position
    /// Staff: the pencil at the top right.
    var onEdit: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The ring sits centered on the right; it moves under the text at large sizes, so nothing is squeezed.
        AdaptiveStack(horizontalAlignment: .center, verticalAlignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let status = PortalFormat.nonEmpty(detail.claimStatus) {
                    Text(status.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail.claimName ?? "Claim")
                    .font(.heroTitle)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                // One fact per line, so numbers never split.
                VStack(alignment: .leading, spacing: 2) {
                    if let number = PortalFormat.nonEmpty(detail.claimNumber) {
                        Text("Claim \(number)")
                    }
                    if let policy = PortalFormat.nonEmpty(detail.policyNumber) {
                        Text("Policy \(policy)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                HeaderAddressLink(address: detail.lossAddress)
            }
            AdaptiveSpacer()
            if let percent = position.percentComplete, case .stage(let index) = position {
                HeroProgress(percent: percent, stage: index + 1, of: ClaimLifecycle.stages.count)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandGradient.hero(colorScheme), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let onEdit {
                HeaderEditButton(label: "Edit Claim", identifier: "claimAction-edit", action: onEdit)
                    .padding(Theme.Spacing.xs)
            }
        }
    }
}

/// ⓘ tip for RCV (spec §9).
struct RCVHelpButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle").iconShadow()
                .font(.caption)
                .frame(minWidth: 28, minHeight: 28)
        }
        .accessibilityLabel("What is RCV?")
        .popover(isPresented: $showing) {
            Text("Replacement Cost Value: the full cost to repair or replace damaged property.")
                .font(.subheadline)
                .padding()
                .frame(idealWidth: 260)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Claim progress. Collapsible: the current status and its guide stay visible when collapsed.
private struct LifecycleCard: View {
    let position: ClaimLifecycle.Position
    let status: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.l) {
                    // The ring goes above the status at large text, so the status isn't squeezed.
                    // The ring is in the hero above; this card is the step-by-step view.
                    AdaptiveStack(spacing: Theme.Spacing.l) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Claim progress")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(PortalFormat.nonEmpty(status) ?? "Status not set")
                                .font(.sectionTitle)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("claimStatusProminent")
                        }
                    }
                    Spacer(minLength: 0)
                    if case .stage = position {
                        Image(systemName: "chevron.down").iconShadow()
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandPrimary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled({ if case .stage = position { false } else { true } }())
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the stages" : "Shows every stage")
            .accessibilityIdentifier("claimProgressToggle")

            if let guide = ClaimLifecycle.guide(for: status) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    guideRow("What's happening", guide.now, icon: "hourglass")
                    guideRow("What's next", guide.next, icon: "arrow.forward.circle")
                }
                .accessibilityIdentifier("stageGuide")
            }

            if expanded, case .stage = position {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ClaimLifecycle.stages.enumerated()), id: \.offset) { index, stage in
                        StepRow(title: stage, state: position.state(ofStageAt: index), isLast: index == ClaimLifecycle.stages.count - 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    private func guideRow(_ title: String, _ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: icon).iconShadow()
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The % ring, for the claim and lead heroes.
struct HeroProgress: View {
    let percent: Int
    let stage: Int
    let of: Int

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            ProgressRing(percent: percent, onBrand: true)
        }
        // A fixed column, so the ring and caption share one center line.
        .frame(minWidth: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent complete, stage \(stage) of \(of)")
    }
}

struct ProgressRing: View {
    let percent: Int
    /// White, for the brand gradient (the claim hero).
    var onBrand = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(onBrand ? Color.white.opacity(0.25) : Color.border, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(onBrand ? Color.white : (percent == 100 ? Color.success : Color.brandPrimary),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.subheadline.bold())
                .foregroundStyle(onBrand ? Color.white : Color.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(6)
        }
        .frame(width: 64, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent complete")
    }
}

struct StepRow: View {
    let title: String
    let state: StepState
    let isLast: Bool
    var detail: String?
    var currentTint: Color = .brandPrimary

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                marker
                if !isLast {
                    Rectangle()
                        .fill(state == .complete ? Color.brandPrimary : Color.border)
                        .frame(width: 2, height: 18)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(state == .current ? .subheadline.bold() : .subheadline)
                    .foregroundStyle(state == .upcoming ? Color.textSecondary : Color.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateLabel)
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill").iconShadow()
                .foregroundStyle(Color.brandPrimary)
        case .current:
            Image(systemName: "circle.inset.filled").iconShadow()
                .foregroundStyle(currentTint)
        case .upcoming:
            // Non-text contrast: at least 3:1 against the card.
            Image(systemName: "circle").iconShadow()
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var stateLabel: String {
        switch state {
        case .complete: "Complete"
        case .current: "Current stage"
        case .upcoming: "Upcoming"
        }
    }
}

/// Section chooser. Chips instead of a segmented control so 5 labels fit at large text sizes.
struct SectionBar<Section: RawRepresentable & CaseIterable & Hashable>: View where Section.RawValue == String, Section.AllCases: RandomAccessCollection {
    @Binding var selection: Section
    /// Tabs the server doesn't support yet.
    var hidden: Set<Section> = []
    @Environment(\.isLeadRecord) private var isLead

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Section.allCases.filter { !hidden.contains($0) }, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.m)
                            .frame(minHeight: Theme.minTapTarget)
                            .foregroundStyle(selection == section ? Color.surface : Color.textPrimary)
                            .background(
                                selection == section ? Color.recordAccent(isLead: isLead) : Color.surface,
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(Color.border, lineWidth: selection == section ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
        }
    }
}

/// Loading, error and content for one section of a detail screen.
struct SectionLoader<Value: Sendable, Content: View>: View {
    let state: LoadState<Value>
    let subject: String
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            SkeletonList(rows: 2)
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Unable to load \(subject). Pull to refresh or contact support.")
                    .foregroundStyle(Color.textSecondary)
                Button("Retry") { Task { await retry() } }
                    .frame(minHeight: Theme.minTapTarget)
            }
            .cardStyle()
        case .loaded(let value, _):
            content(value)
        }
    }
}
