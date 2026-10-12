import PortalKit
import SwiftUI

/// Claim detail (spec §6.5).
struct ClaimDetailView: View {
    @State private var viewModel: ClaimDetailViewModel
    /// The list row, for fields only `GET /claims` returns (loss reason).
    let summary: ClaimSummary?
    let api: PortalAPI

    init(claimId: String, summary: ClaimSummary?, api: PortalAPI) {
        _viewModel = State(initialValue: ClaimDetailViewModel(claimId: claimId, api: api))
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
                ClaimHeader(detail: detail)
                HighlightsRow(detail: detail)
                LifecycleCard(position: detail.lifecycle, status: detail.claimStatus)
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
        .refreshable { await viewModel.load() }
        .recordActions(record: viewModel.record, recordName: recordName, api: api)
    }

    @ViewBuilder
    private func sectionContent(_ detail: ClaimDetail) -> some View {
        switch viewModel.section {
        case .updates:
            SectionLoader(state: viewModel.updates, subject: "updates", retry: { await viewModel.loadUpdates() }) { updates in
                UpdatesList(updates: updates, emptyMessage: "No updates have been published for this claim yet.")
            }
        case .details:
            ClaimDetailsSection(detail: detail, lossReason: summary?.lossReason)
        case .insurance:
            ClaimInsuranceSection(detail: detail)
        case .files:
            SectionLoader(state: viewModel.files, subject: "files", retry: { await viewModel.loadFiles() }) { files in
                FilesList(files: files)
            }
        case .payments:
            SectionLoader(state: viewModel.payments, subject: "payments", retry: { await viewModel.loadPayments() }) { payments in
                PaymentsList(payments: payments, totalCollected: detail.paymentCollected)
            }
        }
    }
}

// MARK: - Header, highlights, lifecycle

private struct ClaimHeader: View {
    let detail: ClaimDetail

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.claimName ?? "Claim")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let status = PortalFormat.nonEmpty(detail.claimStatus) {
                    StatusPill(text: status, tone: StatusPill.tone(forClaimStatus: status))
                }
            }
            HStack(spacing: Theme.Spacing.l) {
                if let number = PortalFormat.nonEmpty(detail.claimNumber) {
                    Text("Claim \(number)")
                }
                if let policy = PortalFormat.nonEmpty(detail.policyNumber) {
                    Text("Policy \(policy)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HighlightsRow: View {
    let detail: ClaimDetail

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.m) {
                tile("Loss Date", PortalFormat.date(detail.lossDate))
                tile("Total RCV", PortalFormat.currency(detail.totalRcv), help: true)
                tile("Payments Collected", PortalFormat.currency(detail.paymentCollected))
                tile("Deductible", PortalFormat.currency(detail.deductible))
            }
        }
    }

    private func tile(_ title: String, _ value: String, help: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if help {
                    RCVHelpButton()
                }
            }
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(Theme.Spacing.m)
        .frame(minWidth: 140, alignment: .leading)
        .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 1))
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

private struct LifecycleCard: View {
    let position: ClaimLifecycle.Position
    let status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.l) {
                if let percent = position.percentComplete {
                    ProgressRing(percent: percent)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Claim progress")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.nonEmpty(status) ?? "Status not set")
                        .font(.headline)
                }
            }

            if case .stage = position {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ClaimLifecycle.stages.enumerated()), id: \.offset) { index, stage in
                        StepRow(title: stage, state: position.state(ofStageAt: index), isLast: index == ClaimLifecycle.stages.count - 1)
                    }
                }
            }
        }
        .cardStyle()
    }
}

struct ProgressRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.border, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(percent == 100 ? Color.success : Color.brandPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.subheadline.bold())
                .monospacedDigit()
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
            Image(systemName: "circle")
                .foregroundStyle(Color.border)
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
