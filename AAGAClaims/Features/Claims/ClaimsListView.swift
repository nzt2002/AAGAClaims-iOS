import PortalKit
import SwiftUI

/// Claims list (spec §6.4). Search, filters and claim detail come in milestone 2.
struct ClaimsListView: View {
    let viewModel: ClaimsListViewModel
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
                    LazyVStack(spacing: Theme.Spacing.m) {
                        ForEach(viewModel.claims) { claim in
                            ClaimCard(claim: claim)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("My Claims")
        .task {
            if viewModel.state.value == nil {
                await viewModel.load()
            }
        }
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct ClaimCard: View {
    let claim: ClaimSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(claim.recordName ?? "Claim")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    if let number = PortalFormat.nonEmpty(claim.claimNumber) {
                        Text(number)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments collected")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.currency(claim.paymentCollected))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
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
        .accessibilityElement(children: .contain)
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
        ClaimsListView(viewModel: PreviewData.loadedClaims(), openSupport: {})
    }
}

#Preview("No claims") {
    NavigationStack {
        ClaimsListView(viewModel: ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty)), openSupport: {})
    }
}

#Preview("Error") {
    NavigationStack {
        ClaimsListView(
            viewModel: ClaimsListViewModel(api: MockPortalAPI(fixtures: .empty, failure: .server(status: 500))),
            openSupport: {}
        )
    }
}
