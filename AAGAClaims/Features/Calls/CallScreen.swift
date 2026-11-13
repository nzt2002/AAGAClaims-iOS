import SwiftUI

/// Full-screen in-call view for business-line calls: who, status and timer, then mute, keypad,
/// speaker and hold, and End. iOS shows its own call screen only on the lock screen, so without
/// this the app drops back to the page the call was started from.
struct CallScreen: View {
    private var calls: CallManager { CallManager.shared }
    @State private var showsKeypad = false
    @State private var typedDigits = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.11, blue: 0.24), Color(red: 0.01, green: 0.18, blue: 0.38)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let call = calls.activeCall {
                VStack(spacing: 0) {
                    topBar
                    header(call)
                        .padding(.top, 24)
                    Spacer(minLength: 24)
                    if showsKeypad {
                        keypad
                    } else {
                        controls(call)
                    }
                    Spacer(minLength: 24)
                    endButton
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 32)
                .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button {
                calls.showsCallScreen = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimise call")
            Spacer()
            if let line = CallManager.display(calls.businessLine) {
                Label(line, systemImage: "briefcase.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("Business line \(line)")
            }
        }
        .padding(.top, 8)
    }

    private func header(_ call: CallManager.ActiveCall) -> some View {
        VStack(spacing: 8) {
            Text(call.title)
                .font(.system(size: 32, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let subtitle = call.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            status(call)
                .font(.body.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            if calls.canControlRecording && call.phase == .connected {
                recordingBadge(call)
            }
            if showsKeypad && !typedDigits.isEmpty {
                Text(typedDigits)
                    .font(.title2.monospacedDigit())
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func status(_ call: CallManager.ActiveCall) -> some View {
        switch call.phase {
        case .connecting:
            Text(call.isOutgoing ? "Calling…" : "Connecting…")
        case .ringing:
            Text("Ringing…")
        case .reconnecting:
            Text("Reconnecting…")
        case .connected:
            if call.isOnHold {
                Text("On hold")
            } else if let start = call.connectedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(CallScreen.duration(from: start, to: context.date))
                }
            }
        }
    }

    private func controls(_ call: CallManager.ActiveCall) -> some View {
        let connected = call.phase == .connected
        return Grid(horizontalSpacing: 28, verticalSpacing: 28) {
            GridRow {
                ControlButton(title: "Mute", systemImage: call.isMuted ? "mic.slash.fill" : "mic.slash",
                              isOn: call.isMuted) { calls.toggleMute() }
                ControlButton(title: "Keypad", systemImage: "circle.grid.3x3.fill", isOn: false) {
                    showsKeypad = true
                }
                .disabled(!connected)
                ControlButton(title: "Speaker", systemImage: "speaker.wave.2.fill",
                              isOn: call.isSpeaker) { calls.toggleSpeaker() }
            }
            GridRow {
                if calls.canControlRecording {
                    // Calls start recorded; tap to pause the recording, tap again to resume.
                    ControlButton(title: call.isRecording ? "Recording" : "Record",
                                  systemImage: call.isRecording ? "record.circle.fill" : "record.circle",
                                  isOn: call.isRecording, onTint: .red) { calls.toggleRecording() }
                        .disabled(!connected || call.isChangingRecording)
                        .accessibilityLabel(call.isRecording ? "Recording. Double-tap to pause." : "Recording paused. Double-tap to resume.")
                        .accessibilityIdentifier("callRecord")
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
                ControlButton(title: call.isOnHold ? "Resume" : "Hold", systemImage: "pause.fill",
                              isOn: call.isOnHold) { calls.toggleHold() }
                    .disabled(!connected)
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    /// "● REC" while recording, "Recording paused" when not, and any pause/resume error.
    private func recordingBadge(_ call: CallManager.ActiveCall) -> some View {
        VStack(spacing: 4) {
            if call.isRecording {
                Label("REC", systemImage: "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
                    .accessibilityLabel("This call is being recorded")
            } else {
                Text("Recording paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let error = call.recordingError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 4)
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
        return VStack(spacing: 18) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            typedDigits.append(key)
                            calls.sendDigit(key)
                        } label: {
                            Text(key)
                                .font(.system(size: 32, weight: .regular))
                                .frame(width: 76, height: 76)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .accessibilityLabel("Key \(key)")
                    }
                }
            }
            Button("Hide Keypad") {
                showsKeypad = false
            }
            .font(.body.weight(.medium))
            .padding(.top, 4)
        }
    }

    private var endButton: some View {
        Button {
            calls.endCall()
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.system(size: 30))
                .frame(width: 76, height: 76)
                .background(Color.red, in: Circle())
        }
        .accessibilityLabel("End call")
    }

    static func duration(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    /// The icon colour when on (Record is red).
    var onTint: Color = .black
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .frame(width: 76, height: 76)
                    .foregroundStyle(isOn ? onTint : Color.white)
                    .background(isOn ? Color.white : Color.white.opacity(0.15), in: Circle())
                Text(title)
                    .font(.footnote)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Green bar at the top of the app while a minimised call is in progress; tap to go back to it.
struct ReturnToCallBar: View {
    private var calls: CallManager { CallManager.shared }

    var body: some View {
        if let call = calls.activeCall, !calls.showsCallScreen {
            Button {
                calls.showsCallScreen = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                    Text("Return to call · \(call.title)")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let start = call.connectedAt {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(CallScreen.duration(from: start, to: context.date))
                                .monospacedDigit()
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.green)
            }
            .accessibilityLabel("Return to call with \(call.title)")
        }
    }
}

extension View {
    /// The in-app call screen over everything while a business-line call is active, and the
    /// "Return to call" bar when it's minimised.
    func businessLineCallScreen() -> some View {
        modifier(CallScreenPresenter())
    }
}

private struct CallScreenPresenter: ViewModifier {
    private var calls: CallManager { CallManager.shared }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                ReturnToCallBar()
            }
            .fullScreenCover(isPresented: Binding(
                get: { calls.activeCall != nil && calls.showsCallScreen },
                set: { if !$0 { calls.showsCallScreen = false } }
            )) {
                CallScreen()
            }
            // A call that didn't start or dropped says why instead of just vanishing (3.9.2).
            .alert(calls.failure?.title ?? "Call failed", isPresented: Binding(
                get: { calls.failure != nil && calls.activeCall == nil },
                set: { if !$0 { calls.failure = nil } }
            )) {
                Button("OK", role: .cancel) { calls.failure = nil }
            } message: {
                Text(calls.failure?.message ?? "")
            }
    }
}
