import PortalKit
import SwiftUI

/// Support cases (spec §6.9). Search, case detail and Request Assistance come in milestone 4.
struct SupportView: View {
    @Bindable var viewModel: CasesListViewModel

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your support cases", retry: reload) { _ in
            List {
                Section {
                    Text("Use Request Assistance when you have a question about a claim or lead, such as a status update, a document request, or a follow-up on an inspection or estimate.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(CasesListViewModel.Filter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowSeparator(.hidden)

                if viewModel.cases.isEmpty {
                    ContentUnavailableView("No support cases", systemImage: "questionmark.bubble")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.cases) { supportCase in
                        CaseRow(supportCase: supportCase)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("Support")
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
    NavigationStack {
        SupportView(viewModel: PreviewData.loadedCases())
    }
}
