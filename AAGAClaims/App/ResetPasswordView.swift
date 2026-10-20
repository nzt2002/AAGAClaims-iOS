import SwiftUI

/// "Forgot password?" on the sign-in screen: request a code by email, then set a new password,
/// all in the app. Falls back to the portal's reset page if the portal doesn't allow it.
struct ResetPasswordView: View {
    let username: String
    /// Called with the username once the password has been changed.
    let finished: (String) -> Void

    private enum Step { case request, reset }
    @State private var step = Step.request
    @State private var user: String
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingWebReset = false
    @State private var offerWebReset = false
    @Environment(\.dismiss) private var dismiss

    private static let webResetURL = URL(string: "https://portal.accurateadjustmentsga.com/s/login/ForgotPassword")!

    init(username: String, finished: @escaping (String) -> Void) {
        self.username = username
        self.finished = finished
        _user = State(initialValue: username)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .request:
                    Section {
                        TextField("Username", text: $user)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("resetUsername")
                    } footer: {
                        Text("We'll email you a code to reset your password.")
                    }
                case .reset:
                    Section {
                        TextField("Code from the email", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("resetCode")
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("resetNewPassword")
                        SecureField("Confirm new password", text: $confirm)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("resetConfirm")
                    } header: {
                        Text("Check your email")
                    } footer: {
                        Text("We sent a code to the email address on \(user). Use at least 8 characters, with letters and numbers.")
                    }
                    Section {
                        Button("Send a new code") { Task { await sendCode() } }
                            .disabled(isWorking)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.warning)
                            .accessibilityIdentifier("resetError")
                        if offerWebReset {
                            Button("Reset on the portal website") { showingWebReset = true }
                        }
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(step == .request ? "Send Code" : "Reset") {
                            Task { step == .request ? await sendCode() : await reset() }
                        }
                        .bold()
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("resetSubmit")
                    }
                }
            }
            .sheet(isPresented: $showingWebReset) {
                SafariView(url: Self.webResetURL).ignoresSafeArea()
            }
        }
    }

    private var canSubmit: Bool {
        switch step {
        case .request: !user.trimmingCharacters(in: .whitespaces).isEmpty
        case .reset: !code.isEmpty && !newPassword.isEmpty && !confirm.isEmpty
        }
    }

    private func sendCode() async {
        isWorking = true
        errorMessage = nil
        offerWebReset = false
        let outcome = await HeadlessPasswordReset.sendCode(username: user.trimmingCharacters(in: .whitespaces))
        isWorking = false
        switch outcome {
        case .done: step = .reset
        default: show(outcome)
        }
    }

    private func reset() async {
        guard newPassword == confirm else {
            errorMessage = "The new passwords don't match."
            return
        }
        isWorking = true
        errorMessage = nil
        let outcome = await HeadlessPasswordReset.reset(username: user.trimmingCharacters(in: .whitespaces),
                                                        code: code.trimmingCharacters(in: .whitespaces), newPassword: newPassword)
        isWorking = false
        if outcome == .done {
            finished(user.trimmingCharacters(in: .whitespaces))
            dismiss()
        } else {
            show(outcome)
        }
    }

    private func show(_ outcome: HeadlessPasswordReset.Outcome) {
        switch outcome {
        case .done: errorMessage = nil
        case .unavailable:
            errorMessage = "Password reset isn't available in the app right now."
            offerWebReset = true
        case .invalidCode: errorMessage = "That code is wrong or has expired. Check the email, or send a new code."
        case .weakPassword(let message): errorMessage = message ?? "Choose a stronger password: at least 8 characters, with letters and numbers."
        case .network: errorMessage = "We couldn't reach the server. Check your connection and try again."
        case .failed(let message):
            errorMessage = message ?? "We couldn't reset your password."
            offerWebReset = true
        }
    }
}
