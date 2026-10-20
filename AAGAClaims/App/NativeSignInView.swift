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
            // The visible height: it shrinks when the keyboard is up, so the card ends just above it.
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Smaller while typing, so the fields and Sign In fit above the keyboard.
                            BrandLogo(layout: focus == nil ? .stacked : .compact, showsTagline: focus == nil)
                                .padding(.top, focus == nil ? 48 : Theme.Spacing.m)
                                .padding(.bottom, focus == nil ? Theme.Spacing.xl : Theme.Spacing.m)
                                .padding(.horizontal, Theme.Spacing.xl)
                            Spacer(minLength: Theme.Spacing.m)
                            card
                        }
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: focus) { _, field in
                        guard field != nil else { return }
                        withAnimation(.snappy) { proxy.scrollTo("signInButton", anchor: .bottom) }
                    }
                    .animation(.snappy, value: focus)
                }
            }
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
            .id("signInButton")
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
        .frame(maxWidth: .infinity)
        .background {
            // White to the bottom edge, under the home indicator or keyboard.
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .padding(.bottom, -400)
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
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first
        guard let clientId = BootConfigCheck.consumerKey else {
            isSigningIn = false
            errorMessage = Self.message(for: .other("no client id"))
            return
        }
        let failure = await HeadlessSignIn.signIn(username: username.trimmingCharacters(in: .whitespaces),
                                                  password: password, clientId: clientId, scene: scene)
        isSigningIn = false
        // On success the SDK finishes signing in and closes this screen.
        errorMessage = failure.map(Self.message(for:))
        if failure != nil { password = "" }
    }

    static func message(for failure: HeadlessSignIn.Failure) -> String {
        switch failure {
        case .invalidCredentials: "That username and password don't match. Try again, or reset your password."
        case .notApproved: "Your account doesn't have access to the app yet. Contact Accurate Adjustments and we'll set it up."
        case .network: "We couldn't reach the server. Check your connection and try again."
        case .other: "We couldn't sign you in. Try again, or use \"Staff? Sign in with Salesforce\"."
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
