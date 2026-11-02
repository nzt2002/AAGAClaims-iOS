import PortalKit
import SwiftUI

enum AppTab: Hashable {
    case home, claims, leads, support, search
}

struct MainTabView: View {
    let session: AppSession
    let user: CurrentUser

    @State private var router: AppRouter
    @State private var safariLink: SafariLink?
    @State private var offeringLock = false
    /// Release notes for a newly installed version, once, after sign-in.
    @State private var whatsNew: WhatsNew.Release?
    /// `GET /meta`; legacy until it loads.
    @State private var serverMeta: ServerMeta = .legacy
    /// Set by New Claim; opened when its sheet has closed.
    @State private var createdClaim: (id: String, name: String)?
    /// "Ask Alex" (staff with Claims Assistant access).
    @State private var showingAskAlex = false
    /// The claim or lead on screen, which Alex takes as the conversation's context.
    @State private var alexContext = AlexRecordContext()
    @Environment(\.scenePhase) private var scenePhase
    /// iPad (full screen or a wide split): lists and records side by side.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var bellSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .body) private var bellButtonSize: CGFloat = 38

    init(session: AppSession, user: CurrentUser) {
        self.session = session
        self.user = user
        _router = State(initialValue: AppRouter(api: session.api, isInternalUser: user.isInternal))
    }

    var body: some View {
        tabs
            .environment(\.isInternalUser, user.isInternal)
            .environment(\.salesforceInstanceURL, user.instanceURL)
            .environment(\.salesforcePage, user.instanceURL.map { instance in
                SalesforcePageAction { path in await SalesforceWebSession.signedInURL(for: path, instanceURL: instance) }
            })
            .environment(\.currentUserName, user.fullName)
            .environment(\.serverMeta, serverMeta)
            .environment(\.alexRecordContext, assistantAgentId != nil ? alexContext : nil)
    }

    private var claimsList: some View {
        ClaimsListView(viewModel: router.claims, api: session.api, openSupport: { router.openSupport(caseId: nil) },
                       showsMine: user.isInternal)
            .onAppear { router.claims.currentUserName = user.fullName }
            .statusBanners(session)
            .toolbar { topBarButtons() }
    }

    private var leadsList: some View {
        LeadsListView(viewModel: router.leads, path: $router.leadsPath, showingSubmit: $router.showingSubmitLead,
                      api: session.api, userEmail: user.email,
                      openSupport: { router.openSupport(caseId: nil) }, showsMine: user.isInternal)
            .onAppear { router.leads.currentUserName = user.fullName }
            .statusBanners(session)
            .toolbar { topBarButtons() }
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(router: router, user: user)
                        .modifier(RecordDestinations(router: router, api: session.api))
                        .statusBanners(session)
                        .toolbar { topBarButtons() }
                }
            }
            Tab("Claims", systemImage: "doc.text", value: .claims) {
                if horizontalSizeClass == .regular {
                    NavigationSplitView {
                        claimsList
                    } detail: {
                        NavigationStack(path: $router.claimsPath) {
                            RecordPlaceholder(noun: "claim", systemImage: "doc.text")
                                .modifier(RecordDestinations(router: router, api: session.api))
                                .navigationDestination(for: ClaimSummary.self) { claim in
                                    ClaimDetailView(claimId: claim.recordId, summary: claim, api: session.api)
                                        .id(claim.recordId)
                                }
                        }
                    }
                } else {
                    NavigationStack(path: $router.claimsPath) {
                        claimsList
                            .modifier(RecordDestinations(router: router, api: session.api))
                    }
                }
            }
            Tab("Leads", systemImage: "person.2", value: .leads) {
                if horizontalSizeClass == .regular {
                    NavigationSplitView {
                        leadsList
                    } detail: {
                        NavigationStack(path: $router.leadsPath) {
                            RecordPlaceholder(noun: "lead", systemImage: "person.2")
                                .modifier(RecordDestinations(router: router, api: session.api))
                        }
                    }
                } else {
                    NavigationStack(path: $router.leadsPath) {
                        leadsList
                            .modifier(RecordDestinations(router: router, api: session.api))
                    }
                }
            }
            Tab("Support", systemImage: "questionmark.bubble", value: .support) {
                NavigationStack(path: $router.supportPath) {
                    SupportView(viewModel: router.cases, path: $router.supportPath,
                                showingRequest: $router.showingRequestAssistance, api: session.api)
                        .modifier(RecordDestinations(router: router, api: session.api))
                        .statusBanners(session)
                        .toolbar { topBarButtons() }
                }
            }
            // The separate glass button at the end of the tab bar (iOS 26): Ask Alex for staff who
            // have him (it opens his chat; search moves to the top bar), otherwise Search.
            if assistantAgentId != nil {
                Tab("Ask Alex", image: "RobotIcon", value: .search, role: .search) {
                    Color.appBackground
                }
            } else {
                // Records found here open in this tab, so Back returns to the results.
                Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                    NavigationStack(path: $router.searchPath) {
                        SearchSheet(api: session.api, includePeople: user.isInternal, inTab: true, close: {}) { result in
                            router.open(result)
                        }
                        .modifier(RecordDestinations(router: router, api: session.api))
                        .statusBanners(session)
                    }
                }
            }
        }
        .modifier(TabBarStyle())
        .environment(\.openSupport, OpenSupportAction { caseId in router.openSupport(caseId: caseId) })
        .environment(\.openRecord, OpenRecordAction { record, name in router.open(record, name: name) })
        .environment(\.isOffline, session.offline.isOffline)
        .onChange(of: session.offline.isOffline) { wasOffline, isOffline in
            // Back online: refresh the dashboard and badge, and send posts written offline.
            if wasOffline && !isOffline {
                Task { await router.home.load() }
                Task { await Outbox.shared.send(using: session.api) }
            }
        }
        .opensWebLinksInSafari($safariLink)
        // Account opens from the profile button (iPhone shows at most five tabs, and Search has one).
        .sheet(isPresented: $router.showingAccount) {
            NavigationStack {
                AccountView(session: session, user: user, openSupport: {
                    router.showingAccount = false
                    router.openSupport(caseId: nil)
                })
                .statusBanners(session)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { router.showingAccount = false }
                            .accessibilityIdentifier("accountDone")
                    }
                }
            }
        }
        .sheet(isPresented: $router.showingNotifications) {
            NotificationsView(router: router)
        }
        .sheet(isPresented: $router.showingSearch) {
            SearchSheet(api: session.api, includePeople: user.isInternal, close: { router.showingSearch = false }) { result in router.open(result) }
        }
        // The new claim opens once the sheet has finished closing: navigation changes made while
        // a sheet animates away can be dropped.
        .sheet(isPresented: $router.showingNewClaim, onDismiss: openCreatedClaim) {
            NewClaimSheet(api: session.api, close: { router.showingNewClaim = false }) { claimId, name in
                createdClaim = (claimId, name)
                router.showingNewClaim = false
            }
        }
        .sheet(isPresented: $showingAskAlex) {
            if let agentId = assistantAgentId {
                AskAlexSheet(agentId: agentId, viewing: alexContext.current) { showingAskAlex = false }
            }
        }
        .sheet(isPresented: $router.showingNewEvent) {
            NewEventSheet(api: session.api, currentUserName: user.fullName) {
                Task { await router.home.loadAgenda() }
            }
        }
        .sheet(isPresented: $router.showingNewTask) {
            NewTaskSheet(api: session.api, currentUserName: user.fullName) {
                Task { await router.home.loadAgenda() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                router.refreshStale()
            }
        }
        .onChange(of: router.home.unreadCount, initial: true) { _, count in
            AppBadge.update(count)
        }
        .onChange(of: DeepLinkInbox.shared.pending, initial: true) { _, link in
            guard let link else { return }
            DeepLinkInbox.shared.pending = nil
            router.handle(link)
        }
        .task {
            // Home also drives the bell badge, so load it up front.
            await router.home.load()
        }
        .task {
            if let meta = try? await session.api.serverMeta() {
                serverMeta = meta
            }
            await Outbox.shared.send(using: session.api)
            if !session.isDemo && serverMeta.supports(.diagnostics) {
                await CrashReporter.shared.send(using: session.api)
            }
        }
        .task {
            // What's new first; then, after the first sign-in, offer Face ID (spec §6.1).
            if let release = WhatsNew.pending(isInternal: user.isInternal) {
                whatsNew = release
            } else if session.lock.shouldOffer {
                offeringLock = true
            } else {
                await askForNotifications()
            }
        }
        .sheet(item: $whatsNew, onDismiss: {
            WhatsNew.markSeen()
            if session.lock.shouldOffer {
                offeringLock = true
            } else {
                Task { await askForNotifications() }
            }
        }) { release in
            WhatsNewSheet(release: release, isInternal: user.isInternal)
        }
        .alert("Use \(session.lock.methodName)?", isPresented: $offeringLock) {
            Button("Turn On") {
                Task {
                    _ = await session.lock.enable()
                    await askForNotifications()
                }
            }
            Button("Not Now", role: .cancel) {
                session.lock.markOffered()
                Task { await askForNotifications() }
            }
        } message: {
            Text("Lock ProClaimer with \(session.lock.methodName) so only you can see your claims. You can change this in Account.")
        }
    }

    /// After sign-in (and What's New and the Face ID offer), ask once to allow notifications:
    /// new updates, payments, @mentions and tasks (spec §8). Not in demo mode or UI tests.
    private func askForNotifications() async {
        guard !session.isDemo, !UserDefaults.standard.bool(forKey: "UITestDemo"),
              await PushNotifications.status() == .notDetermined else { return }
        _ = await PushNotifications.requestPermission(registerWithSalesforce: true)
    }

    private func openCreatedClaim() {
        guard let claim = createdClaim else { return }
        createdClaim = nil
        Task { await router.claims.load() }
        router.open(.claim(claim.id), name: claim.name)
    }

    /// Alex, for staff the server says may use it. Not in demo mode: there's no real agent.
    private var assistantAgentId: String? {
        guard user.isInternal, !session.isDemo else { return nil }
        return serverMeta.assistantAgentId
    }

    /// The tab bar's selection. With Alex, his tab opens his chat over the current tab instead of
    /// switching to it.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { router.selection }, set: { tab in
            if tab == .search && assistantAgentId != nil {
                showingAskAlex = true
            } else {
                router.selection = tab
            }
        })
    }

    /// Top right: Search (staff with Alex, whose tab takes Search's place), the notifications bell and
    /// Account. (Everyone else has the Search tab; Home's hero has a search bar too.)
    @ToolbarContentBuilder
    private func topBarButtons() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if assistantAgentId != nil {
                Button {
                    router.showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: bellSize))
                        .frame(minWidth: bellButtonSize, minHeight: bellButtonSize)
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("topBarSearch")
            }

            Button {
                router.showingNotifications = true
            } label: {
                // 15% smaller than a standard bar icon and button (17 pt and 44 pt).
                Image(systemName: "bell")
                    .font(.system(size: bellSize))
                    // A ring when a new update arrives.
                    .symbolEffect(.bounce, options: .nonRepeating, value: router.home.unreadCount)
                    .frame(minWidth: bellButtonSize, minHeight: bellButtonSize)
                    .overlay(alignment: .topTrailing) {
                        if router.home.unreadCount > 0 {
                            UnreadBadge(count: router.home.unreadCount)
                        }
                    }
            }
            .accessibilityLabel(router.home.unreadCount > 0 ? "Notifications, \(router.home.unreadCount) unread" : "Notifications")
            .accessibilityIdentifier("notificationsBell")

            Button {
                router.showingAccount = true
            } label: {
                ProfileAvatar(name: user.fullName, size: bellButtonSize * 0.72)
                    .frame(minWidth: bellButtonSize, minHeight: bellButtonSize)
            }
            .accessibilityLabel("Account")
            .accessibilityIdentifier("accountButton")
        }
    }
}

/// Unread count on the bell (spec §4).
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.bold())
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.danger, in: Capsule())
            .offset(x: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// iPad: the detail column before a claim or lead is chosen.
private struct RecordPlaceholder: View {
    let noun: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView("Choose a \(noun)", systemImage: systemImage,
                               description: Text("Pick a \(noun) from the list to see it here."))
            .background(Color.appBackground)
    }
}

/// iOS 26: the tab bar shrinks while scrolling down (Liquid Glass). Earlier: capsule buttons as before.
private struct TabBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        // Not in UI tests: they tap tabs straight after scrolling.
        if #available(iOS 26, *), !UserDefaults.standard.bool(forKey: "UITestDemo") {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content.buttonBorderShape(.capsule)
        }
    }
}

/// The signed-in user's initials in a brand circle: opens Account.
struct ProfileAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.surface)
            .frame(width: size, height: size)
            .background(Color.brandPrimary, in: Circle())
            .accessibilityHidden(true)
    }
}
