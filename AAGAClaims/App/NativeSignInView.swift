import SalesforceSDKCore
import SwiftUI
import UIKit

/// The app's own sign-in screen (Mobile SDK native login over Salesforce's Headless Identity API),
/// so portal users never see a web page. The SDK shows it whenever sign-in is needed. Staff, whose
/// accounts can't use headless login, tap "Staff? Sign in with Salesforce" for the web sign-in.
struct NativeSignInView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var showingPassword = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showingReset = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    private static let forgotPasswordURL = URL(string: "https://portal.accurateadjustmentsga.com/s/login/ForgotPassword")!

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        BrandBackdrop {
            ScrollView {
                VStack(spacing: 0) {
                    BrandLogo(layout: .stacked)
                        .padding(.top, 64)
                        .padding(.bottom, Theme.Spacing.xl)
                        .padding(.horizontal, Theme.Spacing.xl)
                    Spacer(minLength: Theme.Spacing.l)
                    card
                }
                .frame(minHeight: UIScreen.main.bounds.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $showingReset) {
            SafariView(url: Self.forgotPasswordURL).ignoresSafeArea()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Sign in")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Use your Accurate Adjustments portal username and password.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            field(icon: "person.fill") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                    .accessibilityIdentifier("nativeUsername")
            }
            field(icon: "lock.fill") {
                Group {
                    if showingPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { Task { await signIn() } }
                .accessibilityIdentifier("nativePassword")
                Button {
                    showingPassword.toggle()
                } label: {
                    Image(systemName: showingPassword ? "eye.slash" : "eye")
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                }
                .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nativeSignInError")
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text(isSigningIn ? "Signing in…" : "Sign In").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(.brandPrimary)
            .disabled(!canSubmit)
            .accessibilityIdentifier("nativeSignIn")

            HStack {
                Button("Forgot password?") { showingReset = true }
                Spacer()
                Button("Staff? Sign in with Salesforce") {
                    SalesforceManager.shared.nativeLoginManager().fallbackToWebAuthentication()
                }
                .accessibilityIdentifier("staffSignIn")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: Theme.minTapTarget)

            Label("Secure sign-in with Salesforce", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            content()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 52)
        .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }

    private func signIn() async {
        guard canSubmit else { return }
        focus = nil
        isSigningIn = true
        errorMessage = nil
        let result = await SalesforceManager.shared.nativeLoginManager()
            .login(username: username.trimmingCharacters(in: .whitespaces), password: password)
        isSigningIn = false
        // On success the SDK finishes signing in and closes this screen.
        errorMessage = Self.message(for: result)
        if result != .success { password = "" }
    }

    static func message(for result: NativeLoginResult) -> String? {
        switch result {
        case .success: nil
        case .invalidUsername, .invalidEmail: "Enter your username. It's usually the email address you use for the portal."
        case .invalidPassword: "Enter your password."
        case .invalidCredentials: "That username and password don't match. Try again, or reset your password."
        default: "We couldn't sign you in. Check your connection and try again, or use \"Staff? Sign in with Salesforce\"."
        }
    }
}

/// Native login's view controller, as the SDK presents it.
enum NativeSignIn {
    static let portalURL = "https://portal.accurateadjustmentsga.com"
    /// Headless login's redirect: the site's echo endpoint, also listed as the app's callback URL in Salesforce.
    static let callbackURL = "https://portal.accurateadjustmentsga.com/services/oauth2/echo"

    static func makeViewController() -> UIViewController {
        let controller = UIHostingController(rootView: NativeSignInView())
        controller.modalPresentationStyle = .fullScreen
        return controller
    }
}
