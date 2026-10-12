import PortalKit
import SwiftUI

/// Search everything the user can open (the magnifying glass next to the bell).
struct SearchSheet: View {
    @State private var viewModel: SearchViewModel
    let open: (SearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isOffline) private var isOffline

    init(api: PortalAPI, open: @escaping (SearchResult) -> Void) {
        _viewModel = State(initialValue: SearchViewModel(api: api))
        self.open = open
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $viewModel.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Claims, leads and cases"
                )
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isOffline {
            ContentUnavailableView("You're offline", systemImage: "wifi.slash",
                                   description: Text("Search is available when you're back online."))
        } else {
            switch viewModel.state {
            case .idle:
                ContentUnavailableView("Search your records", systemImage: "magnifyingglass",
                                       description: Text("Find claims, leads and support cases by name, number or address."))
            case .searching:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ContentUnavailableView("Search is unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("Please try again in a moment."))
            case .results(let results) where results.isEmpty:
                ContentUnavailableView.search(text: viewModel.query)
            case .results:
                List {
                    ForEach(viewModel.sections, id: \.kind) { section in
                        Section(section.kind.displayName) {
                            ForEach(section.results) { result in
                                Button {
                                    dismiss()
                                    open(result)
                                } label: {
                                    row(result)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("searchResult-\(result.id)")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func row(_ result: SearchResult) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon(result.type))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let subtitle = PortalFormat.nonEmpty(result.subtitle) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func icon(_ kind: SearchResult.Kind) -> String {
        switch kind {
        case .claim: "doc.text"
        case .prospect: "person.2"
        case .supportCase: "questionmark.bubble"
        }
    }
}
