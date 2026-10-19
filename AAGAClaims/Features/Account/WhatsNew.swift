import SwiftUI

/// Release notes, shown once after sign-in when a new version is installed, and from Account.
/// Add a `Release` at the top for each version that has something to tell users.
enum WhatsNew {
    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        /// Staff features aren't mentioned to homeowners.
        var staffOnly = false
        var id: String { title }
    }

    struct Release {
        let version: String
        let items: [Item]

        func items(isInternal: Bool) -> [Item] {
            items.filter { isInternal || !$0.staffOnly }
        }
    }

    static let releases: [Release] = [
        Release(version: "0.2.2", items: [
            Item(icon: "clock.arrow.circlepath", title: "Recent activity on claims",
                 detail: "A claim's tasks, calls and events are now on its page, open items first. Tap one to see its details.",
                 staffOnly: true),
            Item(icon: "checklist", title: "Tasks and events from any claim or lead",
                 detail: "Use Task or Event on the record page. Subjects are suggested as you type, like on desktop.",
                 staffOnly: true),
            Item(icon: "at", title: "@mentions that work",
                 detail: "Type @ in a post or reply to notify a colleague.",
                 staffOnly: true),
            Item(icon: "signature", title: "E-Sign without signing in again",
                 detail: "Agreement previews and Proof of Loss documents now open already signed in.",
                 staffOnly: true),
            Item(icon: "lock.shield", title: "Smoother sign-in",
                 detail: "Switching apps to get your verification code no longer clears the sign-in page."),
        ]),
    ]

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// This version's notes for this user.
    static func current(isInternal: Bool) -> Release? {
        guard let release = releases.first(where: { $0.version == currentVersion }),
              !release.items(isInternal: isInternal).isEmpty else { return nil }
        return release
    }

    private static let seenKey = "WhatsNewSeenVersion"

    /// The notes to show at sign-in: once per version. UI tests skip it unless they ask for it.
    static func pending(isInternal: Bool, defaults: UserDefaults = .standard) -> Release? {
        if defaults.bool(forKey: "UITestDemo") && !defaults.bool(forKey: "ShowWhatsNew") { return nil }
        guard defaults.string(forKey: seenKey) != currentVersion else { return nil }
        return current(isInternal: isInternal)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: seenKey)
    }
}

extension WhatsNew.Release: Identifiable {
    var id: String { version }
}

/// "What's new in version x": one row per change, and Continue.
struct WhatsNewSheet: View {
    let release: WhatsNew.Release
    let isInternal: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("What's New")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.textPrimary)
                        Text("AAGA Claims \(release.version)")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Theme.Spacing.l)

                    ForEach(release.items(isInternal: isInternal)) { item in
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            IconBadge(systemName: item.icon, size: 44, filled: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("whatsNewItem")
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.brandPrimary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.m)
                .accessibilityIdentifier("whatsNewContinue")
            }
            .background(Color.appBackground)
        }
    }
}
