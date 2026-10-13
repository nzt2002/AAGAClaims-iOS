import PortalKit
import SwiftUI

enum AppTab: Hashable {
    case home, claims, leads, support, account
}

struct MainTabView: View {
    let session: AppSession
    let user: CurrentUser

    @State private var router: AppRouter
    @State private var safariLink: SafariLink?
    @State private var offeringLock = false
    @Environment(\.scenePhase) private var scenePhase

    init(session: AppSession, user: CurrentUser) {
        self.session = session
        self.user = user
        _router = State(initialValue: AppRouter(api: session.api, isInternalUser: user.isInternal))
    }

    var body: some View {
        TabView(selection: $router.selection) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack {
                    HomeView(router: router, user: user)
                        .statusBanners(session)
                        .toolbar { topBarButtons() }
                }
            }
            Tab("Claims", systemImage: "doc.text", value: .claims) {
                NavigationStack(path: $router.claimsPath) {
                    ClaimsListView(viewModel: router.claims, api: session.api, openSupport: { router.openSupport(caseId: nil) })
                        .statusBanners(session)
                        .toolbar { topBarButtons() }
                }
            }
            Tab("Leads", systemImage: "person.2", value: .leads) {
                NavigationStack(path: $router.leadsPath) {
                    LeadsListView(viewModel: router.leads, path: $router.leadsPath, showingSubmit: $router.showingSubmitLead,
                                  api: session.api, userEmail: user.email,
                                  openSupport: { router.openSupport(caseId: nil) })
                        .statusBanners(session)
                        .toolbar { topBarButtons() }
                }
            }
            Tab("Support", systemImage: "questionmark.bubble", value: .support) {
                NavigationStack(path: $router.supportPath) {
                    SupportView(viewModel: router.cases, path: $router.supportPath,
                                showingRequest: $router.showingRequestAssistance, api: session.api)
                        .statusBanners(session)
                }
            }
            Tab("Account", systemImage: "person.crop.circle", value: .account) {
                NavigationStack {
                    AccountView(session: session, user: user, openSupport: { router.openSupport(caseId: nil) })
                        .statusBanners(session)
                }
            }
        }
        .buttonBorderShape(.capsule)
        .environment(\.openSupport, OpenSupportAction { caseId in router.openSupport(caseId: caseId) })
        .environment(\.isOffline, session.offline.isOffline)
        .onChange(of: session.offline.isOffline) { wasOffline, isOffline in
            // Back online: refresh the dashboard and badge.
            if wasOffline && !isOffline {
                Task { await router.home.load() }
            }
        }
        .opensWebLinksInSafari($safariLink)
        .sheet(isPresented: $router.showingNotifications) {
            NotificationsView(router: router)
        }
        .sheet(isPresented: $router.showingSearch) {
            SearchSheet(api: session.api, close: { router.showingSearch = false }) { result in router.open(result) }
        }
        .sheet(isPresented: $router.showingNewClaim) {
            NewClaimSheet(api: session.api, close: { router.showingNewClaim = false }) { claimId, name in
                router.showingNewClaim = false
                Task { await router.claims.load() }
                router.open(.claim(claimId), name: name)
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
            // After the first sign-in, offer Face ID (spec §6.1).
            if session.lock.shouldOffer {
                offeringLock = true
            }
        }
        .alert("Use \(session.lock.methodName)?", isPresented: $offeringLock) {
            Button("Turn On") { Task { _ = await session.lock.enable() } }
            Button("Not Now", role: .cancel) { session.lock.markOffered() }
        } message: {
            Text("Lock AAGA Claims with \(session.lock.methodName) so only you can see your claims. You can change this in Account.")
        }
    }

    /// Top right: the notifications bell. (Search is the bar in Home's hero.)
    @ToolbarContentBuilder
    private func topBarButtons() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                router.showingNotifications = true
            } label: {
                Image(systemName: "bell")
                    .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                    .overlay(alignment: .topTrailing) {
                        if router.home.unreadCount > 0 {
                            UnreadBadge(count: router.home.unreadCount)
                        }
                    }
            }
            .accessibilityLabel(router.home.unreadCount > 0 ? "Notifications, \(router.home.unreadCount) unread" : "Notifications")
            .accessibilityIdentifier("notificationsBell")
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
            .background(Color.red, in: Capsule())
            .offset(x: 4, y: 2)
            .accessibilityHidden(true)
    }
}
