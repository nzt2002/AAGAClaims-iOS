import AVFoundation
import CallKit
import PortalKit
import PushKit
import TwilioVoice
import UIKit

/// Business-line calls inside the app (staff with a Calling seat, `ServerMeta.canCallInApp`).
///
/// Incoming: the server rings the line owner's app first (`<Dial><Client>` by user Id), through a
/// VoIP push that Twilio sends. iOS requires every VoIP push to be reported to CallKit straight
/// away, so the call shows on the lock screen like a normal phone call. Unanswered calls go on to
/// the user's mobile and then voicemail, on the server.
///
/// Outgoing: `start(to:recordId:name:)` → CallKit → Twilio `connect` with `To` and `claimId`; the
/// server's appcall route dials the customer with the business line as caller ID and logs a Task.
///
/// Every delegate here is called on the main queue (PushKit, CallKit and Twilio are all set up
/// with the main queue), so the conformances are `@preconcurrency`: main-actor methods, with a
/// runtime check that traps if a framework ever calls one off the main thread.
@Observable
final class CallManager: NSObject {
    static let shared = CallManager()

    /// True when the signed-in user may use the business line in the app.
    private(set) var isEnabled = false
    /// E.164 business line, for labels ("Call from (678) 846-6386").
    private(set) var businessLine: String?
    /// A call is ringing, connecting or connected.
    private(set) var hasActiveCall = false
    /// The call on the in-app call screen (outgoing from the moment it starts, incoming once answered).
    private(set) var activeCall: ActiveCall?
    /// False after the user minimises the call screen; a "return to call" bar shows instead.
    var showsCallScreen = true
    /// The firm records calls and the server can pause them: the call screen shows Record.
    private(set) var canControlRecording = false

    struct ActiveCall: Equatable {
        enum Phase: Equatable { case connecting, ringing, connected, reconnecting }
        let uuid: UUID
        /// Name when known, else the formatted number.
        let title: String
        /// The number under the name.
        let subtitle: String?
        let isOutgoing: Bool
        var phase: Phase = .connecting
        var connectedAt: Date?
        var isMuted = false
        var isOnHold = false
        var isSpeaker = false
        /// Calls start recorded when the firm records calls; Record pauses and resumes it.
        var isRecording = false
        /// A pause/resume request is in flight.
        var isChangingRecording = false
        /// Shown under the status when a pause/resume failed.
        var recordingError: String?
    }

    @ObservationIgnored private var api: PortalAPI?
    @ObservationIgnored private var token: VoiceToken?
    @ObservationIgnored private var pushToken: Data?
    @ObservationIgnored private var registeredIdentity: String?
    @ObservationIgnored private var pushRegistry: PKPushRegistry?
    @ObservationIgnored private var pushCompletion: (() -> Void)?

    @ObservationIgnored private let provider: CXProvider
    @ObservationIgnored private let callController = CXCallController()
    @ObservationIgnored private let audioDevice = DefaultAudioDevice()
    @ObservationIgnored private var invites: [UUID: CallInvite] = [:]
    @ObservationIgnored private var calls: [UUID: Call] = [:]
    /// CallKit actions waiting for Twilio to connect (outgoing start, incoming answer).
    @ObservationIgnored private var pendingActions: [UUID: CXCallAction] = [:]
    /// Between CallKit's didActivate and didDeactivate.
    @ObservationIgnored private var audioSessionActive = false

    override private init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        configuration.includesCallsInRecents = true
        configuration.iconTemplateImageData = UIImage(systemName: "briefcase.fill")?.pngData()
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
        TwilioVoiceSDK.audioDevice = audioDevice
    }

    // MARK: - Lifecycle

    /// At launch, before any VoIP push can arrive: PushKit delivers pushes only after a registry exists.
    func startPushRegistry() {
        guard pushRegistry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        pushRegistry = registry
    }

    /// After `/meta` loads (sign-in, foreground). Registers this device for incoming calls, or
    /// unregisters it when the user no longer has in-app calling.
    func configure(api: PortalAPI, enabled: Bool, recordingControl: Bool = false) {
        self.api = api
        canControlRecording = enabled && recordingControl
        if enabled {
            isEnabled = true
            Task { await registerForIncomingCalls() }
        } else if isEnabled || registeredIdentity != nil {
            isEnabled = false
            unregister()
        }
    }

    /// Sign-out: incoming calls must stop ringing this phone for the old account.
    func signOut() {
        unregister()
        isEnabled = false
        canControlRecording = false
        businessLine = nil
        token = nil
        api = nil
    }

    // MARK: - Outgoing

    /// Places a call over the business line. `recordId` (claim or lead) links the call log.
    func start(to number: String, recordId: String?, name: String?) {
        guard isEnabled, !hasActiveCall else { return }
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return CallManager.log("microphone permission denied") }
            Task { @MainActor in CallManager.shared.requestStart(to: number, recordId: recordId, name: name) }
        }
    }

    private func requestStart(to number: String, recordId: String?, name: String?) {
        let uuid = UUID()
        let handle = CXHandle(type: .phoneNumber, value: number)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.contactIdentifier = name
        outgoing[uuid] = OutgoingCall(number: number, recordId: recordId, name: name)
        let formatted = CallManager.display(number) ?? number
        let named = PortalFormat.nonEmpty(name)
        activeCall = ActiveCall(uuid: uuid, title: named ?? formatted, subtitle: named == nil ? nil : formatted, isOutgoing: true,
                                isRecording: canControlRecording)
        showsCallScreen = true
        callController.request(CXTransaction(action: action)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.outgoing[uuid] = nil
                self?.activeCall = nil
                CallManager.log("start call failed: \(error.localizedDescription)")
            }
        }
    }

    private struct OutgoingCall {
        let number: String
        let recordId: String?
        let name: String?
    }

    @ObservationIgnored private var outgoing: [UUID: OutgoingCall] = [:]

    // MARK: - In-call controls (call screen)
    //
    // Each control acts on the Twilio call directly, then tells CallKit so its own screen (lock
    // screen, Dynamic Island) matches. Going only through CallKit transactions meant a refused or
    // lost transaction left the button doing nothing (End didn't hang up, 3.6.0).

    func toggleMute() {
        guard let active = activeCall, let call = calls[active.uuid] else { return }
        let muted = !active.isMuted
        call.isMuted = muted
        updateActive(active.uuid) { $0.isMuted = muted }
        syncCallKit(CXSetMutedCallAction(call: active.uuid, muted: muted))
    }

    func toggleHold() {
        guard let active = activeCall, let call = calls[active.uuid] else { return }
        let held = !active.isOnHold
        call.isOnHold = held
        updateActive(active.uuid) { $0.isOnHold = held }
        syncCallKit(CXSetHeldCallAction(call: active.uuid, onHold: held))
    }

    /// Pauses or resumes the call recording on the server (Twilio). The recording starts when the
    /// other side answers, so this works once the call is connected. Paused audio is left out.
    func toggleRecording() {
        guard canControlRecording, let api, let active = activeCall, active.phase == .connected,
              !active.isChangingRecording, let sid = calls[active.uuid]?.sid, !sid.isEmpty else { return }
        let uuid = active.uuid
        let wanted = !active.isRecording
        updateActive(uuid) {
            $0.isChangingRecording = true
            $0.recordingError = nil
        }
        Task {
            do {
                let now = try await api.setCallRecording(callSid: sid, recording: wanted)
                updateActive(uuid) { $0.isRecording = now }
            } catch {
                CallManager.log("recording \(wanted ? "resume" : "pause") failed: \(error)")
                updateActive(uuid) {
                    $0.recordingError = wanted ? "Couldn't resume recording. Try again." : "Couldn't pause recording. Try again."
                }
            }
            updateActive(uuid) { $0.isChangingRecording = false }
        }
    }

    func sendDigit(_ digit: String) {
        guard let active = activeCall, active.phase == .connected, let call = calls[active.uuid] else { return }
        call.sendDigits(digit)
    }

    /// Hangs up straight away. Twilio's callDidDisconnect then tells CallKit and closes the screen.
    func endCall() {
        guard let active = activeCall else { return }
        let uuid = active.uuid
        if let call = calls[uuid] {
            call.disconnect()
        } else {
            // Not connected yet (still fetching a token or connecting): cancel through CallKit.
            outgoing[uuid] = nil
            callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor in
                    self?.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    self?.ended(uuid)
                }
            }
        }
    }

    func toggleSpeaker() {
        guard let active = activeCall else { return }
        let speaker = !active.isSpeaker
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(speaker ? .speaker : .none)
            updateActive(active.uuid) { $0.isSpeaker = speaker }
        } catch {
            CallManager.log("speaker switch failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors a change already made on the call into CallKit. The perform handlers repeat it,
    /// which is harmless (same value).
    private func syncCallKit(_ action: CXCallAction) {
        callController.request(CXTransaction(action: action)) { error in
            if let error { CallManager.log("CallKit sync failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Tokens and registration

    private func freshToken() async -> VoiceToken? {
        if let token, !token.expiresSoon { return token }
        guard let api else { return nil }
        do {
            let fetched = try await api.voiceToken()
            token = fetched
            businessLine = fetched.businessLine
            return fetched
        } catch {
            CallManager.log("voice token failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func registerForIncomingCalls() async {
        guard isEnabled, let pushToken, let token = await freshToken() else { return }
        TwilioVoiceSDK.register(accessToken: token.token, deviceToken: pushToken) { [weak self] error in
            Task { @MainActor in
                if let error {
                    CallManager.log("register failed: \(error.localizedDescription)")
                } else {
                    self?.registeredIdentity = token.identity
                }
            }
        }
    }

    private func unregister() {
        guard let pushToken, let token, registeredIdentity != nil else { return }
        registeredIdentity = nil
        TwilioVoiceSDK.unregister(accessToken: token.token, deviceToken: pushToken) { error in
            if let error { CallManager.log("unregister failed: \(error.localizedDescription)") }
        }
    }

    private func refreshActiveState() {
        hasActiveCall = !calls.isEmpty || !invites.isEmpty || !outgoing.isEmpty
    }

    nonisolated static func log(_ message: String) {
        #if DEBUG
        print("[Calls] \(message)")
        #endif
    }

    /// "(678) 846-6386" for +16788466386.
    static func display(_ e164: String?) -> String? {
        guard let e164 else { return nil }
        let digits = e164.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else { return e164 }
        let d = Array(digits.dropFirst())
        return "(\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
    }
}

// MARK: - PushKit

extension CallManager: @preconcurrency PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        let deviceToken = credentials.token
        pushToken = deviceToken
        Task { await registerForIncomingCalls() }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        unregister()
        pushToken = nil
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        let dictionary = payload.dictionaryPayload
        pushCompletion = completion
        // Twilio calls callInviteReceived / cancelledCallInviteReceived synchronously on main.
        let handled = TwilioVoiceSDK.handleNotification(dictionary, delegate: self, delegateQueue: nil)
        if !handled {
            // iOS ends apps that receive a VoIP push without reporting a call. Not a Twilio
            // call: report one and end it at once.
            let uuid = UUID()
            provider.reportNewIncomingCall(with: uuid, update: CXCallUpdate()) { [weak self] _ in
                Task { @MainActor in
                    self?.provider.reportCall(with: uuid, endedAt: nil, reason: .failed)
                }
            }
        }
        finishPush()
    }

    private func finishPush() {
        pushCompletion?()
        pushCompletion = nil
    }
}

// MARK: - Twilio notifications (incoming calls)

extension CallManager: @preconcurrency NotificationDelegate {
    func callInviteReceived(callInvite: CallInvite) {
        let update = CXCallUpdate()
        let caller = callInvite.from?.replacingOccurrences(of: "client:", with: "") ?? "Unknown"
        update.remoteHandle = CXHandle(type: .phoneNumber, value: caller)
        update.localizedCallerName = CallManager.display(caller).map { "\($0) · ProClaimer" } ?? "ProClaimer call"
        update.supportsDTMF = true
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.hasVideo = false
        invites[callInvite.uuid] = callInvite
        refreshActiveState()
        provider.reportNewIncomingCall(with: callInvite.uuid, update: update) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                // Do Not Disturb or a call already in progress: let the server ring the mobile.
                CallManager.log("report incoming failed: \(error.localizedDescription)")
                self?.invites[callInvite.uuid]?.reject()
                self?.invites[callInvite.uuid] = nil
                self?.refreshActiveState()
            }
        }
    }

    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: Error) {
        let sid = cancelledCallInvite.callSid
        // The caller hung up, or the 20 s ring ended and the server moved on to the mobile.
        guard let (uuid, _) = invites.first(where: { $0.value.callSid == sid }) else { return }
        invites[uuid] = nil
        provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        refreshActiveState()
    }
}

// MARK: - Twilio call events

extension CallManager: @preconcurrency CallDelegate {
    func callDidStartRinging(call: Call) {
        guard let uuid = call.uuid else { return }
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
        updateActive(uuid) { $0.phase = .ringing }
    }

    func call(call: Call, isReconnectingWithError error: Error) {
        guard let uuid = call.uuid else { return }
        updateActive(uuid) { $0.phase = .reconnecting }
    }

    func callDidReconnect(call: Call) {
        guard let uuid = call.uuid else { return }
        updateActive(uuid) { $0.phase = .connected }
    }

    func callDidConnect(call: Call) {
        guard let uuid = call.uuid else { return }
        pendingActions.removeValue(forKey: uuid)?.fulfill()
        // Belt and braces: CallKit's session is live, so make sure Twilio's audio is on.
        if audioSessionActive && !audioDevice.isEnabled {
            audioDevice.isEnabled = true
        }
        if outgoing[uuid] != nil {
            provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        }
        updateActive(uuid) {
            $0.phase = .connected
            if $0.connectedAt == nil { $0.connectedAt = Date() }
        }
    }

    private func updateActive(_ uuid: UUID, _ change: (inout ActiveCall) -> Void) {
        guard var call = activeCall, call.uuid == uuid else { return }
        change(&call)
        activeCall = call
    }

    func callDidFailToConnect(call: Call, error: Error) {
        let message = error.localizedDescription
        guard let uuid = call.uuid else { return }
        CallManager.log("connect failed: \(message)")
        pendingActions.removeValue(forKey: uuid)?.fail()
        provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
        ended(uuid)
    }

    func callDidDisconnect(call: Call, error: Error?) {
        let failed = error != nil
        guard let uuid = call.uuid else { return }
        // Report unless a CXEndCallAction (iOS's own End button) already told CallKit. The app's
        // End button disconnects directly, so it's reported here.
        if calls[uuid] != nil {
            provider.reportCall(with: uuid, endedAt: Date(), reason: failed ? .failed : .remoteEnded)
        }
        ended(uuid)
    }

    private func ended(_ uuid: UUID) {
        // A start or answer still waiting for "connected" must be completed, or CallKit hangs on to it.
        pendingActions.removeValue(forKey: uuid)?.fail()
        if activeCall?.uuid == uuid {
            activeCall = nil
            showsCallScreen = true
        }
        calls[uuid] = nil
        invites[uuid] = nil
        outgoing[uuid] = nil
        pendingActions[uuid] = nil
        refreshActiveState()
    }
}

// MARK: - CallKit

extension CallManager: @preconcurrency CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        audioDevice.isEnabled = false
        for call in calls.values { call.disconnect() }
        for invite in invites.values { invite.reject() }
        calls = [:]
        invites = [:]
        outgoing = [:]
        activeCall = nil
        pendingActions = [:]
        refreshActiveState()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let uuid = action.callUUID
        guard let request = outgoing[uuid] else {
            action.fail()
            return
        }
        audioDevice.isEnabled = false
        audioDevice.block()
        refreshActiveState()
        Task {
            guard let token = await freshToken() else {
                action.fail()
                ended(uuid) // closes the call screen too
                return
            }
            guard outgoing[uuid] != nil else {
                action.fail() // ended while the token was loading
                return
            }
            var params = ["To": request.number]
            if let recordId = request.recordId { params["claimId"] = recordId }
            let options = ConnectOptions(accessToken: token.token) { builder in
                builder.params = params
                builder.uuid = uuid
            }
            calls[uuid] = TwilioVoiceSDK.connect(options: options, delegate: self)
            pendingActions[uuid] = action
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuid = action.callUUID
        guard let invite = invites.removeValue(forKey: uuid) else {
            action.fail()
            return
        }
        // Don't switch the audio device off here (as for outgoing calls): when answering, CallKit
        // can activate the audio session before this runs, and audio would then stay off. Fulfil
        // straight away, as in Twilio's sample, so CallKit activates the session.
        let options = AcceptOptions(callInvite: invite) { builder in
            builder.uuid = invite.uuid
        }
        calls[uuid] = invite.accept(options: options, delegate: self)
        let caller = invite.from?.replacingOccurrences(of: "client:", with: "") ?? "Unknown caller"
        activeCall = ActiveCall(uuid: uuid, title: CallManager.display(caller) ?? caller, subtitle: nil, isOutgoing: false,
                                isRecording: canControlRecording)
        showsCallScreen = true
        refreshActiveState()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        if let invite = invites.removeValue(forKey: uuid) {
            invite.reject() // Declined: the server goes on to the mobile.
        } else if let call = calls.removeValue(forKey: uuid) {
            call.disconnect()
        }
        outgoing[uuid] = nil
        pendingActions.removeValue(forKey: uuid)?.fail()
        refreshActiveState()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = calls[action.callUUID] else { return action.fail() }
        call.isMuted = action.isMuted
        updateActive(action.callUUID) { $0.isMuted = action.isMuted }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = calls[action.callUUID] else { return action.fail() }
        call.isOnHold = action.isOnHold
        updateActive(action.callUUID) { $0.isOnHold = action.isOnHold }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard let call = calls[action.callUUID] else { return action.fail() }
        call.sendDigits(action.digits)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        audioSessionActive = true
        audioDevice.isEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audioSessionActive = false
        audioDevice.isEnabled = false
    }
}
