import AgentforceSDK
import AgentforceService
import PortalKit
import QuickLook
import SalesforceNavigation
import SalesforceSDKCore
import SalesforceUser
import SwiftUI

/// "Ask Alex" (staff): the Claims Assistant Agentforce employee agent in the Agentforce SDK's chat.
/// Shown only when `/meta` returns `assistantAgentId`, i.e. the user has the Claims Assistant
/// Access permission set. The agent runs as the signed-in user, so it sees what they can see.
struct AskAlexSheet: View {
    let agentId: String
    /// The claim or lead on screen when Alex was opened: the conversation's starting context.
    let viewing: AlexRecordContext.ViewedRecord?
    /// Chat history (feature `assistantHistory`): chats are saved when they close, and "Past chats"
    /// lists them. Nil when the server can't store them.
    var history: PortalAPI? = nil
    /// Opens the files Alex links to in Quick Look (nil: links open in Safari).
    var files: PortalAPI? = nil
    let close: () -> Void

    @State private var assistant = AskAlexAssistant()
    /// "Did Alex help?" after the user closes a chat in which they asked something.
    @State private var askingFeedback = false
    @State private var saved = false
    @State private var showingPastChats = false
    @State private var preview: PreviewFile?
    @State private var previewError: String?
    /// Files Alex asked the user to pick, shown as checkboxes.
    @State private var fileChoice: AlexFileChoice?

    var body: some View {
        Group {
            if askingFeedback {
                AlexClosingFeedback(answer: { helpful, reason in finish(helpful: helpful, reason: reason) },
                                    skip: { finish(helpful: nil, reason: nil) })
            } else {
                switch assistant.state {
                case .starting:
                    ProgressView("Connecting to Alex…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready(let chat):
                    chat
                        // Links in Alex's replies, if the SDK opens them through SwiftUI.
                        .environment(\.openURL, OpenURLAction { url in
                            assistant.navigation.open(url)
                            return .handled
                        })
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Alex isn't available", systemImage: "exclamationmark.bubble")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await start() } }
                        Button("Close", action: close)
                    }
                }
            }
        }
        .background(Color.appBackground)
        .task { await start() }
        .quickLookPreview($preview.url)
        .onChange(of: preview) { old, new in
            // Delete the temporary copy once Quick Look closes (no file caching).
            if new == nil, let old {
                try? FileManager.default.removeItem(at: old.directory)
            }
        }
        .alert("Couldn't open file", isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewError ?? "")
        }
        .sheet(item: $fileChoice) { choice in
            AlexFilePickerSheet(choice: choice) { reply in
                Task { await assistant.send(reply) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPastChats) {
            if let history {
                NavigationStack {
                    AlexChatsList(api: history, recordId: nil, title: "Past chats")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingPastChats = false }
                            }
                        }
                }
            }
        }
        .onDisappear {
            // Swiped away: keep the chat, without feedback.
            if !saved { save(helpful: nil, reason: nil) }
            assistant.end()
        }
    }

    private func start() async {
        assistant.onPastChats = history == nil ? nil : { showingPastChats = true }
        assistant.onFileChoice = { fileChoice = $0 }
        if let files {
            assistant.navigation.openFile = { id in Task { await openFile(id, api: files) } }
        }
        await assistant.start(agentId: agentId, viewing: viewing, close: requestClose)
    }

    /// The chat's close button: ask "Did Alex help?" when there's a chat worth rating.
    private func requestClose() {
        if history != nil, assistant.transcript(viewing: viewing) != nil {
            withAnimation { askingFeedback = true }
        } else {
            close()
        }
    }

    private func finish(helpful: Bool?, reason: AssistantFeedbackReason?) {
        save(helpful: helpful, reason: reason)
        close()
    }

    /// A file Alex linked to, in Quick Look over the chat.
    private func openFile(_ contentDocumentId: String, api: PortalAPI) async {
        do {
            let data = try await api.fileContent(contentDocumentId: contentDocumentId)
            preview = try PreviewFile.write(data: data, title: nil, fileType: Self.officeType(of: data))
        } catch PortalAPIError.offline {
            previewError = "You're offline. Files open when you're back online."
        } catch {
            previewError = "Please try again, or open it from the claim's Files."
        }
    }

    /// Word and Excel files are zips that Quick Look only opens with the right extension
    /// (Alex's supplement requests are .docx); other types are recognised from their bytes.
    static func officeType(of data: Data) -> String? {
        guard data.starts(with: [0x50, 0x4B]) else { return nil }
        if data.range(of: Data("word/".utf8)) != nil { return "WORD_X" }
        if data.range(of: Data("xl/".utf8)) != nil { return "EXCEL_X" }
        return nil
    }

    /// Saves the chat (best effort: a chat closed while offline isn't kept).
    private func save(helpful: Bool?, reason: AssistantFeedbackReason?) {
        guard !saved, let history, var conversation = assistant.transcript(viewing: viewing) else { return }
        saved = true
        conversation.helpful = helpful
        conversation.reason = reason
        Task { try? await history.saveAssistantConversation(conversation) }
    }
}

@MainActor
@Observable
final class AskAlexAssistant {
    enum State {
        case starting
        case ready(AgentforceChatView)
        case failed(String)
    }

    /// The agent is Alex everywhere in the chat: never the SDK's default "Agentforce".
    static let agentName = "Alex"
    private static let alexNames: [AgentforceDisplayNameType: String] = [
        .serviceAgentChatTitle: agentName,
        .serviceAIAgentName: agentName,
        .onboardingTitle: "You're about to use Alex",
        .onboardingDescription: "Alex is ProClaimer's claims assistant. Ask about a claim or lead, its documents or what the carrier is paying, or what needs you today; have Alex draft and send emails, create tasks and notes, update a claim's status, build a supplement with photos, or run a report across your claims. Alex always shows you a preview and waits for your yes before changing or sending anything. Alex can make mistakes, so check answers before you act on them.",
        .loadingMessage: "Alex is on the way…",
    ]

    private(set) var state: State = .starting
    /// Kept alive for the life of the sheet, as the SDK requires.
    private var client: AgentforceClient?
    private var conversation: (any AgentConversation)?
    /// Titles the SDK's top bar "Alex"; it otherwise shows "Agentforce" in employee mode.
    private var navigationBar = AlexNavigationBar(onPastChats: nil)
    /// Opens "Past chats" from the chat's top bar (nil hides the button).
    var onPastChats: (() -> Void)?
    /// Alex listed files to choose from (a checklist in his reply).
    var onFileChoice: ((AlexFileChoice) -> Void)?
    /// Adds the record Id to the opening line as it's sent (kept alive with the chat).
    private var delegate: AlexChatDelegate?
    /// Where links in Alex's replies go (kept alive with the chat).
    let navigation = AlexLinkNavigation()

    func start(agentId: String, viewing: AlexRecordContext.ViewedRecord?, close: @escaping () -> Void) async {
        state = .starting
        guard let account = UserAccountManager.shared.currentUserAccount else {
            state = .failed("You're signed out. Sign in again and retry.")
            return
        }
        // The SDK's requests don't go through the Mobile SDK, so it can't refresh an expired
        // token itself: refresh first so the chat starts with a working one. A token refreshed
        // in the last few minutes is still good (sessions last far longer), so reopening Alex
        // skips that round trip.
        if let last = Self.lastRefresh, Date().timeIntervalSince(last) < Self.refreshReuse {
            // Fresh enough.
        } else {
            await Self.refresh(account.credentials)
            Self.lastRefresh = Date()
        }

        let credentials = account.credentials
        guard let orgId = credentials.organizationId, let userId = credentials.userId,
              let instance = credentials.instanceUrl else {
            state = .failed("Your sign-in is missing account details. Sign out and in again.")
            return
        }
        let identity = account.idData
        let user = User(
            userId: userId,
            org: Org(id: orgId),
            username: identity.username,
            displayName: identity.displayName ?? identity.email,
            firstName: identity.firstName
        )
        let provider = AskAlexCredentialProvider()
        let configuration = EmployeeAgentConfiguration(
            user: user,
            forceConfigEndpoint: instance.absoluteString,
            authProvider: provider
        )
        .setTheming(.overrides(displayNames: Self.alexNames))
        .withNavigation(navigation)
        let client = AgentforceClient(credentialProvider: provider, mode: .employeeAgent(configuration))
        let conversation = client.startAgentforceConversation(forAgentId: agentId, preferredAgentName: Self.agentName)
        let delegate = AlexChatDelegate(viewing: viewing)
        delegate.onFileChoice = onFileChoice
        navigationBar = AlexNavigationBar(onPastChats: onPastChats)
        do {
            let chat = try client.createAgentforceChatView(
                conversation: conversation,
                delegate: delegate,
                showTopBar: true,
                onContainerClose: close,
                navigationBarBuilder: navigationBar
            )
            self.client = client
            self.conversation = conversation
            self.delegate = delegate
            state = .ready(chat)
        } catch {
            state = .failed("Couldn't open the chat (\(error.localizedDescription)).")
            return
        }
        if let viewing {
            await Self.setContext(viewing, on: conversation)
        }
    }

    /// Starts the conversation on the record on screen: the page-context variables Salesforce's own
    /// panel sends, plus an opening line naming the record, which Alex answers by confirming it
    /// (the agent's instructions), so the context is visible and easy to correct.
    private static func setContext(_ viewing: AlexRecordContext.ViewedRecord, on conversation: any AgentConversation) async {
        guard await waitUntilActive(conversation) else { return }
        // The SDK's conversation isn't Sendable, but its implementations of these run on the main actor.
        nonisolated(unsafe) let conversation = conversation
        try? await conversation.setAdditionalContext(context: [
            AgentforceVariable(name: "currentRecordId", type: "Text", value: .string(viewing.record.id)),
            AgentforceVariable(name: "currentObjectApiName", type: "Text", value: .string(viewing.objectApiName)),
            AgentforceVariable(name: "currentPageType", type: "Text", value: .string("record__page")),
        ])
        await conversation.sendUtterance(utterance: openingLine(for: viewing), attachment: nil)
    }

    /// What the user sees: the record's name, no Salesforce Id.
    static func openingLine(for viewing: AlexRecordContext.ViewedRecord) -> String {
        // A name not loaded yet (or blank) is left out: Alex then looks the record up by its Id.
        let name = viewing.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : " \"\($0)\"" } ?? ""
        let hint = viewing.hint.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : " (\($0))" } ?? ""
        return "I'm viewing the \(viewing.noun)\(name)\(hint)."
    }

    /// What Alex receives: the same line with the record Id, so he looks up the right record.
    static func openingLineWithId(for viewing: AlexRecordContext.ViewedRecord) -> String {
        openingLine(for: viewing) + " [record Id \(viewing.record.id)]"
    }

    /// The session is ready for messages (up to 20 seconds).
    private static func waitUntilActive(_ conversation: any AgentConversation) async -> Bool {
        let deadline = Date().addingTimeInterval(20)
        for await state in conversation.conversationState.values {
            if state == .active { return true }
            if state == .error || state == .ended || Date() > deadline { return false }
        }
        return false
    }

    /// Sends a message as the user, as if typed (e.g. the files picked in the checklist).
    func send(_ text: String) async {
        guard let current = conversation else { return }
        // The SDK's conversation isn't Sendable, but its implementations of this run on the main actor.
        nonisolated(unsafe) let unchecked = current
        await unchecked.sendUtterance(utterance: text, attachment: nil)
    }

    func end() {
        conversation = nil
        client = nil
        delegate = nil
    }

    /// The chat to save, or nil when the user never asked anything (only the automatic opening line).
    func transcript(viewing: AlexRecordContext.ViewedRecord?) -> AssistantConversation? {
        guard let messages = delegate?.transcript, let first = messages.first else { return nil }
        let opening = viewing.map { [Self.openingLine(for: $0), Self.openingLineWithId(for: $0)] } ?? []
        guard messages.contains(where: { $0.role == "user" && !opening.contains($0.text) }) else { return nil }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return AssistantConversation(
            recordId: viewing?.record.id,
            startedAt: first.at ?? Date(),
            endedAt: Date(),
            source: "iOS app \(version) (\(build))",
            messages: messages
        )
    }

    /// When the token was last refreshed for Alex, and how long that refresh is reused.
    private static var lastRefresh: Date?
    private static let refreshReuse: TimeInterval = 10 * 60

    private static func refresh(_ credentials: OAuthCredentials) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let started = UserAccountManager.shared.refresh(credentials: credentials) { _ in
                done.resume()
            }
            // Already refreshing: that refresh will finish shortly; carry on with the saved token.
            if !started { done.resume() }
        }
    }
}

/// Sends the opening line with the record Id the user doesn't see (the chat shows the line as
/// written; this rewrites only what goes to Alex), and keeps the transcript for saving.
final class AlexChatDelegate: AgentforceUIDelegate, @unchecked Sendable {
    private let shown: String?
    private let sent: String?
    /// Guards `messages`: the SDK calls back from its own queues.
    private let lock = NSLock()
    private var messages: [AssistantConversation.Message] = []
    /// Called on the main actor when a reply of Alex's asks the user to pick files.
    @MainActor var onFileChoice: ((AlexFileChoice) -> Void)?

    @MainActor init(viewing: AlexRecordContext.ViewedRecord?) {
        shown = viewing.map { AskAlexAssistant.openingLine(for: $0) }
        sent = viewing.map { AskAlexAssistant.openingLineWithId(for: $0) }
    }

    /// What was said so far, in order.
    var transcript: [AssistantConversation.Message] {
        lock.withLock { messages }
    }

    func modifyUtteranceBeforeSending(_ utterance: AgentforceUtterance) async -> AgentforceUtterance {
        guard let shown, let sent, utterance.utterance == shown else { return utterance }
        return AgentforceUtterance(utterance: sent, attachment: utterance.attachment)
    }

    func didSendUtterance(_ utterance: AgentforceUtterance) {
        record(role: "user", text: utterance.utterance)
    }

    /// Replies stream in; only the finished message is kept.
    func didReceiveResponse(_ message: AgentforceMessage, from conversation: any AgentConversation) {
        guard !message.isUserMessage, !message.isWelcomeMessage, message.state == .finished,
              let text = message.message else { return }
        // Only a new reply opens the picker: the SDK can report a finished reply more than once.
        guard record(role: "alex", text: text), let choice = AlexFileChoice.parse(text) else { return }
        Task { @MainActor in onFileChoice?(choice) }
    }

    /// Adds a message to the transcript; false when it's empty or a repeat of the last one.
    @discardableResult
    private func record(role: String, text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return lock.withLock {
            // The SDK can report a finished reply more than once.
            if let last = messages.last, last.role == role, last.text == text { return false }
            messages.append(AssistantConversation.Message(role: role, text: text, at: Date()))
            return true
        }
    }
}

/// Links in Alex's replies. Alex links file names to their Lightning file page
/// (`/lightning/r/ContentDocument/069…/view`), which opens in the app's own viewer; other links open in Safari.
final class AlexLinkNavigation: Navigation, @unchecked Sendable {
    /// Set by the sheet; nil opens file links in Safari too.
    @MainActor var openFile: ((String) -> Void)?

    func go(to destination: any Destination) {
        go(to: destination, replace: false)
    }

    func go(to destination: any Destination, replace: Bool) {
        guard let link = destination as? SalesforceNavigation.Link else { return }
        let url = link.url
        Task { @MainActor in open(url) }
    }

    @MainActor func open(_ url: URL) {
        if let id = Self.contentDocumentId(in: url), let openFile {
            openFile(id)
        } else {
            UIApplication.shared.open(url)
        }
    }

    static func contentDocumentId(in url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "ContentDocument"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.hasPrefix("069") && (id.count == 15 || id.count == 18) ? id : nil
    }
}

/// The chat's top bar: the SDK's own buttons, with the title "Alex" on every screen.
final class AlexNavigationBar: NavigationBarBuilder {
    var handleNavigation: HandleNavigationClosure?
    var refreshHandler: (any NavigationRefreshable)?

    /// `onPastChats`: adds a "Past chats" button on the conversation screen.
    init(onPastChats: (() -> Void)?) {
        handleNavigation = { screen, toolbarItems, _ in
            toolbarItems.title = AskAlexAssistant.agentName
            toolbarItems.showDefaults = true
            if let onPastChats, screen == .conversation {
                toolbarItems.leading.append(CustomToolbarItem(placement: .topBarLeading, content: AnyView(
                    Button(action: onPastChats) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Past chats")
                    .accessibilityIdentifier("alexPastChats")
                )))
            }
        }
    }
}

/// Gives the SDK the signed-in user's current Salesforce token (never a cached copy).
nonisolated final class AskAlexCredentialProvider: AgentforceAuthCredentialProviding, @unchecked Sendable {
    func getAuthCredentials() -> AgentforceAuthCredentials {
        let credentials = UserAccountManager.shared.currentUserAccount?.credentials
        return .OAuth(
            authToken: credentials?.accessToken ?? "",
            orgId: credentials?.organizationId ?? "",
            userId: credentials?.userId ?? ""
        )
    }
}
