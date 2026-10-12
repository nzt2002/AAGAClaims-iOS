import PortalKit
import SwiftUI

enum AppTab: Hashable {
    case home, claims, leads, support, account
}

struct MainTabView: View {
    let session: AppSession
    let user: CurrentUser

    @State private var selection: AppTab = .home
    @State private var home: HomeViewModel
    @State private var claims: ClaimsListViewModel
    @State private var leads: LeadsListViewModel
    @State private var cases: CasesListViewModel
    @State private var showingNotifications = false

    init(session: AppSession, user: CurrentUser) {
        self.session = session
        self.user = user
        _home = State(initialValue: HomeViewModel(api: session.api))
        _claims = State(initialValue: ClaimsListViewModel(api: session.api))
        _leads = State(initialValue: LeadsListViewModel(api: session.api))
        _cases = State(initialValue: CasesListViewModel(api: session.api))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack {
                    HomeView(viewModel: home, user: user, selectTab: { selection = $0 })
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Claims", systemImage: "doc.text", value: .claims) {
                NavigationStack {
                    ClaimsListView(viewModel: claims, openSupport: { selection = .support })
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Leads", systemImage: "person.2", value: .leads) {
                NavigationStack {
                    LeadsListView(viewModel: leads, openSupport: { selection = .support })
                        .demoBanner(session.isDemo)
                        .toolbar { bell }
                }
            }
            Tab("Support", systemImage: "questionmark.bubble", value: .support) {
                NavigationStack {
                    SupportView(viewModel: cases)
                        .demoBanner(session.isDemo)
                }
            }
            Tab("Account", systemImage: "person.crop.circle", value: .account) {
                NavigationStack {
                    AccountView(session: session, user: user, openSupport: { selection = .support })
                        .demoBanner(session.isDemo)
                }
            }
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsView(viewModel: home)
        }
        .task {
            // Home also drives the bell badge, so load it up front.
            await home.load()
        }
    }

    private var bell: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNotifications = true
            } label: {
                Image(systemName: home.unreadCount > 0 ? "bell.badge" : "bell")
                    .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
            }
            .accessibilityLabel(home.unreadCount > 0 ? "Notifications, \(home.unreadCount) unread" : "Notifications")
            .accessibilityIdentifier("notificationsBell")
        }
    }
}
