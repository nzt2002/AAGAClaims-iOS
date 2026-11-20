import PortalKit
import SwiftUI

/// Alex on the ProClaimer platform: a plain chat that sends the conversation to `POST /assistant/chat`. The server looks
/// things up fresh each time and keeps no history, so this screen keeps the chat only while it's open.
struct AlexChatSheet: View {
    let api: any PortalAPI
    /// The claim or lead open behind this sheet, so Alex starts with it as context.
    let viewing: AlexRecordContext.ViewedRecord?
    let close: () -> Void

    @State private var turns: [AssistantChatTurn] = []
    @State private var draft = ""
    @State private var thinking = false
    @State private var errorText: String?
    @FocusState private var typing: Bool

    /// Only a claim's Id goes to the server; a lead isn't something Alex can read yet.
    private var recordId: String? {
        if case .claim(let id)? = viewing?.record { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if turns.isEmpty { intro }
                            ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                                bubble(turn).id(index)
                            }
                            if thinking {
                                HStack(spacing: 8) { ProgressView(); Text("Alex is looking…").foregroundStyle(.secondary) }
                                    .id("thinking")
                            }
                            if let errorText {
                                Text(errorText).font(.footnote).foregroundStyle(.red).id("error")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: turns.count) { _, _ in scrollToEnd(proxy) }
                    .onChange(of: thinking) { _, _ in scrollToEnd(proxy) }
                    .onChange(of: errorText) { _, _ in scrollToEnd(proxy) }
                }
                Divider()
                composer
            }
            .background(Color.appBackground)
            .navigationTitle("Alex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
            }
        }
        .accessibilityIdentifier("alexChatSheet")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask Alex").font(.title3.weight(.semibold))
            if let name = viewing?.name, recordId != nil {
                Text("Alex knows you're looking at \(name).").foregroundStyle(.secondary)
            }
            Text("Find a claim, see where it stands, or ask what's on your plate today. Alex only reads for now: it can't send or change anything.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ turn: AssistantChatTurn) -> some View {
        let mine = turn.role == "user"
        return Text(Self.formatted(turn.text))
            .textSelection(.enabled)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(mine ? Color.white : Color.primary)
            .background(mine ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Alex…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .accessibilityIdentifier("alexChatField")
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            Text("Alex can make mistakes. Check amounts, dates and names before you send or save anything.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if errorText != nil { proxy.scrollTo("error", anchor: .bottom) }
            else if thinking { proxy.scrollTo("thinking", anchor: .bottom) }
            else if !turns.isEmpty { proxy.scrollTo(turns.count - 1, anchor: .bottom) }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        draft = ""
        errorText = nil
        turns.append(.user(text))
        let sending = turns
        thinking = true
        Task {
            defer { thinking = false }
            do {
                let reply = try await api.assistantChat(messages: sending, recordId: recordId)
                turns.append(.assistant(reply))
            } catch {
                // Take the unanswered question back out so it can be sent again.
                if turns.last == .user(text) { turns.removeLast() }
                draft = text
                errorText = Self.explain(error)
            }
        }
    }

    /// What went wrong, in words for the person.
    static func explain(_ error: Error) -> String {
        switch error as? PortalAPIError {
        case .offline?: "No connection. Check your signal and try again."
        case .sessionExpired?: "You've been signed out. Sign in again to use Alex."
        case .server(let status)?:
            switch status {
            case 403: "Alex isn't turned on for your company."
            case 429: "You're asking quickly. Wait a moment and try again."
            case 503: "Alex isn't set up yet. Ask ProClaimer."
            default: "Alex couldn't answer just now. Try again in a moment."
            }
        default: "Alex couldn't answer just now. Try again in a moment."
        }
    }

    /// Alex writes short Markdown (bold, lists); show it as formatted text, falling back to plain.
    static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
