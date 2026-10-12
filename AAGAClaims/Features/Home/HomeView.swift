import PortalKit
import SwiftUI

/// Home: welcome, quick actions, upcoming tasks and events, recent claims, then status overview
/// and recent activity.
struct HomeView: View {
    @Bindable var router: AppRouter
    let user: CurrentUser

    private var viewModel: HomeViewModel { router.home }
    @Environment(\.isOffline) private var isOffline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your dashboard", retry: reload) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    quickActions
                    upcoming
                    recentClaims
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

    // MARK: - Quick actions

    private var quickActions: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
            quickAction("Submit a Lead", "person.badge.plus", id: "quickSubmitLead") { router.submitLead() }
                .disabledWhenOffline(isOffline)
            quickAction("Ask Question", "questionmark.bubble", id: "quickAskQuestion") { router.requestAssistance() }
                .disabledWhenOffline(isOffline)
            quickAction("My Claims", "doc.text", id: "quickMyClaims") { router.showClaims() }
            if viewModel.canCreateTasks {
                quickAction("New Task", "checklist", id: "quickNewTask") { router.showingNewTask = true }
                    .disabledWhenOffline(isOffline)
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Upcoming

    @ViewBuilder
    private var upcoming: some View {
        switch viewModel.agenda {
        case .idle, .loading:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeading("Upcoming")
                HStack {
                    Text("Unable to load your tasks and events.")
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Retry") { Task { await viewModel.loadAgenda() } }
                        .frame(minHeight: Theme.minTapTarget)
                }
                .cardStyle()
            }
        case .loaded(let agenda, _):
            // Homeowners usually have nothing scheduled; only show an empty section to people who manage tasks.
            if !viewModel.upcoming.isEmpty || agenda.canCreateTasks {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeading("Upcoming")
                    if viewModel.upcoming.isEmpty {
                        Text("Nothing scheduled. You're all caught up.")
                            .foregroundStyle(Color.textSecondary)
                            .cardStyle()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(viewModel.upcoming) { item in
                                AgendaRow(item: item) { record in
                                    router.open(record, name: item.relatedRecordName)
                                }
                                if item.id != viewModel.upcoming.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .cardStyle()
                    }
                }
            }
        }
    }

    // MARK: - Recent claims

    @ViewBuilder
    private var recentClaims: some View {
        if !viewModel.recentClaims.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    SectionHeading("Recent claims")
                    Spacer()
                    Button {
                        router.showClaims()
                    } label: {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("See all claims")
                }
                VStack(spacing: 0) {
                    ForEach(viewModel.recentClaims) { claim in
                        Button {
                            router.open(.claim(claim.recordId), name: claim.recordName)
                        } label: {
                            RecentClaimRow(claim: claim)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recentClaim-\(claim.recordId)")
                        if claim.id != viewModel.recentClaims.last?.id {
                            Divider()
                        }
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Status overview and activity

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

/// One upcoming task or event.
struct AgendaRow: View {
    let item: AgendaItem
    let open: (RecordRef) -> Void

    var body: some View {
        if let record = item.recordRef {
            Button {
                open(record)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the \(item.relatedRecordType?.displayName.lowercased() ?? "record")")
            .accessibilityIdentifier("agenda-\(item.id)")
        } else {
            // Not linked to a claim or lead: a plain row, not a disabled (faded) button.
            row
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agenda-\(item.id)")
        }
    }

    private var row: some View {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: item.kind == .event ? "calendar" : "checklist")
                    .foregroundStyle(item.isOverdue == true ? Color.warning : Color.brandPrimary)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subject ?? (item.kind == .event ? "Event" : "Task"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(when)
                        .font(.caption)
                        .foregroundStyle(item.isOverdue == true ? Color.warning : Color.textSecondary)
                    if let name = PortalFormat.nonEmpty(item.relatedRecordName), let type = item.relatedRecordType {
                        Text("\(type.displayName) · \(name)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if let location = PortalFormat.nonEmpty(item.location) {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if item.recordRef != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
    }

    private var when: String {
        switch item.kind {
        case .task:
            guard let due = item.dueDate else { return "No due date" }
            let date = PortalFormat.date(due)
            return item.isOverdue == true ? "Overdue · Due \(date)" : "Due \(date)"
        case .event:
            guard let start = item.startDateTime else { return "" }
            if item.isAllDay == true {
                // Salesforce stores all-day events at midnight UTC; show that date, not the local one.
                var utc = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                utc.timeZone = TimeZone(identifier: "UTC")!
                return "\(start.formatted(utc)) · All day"
            }
            let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let startTime = start.formatted(date: .omitted, time: .shortened)
            if let end = item.endDateTime {
                return "\(day) · \(startTime) – \(end.formatted(date: .omitted, time: .shortened))"
            }
            return "\(day) · \(startTime)"
        }
    }
}

/// A compact claim row for Home.
struct RecentClaimRow: View {
    let claim: ClaimSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.recordName ?? "Claim")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text("Updated \(PortalFormat.date(claim.lastModifiedDate))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            if let status = PortalFormat.nonEmpty(claim.claimStatus) {
                StatusPill(text: status, tone: StatusPill.tone(forClaimStatus: status))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens claim details")
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
