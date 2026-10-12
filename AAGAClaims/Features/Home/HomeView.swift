import PortalKit
import SwiftUI

/// Home dashboard (spec §6.2).
struct HomeView: View {
    @Bindable var router: AppRouter
    let user: CurrentUser

    private var viewModel: HomeViewModel { router.home }

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your dashboard", retry: reload) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    if let summary = viewModel.summary {
                        tiles(summary)
                    }
                    quickActions
                    if let summary = viewModel.summary, viewModel.hasClaims {
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
        .sheet(item: $router.homeUpdate) { item in
            UpdateSheet(item: item) { record, name in router.open(record, name: name) }
        }
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
            tile("Open Claims", summary.openClaims, "doc.text", id: "tileOpenClaims") {
                router.showClaims(openOnly: true)
            }
            tile("Open Leads", summary.openLeads, "person.2", id: "tileOpenLeads") {
                router.showLeads(openOnly: true)
            }
            tile("Completed", summary.completed, "checkmark.seal", id: "tileCompleted") {
                // Closed claims; converted leads are a filter away on the Leads tab.
                router.showClaims(stage: "Closed")
            }
            tile("Unread Updates", summary.unreadUpdates, "bell", id: "tileUnread") {
                router.showingNotifications = true
            }
        }
    }

    private func tile(_ title: String, _ count: Int, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeading("Quick actions")
            HStack(spacing: Theme.Spacing.s) {
                quickAction("Submit a Lead", "person.badge.plus", id: "quickSubmitLead") { router.submitLead() }
                quickAction("Request Assistance", "questionmark.bubble", id: "quickRequestAssistance") { router.requestAssistance() }
                quickAction("View My Claims", "doc.text", id: "quickViewClaims") { router.showClaims() }
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.brandPrimary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, Theme.Spacing.s)
            .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func statusOverview(_ summary: HomeViewModel.Summary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeading("Status overview")
            VStack(spacing: 0) {
                ForEach(summary.claimsByStage, id: \.stage) { row in
                    Button {
                        router.showClaims(stage: row.stage)
                    } label: {
                        HStack {
                            Text(row.stage)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(row.count)")
                                .foregroundStyle(Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.stage): \(row.count) \(row.count == 1 ? "claim" : "claims")")
                    .accessibilityIdentifier("stage-\(row.stage)")
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
            SectionHeading("Recent activity")
            if viewModel.recentActivity.isEmpty {
                Text("No updates yet. We'll let you know as soon as there's news.")
                    .foregroundStyle(Color.textSecondary)
                    .cardStyle()
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(viewModel.recentActivity) { item in
                        Button {
                            router.present(item, fromNotifications: false)
                        } label: {
                            ActivityRow(item: item)
                                .cardStyle()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("activity-\(item.commentId)")
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
                    .multilineTextAlignment(.leading)
                Text(PortalFormat.date(item.createdDate))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? "" : "Unread")
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(router: PreviewData.router(), user: .demo)
    }
}
