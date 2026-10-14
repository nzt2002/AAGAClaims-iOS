import Network
import Observation
import PortalKit
import SwiftUI

/// Network reachability. `-SimulateOffline YES` forces offline for tests and demos.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private let simulateOffline = UserDefaults.standard.bool(forKey: "SimulateOffline")

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        if simulateOffline {
            isOnline = false
            onChange(false)
            return
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                onChange(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "Connectivity"))
    }
}

/// What the offline banner shows: when the cached data on screen was saved (spec §7).
@MainActor
@Observable
final class OfflineState {
    private(set) var isOffline = false
    /// The oldest save time of cached data shown since going offline.
    private(set) var showingDataFrom: Date?

    func setOffline(_ offline: Bool) {
        isOffline = offline
        if !offline {
            showingDataFrom = nil
        }
    }

    func servedFromCache(savedAt: Date) {
        isOffline = true
        showingDataFrom = min(showingDataFrom ?? savedAt, savedAt)
    }
}

extension EnvironmentValues {
    /// True while offline: write actions are disabled (spec §7).
    @Entry var isOffline = false
}

/// "You're offline. Showing data from {time}." (spec §7)
struct OfflineBanner: View {
    let showingDataFrom: Date?

    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(Color.textPrimary)
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Color.warning.opacity(0.18))
            .accessibilityIdentifier("offlineBanner")
    }

    private var text: String {
        guard let date = showingDataFrom else { return "You're offline." }
        let time = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
        return "You're offline. Showing data from \(time)."
    }
}

/// Explains why a write action is disabled.
struct OfflineHint: View {
    var body: some View {
        Label("Available when you're back online.", systemImage: "wifi.slash")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
    }
}

extension View {
    /// Disables a write action while offline, with a hint for pointer and VoiceOver users.
    func disabledWhenOffline(_ isOffline: Bool) -> some View {
        disabled(isOffline)
            .help(isOffline ? "Available when you're back online." : "")
            .accessibilityHint(isOffline ? "Available when you're back online." : "")
    }
}

extension EnvironmentValues {
    /// Staff (Salesforce user type Standard): claim actions, Claim Feed, People.
    @Entry var isInternalUser = false
    /// The org's web address, for Salesforce-only pages. Nil in demo mode.
    @Entry var salesforceInstanceURL: URL? = nil
}
