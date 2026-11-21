import PortalKit
import SwiftUI

/// Where a job is on its board, as a pill: finished jobs are green, the rest blue.
extension JobSummary {
    var stageTone: StatusPill.Tone { isComplete ? .success : .active }
}

/// Jobs list, for a company on jobs alone (the Contractor add-on without Claims). It takes the place of the Claims list.
struct JobsListView: View {
    @Bindable var viewModel: JobsListViewModel
    let api: PortalAPI
    let openSupport: () -> Void

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "jobs", retry: reload) { _ in
            ScrollView {
                if viewModel.jobs.isEmpty {
                    EmptyRecordsView(title: "No jobs yet", message: "When a job is started for you, it will appear here.", openSupport: openSupport)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        chips
                        if viewModel.filteredJobs.isEmpty {
                            if viewModel.searchText.isEmpty {
                                ContentUnavailableView("No jobs match", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try clearing the filters."))
                            } else {
                                ContentUnavailableView.search(text: viewModel.searchText)
                            }
                        }
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.filteredJobs) { job in
                                NavigationLink(value: JobRoute(id: job.id, name: job.name)) { JobCard(job: job) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("jobCard-\(job.id)")
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search jobs")
        .task { if viewModel.state.value == nil { await viewModel.load() } }
    }

    private var chips: some View {
        ChipBar {
            FilterChip(title: "Open", isActive: viewModel.openOnly) { viewModel.openOnly.toggle() }
                .accessibilityIdentifier("filterChip-open")
            MenuChip(title: "Stage", value: viewModel.stageFilter) {
                Picker("Stage", selection: $viewModel.stageFilter) {
                    Text("All stages").tag(String?.none)
                    ForEach(viewModel.stageOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .accessibilityIdentifier("filterChip-stage")
            if viewModel.hasActiveFilters && !(viewModel.openOnly && viewModel.stageFilter == nil) {
                ClearChip { viewModel.clearFilters() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jobFilters")
    }

    private func reload() { Task { await viewModel.load() } }
}

/// A job in the list: name and number, stage, address, customer and how far along the board it is.
struct JobCard: View {
    let job: JobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name).font(.headline).fixedSize(horizontal: false, vertical: true).foregroundStyle(Color.textPrimary)
                    if let number = PortalFormat.nonEmpty(job.number) {
                        Text(number).font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                AdaptiveSpacer()
                StatusPill(text: job.isComplete ? "Complete" : job.stage, tone: job.stageTone)
            }
            InfoRow(label: "Job site", value: job.address, systemImage: "mappin.and.ellipse")
            InfoRow(label: "Customer", value: job.customerName, systemImage: "person")
            InfoRow(label: "Trade", value: job.trade, systemImage: "hammer")
            ProgressBar(percent: job.isComplete ? 100 : Int((job.progress * 100).rounded()))
            if let amount = job.contractAmount {
                Divider()
                HStack {
                    Text("Contract").font(.caption).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(PortalFormat.currency(amount)).font(.subheadline.weight(.semibold))
                }
            }
            Text("Updated \(PortalFormat.date(job.updatedDate))").font(.caption).foregroundStyle(Color.textSecondary)
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens job details")
    }
}

/// A job to open, from the list, Home or search.
struct JobRoute: Hashable {
    let id: String
    let name: String?
}
