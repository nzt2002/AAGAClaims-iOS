import PortalKit
import SwiftUI

/// Global search, opened from the search bar on Home: claims, leads and cases the user can open.
struct SearchSheet: View {
    @State private var viewModel: SearchViewModel
    /// Closes the sheet. Inside an active search, `dismiss` only ends the search, so the
    /// presenter closes it instead.
    let close: () -> Void
    let open: (SearchResult) -> Void

    @Environment(\.isOffline) private var isOffline
    @FocusState private var fieldFocused: Bool

    private let api: PortalAPI

    init(api: PortalAPI, includePeople: Bool = false, close: @escaping () -> Void, open: @escaping (SearchResult) -> Void) {
        _viewModel = State(initialValue: SearchViewModel(api: api, store: UserDefaultsRecentSearchStore(), includePeople: includePeople))
        self.api = api
        self.close = close
        self.open = open
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    scopeChips
                    content
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            // The app's own field rather than .searchable: while a system search is active, iOS
            // hides the toolbar and shows an X that only cancels the search, not the sheet.
            .safeAreaInset(edge: .top, spacing: 0) { searchField }
            .background(Color.appBackground)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        fieldFocused = false
                        close()
                    }
                    .accessibilityIdentifier("searchClose")
                }
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonView(api: api, personId: route.id, name: route.name)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark", action: close)
                                .accessibilityIdentifier("searchClose")
                        }
                    }
            }
            .task {
                // Keyboard up as soon as the sheet opens.
                try? await Task.sleep(for: .milliseconds(150))
                fieldFocused = true
            }
        }
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            TextField("Name, claim number, address or email", text: $viewModel.query)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { viewModel.commitSearch() }
                .accessibilityLabel("Search claims, leads and cases")
                .accessibilityIdentifier("searchField")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("searchClear")
            }
        }
        .padding(.leading, Theme.Spacing.m)
        .frame(minHeight: 48)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().stroke(fieldFocused ? Color.brandPrimary : Color.border, lineWidth: fieldFocused ? 2 : 1))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .background(Color.appBackground)
    }

    // MARK: - Scope

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(viewModel.scopes, id: \.self) { scope in
                    let selected = viewModel.scope == scope
                    let count = viewModel.count(for: scope)
                    Button {
                        withAnimation(.snappy) { viewModel.scope = scope }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(scope.rawValue)
                            if !viewModel.allResults.isEmpty {
                                Text("\(count)")
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .background((selected ? Color.surface : Color.surfaceTintedStrong).opacity(selected ? 0.25 : 1), in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.surface : Color.textPrimary)
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(minHeight: 40)
                        .background(selected ? Color.brandPrimary : Color.surface, in: Capsule())
                        .overlay(Capsule().stroke(Color.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.minTapTarget)
                    .accessibilityLabel("\(scope.rawValue)\(viewModel.allResults.isEmpty ? "" : ", \(count) results")")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("searchScope-\(scope.rawValue)")
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isOffline {
            message("You're offline", "wifi.slash", "Search is available when you're back online.")
        } else {
            switch viewModel.state {
            case .idle:
                recents
            case .searching:
                SkeletonList(rows: 3)
            case .failed:
                message("Search is unavailable", "exclamationmark.triangle", "Please try again in a moment.")
            case .results:
                if viewModel.hasResultsInScope {
                    results
                } else {
                    noResults
                }
            }
        }
    }

    @ViewBuilder
    private var recents: some View {
        if viewModel.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Find anything")
                    .font(.sectionTitle)
                tip("doc.text", "A claim by name or claim number, like \"CLM-1234\"")
                tip("mappin.and.ellipse", "A property by street address")
                tip("person.2", "A lead by name or email")
                tip("questionmark.bubble", "A support case by subject or case number")
                if viewModel.includePeople {
                    tip("person.crop.circle", "A colleague by name, to see their profile and Chatter")
                }
            }
            .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Recent searches") {
                    Button("Clear") { withAnimation { viewModel.clearRecents() } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: Theme.minTapTarget)
                        .accessibilityLabel("Clear recent searches")
                }
                VStack(spacing: 0) {
                    ForEach(viewModel.recentSearches, id: \.self) { term in
                        Button {
                            viewModel.query = term
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.textSecondary)
                                Text(term)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Searches again")
                        .accessibilityIdentifier("recentSearch-\(term)")
                        if term != viewModel.recentSearches.last {
                            Divider()
                        }
                    }
                }
                .cardStyle()
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(viewModel.sections, id: \.kind) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("\(section.kind.displayName) · \(section.results.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(section.results) { result in
                            if result.type == .user {
                                // People open here, in the sheet: profile and Chatter.
                                NavigationLink(value: PersonRoute(id: result.id, name: result.title)) {
                                    row(result)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { viewModel.commitSearch() })
                                .accessibilityIdentifier("searchResult-\(result.id)")
                            } else {
                                Button {
                                    viewModel.commitSearch()
                                    close()
                                    open(result)
                                } label: {
                                    row(result)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("searchResult-\(result.id)")
                            }
                            if result.id != section.results.last?.id {
                                Divider()
                            }
                        }
                    }
                    .cardStyle()
                }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color.textSecondary)
            Text(viewModel.scope == .all ? "No results for \"\(viewModel.query)\"" : "No \(viewModel.scope.rawValue.lowercased()) match \"\(viewModel.query)\"")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Check the spelling, or try a claim number, street name or email.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if viewModel.scope != .all && viewModel.count(for: .all) > 0 {
                Button("Show all \(viewModel.count(for: .all)) results") {
                    withAnimation(.snappy) { viewModel.scope = .all }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Theme.minTapTarget)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private func row(_ result: SearchResult) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(systemName: icon(result.type), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(result.title ?? "Untitled"))
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle = PortalFormat.nonEmpty(result.subtitle) {
                    Text(highlighted(subtitle))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Bolds the parts that match the query.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in viewModel.highlightRanges(in: text) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                attributed[lower..<upper].foregroundColor = Color.brandPrimary
            }
        }
        return attributed
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(systemName: icon, size: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func message(_ title: String, _ icon: String, _ text: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(text))
            .padding(.top, Theme.Spacing.xl)
    }

    private func icon(_ kind: SearchResult.Kind) -> String {
        switch kind {
        case .claim: "doc.text"
        case .prospect: "person.2"
        case .supportCase: "questionmark.bubble"
        case .user: "person.crop.circle"
        }
    }
}
