import PortalKit
import SwiftUI

/// Pushes a person's page inside the search sheet.
struct PersonRoute: Hashable {
    let id: String
    let name: String?
}

/// A colleague from search (staff only): their profile and Chatter feed. Replies are written and
/// edited right here.
struct PersonView: View {
    @State private var viewModel: PersonViewModel
    let name: String?

    init(api: PortalAPI, personId: String, name: String?) {
        _viewModel = State(initialValue: PersonViewModel(api: api, personId: personId))
        self.name = name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                profile
                SectionHeader("Chatter")
                ChatterFeedSection(model: viewModel.chatter, emptyMessage: "No Chatter posts yet.")
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground)
        .navigationTitle(name ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            if viewModel.person.value == nil { await viewModel.load() }
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profile: some View {
        switch viewModel.person {
        case .idle, .loading:
            SkeletonList(rows: 1)
        case .failed:
            ErrorStateView(subject: "this profile") { Task { await viewModel.load() } }
        case .loaded(let person, _):
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    Text(person.initials)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(BrandGradient.hero(.light), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name ?? "")
                            .font(.title3.bold())
                            .foregroundStyle(Color.textPrimary)
                        if let role = PortalFormat.nonEmpty([person.title, person.department].compactMap { $0 }.joined(separator: " · ")) {
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        if let place = PortalFormat.nonEmpty([person.city, person.state].compactMap { $0 }.joined(separator: ", ")) {
                            Label(place, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("personHeader")

                if person.email != nil || person.phone != nil || person.mobilePhone != nil {
                    Divider()
                    contact("envelope", person.email, url: person.email.map { "mailto:\($0)" })
                    contact("phone", person.phone, url: person.phone.map(telURL))
                    contact("iphone", person.mobilePhone, url: person.mobilePhone.map(telURL))
                }
                if let manager = PortalFormat.nonEmpty(person.managerName) {
                    Label("Reports to \(manager)", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                if let about = PortalFormat.nonEmpty(person.aboutMe) {
                    Text(about)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private func contact(_ icon: String, _ value: String?, url: String?) -> some View {
        if let value = PortalFormat.nonEmpty(value), let url = url.flatMap(URL.init(string:)) {
            Link(destination: url) {
                Label(value, systemImage: icon)
                    .font(.subheadline)
                    .frame(minHeight: Theme.minTapTarget, alignment: .leading)
            }
        }
    }

    private func telURL(_ number: String) -> String {
        "tel:" + number.filter { $0.isNumber || $0 == "+" }
    }

}

/// A Chatter feed: posts with their latest replies, an inline reply box on each post, and Edit on
/// the user's own replies. Used for a person's profile feed and a claim's Claim Feed.
struct ChatterFeedSection: View {
    let model: ChatterFeedViewModel
    let emptyMessage: String
    /// Show this many posts and scroll for the rest; nil shows them all.
    var visibleCount: Int? = nil
    @FocusState private var editFocused: Bool

    var body: some View {
        switch model.feed {
        case .idle, .loading:
            SkeletonList(rows: 2)
        case .failed:
            ErrorStateView(subject: "Chatter") { Task { await model.load() } }
        case .loaded(let posts, _):
            if posts.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else if let visibleCount {
                ScrollingStack(items: posts, visibleCount: visibleCount, spacing: Theme.Spacing.m, noun: "posts") { postCard($0) }
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    ForEach(posts) { post in
                        postCard(post)
                    }
                }
            }
        }
    }
    private func postCard(_ post: ChatterPost) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text([post.parentName.map { "on \($0)" }, PortalFormat.date(post.createdDate)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(post.text ?? "")
                .font(.body)
                .foregroundStyle(Color.textPrimary)

            if !post.replies.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let total = post.totalReplies, total > post.replies.count {
                        Text("Latest \(post.replies.count) of \(total) replies")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    ForEach(post.replies) { reply in
                        replyRow(reply)
                    }
                }
                .padding(.leading, Theme.Spacing.m)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.border).frame(width: 2)
                }
            }

            composer(post)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func replyRow(_ reply: ChatterReply) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(reply.authorName ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(PortalFormat.date(reply.createdDate))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if reply.isMine == true && model.editingReplyId != reply.id {
                    Button("Edit") { model.startEditing(reply) }
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                        .accessibilityLabel("Edit your reply")
                        .accessibilityIdentifier("editReply-\(reply.id)")
                }
            }
            if model.editingReplyId == reply.id {
                @Bindable var editing = model
                TextField("Reply", text: $editing.editText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(Theme.Spacing.s)
                    .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                    .focused($editFocused)
                    .onAppear { editFocused = true }
                    .accessibilityIdentifier("editReplyField")
                HStack {
                    Button("Cancel") { model.cancelEditing() }
                        .frame(minHeight: Theme.minTapTarget)
                    Spacer()
                    if model.saving.contains(reply.id) {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await model.saveEdit() } }
                            .bold()
                            .frame(minHeight: Theme.minTapTarget)
                            .disabled(model.editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("saveReply")
                    }
                }
                failure(for: reply.id, "We couldn't save your edit. You can only edit your own replies.")
            } else {
                Text(reply.text ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityIdentifier("replyText-\(reply.id)")
            }
        }
    }

    private func composer(_ post: ChatterPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField("Write a reply…", text: Binding(
                    get: { model.drafts[post.id] ?? "" },
                    set: { model.drafts[post.id] = $0 }
                ), axis: .vertical)
                .lineLimit(1...5)
                .padding(Theme.Spacing.s)
                .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("replyField-\(post.id)")
                if model.saving.contains(post.id) {
                    ProgressView()
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                } else {
                    Button {
                        Task { await model.sendReply(to: post.id) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                    }
                    .disabled(!model.canSend(post.id))
                    .accessibilityLabel("Send reply")
                    .accessibilityIdentifier("sendReply-\(post.id)")
                }
            }
            failure(for: post.id, "We couldn't post your reply. Please try again.")
        }
    }

    @ViewBuilder
    private func failure(for id: String, _ message: String) -> some View {
        if model.failedId == id {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.warning)
        }
    }
}
