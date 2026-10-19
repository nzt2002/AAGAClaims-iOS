import PortalKit
import QuickLook
import SwiftUI

/// A Chatter feed: a person's profile feed or a claim's (or lead's) Claim Feed.
///
/// Each post is a collapsible card. Collapsed, it shows the author, date, the start of the text and
/// how many replies and files it has. Expanded, it shows the whole post, its files and its latest
/// replies, with Edit on the user's own replies. Reply opens a reply box (three lines, @mentions,
/// and on claims and leads a file).
struct ChatterFeedSection: View {
    let model: ChatterFeedViewModel
    let emptyMessage: String
    /// Show this many posts and scroll for the rest; nil shows them all.
    var visibleCount: Int? = nil

    @State private var expanded: Set<String> = []
    /// The post whose reply box is open.
    @State private var replyingTo: String?
    @State private var preview: PreviewFile?
    @State private var openingFileId: String?
    @State private var previewError: String?

    var body: some View {
        content
            .quickLookPreview($preview.url)
            .onChange(of: preview) { old, new in
                // Delete the temporary copy once Quick Look closes (spec §8: no file caching).
                if new == nil, let old {
                    try? FileManager.default.removeItem(at: old.directory)
                }
            }
            .alert("Couldn't open file", isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(previewError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
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

    // MARK: - Post

    private func isExpanded(_ post: ChatterPost) -> Bool {
        expanded.contains(post.id)
    }

    private func toggle(_ post: ChatterPost) {
        withAnimation(.snappy) {
            if expanded.contains(post.id) {
                expanded.remove(post.id)
                if replyingTo == post.id { replyingTo = nil }
            } else {
                expanded.insert(post.id)
            }
        }
    }

    private func postCard(_ post: ChatterPost) -> some View {
        let open = isExpanded(post)
        let files = post.attachments ?? []
        let replyCount = max(post.totalReplies ?? 0, post.replies.count)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { toggle(post) } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.authorName ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text([post.parentName.map { "on \($0)" }, PortalFormat.date(post.createdDate)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                    Text(mentionText(post.text ?? "", mentions: post.mentions))
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(open ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Collapses the post" : "Expands the post")
            .accessibilityAddTraits(open ? .isSelected : [])
            .accessibilityIdentifier("togglePost-\(post.id)")

            if open {
                if !files.isEmpty {
                    attachmentList(files)
                }
                replies(post)
            }

            HStack(spacing: Theme.Spacing.m) {
                Button {
                    withAnimation(.snappy) {
                        expanded.insert(post.id)
                        replyingTo = post.id
                    }
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(replyingTo == post.id)
                .accessibilityIdentifier("replyButton-\(post.id)")
                Spacer()
                if !open {
                    summary(replies: replyCount, files: files.count)
                }
            }

            if replyingTo == post.id {
                composer(post)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    /// "2 replies · 1 file", for a collapsed post.
    @ViewBuilder
    private func summary(replies: Int, files: Int) -> some View {
        let parts = [
            replies > 0 ? "\(replies) \(replies == 1 ? "reply" : "replies")" : nil,
            files > 0 ? "\(files) \(files == 1 ? "file" : "files")" : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private func replies(_ post: ChatterPost) -> some View {
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
                MentionField(prompt: "Reply", draft: $editing.editDraft, search: model.mentionCandidates,
                             lineLimit: 3...8, autofocus: true, identifier: "editReplyField")
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
                Text(mentionText(reply.text ?? "", mentions: reply.mentions))
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityIdentifier("replyText-\(reply.id)")
            }
            if let files = reply.attachments, !files.isEmpty {
                attachmentList(files)
            }
        }
    }

    // MARK: - Reply box

    private func composer(_ post: ChatterPost) -> some View {
        let files = model.attachments[post.id] ?? []
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            MentionField(prompt: "Write a reply… (type @ to mention)", draft: Binding(
                get: { model.drafts[post.id] ?? MentionDraft() },
                set: { model.drafts[post.id] = $0 }
            ), search: model.mentionCandidates, lineLimit: 3...8, autofocus: true, identifier: "replyField-\(post.id)")

            if !files.isEmpty || model.uploading.contains(post.id) {
                DraftAttachments(files: files, isUploading: model.uploading.contains(post.id)) { file in
                    model.removeAttachment(file.id, from: post.id)
                }
            }
            if let error = model.attachmentErrors[post.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
            }

            HStack(spacing: Theme.Spacing.s) {
                if model.supportsAttachments {
                    FileSourceMenu(maxCount: model.maxFiles(for: post.id), onPicked: { uploads in
                        Task { await model.attach(uploads, to: post.id) }
                    }) {
                        Image(systemName: "paperclip")
                            .font(.body.weight(.semibold))
                            .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .disabled(!model.canAttach(to: post.id))
                    .accessibilityLabel("Attach a file")
                    .accessibilityIdentifier("attachReply-\(post.id)")
                }
                Spacer()
                Button("Cancel") {
                    withAnimation(.snappy) { replyingTo = nil }
                    model.discardDraft(post.id)
                }
                .frame(minHeight: Theme.minTapTarget)
                .accessibilityIdentifier("cancelReply-\(post.id)")
                if model.saving.contains(post.id) {
                    ProgressView()
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                } else {
                    Button {
                        Task {
                            if await model.sendReply(to: post.id) {
                                withAnimation(.snappy) { replyingTo = nil }
                            }
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.brandPrimary)
                    .disabled(!model.canSend(post.id))
                    .accessibilityLabel("Send reply")
                    .accessibilityIdentifier("sendReply-\(post.id)")
                }
            }
            failure(for: post.id, "We couldn't post your reply. Please try again.")
        }
    }

    // MARK: - Files

    private func attachmentList(_ files: [ChatterAttachment]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(files) { file in
                Button {
                    Task { await open(file) }
                } label: {
                    AttachmentChip(file: file, isLoading: openingFileId == file.id)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the file")
                .accessibilityIdentifier("attachment-\(file.id)")
            }
        }
    }

    private func open(_ file: ChatterAttachment) async {
        openingFileId = file.id
        defer { openingFileId = nil }
        do {
            let data = try await model.fileContent(file.id)
            preview = try PreviewFile.write(data: data, title: file.title, fileType: file.fileType ?? file.fileExtension)
        } catch PortalAPIError.offline {
            previewError = "You're offline. Files open when you're back online."
        } catch {
            previewError = "Please try again, or contact support if this keeps happening."
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

/// A file on a post or reply: icon, name and size.
struct AttachmentChip: View {
    let file: ChatterAttachment
    var isLoading = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: FilesList.icon(for: file.fileType ?? file.fileExtension))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.title ?? "File")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                if let size = file.contentSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if isLoading {
                ProgressView()
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.minTapTarget)
        .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Files picked for a draft post or reply, each with a remove button, plus an uploading row.
struct DraftAttachments: View {
    let files: [ChatterAttachment]
    let isUploading: Bool
    let remove: (ChatterAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(files) { file in
                HStack(spacing: Theme.Spacing.xs) {
                    AttachmentChip(file: file)
                    Button { remove(file) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(file.title ?? "file")")
                    .accessibilityIdentifier("removeAttachment-\(file.id)")
                }
            }
            if isUploading {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("Uploading…")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
