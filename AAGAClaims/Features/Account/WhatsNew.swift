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
        Release(version: "3.2.0", date: "Nov 4, 2026", items: [
            Item(icon: "checklist.checked", title: "Pick files with checkboxes",
                 detail: "When Alex asks which estimate, report or document to use, tick the files in the list that pops up and tap Use. No more typing file names.",
                 staffOnly: true),
        ]),
        Release(version: "3.1.0", date: "Nov 4, 2026", items: [
            Item(icon: "sun.max", title: "What needs me today?",
                 detail: "Ask Alex for your day: overdue and due-today tasks, new carrier emails on your claims, payments collected and claims that have gone quiet.",
                 staffOnly: true),
            Item(icon: "person.crop.rectangle", title: "Alex knows your leads",
                 detail: "Open Alex on a lead and he picks it up: contact details, the loss, status, tasks, notes and files.",
                 staffOnly: true),
            Item(icon: "arrow.triangle.2.circlepath", title: "Update a claim's status",
                 detail: "\"Move this to Negotiations; next step: wait for re-inspection.\" Alex shows the change and makes it after your yes.",
                 staffOnly: true),
            Item(icon: "photo.on.rectangle", title: "Photos in supplement requests",
                 detail: "Supplement documents from Alex now include the claim's photos, grouped by roof area.",
                 staffOnly: true),
            Item(icon: "dollarsign.circle", title: "Clearer carrier payouts",
                 detail: "Alex now accounts for prior payments and each coverage on supplement estimates.",
                 staffOnly: true),
        ]),
        Release(version: "3.0.0", date: "Nov 4, 2026", items: [
            Item(icon: "paperplane", title: "Alex sends your emails",
                 detail: "Ask Alex to email the carrier: he drafts it, shows you who it goes to, and sends it only after you say yes. Sent emails are logged on the claim, and replies file back to it.",
                 staffOnly: true),
            Item(icon: "checklist", title: "Tasks and notes with Alex",
                 detail: "\"Remind me to call State Farm Friday\", \"mark the inspection task done\", \"give these tasks to Daniel\" or \"note that the homeowner sent photos\": Alex previews each one and waits for your yes.",
                 staffOnly: true),
            Item(icon: "dollarsign.circle", title: "What is the carrier paying?",
                 detail: "Ask Alex and he reads the latest estimate: RCV, depreciation, deductible, the net payment now and what's still recoverable once the work is done.",
                 staffOnly: true),
        ]),
        Release(version: "2.5.0", date: "Nov 2, 2026", items: [
            Item(icon: "doc.text.magnifyingglass", title: "Open files from Alex",
                 detail: "When Alex mentions a document, tap its name to open it right in the app.",
                 staffOnly: true),
            Item(icon: "checkmark.bubble", title: "Alex finds your claim more reliably",
                 detail: "If Alex isn't sure which claim you mean, for example two claims with the same name, he now asks instead of saying it can't be found.",
                 staffOnly: true),
        ]),
        Release(version: "2.4.2", date: "Nov 2, 2026", items: [
            Item(icon: "bubble.left.fill", title: "A bigger Alex button",
                 detail: "Alex's chat bubble now fills the button, with ALEX in large letters.",
                 staffOnly: true),
        ]),
        Release(version: "2.4.1", date: "Nov 2, 2026", items: [
            Item(icon: "bubble.left.fill", title: "A new look for Alex",
                 detail: "The Ask Alex button is now a chat bubble with Alex's name on it.",
                 staffOnly: true),
            Item(icon: "briefcase", title: "Support has a new icon",
                 detail: "Support is the briefcase in the bottom row. On Support, tap the question mark at the top right to ask a question."),
        ]),
        Release(version: "2.4.0", date: "Nov 2, 2026", items: [
            Item(icon: "clock.arrow.circlepath", title: "Your chats with Alex are saved",
                 detail: "Chats are saved when you close Alex. Open Past chats from the clock in Alex's top bar, or Alex chats on any claim or lead to see what the team asked.",
                 staffOnly: true),
            Item(icon: "hand.thumbsup", title: "Tell us if Alex helped",
                 detail: "When you close a chat, tap Yes or No, and if No, tap what went wrong. It helps us make Alex better.",
                 staffOnly: true),
        ]),
        Release(version: "2.2.2", date: "Nov 2, 2026", items: [
            Item(icon: "sparkles", title: "Alex finds the claim you're on",
                 detail: "Alex now finds your claim even after you've opened an activity, case or file from it, and tells apart claims with the same name.",
                 staffOnly: true),
        ]),
        Release(version: "2.2.1", date: "Nov 2, 2026", items: [
            Item(icon: "sparkles", title: "Shorter, cleaner answers from Alex",
                 detail: "Alex answers in a bold headline and a few bullet points, and no longer shows record IDs.",
                 staffOnly: true),
        ]),
        Release(version: "2.2.0", date: "Nov 2, 2026", items: [
            Item(icon: "sparkles", title: "Alex knows what you're looking at",
                 detail: "Open Alex from a claim or lead and he starts with that record: his first reply confirms it, and he sticks with it until you mention another claim.",
                 staffOnly: true),
        ]),
        Release(version: "2.1.1", date: "Nov 2, 2026", items: [
            Item(icon: "person.badge.key", title: "Simpler sign-in",
                 detail: "The sign-in and welcome screens have clearer wording."),
            Item(icon: "sparkles", title: "Alex, by name",
                 detail: "The chat window is titled Alex, and Alex's replies are labelled Alex.",
                 staffOnly: true),
        ]),
        Release(version: "2.1.0", date: "Nov 2, 2026", items: [
            Item(icon: "sparkles", title: "Ask Alex, your claims assistant",
                 detail: "Tap the sparkles at the top right to chat with Alex. Ask about a claim's status, payments, deductible or next steps, or what the policy and estimate PDFs say.",
                 staffOnly: true),
            Item(icon: "square.and.pencil", title: "Drafts and portal updates",
                 detail: "Alex drafts updates and emails for homeowners, carriers and contractors. Alex can post a homeowner update to the portal, but only after showing you a preview and getting your OK.",
                 staffOnly: true),
            Item(icon: "chart.bar.doc.horizontal", title: "Reports across your claims",
                 detail: "Ask which claims have gone quiet, what's outstanding by carrier, or what's on your plate.",
                 staffOnly: true),
        ]),
        Release(version: "2.0.0", date: "Nov 1, 2026", items: [
            Item(icon: "questionmark.bubble", title: "A Cases tab on every claim and lead",
                 detail: "The last tab on a claim or lead lists the questions and cases opened for it. Tap one to see the conversation. Case replies also appear in Updates."),
            Item(icon: "checkmark.circle", title: "Mark a case as completed",
                 detail: "Question answered? Tap Mark as Completed at the end of the case to close it."),
            Item(icon: "map", title: "Tap the address for directions",
                 detail: "The loss address on claims and leads now has its own card. Tap it to open Maps. Lead pages are green, header and buttons, so you can tell leads from claims at a glance."),
            Item(icon: "bell.badge", title: "More notifications",
                 detail: "Get notified about new portal updates and replies to your cases."),
            Item(icon: "switch.2", title: "Choose your notifications",
                 detail: "In your account (tap your initials), turn each kind of notification on or off: updates, payments, support replies and more."),
            Item(icon: "bubble.left.and.text.bubble.right", title: "Case replies in the Chatter feed",
                 detail: "Replies on a case are posted to its claim's or lead's Chatter feed, so the whole team sees them.",
                 staffOnly: true),
            Item(icon: "bell.badge.fill", title: "Staff notifications",
                 detail: "Staff are also notified about Chatter posts on their claims and leads, case updates, and e-sign documents being viewed, signed or declined.",
                 staffOnly: true),
            Item(icon: "envelope", title: "Email ID on every email",
                 detail: "Emails written from a claim or lead end with its email ID, so replies CC'd to the tracking mailbox are filed on the record.",
                 staffOnly: true),
        ]),
        Release(version: "1.1.0", date: "Oct 21, 2026", items: [
            Item(icon: "sparkles", title: "A fresh new look, and a new name",
                 detail: "The app is now called ProClaimer, updated for the latest iPhone design with bolder headers, cleaner cards and a tab bar that steps aside while you scroll."),
            Item(icon: "exclamationmark.circle", title: "Needs attention",
                 detail: "Home now leads with what needs you today: overdue tasks, unread updates, recent payments and unsigned agreements."),
            Item(icon: "magnifyingglass", title: "Search has its own tab",
                 detail: "Tap the magnifying glass at the bottom right to search claims, leads and cases from anywhere."),
            Item(icon: "line.3.horizontal.decrease.circle", title: "Filter and sort",
                 detail: "Narrow your claims and leads with one tap on the filters above the list, and sort by date or name. The app remembers your choice."),
            Item(icon: "chart.bar.fill", title: "Your claim at a glance",
                 detail: "The top of each claim shows its stage and progress, and a chart shows how much has been collected."),
            Item(icon: "person.crop.circle", title: "Account has moved",
                 detail: "Tap the circle with your initials at the top right to open your account and settings."),
        ]),
        Release(version: "1.0.0", date: "Oct 20, 2026", items: [
            Item(icon: "star.fill", title: "ProClaimer 1.0",
                 detail: "Thank you for testing. This is the version going to the App Store, with a new app icon."),
            Item(icon: "location.slash", title: "Photos stay private",
                 detail: "Photos you upload no longer include where they were taken."),
            Item(icon: "faceid", title: "Sign in with Face ID",
                 detail: "With Face ID turned on, signing back in is a glance. No need to type your username and password."),
            Item(icon: "key.fill", title: "Reset your password in the app",
                 detail: "Tap \"Forgot password?\" on the sign-in screen and we'll email you a code to set a new one."),
        ]),
        Release(version: "0.4.2", date: "Oct 19, 2026", items: [
            Item(icon: "person.badge.key", title: "Sign in right in the app",
                 detail: "Enter your username and password on the app's own sign-in screen. No more web page. Staff sign in with \"Staff? Sign in with Salesforce\"."),
        ]),
        Release(version: "0.4.1", date: "Oct 19, 2026", items: [
            Item(icon: "sparkles", title: "A fresh welcome",
                 detail: "ProClaimer opens with the ProClaimer look, and sign-in starts from a welcome screen instead of a web page."),
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
                 detail: "ProClaimer runs on iPad, with your list and the claim or lead side by side."),
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
                        Text("ProClaimer \(release.version)")
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
