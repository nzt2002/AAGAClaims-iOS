import Charts
import PortalKit
import SwiftUI

/// Claim detail (spec §6.5).
struct ClaimDetailView: View {
    @State private var viewModel: ClaimDetailViewModel
    /// Staff only: quick actions, communication and the Claim Feed.
    @State private var actions: ClaimActionsViewModel
    @State private var claimFeed: ChatterFeedViewModel
    @State private var activity: RecordActivityViewModel
    @State private var openAction: ClaimAction?
    @State private var showingESign = false
    @State private var eSignAvailable = false
    @State private var updatesFilter: UpdatesFilter = .claimFeed
    @Environment(\.isInternalUser) private var isInternal
    @Environment(\.isOffline) private var isOffline
    @Environment(\.currentUserName) private var currentUserName
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.serverMeta) private var serverMeta

    enum UpdatesFilter: String, CaseIterable {
        case claimFeed = "Claim Feed"
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

    var body: some View {
        content
            .background(Color.appBackground)
            // The header shows the name; repeating it in the bar wastes space.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.detail.value == nil {
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
                        Task { await loadActivity() }
                    }
                case .event:
                    NewEventSheet(api: api, currentUserName: currentUserName, record: .claim(viewModel.claimId)) {
                        Task { await loadActivity() }
                    }
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
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ClaimHeader(detail: detail, position: detail.lifecycle)
                if isInternal {
                    ClaimQuickActions(onESign: { showingESign = true }) { openAction = $0 }
                }
                PaymentsCard(detail: detail, payments: viewModel.payments.value ?? [])
                LifecycleCard(position: detail.lifecycle, status: detail.claimStatus)
                if isInternal {
                    if serverMeta.supports(.claimActivities) {
                        RecordActivitySection(model: activity, api: api, noun: "claim")
                    }
                }
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
                async let feed: Void = claimFeed.load()
                async let activity: Void = loadActivity()
                _ = await (feed, activity)
            }
        }
        .toolbar {
            if isInternal {
                ToolbarItem(placement: .topBarTrailing) {
                    // A text label, as on leads.
                    Button("Edit") { openAction = .edit }
                        .disabledWhenOffline(isOffline)
                        .accessibilityLabel("Edit Claim")
                        .accessibilityIdentifier("claimAction-edit")
                }
            }
        }
        // Ask Question is a top-bar icon on claims; there's no Add Comment here.
        .recordActions(record: viewModel.record, recordName: recordName, api: api, placement: .toolbarIcon)
        .documentGeneration(record: viewModel.record, recordName: recordName, api: api,
                            isPresented: $showingESign, isAvailable: $eSignAvailable)
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
                // Staff: the claim's Chatter feed (default) or the published portal updates.
                Picker("Show", selection: $updatesFilter) {
                    ForEach(UpdatesFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("updatesFilter")
            }
            if isInternal && updatesFilter == .claimFeed {
                ChatterFeedSection(model: claimFeed, emptyMessage: "No posts on this claim yet. Use Post to start one.", visibleCount: 3)
            } else {
                SectionLoader(state: viewModel.updates, subject: "updates", retry: { await viewModel.loadUpdates() }) { updates in
                    UpdatesList(updates: updates, emptyMessage: "No updates have been published for this claim yet.", visibleCount: 3)
                }
            }
        case .details:
            ClaimDetailsSection(detail: detail, lossReason: summary?.lossReason)
        case .insurance:
            ClaimInsuranceSection(detail: detail)
        case .files:
            FilesSection(record: viewModel.record, state: viewModel.files, api: api) { await viewModel.loadFiles() }
        case .payments:
            SectionLoader(state: viewModel.payments, subject: "payments", retry: { await viewModel.loadPayments() }) { payments in
                PaymentsList(payments: payments, totalCollected: detail.paymentCollected, totalRcv: detail.totalRcv)
            }
        }
    }
}

// MARK: - Header, highlights, lifecycle

/// The claim's hero: name, status, address, numbers and loss date on the brand gradient, with
/// the progress ring. The step-by-step lifecycle stays in the card below.
private struct ClaimHeader: View {
    let detail: ClaimDetail
    let position: ClaimLifecycle.Position
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The ring moves under the text at large sizes, so nothing is squeezed.
        AdaptiveStack(horizontalAlignment: .top, verticalAlignment: .leading, spacing: Theme.Spacing.l) {
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
                if let address = PortalFormat.nonEmpty(detail.lossAddress) {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Loss address: \(address)")
                        .accessibilityIdentifier("headerLossAddress")
                }
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
            AdaptiveSpacer()
            if let percent = position.percentComplete, case .stage(let index) = position {
                VStack(spacing: Theme.Spacing.xs) {
                    ProgressRing(percent: percent, onBrand: true)
                    Text("Stage \(index + 1) of \(ClaimLifecycle.stages.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandGradient.hero(colorScheme), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Payments at a glance: collected against the claim's total (RCV) as a bar, the key amounts,
/// and the payments over time once there are two or more.
private struct PaymentsCard: View {
    let detail: ClaimDetail
    let payments: [Payment]

    private var collected: Double { (detail.paymentCollected as NSDecimalNumber?)?.doubleValue ?? 0 }
    private var total: Double { (detail.totalRcv as NSDecimalNumber?)?.doubleValue ?? 0 }
    private var deductible: Double { (detail.deductible as NSDecimalNumber?)?.doubleValue ?? 0 }

    /// Running total by notice date.
    private var timeline: [(date: Date, amount: Double)] {
        var running = 0.0
        return payments
            .compactMap { payment -> (Date, Double)? in
                guard let day = payment.dateOfNotice, let date = Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else { return nil }
                return (date, (payment.netDeposit as NSDecimalNumber?)?.doubleValue ?? 0)
            }
            .sorted { $0.0 < $1.0 }
            .map { running += $0.1; return (date: $0.0, amount: running) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Payments")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if total > 0 {
                    Text("\(Int((min(collected / total, 1) * 100).rounded()))% collected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .contentTransition(.numericText())
                }
            }
            if total > 0 {
                Chart {
                    BarMark(xStart: .value("Start", 0), xEnd: .value("Collected", min(collected, total)), y: .value("Claim", "RCV"))
                        .foregroundStyle(Color.brandPrimary)
                    BarMark(xStart: .value("Collected", min(collected, total)), xEnd: .value("Total", total), y: .value("Claim", "RCV"))
                        .foregroundStyle(Color.surfaceTintedStrong)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(domain: 0...total)
                .frame(height: 28)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }
            AdaptiveStack(horizontalAlignment: .top, spacing: Theme.Spacing.l) {
                figure("Collected", PortalFormat.currency(detail.paymentCollected))
                figure("Total RCV", PortalFormat.currency(detail.totalRcv), help: true)
                if deductible > 0 {
                    figure("Deductible", PortalFormat.currency(detail.deductible))
                }
            }
            if timeline.count >= 2 {
                Chart(timeline, id: \.date) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Collected", point.amount))
                        .foregroundStyle(LinearGradient(colors: [Color.brandPrimary.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.stepEnd)
                    LineMark(x: .value("Date", point.date), y: .value("Collected", point.amount))
                        .foregroundStyle(Color.brandPrimary)
                        .interpolationMethod(.stepEnd)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 70)
                .accessibilityLabel("Payments over time")
                .accessibilityValue("\(timeline.count) payments, \(PortalFormat.currency(detail.paymentCollected)) in total")
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paymentsChart")
    }

    private func figure(_ title: String, _ value: String, help: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Same height with or without the ⓘ button, so the amounts line up.
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.metaLabel)
                    .foregroundStyle(Color.textSecondary)
                if help { RCVHelpButton() }
            }
            .frame(minHeight: 28, alignment: .leading)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// ⓘ tip for RCV (spec §9).
struct RCVHelpButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
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
            Image(systemName: icon)
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandPrimary)
        case .current:
            Image(systemName: "circle.inset.filled")
                .foregroundStyle(currentTint)
        case .upcoming:
            // Non-text contrast: at least 3:1 against the card.
            Image(systemName: "circle")
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Section.allCases, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.m)
                            .frame(minHeight: Theme.minTapTarget)
                            .foregroundStyle(selection == section ? Color.surface : Color.textPrimary)
                            .background(
                                selection == section ? Color.brandPrimary : Color.surface,
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
