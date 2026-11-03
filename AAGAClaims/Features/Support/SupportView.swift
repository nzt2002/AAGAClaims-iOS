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

    @Environment(\.isOffline) private var isOffline

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your support cases", retry: reload) { _ in
            List {
                Section {
                    Text("Use Ask Question when you have a question about a claim or lead, such as a status update, a document request, or a follow-up on an inspection or estimate.")
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
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search cases")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRequest = true
                } label: {
                    Label("Ask Question", systemImage: "questionmark.bubble")
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                }
                .disabledWhenOffline(isOffline)
                .accessibilityIdentifier("supportRequestAssistance")
            }
        }
        // Case and related-record destinations are in RecordDestinations: cases also open from a claim's or lead's Updates.
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
                description: Text("Need help with a claim or lead? Tap Ask Question.")
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
            AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                Text(supportCase.caseNumber.map { "Case \($0)" } ?? "Case")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                AdaptiveSpacer()
                if let status = PortalFormat.nonEmpty(supportCase.status) {
                    StatusPill(text: status, tone: supportCase.isClosed ? .neutral : .active)
                }
            }
            Text(supportCase.subject ?? "Support request")
                .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.textPrimary)
            if let name = supportCase.relatedRecordName, let type = supportCase.relatedRecordType {
                Label(name, systemImage: type == .claim ? "doc.text" : "person.2")
                    .font(.subheadline)
                    .accessibilityLabel("\(type.displayName): \(name)")
            }
            AdaptiveStack(spacing: Theme.Spacing.xs) {
                Text("Account manager: \(PortalFormat.nonEmpty(supportCase.accountManager) ?? "—")")
                AdaptiveSpacer()
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
