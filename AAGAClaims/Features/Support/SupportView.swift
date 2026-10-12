import PortalKit
import SwiftUI

struct CaseRoute: Hashable {
    let id: String
}

/// A claim or lead opened from a support case.
struct RelatedRecordRoute: Hashable {
    let record: RecordRef
    let name: String?
}

/// Support cases (spec §6.9).
struct SupportView: View {
    @Bindable var viewModel: CasesListViewModel
    @Binding var path: NavigationPath
    @Binding var showingRequest: Bool
    let api: PortalAPI

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your support cases", retry: reload) { _ in
            List {
                Section {
                    Text("Use Request Assistance when you have a question about a claim or lead, such as a status update, a document request, or a follow-up on an inspection or estimate.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(CasesListViewModel.Filter.allCases, id: \.self) { filter in
                            Text("\(filter.rawValue) (\(viewModel.count(for: filter)))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowSeparator(.hidden)

                if viewModel.cases.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.cases) { supportCase in
                        NavigationLink(value: CaseRoute(id: supportCase.caseId)) {
                            CaseRow(supportCase: supportCase)
                        }
                        .accessibilityIdentifier("caseRow-\(supportCase.caseId)")
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Subject, case number, claim or lead")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRequest = true
                } label: {
                    Label("Request Assistance", systemImage: "plus.bubble")
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                }
                .accessibilityIdentifier("supportRequestAssistance")
            }
        }
        .navigationDestination(for: CaseRoute.self) { route in
            CaseDetailView(caseId: route.id, api: api)
        }
        .navigationDestination(for: RelatedRecordRoute.self) { route in
            switch route.record {
            case .claim(let id): ClaimDetailView(claimId: id, summary: nil, api: api)
            case .lead(let id): LeadDetailView(leadId: id, fallbackName: route.name, api: api)
            }
        }
        .sheet(isPresented: $showingRequest) {
            RequestAssistanceSheet(api: api) { caseId in
                showingRequest = false
                viewModel.filter = .open
                Task { await viewModel.load() }
                path.append(CaseRoute(id: caseId))
            }
        }
        .task {
            if viewModel.state.value == nil {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !viewModel.searchText.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            ContentUnavailableView(
                viewModel.filter == .closed ? "No closed cases" : "No open cases",
                systemImage: "questionmark.bubble",
                description: Text("Need help with a claim or lead? Tap Request Assistance.")
            )
        }
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct CaseRow: View {
    let supportCase: SupportCase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(supportCase.caseNumber.map { "Case \($0)" } ?? "Case")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let status = PortalFormat.nonEmpty(supportCase.status) {
                    StatusPill(text: status, tone: supportCase.isClosed ? .neutral : .active)
                }
            }
            Text(supportCase.subject ?? "Support request")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            if let name = supportCase.relatedRecordName, let type = supportCase.relatedRecordType {
                Label(name, systemImage: type == .claim ? "doc.text" : "person.2")
                    .font(.subheadline)
                    .accessibilityLabel("\(type.displayName): \(name)")
            }
            HStack {
                Text("Account manager: \(PortalFormat.nonEmpty(supportCase.accountManager) ?? "—")")
                Spacer()
                Text(PortalFormat.date(supportCase.createdDate))
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Support") {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        SupportView(viewModel: PreviewData.loadedCases(), path: $path, showingRequest: .constant(false), api: PreviewData.api())
    }
}
