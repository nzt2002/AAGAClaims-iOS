import PortalKit
import SwiftUI

/// A lead to open, from the list or after Submit a Lead.
struct LeadRoute: Hashable {
    let id: String
    let name: String?
}

/// Leads list (spec §6.6).
struct LeadsListView: View {
    @Bindable var viewModel: LeadsListViewModel
    @Binding var path: NavigationPath
    @Binding var showingSubmit: Bool
    let api: PortalAPI
    let userEmail: String
    let openSupport: () -> Void
    /// Staff see "Mine" (leads where they're the adjuster or account manager).
    var showsMine = false

    @Environment(\.isOffline) private var isOffline

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
                            message: "Leads you refer to us will appear here. Tap Submit a Lead to send one.",
                            openSupport: openSupport
                        )
                    } else {
                        chips
                        if viewModel.filteredLeads.isEmpty {
                            ContentUnavailableView.search(text: viewModel.searchText)
                        }
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.filteredLeads) { lead in
                                NavigationLink(value: LeadRoute(id: lead.recordId, name: lead.recordName)) {
                                    LeadCard(lead: lead)
                                        .recordZoomSource(lead.recordId)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("leadCard-\(lead.recordId)")
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
        .searchable(text: $viewModel.searchText, prompt: "Search leads")
        .onChange(of: viewModel.filterState) { _, state in
            if !UserDefaults.standard.bool(forKey: "UITestDemo") { ListFilterMemory.save(state, for: "leads") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SortMenu(order: $viewModel.sortOrder)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSubmit = true
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                }
                .accessibilityLabel("Submit a Lead")
                .disabledWhenOffline(isOffline)
                .accessibilityIdentifier("submitLead")
            }
        }
        // LeadRoute is in RecordDestinations.
        .sheet(isPresented: $showingSubmit) {
            SubmitLeadView(api: api, userEmail: userEmail) { newLeadId, name in
                showingSubmit = false
                Task { await viewModel.load() }
                path.append(LeadRoute(id: newLeadId, name: name))
            }
        }
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
            MenuChip(title: "Status", value: viewModel.statusFilter) {
                Picker("Status", selection: $viewModel.statusFilter) {
                    Text("All statuses").tag(String?.none)
                    ForEach(viewModel.statusOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .accessibilityIdentifier("filterChip-status")
            MenuChip(title: "Peril", value: viewModel.perilFilter) {
                Picker("Peril", selection: $viewModel.perilFilter) {
                    Text("All perils").tag(String?.none)
                    ForEach(viewModel.perilOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .accessibilityIdentifier("filterChip-peril")
            MenuChip(title: "Agreement", value: viewModel.agreementFilter == .any ? nil : viewModel.agreementFilter.rawValue) {
                Picker("Agreement", selection: $viewModel.agreementFilter) {
                    ForEach(LeadsListViewModel.AgreementFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            .accessibilityIdentifier("filterChip-agreement")
            if viewModel.hasActiveFilters {
                ClearChip { viewModel.clearFilters() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("leadFilters")
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct LeadCard: View {
    let lead: LeadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.recordName ?? "Lead")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.textPrimary)
                    if let number = PortalFormat.nonEmpty(lead.claimNumber) {
                        Text(number)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                AdaptiveSpacer()
                if let status = PortalFormat.nonEmpty(lead.prospectStatus) {
                    StatusPill(text: status, tone: StatusPill.tone(forLeadStatus: status))
                }
            }

            InfoRow(label: "Loss address", value: lead.lossAddress, systemImage: "mappin.and.ellipse")
            InfoRow(label: "Peril", value: lead.peril, systemImage: "cloud.bolt")

            Divider()

            agreement

            AdaptiveStack(verticalAlignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Account manager: \(PortalFormat.nonEmpty(lead.accountManagerName) ?? "—")")
                AdaptiveSpacer()
                Text("Updated \(PortalFormat.date(lead.lastModifiedDate))")
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens lead details")
    }

    @ViewBuilder
    private var agreement: some View {
        if let sent = lead.agreementSentDate {
            AdaptiveStack(spacing: Theme.Spacing.l) {
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
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        LeadsListView(viewModel: PreviewData.loadedLeads(), path: $path, showingSubmit: .constant(false), api: PreviewData.api(),
                      userEmail: "taylor@example.com", openSupport: {})
    }
}
