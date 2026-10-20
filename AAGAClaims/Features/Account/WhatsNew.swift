import SwiftUI

/// Release notes: shown once after sign-in when a new version is installed, and every version's
/// notes in Account → Release Notes. Add a `Release` at the top for each version.
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
        /// When it went to TestFlight, e.g. "Oct 19, 2026".
        let date: String
        let items: [Item]

        func items(isInternal: Bool) -> [Item] {
            items.filter { isInternal || !$0.staffOnly }
        }
    }

    static let releases: [Release] = [
        Release(version: "0.4.1", date: "Oct 19, 2026", items: [
            Item(icon: "sparkles", title: "A fresh welcome",
                 detail: "AAGA Claims opens with the Accurate Adjustments GA look, and sign-in starts from a welcome screen instead of a web page."),
        ]),
        Release(version: "0.4.0", date: "Oct 19, 2026", items: [
            Item(icon: "person.text.rectangle", title: "A clearer lead page",
                 detail: "The loss address is under the lead's name, lead progress folds away like a claim's, and Referred By has its own tab after Details."),
            Item(icon: "doc.badge.arrow.up", title: "Bigger files",
                 detail: "Upload documents and scans up to 25 MB, and open large files that wouldn't open before."),
            Item(icon: "textformat.size", title: "Easier to read at large text sizes",
                 detail: "Claim numbers, claim progress and task pages now lay out cleanly with the largest text settings."),
            Item(icon: "person.crop.circle.badge.xmark", title: "Delete your account",
                 detail: "You can ask us to delete your account and personal information from Account."),
            Item(icon: "stethoscope", title: "Problems reported automatically",
                 detail: "If the app crashes or stops responding, a report (with no personal information) is sent to our team so we can fix it."),
        ]),
        Release(version: "0.3.0", date: "Oct 19, 2026", items: [
            Item(icon: "bell.badge", title: "Notifications",
                 detail: "Get notified when there's a new update on your claim or a payment is recorded. Staff are also notified about @mentions and tasks assigned to them. Turn them on in Account."),
            Item(icon: "chart.bar.fill", title: "Payment progress",
                 detail: "The Payments tab shows how much has been collected toward your claim's total RCV, and how much is left."),
            Item(icon: "signpost.right.fill", title: "What each stage means",
                 detail: "Claim progress now explains, in plain words, what's happening at the current stage and what comes next."),
            Item(icon: "ipad.landscape", title: "iPad",
                 detail: "AAGA Claims runs on iPad, with your list and the claim or lead side by side."),
            Item(icon: "checkmark.circle.fill", title: "Work on tasks from their page",
                 detail: "Mark a task complete, edit it, or reassign it, without going to Salesforce. Events can be edited and reassigned too.",
                 staffOnly: true),
            Item(icon: "clock.arrow.circlepath", title: "Recent activity on leads, with emails",
                 detail: "Leads now have Recent activity, and emails sent and received on a claim or lead appear there, with their own page.",
                 staffOnly: true),
            Item(icon: "camera.on.rectangle", title: "Inspection photos and scanning",
                 detail: "Take several photos with a caption each, or scan documents into a PDF, straight to the claim's files.",
                 staffOnly: true),
            Item(icon: "wifi.slash", title: "Post without a signal",
                 detail: "Posts and replies written offline wait on your phone and send as soon as you're back online.",
                 staffOnly: true),
            Item(icon: "doc.text.magnifyingglass", title: "Release notes",
                 detail: "See the notes for every version, any time, in Account → Release Notes."),
        ]),
        Release(version: "0.2.3", date: "Oct 19, 2026", items: [
            Item(icon: "arrow.uturn.backward", title: "Back takes you back",
                 detail: "Claims and leads open on top of the screen you're on, so Back returns there. Search now always opens the claim you tap."),
            Item(icon: "person.crop.rectangle.stack", title: "Every claim and lead you're on",
                 detail: "My Claims and My Leads now list every record you're named on, as owner, account manager, adjuster, desk adjuster or creator.",
                 staffOnly: true),
            Item(icon: "bubble.left.and.text.bubble.right", title: "A tidier Claim Feed",
                 detail: "Posts fold up to a short preview; tap one to see it all. Reply opens a reply box, and you can attach a photo or file to posts and replies.",
                 staffOnly: true),
            Item(icon: "number", title: "Claim Id, ready to copy",
                 detail: "A claim's Id is under Details with a Copy button, and new emails include it so replies file on the claim.",
                 staffOnly: true),
        ]),
        Release(version: "0.2.2", date: "Oct 19, 2026", items: [
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
        Release(version: "0.2.1", date: "Oct 19, 2026", items: [
            Item(icon: "lock.shield", title: "Sign-in fix",
                 detail: "The sign-in page no longer resets when you leave the app to fetch a verification code."),
        ]),
        Release(version: "0.2.0", date: "Oct 14, 2026", items: [
            Item(icon: "rectangle.stack.badge.plus", title: "Staff tools on claims",
                 detail: "Apply Payments, Edit Claim, Add Contact, Update Address, Change Owner, Proof of Loss, Post and Send an Email, right from the claim page.",
                 staffOnly: true),
            Item(icon: "person.2.fill", title: "Lead tools",
                 detail: "Convert to Account, Edit, Post and the e-sign agreement preview on the lead page.",
                 staffOnly: true),
            Item(icon: "magnifyingglass", title: "Search people and Chatter",
                 detail: "Find colleagues in Search, see their Chatter, and reply inline.",
                 staffOnly: true),
            Item(icon: "mappin.and.ellipse", title: "Address lookup",
                 detail: "Addresses fill in as you type on New Lead and New Claim."),
            Item(icon: "doc.badge.plus", title: "New Claim",
                 detail: "Create a claim from Home, with the same duplicate checks as Salesforce.",
                 staffOnly: true),
        ]),
        Release(version: "0.1.0", date: "Oct 13, 2026", items: [
            Item(icon: "house.fill", title: "First release",
                 detail: "Your claims and leads with their progress, updates, files and payments; Support; notifications of updates; search; Face ID; photo and file uploads; and offline viewing."),
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

/// Account → Release Notes: every version's notes, newest first, with the installed one marked.
struct ReleaseNotesView: View {
    let isInternal: Bool

    var body: some View {
        List {
            ForEach(WhatsNew.releases, id: \.version) { release in
                let items = release.items(isInternal: isInternal)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                IconBadge(systemName: item.icon, size: 32, filled: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        HStack(spacing: Theme.Spacing.s) {
                            Text("Version \(release.version)")
                            if release.version == WhatsNew.currentVersion {
                                Text("Current")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.surface)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.brandPrimary, in: Capsule())
                                    .accessibilityIdentifier("currentVersionBadge")
                            }
                            Spacer()
                            Text(release.date)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("release-\(release.version)")
                    }
                }
            }
        }
        .navigationTitle("Release Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
