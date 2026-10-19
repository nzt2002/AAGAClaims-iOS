import PortalKit
import SwiftUI

/// Home: welcome, quick actions, upcoming tasks and events, recent claims and recent activity
/// (updates, plus Chatter posts for staff). Ask Question, Search and the bell are in the top bar.
struct HomeView: View {
    @Bindable var router: AppRouter
    let user: CurrentUser

    private var viewModel: HomeViewModel { router.home }
    @Environment(\.isOffline) private var isOffline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your dashboard", retry: reload) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    hero
                    quickActions
                    upcoming
                    recentClaims
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

    /// Greeting on the brand gradient, with the global search bar.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Welcome back, \(user.firstName ?? user.fullName)!")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("We're here to help with your claim")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)

            // Global search: everything the user can open.
            Button {
                router.showingSearch = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0x0B / 255, green: 0x5C / 255, blue: 0xAB / 255))
                    Text("Search claims, leads and cases")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0x54 / 255, green: 0x60 / 255, blue: 0x6E / 255))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 52)
                // White in both modes, so the text colours above are fixed (6.4:1 and better).
                .background {
                    Capsule().fill(.white).shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(QuickActionPressStyle())
            .accessibilityLabel("Search claims, leads and cases")
            .accessibilityIdentifier("homeSearch")
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Shadow on the shape only, so the text stays crisp.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandGradient.hero(colorScheme))
                .overlay(alignment: .topTrailing) {
                    // Decorative ring, kept to the top-right corner, away from the text.
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 18)
                        .frame(width: 140, height: 140)
                        .offset(x: 50, y: -50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.brandBright.opacity(colorScheme == .dark ? 0 : 0.28), radius: 18, x: 0, y: 10)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        // Two columns: New Event sits directly above New Task.
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
            quickAction("New Lead", "person.badge.plus", id: "quickSubmitLead") { router.submitLead() }
                .disabledWhenOffline(isOffline)
            if viewModel.canCreateTasks {
                quickAction("New Event", "calendar.badge.plus", id: "quickNewEvent") { router.showingNewEvent = true }
                    .disabledWhenOffline(isOffline)
            }
            // Staff create claims here; portal users can't, so they keep My Claims.
            if user.isInternal {
                quickAction("New Claim", "doc.badge.plus", id: "quickNewClaim") { router.showingNewClaim = true }
                    .disabledWhenOffline(isOffline)
            } else {
                quickAction("My Claims", "doc.text", id: "quickMyClaims") { router.showClaims() }
            }
            if viewModel.canCreateTasks {
                quickAction("New Task", "checklist", id: "quickNewTask") { router.showingNewTask = true }
                    .disabledWhenOffline(isOffline)
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                IconBadge(systemName: icon, size: 32, filled: true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 8, x: 0, y: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickActionPressStyle())
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
                SectionHeader("Upcoming")
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
                    SectionHeader("Upcoming")
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
                SectionHeader("Recent claims") {
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

    // MARK: - Recent activity

    /// Staff only: Chatter (their default), portal updates, or both.
    private var activityFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(HomeViewModel.ActivityFilter.allCases, id: \.self) { filter in
                    let selected = viewModel.activityFilter == filter
                    Button {
                        withAnimation(.snappy) { viewModel.activityFilter = filter }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.surface : Color.textPrimary)
                            .padding(.horizontal, Theme.Spacing.m)
                            .frame(minHeight: 36)
                            .background(selected ? Color.brandPrimary : Color.surface, in: Capsule())
                            .overlay(Capsule().stroke(Color.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.minTapTarget)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("activityFilter-\(filter.rawValue)")
                }
            }
        }
    }

    private var emptyActivityMessage: String {
        switch viewModel.isInternalUser ? viewModel.activityFilter : .updates {
        case .chatter: "No Chatter posts yet."
        case .updates, .all: "No updates yet. We'll let you know as soon as there's news."
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent activity")
            if viewModel.isInternalUser {
                activityFilter
            }
            if viewModel.recentEntries.isEmpty {
                Text(emptyActivityMessage)
                    .foregroundStyle(Color.textSecondary)
                    .cardStyle()
            } else {
                // Three at a time; the rest scroll.
                ScrollingStack(items: viewModel.recentEntries, noun: "updates") { entry in
                        switch entry {
                        case .update(let item):
                            Button {
                                router.present(item, fromNotifications: false)
                            } label: {
                                ActivityRow(item: item)
                                    .cardStyle()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activity-\(item.commentId)")
                        case .post(let post):
                            if let record = post.recordRef {
                                Button {
                                    router.open(record, name: post.parentName)
                                } label: {
                                    FeedPostRow(post: post)
                                        .cardStyle()
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens the \(post.parentType?.displayName.lowercased() ?? "record")")
                                .accessibilityIdentifier("post-\(post.id)")
                            } else {
                                FeedPostRow(post: post)
                                    .cardStyle()
                                    .accessibilityIdentifier("post-\(post.id)")
                            }
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
                IconBadge(
                    systemName: item.kind == .event ? "calendar" : "checklist",
                    tint: item.isOverdue == true ? .warning : .brandPrimary,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subject ?? (item.kind == .event ? "Event" : "Task"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(Self.whenText(item))
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

    /// "Today", "Tomorrow", a weekday this week, or a date. For the hero's Next up.
    static func relativeWhen(_ item: AgendaItem) -> String {
        let calendar = Calendar.current
        let day: Date?
        if item.kind == .task, let due = item.dueDate {
            day = due.date(in: calendar)
        } else {
            day = item.startDateTime
        }
        guard let day else { return "" }
        if item.kind == .task && item.isOverdue == true { return "Overdue" }
        if calendar.isDateInToday(day) {
            if item.kind == .event, item.isAllDay != true, let start = item.startDateTime {
                return start.formatted(date: .omitted, time: .shortened)
            }
            return "Today"
        }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: day)).day, days > 0, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Due tomorrow", "Overdue · Due Oct 3", "Thu, Oct 9 · 10:00 AM – 11:00 AM"…
    static func whenText(_ item: AgendaItem) -> String {
        switch item.kind {
        case .task:
            guard let due = item.dueDate else { return "No due date" }
            let date = PortalFormat.date(due)
            if item.isOverdue == true { return "Overdue · Due \(date)" }
            let calendar = Calendar.current
            if let day = due.date(in: calendar) {
                if calendar.isDateInToday(day) { return "Due today" }
                if calendar.isDateInTomorrow(day) { return "Due tomorrow" }
            }
            return "Due \(date)"
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

/// A Chatter post in Recent activity (staff).
/// A gentle press effect for quick actions.
struct QuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FeedPostRow: View {
    let post: FeedPost

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.caption)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 8)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                RecordHeader(type: post.parentType?.displayName, name: post.parentName ?? "Chatter")
                Text(["Chatter", post.authorName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(post.text ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(PortalFormat.date(post.createdDate))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
                RecordHeader(type: item.relatedRecordType.displayName, name: item.relatedRecordName ?? "")
                Text(["Portal update", item.title].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · "))
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

/// "Claim · Smith - Roof": the record type in regular weight, the record name in bold.
struct RecordHeader: View {
    let type: String?
    let name: String

    var body: some View {
        if let type = PortalFormat.nonEmpty(type) {
            Text("\(Text("\(type) · ").foregroundStyle(Color.textSecondary))\(Text(name).fontWeight(.semibold))")
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
        } else {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(router: PreviewData.router(), user: .demo)
    }
}
