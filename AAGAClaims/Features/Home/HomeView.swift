import PortalKit
import SwiftUI

/// Home: welcome, quick actions, upcoming tasks and events, recent claims and recent activity
/// (updates, plus Chatter posts for staff). Ask Question, Search and the bell are in the top bar.
struct HomeView: View {
    @Bindable var router: AppRouter
    let user: CurrentUser

    private var viewModel: HomeViewModel { router.home }
    @Environment(\.isOffline) private var isOffline
    @Environment(\.serverMeta) private var serverMeta
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    /// iPad, with room for two columns.
    @State private var isWide = false

    var body: some View {
        LoadingContainer(state: viewModel.state, subject: "your dashboard", retry: reload) { _ in
            ScrollView {
                Group {
                    if isWide {
                        // iPad: actions in one row; what needs doing and the activity feed on the
                        // left, the agenda and recent claims in a rail on the right.
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            hero
                            quickActions
                            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                                    NeedsAttentionSection(viewModel: viewModel, router: router)
                                    recentActivity
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                                    recentActivityCard
                                    openSupport
                                    waitingSignatures
                                    recentClaims
                                }
                                .frame(width: WideLayout.railWidth + 20)
                            }
                        }
                        .frame(maxWidth: WideLayout.maxContentWidth)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            hero
                            // Staff: what needs them comes first, then the shortcuts.
                            if user.isInternal {
                                NeedsAttentionSection(viewModel: viewModel, router: router)
                                quickActions
                            } else {
                                quickActions
                                NeedsAttentionSection(viewModel: viewModel, router: router)
                            }
                            recentActivityCard
                            openSupport
                            waitingSignatures
                            recentClaims
                            recentActivity
                        }
                    }
                }
                .padding(isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            }
            .readsWideLayout($isWide)
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
            // The company's logo and name, as on the website's header.
            if let company = CompanyBrand.shared.company {
                HStack(spacing: Theme.Spacing.s) {
                    CompanyLogo(size: 36)
                    Text(company.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("homeCompany")
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Welcome back, \(user.firstName ?? user.fullName)!")
                    .font(.heroTitle)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(user.isInternal ? "Here's what needs you today" : "We're here to help with your claim")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)

            // Global search: everything the user can open.
            Button {
                router.showingSearch = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass").iconShadow()
                        .font(.headline)
                        .foregroundStyle(Theme.OnWhite.brand)
                    Text(serverMeta.jobsOnly ? "Search jobs, leads and cases" : "Search claims, leads and cases")
                        .font(.subheadline)
                        .foregroundStyle(Theme.OnWhite.secondary)
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
            .accessibilityLabel(serverMeta.jobsOnly ? "Search jobs, leads and cases" : "Search claims, leads and cases")
            .accessibilityIdentifier("homeSearch")
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Shadow on the shape only, so the text stays crisp.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandGradient.hero(colorScheme))
                .overlay {
                    if let logo = CompanyBrand.shared.company?.logoUrl {
                        HeroLogoBackdrop(url: logo)
                    } else {
                        // No company logo: a decorative ring, kept to the top-right corner, away from the text.
                        Circle()
                            .stroke(.white.opacity(0.12), lineWidth: 18)
                            .frame(width: 140, height: 140)
                            .offset(x: 50, y: -50)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.brandBright.opacity(colorScheme == .dark ? 0 : 0.28), radius: 18, x: 0, y: 10)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: dynamicTypeSize.isAccessibilitySize ? 1 : (isWide ? 4 : 2))
        // Two columns: New Event sits directly above New Task. iPad: all four in one row.
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
            quickAction("New Lead", "person.badge.plus", id: "quickSubmitLead") { router.submitLead() }
                .disabledWhenOffline(isOffline)
            if viewModel.canCreateTasks {
                quickAction("New Event", "calendar.badge.plus", id: "quickNewEvent") { router.showingNewEvent = true }
                    .disabledWhenOffline(isOffline)
            }
            // Staff create claims here; portal users can't, so they keep My Claims.
            if serverMeta.jobsOnly {
                // A Contractor-only company has jobs, not claims.
                quickAction("My Jobs", "hammer", id: "quickMyJobs") { router.showClaims() }
            } else if user.isInternal {
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

    // MARK: - Recent activity card: tasks and events

    /// Your open tasks and upcoming events in a card that scrolls (about three rows show), with a ⋯ menu to show or hide
    /// finished tasks.
    @ViewBuilder
    private var recentActivityCard: some View {
        switch viewModel.agenda {
        case .idle, .loading:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Recent activity")
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
            // Homeowners usually have nothing scheduled; only show an empty card to people who manage tasks.
            let items = viewModel.recentActivityItems
            if !items.isEmpty || agenda.canCreateTasks {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader("Recent activity") {
                        if viewModel.isInternalUser {
                            Menu {
                                Button(viewModel.showCompleted ? "Hide Completed Tasks" : "Show Completed Tasks",
                                       systemImage: viewModel.showCompleted ? "eye.slash" : "checkmark.circle") {
                                    viewModel.showCompleted.toggle()
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").iconShadow()
                                    .font(.title3)
                                    .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Recent activity options")
                            .accessibilityIdentifier("recentActivityMenu")
                        }
                    }
                    if items.isEmpty {
                        Text("Nothing scheduled. You're all caught up.")
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                    } else {
                        // About three rows tall; the rest scroll inside the card.
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { item in
                                    AgendaRow(item: item) { record in
                                        router.open(record, name: item.relatedRecordName)
                                    }
                                    if item.id != items.last?.id { Divider() }
                                }
                            }
                            // Room for the scroll bar, so it doesn't sit on the row chevrons.
                            .padding(.trailing, Theme.Spacing.s)
                        }
                        .frame(maxHeight: 250)
                        .cardStyle()
                    }
                }
            }
        }
    }

    // MARK: - Open support requests

    @ViewBuilder
    private var openSupport: some View {
        if case .loaded(let cases, _) = viewModel.openCases, !cases.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Open support requests") {
                    Button { router.openSupport(caseId: nil) } label: {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("See all support requests")
                }
                VStack(spacing: 0) {
                    ForEach(cases) { item in
                        Button { router.openSupport(caseId: item.caseId) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                IconBadge(systemName: "lifepreserver", size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.subject ?? "Support request")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text([item.caseNumber, item.relatedRecordName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer(minLength: Theme.Spacing.s)
                                if let status = PortalFormat.nonEmpty(item.status) {
                                    StatusPill(text: status, tone: .neutral)
                                }
                                Image(systemName: "chevron.right").iconShadow().font(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .frame(minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("openCase-\(item.caseId)")
                        if item.id != cases.last?.id { Divider() }
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Waiting for signature

    @ViewBuilder
    private var waitingSignatures: some View {
        if case .loaded(let waiting, _) = viewModel.signatures, !waiting.items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Waiting for signature")
                VStack(spacing: 0) {
                    ForEach(waiting.items) { item in
                        Button {
                            if let record = item.recordRef { router.open(record, name: item.relatedRecordName) }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                IconBadge(systemName: "signature", size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.subject)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text((item.clients.joined(separator: ", ") + (item.relatedRecordName.map { " · " + $0 } ?? "")).trimmingCharacters(in: [" ", "·"]))
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: Theme.Spacing.s)
                                Text(item.daysWaiting == 0 ? "Today" : "\(item.daysWaiting)d")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.daysWaiting >= 7 ? Color.warning : Color.textSecondary)
                                Image(systemName: "chevron.right").iconShadow().font(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .frame(minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(item.recordRef == nil)
                        .accessibilityIdentifier("waitingSignature-\(item.id)")
                        if item.id != waiting.items.last?.id { Divider() }
                    }
                    if waiting.total > waiting.items.count {
                        Text("and \(waiting.total - waiting.items.count) more")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Recent claims

    @ViewBuilder
    private var recentClaims: some View {
        if !viewModel.recentClaims.isEmpty && !serverMeta.jobsOnly {
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
        ChipBar {
            ForEach(HomeViewModel.ActivityFilter.allCases, id: \.self) { filter in
                FilterChip(title: filter.rawValue, isActive: viewModel.activityFilter == filter) {
                    withAnimation(.snappy) { viewModel.activityFilter = filter }
                }
                .accessibilityIdentifier("activityFilter-\(filter.rawValue)")
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
            SectionHeader("Latest updates")
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
                    systemName: item.kind == .event ? "calendar" : (item.isClosed == true ? "checkmark.circle.fill" : "checklist"),
                    tint: item.isOverdue == true ? .warning : (item.isClosed == true && item.kind == .task ? .success : .brandTheme),
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subject ?? (item.kind == .event ? "Event" : "Task"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.kind == .task && item.isClosed == true ? Color.textSecondary : Color.textPrimary)
                        .strikethrough(item.kind == .task && item.isClosed == true)
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
                    Image(systemName: "chevron.right").iconShadow()
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
        case .email:
            return item.startDateTime.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
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
            Image(systemName: "chevron.right").iconShadow()
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
            Image(systemName: "bubble.left.and.text.bubble.right").iconShadow()
                .font(.caption)
                .foregroundStyle(Color.brandTheme)
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
                .fill(item.isRead ? Color.clear : Color.brandTheme)
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


/// The company's logo as a watermark behind the Home header, as on the website's header: an oversized, tilted, pale
/// grayscale copy at about 11% opacity, with a soft pool of brand light behind the logo plate. It's too faint to
/// affect the greeting's contrast.
struct HeroLogoBackdrop: View {
    let url: URL
    private var brand: CompanyBrand { CompanyBrand.shared }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Light pooling at the top left, behind the company's logo plate.
            RadialGradient(colors: [(brand.heroStart ?? .heroStart).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.12, y: 0.1), startRadius: 0, endRadius: 260)
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .grayscale(1)
                        .brightness(0.55)
                        .opacity(0.14)
                } else {
                    Color.clear
                }
            }
            .frame(width: 190, height: 190)
            .rotationEffect(.degrees(-10))
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
