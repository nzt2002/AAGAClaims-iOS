import PortalKit
import SwiftUI

/// Claims list (spec §6.4).
struct ClaimsListView: View {
    @Bindable var viewModel: ClaimsListViewModel
    let api: PortalAPI
    let openSupport: () -> Void
    /// Staff see "Mine" (claims where they're the adjuster or account manager).
    var showsMine = false

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "claims", retry: reload) { _ in
            ScrollView {
                if viewModel.claims.isEmpty {
                    EmptyRecordsView(
                        title: "No claims yet",
                        message: "When we open a claim for you, it will appear here.",
                        openSupport: openSupport
                    )
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        chips
                        if viewModel.filteredClaims.isEmpty {
                            ContentUnavailableView.search(text: viewModel.searchText)
                        }
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.filteredClaims) { claim in
                                NavigationLink(value: claim) {
                                    ClaimCard(claim: claim)
                                        .recordZoomSource(claim.recordId)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("claimCard-\(claim.recordId)")
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("My Claims")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search claims")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SortMenu(order: $viewModel.sortOrder)
            }
        }
        .navigationDestination(for: ClaimSummary.self) { claim in
            ClaimDetailView(claimId: claim.recordId, summary: claim, api: api)
                .recordZoomDestination(claim.recordId)
                .id(claim.recordId)
        }
        .onChange(of: viewModel.filterState) { _, state in
            if !UserDefaults.standard.bool(forKey: "UITestDemo") { ListFilterMemory.save(state, for: "claims") }
        }
        // ClaimRoute (opened from Home, search, an update…) is in RecordDestinations.
        .task {
            if viewModel.state.value == nil {
                await viewModel.load()
            }
        }
    }

    private var chips: some View {
        ChipBar {
            FilterChip(title: "Open", isActive: viewModel.openOnly) { viewModel.openOnly.toggle() }
                .accessibilityIdentifier("filterChip-open")
            if showsMine {
                FilterChip(title: "Mine", systemImage: "person.fill", isActive: viewModel.mineOnly) {
                    viewModel.mineOnly.toggle()
                }
                .accessibilityIdentifier("filterChip-mine")
            }
            MenuChip(title: "Stage", value: viewModel.statusFilter) {
                Picker("Stage", selection: $viewModel.statusFilter) {
                    Text("All stages").tag(String?.none)
                    ForEach(viewModel.statusOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .accessibilityIdentifier("filterChip-stage")
            MenuChip(title: "Peril", value: viewModel.perilFilter) {
                Picker("Peril", selection: $viewModel.perilFilter) {
                    Text("All perils").tag(String?.none)
                    ForEach(viewModel.perilOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .accessibilityIdentifier("filterChip-peril")
            MenuChip(title: "Payments", value: viewModel.paymentFilter == .any ? nil : viewModel.paymentFilter.rawValue) {
                Picker("Payments", selection: $viewModel.paymentFilter) {
                    ForEach(ClaimsListViewModel.PaymentFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            .accessibilityIdentifier("filterChip-payments")
            if viewModel.hasActiveFilters {
                ClearChip { viewModel.clearFilters() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claimFilters")
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct ClaimCard: View {
    let claim: ClaimSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(claim.recordName ?? "Claim")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.textPrimary)
                    if let number = PortalFormat.nonEmpty(claim.claimNumber) {
                        Text(number)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                AdaptiveSpacer()
                if let status = PortalFormat.nonEmpty(claim.claimStatus) {
                    StatusPill(text: status, tone: StatusPill.tone(forClaimStatus: status))
                }
            }

            InfoRow(label: "Loss address", value: claim.lossAddress, systemImage: "mappin.and.ellipse")
            InfoRow(label: "Peril", value: claim.peril, systemImage: "cloud.bolt")

            if let percent = claim.lifecycle.percentComplete {
                ProgressBar(percent: percent)
            }

            Divider()

            AdaptiveStack(horizontalAlignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments collected")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.currency(claim.paymentCollected))
                        .font(.subheadline.weight(.semibold))
                }
                AdaptiveSpacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account manager")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.nonEmpty(claim.accountManagerName) ?? "—")
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)

            Text("Updated \(PortalFormat.date(claim.lastModifiedDate))")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens claim details")
    }
}

struct EmptyRecordsView: View {
    let title: String
    let message: String
    let openSupport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            Text(message)
        } actions: {
            Button("Contact support", action: openSupport)
                .frame(minHeight: Theme.minTapTarget)
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

#Preview("Claims") {
    NavigationStack {
        ClaimsListView(viewModel: PreviewData.loadedClaims(), api: PreviewData.api(), openSupport: {})
    }
}

#Preview("No claims") {
    NavigationStack {
        ClaimsListView(viewModel: ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty)), api: PreviewData.api(), openSupport: {})
    }
}

#Preview("Error") {
    NavigationStack {
        ClaimsListView(
            viewModel: ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty, failure: .server(status: 500))),
            api: PreviewData.api(),
            openSupport: {}
        )
    }
}

#Preview("Claim detail") {
    NavigationStack {
        ClaimDetailView(claimId: "a23000000000001AAA", summary: nil, api: PreviewData.api())
    }
}
