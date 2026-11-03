import PortalKit
import SwiftUI

/// "Did Alex help?": one tap. Yes ends it; No asks why, also one tap. No typing.
struct AlexFeedbackButtons: View {
    let answer: (_ helpful: Bool, _ reason: AssistantFeedbackReason?) -> Void
    @State private var askingWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if askingWhy {
                Text("What went wrong?")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)],
                          alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(AssistantFeedbackReason.allCases) { reason in
                        Button {
                            answer(false, reason)
                        } label: {
                            Label(reason.label, systemImage: reason.systemImage)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.m)
                                .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("alexFeedbackReason-\(reason.rawValue)")
                    }
                }
            } else {
                Text("Did Alex help?")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        answer(true, nil)
                    } label: {
                        Label("Yes", systemImage: "hand.thumbsup.fill")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.success)
                    .accessibilityIdentifier("alexFeedbackYes")
                    Button {
                        withAnimation { askingWhy = true }
                    } label: {
                        Label("No", systemImage: "hand.thumbsdown.fill")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.warning)
                    .accessibilityIdentifier("alexFeedbackNo")
                }
            }
        }
    }
}

/// Shown when a chat closes: answer, or skip (the chat is saved either way).
struct AlexClosingFeedback: View {
    let answer: (_ helpful: Bool, _ reason: AssistantFeedbackReason?) -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Image("AskAlexIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            AlexFeedbackButtons(answer: answer)
            Button("Skip", action: skip)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                .accessibilityIdentifier("alexFeedbackSkip")
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

/// A claim's or lead's saved Alex chats (or the user's own, with `recordId` nil).
struct AlexChatsList: View {
    let api: PortalAPI
    let recordId: String?
    var title = "Alex chats"

    @State private var state: LoadState<[AssistantChatSummary]> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                SkeletonList(rows: 3).padding(Theme.Spacing.l)
            case .failed:
                ErrorStateView(subject: "Alex chats") { Task { await load() } }
            case .loaded(let chats, _) where chats.isEmpty:
                ContentUnavailableView("No Alex chats yet", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text(recordId == nil
                                           ? "Chats you have with Alex are saved here when you close them."
                                           : "Chats about this record are saved here when they're closed."))
            case .loaded(let chats, _):
                List(chats) { chat in
                    NavigationLink {
                        AlexChatDetailView(api: api, summary: chat)
                    } label: {
                        AlexChatRow(chat: chat, showsRecord: recordId == nil)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        do {
            state = .loaded(try await api.assistantConversations(recordId: recordId), at: Date())
        } catch {
            state = .failed(error as? PortalAPIError ?? .invalidRequest)
        }
    }
}

struct AlexChatRow: View {
    let chat: AssistantChatSummary
    /// "Past chats" show which claim or lead each chat was about.
    var showsRecord = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(chat.firstQuestion ?? "Opened on \(chat.recordName ?? "a record")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: Theme.Spacing.s)
                AlexFeedbackBadge(helpful: chat.helpful)
            }
            Text(meta)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts: [String] = []
        if let started = chat.startedAt { parts.append(started.formatted(date: .abbreviated, time: .shortened)) }
        if !chat.isMine, let user = chat.userName { parts.append(user) }
        if showsRecord, let record = chat.recordName { parts.append(record) }
        parts.append("\(chat.messageCount) message\(chat.messageCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

struct AlexFeedbackBadge: View {
    let helpful: Bool?

    var body: some View {
        if let helpful {
            Image(systemName: helpful ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.caption)
                .foregroundStyle(helpful ? Color.success : Color.warning)
                .accessibilityLabel(helpful ? "Helpful" : "Not helpful")
        }
    }
}

/// One saved chat as bubbles, with "Did Alex help?" when the user hasn't answered.
struct AlexChatDetailView: View {
    let api: PortalAPI
    @State var summary: AssistantChatSummary
    @State private var messages: LoadState<[AssistantConversation.Message]> = .idle

    init(api: PortalAPI, summary: AssistantChatSummary) {
        self.api = api
        _summary = State(initialValue: summary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                switch messages {
                case .idle, .loading:
                    SkeletonList(rows: 3)
                case .failed:
                    ErrorStateView(subject: "this chat") { Task { await load() } }
                case .loaded(let messages, _):
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        AlexBubble(message: message)
                    }
                }
                feedback
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.appBackground)
        .navigationTitle(summary.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Alex chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { if messages.value == nil { await load() } }
    }

    @ViewBuilder
    private var feedback: some View {
        if summary.canRate {
            AlexFeedbackButtons { helpful, reason in
                Task {
                    if let updated = try? await api.rateAssistantConversation(id: summary.id, helpful: helpful, reason: reason) {
                        withAnimation { summary = updated }
                    }
                }
            }
            .cardStyle()
        } else if let helpful = summary.helpful {
            Label(helpful ? "Marked as helpful" : "Marked as not helpful\(summary.feedbackReason.map { ": \($0.label)" } ?? "")",
                  systemImage: helpful ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func load() async {
        do {
            let detail = try await api.assistantConversation(id: summary.id)
            summary = detail.conversation
            messages = .loaded(detail.messages, at: Date())
        } catch {
            messages = .failed(error as? PortalAPIError ?? .invalidRequest)
        }
    }
}

/// A message: Alex on the left, the user on the right. Alex writes Markdown (bold, bullets).
private struct AlexBubble: View {
    let message: AssistantConversation.Message

    var body: some View {
        HStack {
            if !message.isAlex { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(markdown)
                    .font(.subheadline)
                    .foregroundStyle(message.isAlex ? Color.textPrimary : Color.white)
                    .textSelection(.enabled)
                if let at = message.at {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(message.isAlex ? Color.textSecondary : Color.white.opacity(0.8))
                }
            }
            .padding(Theme.Spacing.m)
            .background(message.isAlex ? Color.surface : Color.brandPrimary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.isAlex { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isAlex ? "Alex" : "You"): \(message.text)")
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }
}

/// On a claim or lead page (staff): opens the record's saved Alex chats.
struct AlexChatsLink: View {
    let api: PortalAPI
    let recordId: String

    var body: some View {
        NavigationLink {
            AlexChatsList(api: api, recordId: recordId)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image("AskAlexIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)
                Text("Alex chats")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minHeight: Theme.minTapTarget)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alexChatsLink")
    }
}
