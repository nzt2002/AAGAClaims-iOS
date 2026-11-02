import AgentforceSDK
import AgentforceService
import SalesforceSDKCore
import SalesforceUser
import SwiftUI

/// "Ask Alex" (staff): the Claims Assistant Agentforce employee agent in the Agentforce SDK's chat.
/// Shown only when `/meta` returns `assistantAgentId`, i.e. the user has the Claims Assistant
/// Access permission set. The agent runs as the signed-in user, so it sees what they can see.
struct AskAlexSheet: View {
    let agentId: String
    let close: () -> Void

    @State private var assistant = AskAlexAssistant()

    var body: some View {
        Group {
            switch assistant.state {
            case .starting:
                ProgressView("Connecting to Alex…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let chat):
                chat
            case .failed(let message):
                ContentUnavailableView {
                    Label("Alex isn't available", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await assistant.start(agentId: agentId, close: close) } }
                    Button("Close", action: close)
                }
            }
        }
        .background(Color.appBackground)
        .task { await assistant.start(agentId: agentId, close: close) }
        .onDisappear { assistant.end() }
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
        .onboardingDescription: "Alex is ProClaimer's claims assistant. Ask about a claim, its payments and documents, have Alex draft an update, or run a report across your claims. Alex can make mistakes, so check answers before you act on them.",
        .loadingMessage: "Alex is on the way…",
    ]

    private(set) var state: State = .starting
    /// Kept alive for the life of the sheet, as the SDK requires.
    private var client: AgentforceClient?
    private var conversation: (any AgentConversation)?
    /// Titles the SDK's top bar "Alex"; it otherwise shows "Agentforce" in employee mode.
    private let navigationBar = AlexNavigationBar()

    func start(agentId: String, close: @escaping () -> Void) async {
        state = .starting
        guard let account = UserAccountManager.shared.currentUserAccount else {
            state = .failed("You're signed out. Sign in again and retry.")
            return
        }
        // The SDK's requests don't go through the Mobile SDK, so it can't refresh an expired
        // token itself: refresh first so the chat starts with a working one.
        await Self.refresh(account.credentials)

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
        let client = AgentforceClient(credentialProvider: provider, mode: .employeeAgent(configuration))
        let conversation = client.startAgentforceConversation(forAgentId: agentId, preferredAgentName: Self.agentName)
        do {
            let chat = try client.createAgentforceChatView(
                conversation: conversation,
                delegate: nil as (any AgentforceUIDelegate)?,
                showTopBar: true,
                onContainerClose: close,
                navigationBarBuilder: navigationBar
            )
            self.client = client
            self.conversation = conversation
            state = .ready(chat)
        } catch {
            state = .failed("Couldn't open the chat (\(error.localizedDescription)).")
        }
    }

    func end() {
        conversation = nil
        client = nil
    }

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

/// The chat's top bar: the SDK's own buttons, with the title "Alex" on every screen.
final class AlexNavigationBar: NavigationBarBuilder {
    var handleNavigation: HandleNavigationClosure? = { _, toolbarItems, _ in
        toolbarItems.title = AskAlexAssistant.agentName
        toolbarItems.showDefaults = true
    }
    var refreshHandler: (any NavigationRefreshable)?
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
