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

    init(session: AppSession, user: CurrentUser) {
        self.session = session
        self.user = user
        _router = State(initialValue: AppRouter(api: session.api))
    }

    var body: some View {
        TabView(selection: $router.selection) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack {
                    HomeView(router: router, user: user)
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Claims", systemImage: "doc.text", value: .claims) {
                NavigationStack(path: $router.claimsPath) {
                    ClaimsListView(viewModel: router.claims, api: session.api, openSupport: { router.openSupport(caseId: nil) })
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Leads", systemImage: "person.2", value: .leads) {
                NavigationStack(path: $router.leadsPath) {
                    LeadsListView(viewModel: router.leads, path: $router.leadsPath, showingSubmit: $router.showingSubmitLead,
                                  api: session.api, userEmail: user.email,
                                  openSupport: { router.openSupport(caseId: nil) })
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Support", systemImage: "questionmark.bubble", value: .support) {
                NavigationStack(path: $router.supportPath) {
                    SupportView(viewModel: router.cases, path: $router.supportPath,
                                showingRequest: $router.showingRequestAssistance, api: session.api)
                        .demoBanner(session.isDemo)
                }
            }
            Tab("Account", systemImage: "person.crop.circle", value: .account) {
                NavigationStack {
                    AccountView(session: session, user: user, openSupport: { router.openSupport(caseId: nil) })
                        .demoBanner(session.isDemo)
                }
            }
        }
        .environment(\.openSupport, OpenSupportAction { caseId in router.openSupport(caseId: caseId) })
        .opensWebLinksInSafari($safariLink)
        .sheet(isPresented: $router.showingNotifications) {
            NotificationsView(router: router)
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
    }

    private var bell: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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
