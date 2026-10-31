import PortalKit
import SwiftUI

/// Case detail with a chat-style thread and reply composer (spec §6.9).
struct CaseDetailView: View {
    @State private var viewModel: CaseDetailViewModel
    @Environment(\.scenePhase) private var scenePhase

    @FocusState private var replyFocused: Bool
    @Environment(\.isOffline) private var isOffline
    @Environment(\.isInternalUser) private var isInternal
    @State private var confirmingComplete = false

    init(caseId: String, api: PortalAPI) {
        _viewModel = State(initialValue: CaseDetailViewModel(caseId: caseId, api: api))
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.state.value == nil {
                    await viewModel.load()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Back in the foreground with data more than 5 minutes old (spec §7).
                if phase == .active, viewModel.state.isStale() {
                    Task { await viewModel.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView { SkeletonList(rows: 3).padding(Theme.Spacing.l) }
        case .failed(.notFound):
            ContentUnavailableView(
                "Case not found",
                systemImage: "questionmark.bubble",
                description: Text("This case isn't available on your account.")
            )
        case .failed:
            ErrorStateView(subject: "this case") { Task { await viewModel.load() } }
        case .loaded(let detail, _):
            loaded(detail)
        }
    }

    private func loaded(_ detail: SupportCaseDetail) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    CaseHeader(detail: detail)

                    if let description = PortalFormat.nonEmpty(detail.description) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            SectionHeading("Your request")
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                        }
                        .cardStyle()
                    }

                    SectionHeading("Case updates")
                    if viewModel.comments.isEmpty {
                        Text("No updates have been posted yet.")
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        VStack(spacing: Theme.Spacing.m) {
                            ForEach(viewModel.comments) { comment in
                                MessageBubble(comment: comment)
                                    .id(comment.id)
                            }
                        }
                    }

                    // The end of the case: homeowners close it themselves once they're happy.
                    if !isInternal {
                        completeSection(detail)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .refreshable { await viewModel.load() }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                composer {
                    if let last = viewModel.comments.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completeSection(_ detail: SupportCaseDetail) -> some View {
        if SupportCase.isClosedStatus(detail.status) {
            Label("This case is \(detail.status?.lowercased() ?? "closed").", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.success)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityIdentifier("caseCompletedLabel")
        } else {
            VStack(spacing: Theme.Spacing.xs) {
                Button {
                    confirmingComplete = true
                } label: {
                    Group {
                        if viewModel.isCompleting {
                            ProgressView()
                        } else {
                            Label("Mark as Completed", systemImage: "checkmark.circle")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(.success)
                .disabled(!viewModel.canComplete)
                .disabledWhenOffline(isOffline)
                .accessibilityIdentifier("completeCase")
                if viewModel.completeError != nil {
                    Label("We couldn't update this case. Please try again.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
                Text("Your question has been answered? Mark the case completed to close it.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .confirmationDialog("Mark this case as completed?", isPresented: $confirmingComplete, titleVisibility: .visible) {
                Button("Mark as Completed") {
                    Task { await viewModel.complete() }
                }
            } message: {
                Text("We'll close the case. You can always ask a new question.")
            }
        }
    }

    private func composer(onSent: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if isOffline {
                OfflineHint()
            }
            if viewModel.replyError != nil {
                Label("We couldn't send your reply. Please try again.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField("Write a reply", text: $viewModel.replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($replyFocused)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(viewModel.isReplyOverLimit ? Color.warning : Color.border, lineWidth: 1)
                    )
                    .disabledWhenOffline(isOffline)
                    .accessibilityIdentifier("replyText")

                Button {
                    Task {
                        if await viewModel.sendReply() {
                            replyFocused = false
                            onSent()
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                        }
                    }
                    .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                }
                .disabled(!viewModel.canSendReply || isOffline)
                .accessibilityLabel("Send reply")
                .accessibilityIdentifier("sendReply")
            }
            if !viewModel.replyText.isEmpty {
                Text("\(viewModel.replyText.count.formatted()) / \(viewModel.replyLimit.formatted())")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.isReplyOverLimit ? Color.warning : Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(viewModel.replyText.count) of \(viewModel.replyLimit) characters")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }
}

private struct CaseHeader: View {
    let detail: SupportCaseDetail

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                Text(detail.subject ?? "Support request")
                    .font(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.textPrimary)
                AdaptiveSpacer()
                if let status = PortalFormat.nonEmpty(detail.status) {
                    StatusPill(text: status, tone: SupportCase.isClosedStatus(status) ? .neutral : .active)
                }
            }
            Group {
                if let number = detail.caseNumber {
                    Text("Case \(number) · Filed \(PortalFormat.date(detail.createdDate))")
                }
                if let manager = PortalFormat.nonEmpty(detail.accountManager) {
                    Text("Account manager: \(manager)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)

            if let id = detail.relatedRecordId, let type = detail.relatedRecordType {
                NavigationLink(value: RelatedRecordRoute(
                    record: type == .claim ? .claim(id) : .lead(id),
                    name: detail.relatedRecordName
                )) {
                    HStack {
                        Label(detail.relatedRecordName ?? type.displayName, systemImage: type == .claim ? "doc.text" : "person.2")
                            .font(.subheadline.weight(.semibold))
                        if let stage = PortalFormat.nonEmpty(detail.relatedRecordStage) {
                            Text("· \(stage)")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(minHeight: Theme.minTapTarget)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(type.displayName): \(detail.relatedRecordName ?? "")")
                .accessibilityHint("Opens the \(type.displayName.lowercased())")
                .accessibilityIdentifier("caseRelatedRecord")
            }
        }
        .cardStyle()
    }
}

/// A thread message. The user's own messages are right-aligned (spec §6.9).
private struct MessageBubble: View {
    let comment: CaseComment

    var body: some View {
        HStack {
            if comment.isOwn { Spacer(minLength: 48) }
            VStack(alignment: comment.isOwn ? .trailing : .leading, spacing: Theme.Spacing.xs) {
                Text(comment.body ?? "")
                    .font(.subheadline)
                    .foregroundStyle(comment.isOwn ? Color.surface : Color.textPrimary)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(
                        comment.isOwn ? Color.brandPrimary : Color.surface,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(comment.isOwn ? Color.clear : Color.border, lineWidth: 1)
                    )
                    .textSelection(.enabled)
                Text("\(comment.isOwn ? "You" : (comment.authorName ?? "ProClaimer")) · \(PortalFormat.date(comment.createdDate))")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            if !comment.isOwn { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.isOwn ? "You" : (comment.authorName ?? "Staff")) wrote: \(comment.body ?? "")")
    }
}

#Preview("Case detail") {
    NavigationStack {
        CaseDetailView(caseId: "500000000000001AAA", api: PreviewData.api())
    }
}
