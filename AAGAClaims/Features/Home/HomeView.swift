import PortalKit
import SwiftUI

/// Home dashboard (spec §6.2). Milestone 1: tiles, status overview and recent activity from
/// mock data. Tile and row navigation, the Update sheet and quick actions come in milestone 5.
struct HomeView: View {
    let viewModel: HomeViewModel
    let user: CurrentUser
    let selectTab: (AppTab) -> Void

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your dashboard", retry: reload) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    if let summary = viewModel.summary {
                        tiles(summary)
                        statusOverview(summary)
                    }
                    recentActivity
                }
                .padding(Theme.Spacing.l)
            }
            .refreshable { await viewModel.load() }
        }
        .background(Color.appBackground)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Welcome back, \(user.firstName ?? user.fullName)!")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("We're here to help with your claim")
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ summary: HomeViewModel.Summary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
            tile("Open Claims", summary.openClaims, "doc.text") { selectTab(.claims) }
            tile("Open Leads", summary.openLeads, "person.2") { selectTab(.leads) }
            tile("Completed", summary.completed, "checkmark.seal") { selectTab(.claims) }
            tile("Unread Updates", summary.unreadUpdates, "bell") {}
        }
    }

    private func tile(_ title: String, _ count: Int, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Image(systemName: icon)
                    .foregroundStyle(Color.brandPrimary)
                Text("\(count)")
                    .font(.title.bold())
                    .foregroundStyle(Color.textPrimary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
    }

    private func statusOverview(_ summary: HomeViewModel.Summary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Status overview")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(summary.claimsByStage, id: \.stage) { row in
                    HStack {
                        Text(row.stage)
                        Spacer()
                        Text("\(row.count)")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(minHeight: Theme.minTapTarget)
                    .accessibilityElement(children: .combine)
                    if row.stage != summary.claimsByStage.last?.stage {
                        Divider()
                    }
                }
            }
            .cardStyle()
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Recent activity")
                .font(.headline)
            if viewModel.recentActivity.isEmpty {
                Text("No updates yet. We'll let you know as soon as there's news.")
                    .foregroundStyle(Color.textSecondary)
                    .cardStyle()
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(viewModel.recentActivity) { item in
                        ActivityRow(item: item)
                            .cardStyle()
                    }
                }
            }
        }
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Circle()
                .fill(item.isRead ? Color.clear : Color.brandPrimary)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.title ?? "Update")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(item.relatedRecordType.displayName) · \(item.relatedRecordName ?? "")")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(HTMLText.plainText(item.text))
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(PortalFormat.date(item.createdDate))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isRead ? "" : "Unread")
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(viewModel: PreviewData.loadedHome(), user: .demo, selectTab: { _ in })
    }
}
