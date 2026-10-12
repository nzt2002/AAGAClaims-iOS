import PortalKit
import SwiftUI

/// Leads list (spec §6.6). Filters, lead detail and Submit a Lead come in milestone 3.
struct LeadsListView: View {
    let viewModel: LeadsListViewModel
    let openSupport: () -> Void

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "leads", retry: reload) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Leads connected to your email address.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    if viewModel.leads.isEmpty {
                        EmptyRecordsView(
                            title: "No leads yet",
                            message: "Leads you refer to us will appear here.",
                            openSupport: openSupport
                        )
                    } else {
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.leads) { lead in
                                LeadCard(lead: lead)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("My Leads")
        .navigationBarTitleDisplayMode(.inline)
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

struct LeadCard: View {
    let lead: LeadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(lead.recordName ?? "Lead")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let status = PortalFormat.nonEmpty(lead.prospectStatus) {
                    StatusPill(text: status, tone: StatusPill.tone(forLeadStatus: status))
                }
            }

            InfoRow(label: "Loss address", value: lead.lossAddress, systemImage: "mappin.and.ellipse")
            InfoRow(label: "Peril", value: lead.peril, systemImage: "cloud.bolt")

            Divider()

            agreement

            HStack {
                Text("Account manager: \(PortalFormat.nonEmpty(lead.accountManagerName) ?? "—")")
                Spacer()
                Text("Updated \(PortalFormat.date(lead.lastModifiedDate))")
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var agreement: some View {
        if let sent = lead.agreementSentDate {
            HStack(spacing: Theme.Spacing.l) {
                Label("Sent \(PortalFormat.date(sent))", systemImage: "paperplane")
                if let signed = lead.agreementCompletedDate {
                    Label("Signed \(PortalFormat.date(signed))", systemImage: "signature")
                        .foregroundStyle(Color.success)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
        } else {
            Text("Visible once an agreement has been sent.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview("Leads") {
    NavigationStack {
        LeadsListView(viewModel: PreviewData.loadedLeads(), openSupport: {})
    }
}
