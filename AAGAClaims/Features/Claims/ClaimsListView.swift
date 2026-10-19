import PortalKit
import SwiftUI

/// Claims list (spec §6.4).
struct ClaimsListView: View {
    @Bindable var viewModel: ClaimsListViewModel
    let api: PortalAPI
    let openSupport: () -> Void

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
                        if viewModel.hasActiveFilters {
                            activeFilters
                        }
                        if viewModel.filteredClaims.isEmpty {
                            ContentUnavailableView.search(text: viewModel.searchText)
                        }
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.filteredClaims) { claim in
                                NavigationLink(value: claim) {
                                    ClaimCard(claim: claim)
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
                filterMenu
            }
        }
        .navigationDestination(for: ClaimSummary.self) { claim in
            ClaimDetailView(claimId: claim.recordId, summary: claim, api: api)
                .id(claim.recordId)
        }
        // ClaimRoute (opened from Home, search, an update…) is in RecordDestinations.
        .task {
            if viewModel.state.value == nil {
                await viewModel.load()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $viewModel.statusFilter) {
                Text("All statuses").tag(String?.none)
                ForEach(viewModel.statusOptions, id: \.self) { status in
                    Text(status).tag(String?.some(status))
                }
            }
            .pickerStyle(.menu)

            Picker("Payment Collected", selection: $viewModel.paymentFilter) {
                ForEach(ClaimsListViewModel.PaymentFilter.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)

            Picker("Peril", selection: $viewModel.perilFilter) {
                Text("All perils").tag(String?.none)
                ForEach(viewModel.perilOptions, id: \.self) { peril in
                    Text(peril).tag(String?.some(peril))
                }
            }
            .pickerStyle(.menu)

            if viewModel.hasActiveFilters {
                Button("Clear filters", role: .destructive) { viewModel.clearFilters() }
            }
        } label: {
            Image(systemName: viewModel.hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
        }
        .accessibilityLabel(viewModel.hasActiveFilters ? "Filters, active" : "Filters")
        .accessibilityIdentifier("claimFilters")
    }

    private var activeFilters: some View {
        HStack {
            Text(activeFilterSummary)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer()
            Button("Clear filters") { viewModel.clearFilters() }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: Theme.minTapTarget)
        }
    }

    private var activeFilterSummary: String {
        var parts: [String] = []
        if viewModel.openOnly { parts.append("Open claims") }
        if let status = viewModel.statusFilter { parts.append(status) }
        if viewModel.paymentFilter != .any { parts.append(viewModel.paymentFilter.rawValue) }
        if let peril = viewModel.perilFilter { parts.append(peril) }
        return "Showing: " + parts.joined(separator: " · ")
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
