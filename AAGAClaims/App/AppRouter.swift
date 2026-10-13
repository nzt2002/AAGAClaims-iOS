import Observation
import PortalKit
import SwiftUI
import UserNotifications

/// A claim to open by id, e.g. from an update or a support case.
struct ClaimRoute: Hashable {
    let id: String
    let name: String?
}

/// Cross-tab navigation: which tab is showing, each tab's stack, and the sheets other tabs can
/// open (Home tiles and quick actions, the Update sheet's "Open Claim" button, "View case").
@MainActor
@Observable
final class AppRouter {
    var selection: AppTab = .home
    var claimsPath = NavigationPath()
    var leadsPath = NavigationPath()
    var supportPath = NavigationPath()

    var showingNotifications = false
    var showingSubmitLead = false
    var showingRequestAssistance = false
    var showingNewTask = false
    /// New Claim (staff only).
    var showingNewClaim = false
    var showingNewEvent = false
    var showingSearch = false
    /// The Update sheet opened from Home's recent activity.
    var homeUpdate: ActivityItem?
    /// The Update sheet opened from the Notifications sheet.
    var notificationUpdate: ActivityItem?

    let home: HomeViewModel
    let claims: ClaimsListViewModel
    let leads: LeadsListViewModel
    let cases: CasesListViewModel

    init(api: PortalAPI, isInternalUser: Bool) {
        home = HomeViewModel(api: api, isInternalUser: isInternalUser)
        claims = ClaimsListViewModel(api: api)
        leads = LeadsListViewModel(api: api)
        cases = CasesListViewModel(api: api)
    }

    /// Reloads anything more than 5 minutes old when the app returns to the foreground (spec §7).
    func refreshStale() {
        if home.state.isStale() { Task { await home.load() } }
        if claims.state.isStale() { Task { await claims.load() } }
        if leads.state.isStale() { Task { await leads.load() } }
        if cases.state.isStale() { Task { await cases.load() } }
    }

    // MARK: - Home tiles and status overview

    func showClaims(stage: String? = nil, openOnly: Bool = false) {
        claims.clearFilters()
        claims.searchText = ""
        claims.statusFilter = stage
        claims.openOnly = openOnly
        claimsPath = NavigationPath()
        selection = .claims
    }

    func showLeads(openOnly: Bool = false) {
        leads.clearFilters()
        leads.searchText = ""
        leads.openOnly = openOnly
        leadsPath = NavigationPath()
        selection = .leads
    }

    // MARK: - Quick actions

    func submitLead() {
        leadsPath = NavigationPath()
        selection = .leads
        showingSubmitLead = true
    }

    func requestAssistance() {
        supportPath = NavigationPath()
        selection = .support
        showingRequestAssistance = true
    }

    // MARK: - Opening records

    /// Opens an update: marks it read and shows the Update sheet.
    func present(_ item: ActivityItem, fromNotifications: Bool) {
        if fromNotifications {
            notificationUpdate = item
        } else {
            homeUpdate = item
        }
        if !item.isRead {
            Task { await home.markRead([item.commentId]) }
        }
    }

    /// Closes any sheets and opens the claim or lead in its tab.
    func open(_ record: RecordRef, name: String?) {
        homeUpdate = nil
        notificationUpdate = nil
        showingNotifications = false
        switch record {
        case .claim(let id):
            claimsPath = NavigationPath()
            claimsPath.append(ClaimRoute(id: id, name: name))
            selection = .claims
        case .lead(let id):
            leadsPath = NavigationPath()
            leadsPath.append(LeadRoute(id: id, name: name))
            selection = .leads
        }
    }

    /// Opens a deep link, universal link or push (spec §8).
    func handle(_ link: DeepLink) {
        switch link {
        case .claim(let id):
            open(.claim(id), name: nil)
        case .lead(let id):
            open(.lead(id), name: nil)
        case .supportCase(let id):
            homeUpdate = nil
            notificationUpdate = nil
            showingNotifications = false
            openSupport(caseId: id)
        case .update(let record, let commentId):
            open(record, name: nil)
            if let commentId {
                Task {
                    await home.markRead([commentId])
                    await home.load()
                }
            }
        }
    }

    /// Opens a search result in its tab.
    func open(_ result: SearchResult) {
        switch result.type {
        case .claim: open(.claim(result.id), name: result.title)
        case .prospect: open(.lead(result.id), name: result.title)
        case .supportCase: openSupport(caseId: result.id)
        // People open inside the search sheet.
        case .user: break
        }
    }

    func openSupport(caseId: String?) {
        supportPath = NavigationPath()
        if let caseId {
            cases.filter = .open
            supportPath.append(CaseRoute(id: caseId))
        }
        selection = .support
        Task { await cases.load() }
    }
}

/// The app icon badge shows the unread update count (spec §8). It only appears once the user
/// has allowed notifications, which is asked for with push in milestone 6.
enum AppBadge {
    static func update(_ count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}
