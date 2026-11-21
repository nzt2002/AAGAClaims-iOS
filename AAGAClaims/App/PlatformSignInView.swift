import LocalAuthentication
import PortalKit
import SwiftUI

/// The app's sign-in on the new platform: email and password (Supabase Auth), Face ID to fill them in, and a reset link by email.
struct PlatformSignInView: View {
    let session: AppSession

    @State private var email = ""
    @State private var password = ""
    @State private var showingPassword = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showingReset = false
    @State private var resetEmail = ""
    @State private var hasSavedSignIn = SavedSignIn.exists
    @State private var didOfferSavedSignIn = false
    /// The company the typed email belongs to (shown above the fields once found).
    @State private var company: PlatformCompany?
    @State private var lookedUp = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        BrandBackdrop {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
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
                        withAnimation(.snappy) { proxy.scrollTo("platformSignInButton", anchor: .bottom) }
                    }
                    .animation(.snappy, value: focus)
                }
            }
        }
        .onAppear {
            hasSavedSignIn = SavedSignIn.exists
            guard hasSavedSignIn, !didOfferSavedSignIn else { return }
            didOfferSavedSignIn = true
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await signInWithSavedDetails()
            }
        }
        .onDisappear { didOfferSavedSignIn = false }
        // Leaving the email field (to the password, or elsewhere) looks the company up.
        .onChange(of: focus) { old, _ in
            if old == .email { Task { await findCompany() } }
        }
        .alert("Reset your password", isPresented: $showingReset) {
            TextField("Email", text: $resetEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send link") { Task { await sendReset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll email you a link to choose a new password.")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Sign in")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Use the email and password for your ProClaimer account.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let company {
                companyBadge(company)
            }
            field(icon: "envelope.fill") {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit {
                        focus = .password
                        Task { await findCompany() }
                    }
                    .accessibilityIdentifier("platformEmail")
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
                .accessibilityIdentifier("platformPassword")
                Button {
                    showingPassword.toggle()
                } label: {
                    Image(systemName: showingPassword ? "eye.slash" : "eye").iconShadow()
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                }
                .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
            }

            if let notice, errorMessage == nil {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("platformSignInError")
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
            .id("platformSignInButton")
            .accessibilityIdentifier("platformSignIn")

            if hasSavedSignIn {
                Button {
                    Task { await signInWithSavedDetails() }
                } label: {
                    Label("Sign in with \(Self.biometryName)", systemImage: Self.biometryIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.brandPrimary)
                .disabled(isSigningIn)
                .accessibilityIdentifier("faceIDSignIn")
            }

            Button("Forgot password?") {
                resetEmail = email.trimmingCharacters(in: .whitespaces)
                showingReset = true
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: Theme.minTapTarget)

            Label("Secure sign-in", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.surface)
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .padding(.bottom, -400)
        }
    }

    /// "Signing in to Accurate Adjustments GA", with its logo, so the person knows the app found the right company.
    private func companyBadge(_ company: PlatformCompany) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            AsyncImage(url: company.logoUrl) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(company.markText ?? String(company.name.prefix(2)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.color(company.brandColor) ?? Color.brandPrimary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
            Text("Signing in to **\(company.name)**")
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .background(Color.surfaceTinted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("platformCompany")
        .transition(.opacity)
    }

    private static func color(_ hex: String?) -> Color? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Asks which company this email belongs to, once per address.
    private func findCompany() async {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@"), address != lookedUp else { return }
        lookedUp = address
        let found = await session.discoverCompanies(email: address)
        // Only if the field still holds the address that was asked about.
        guard address == email.trimmingCharacters(in: .whitespaces).lowercased() else { return }
        withAnimation { company = found.first }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon).iconShadow()
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

    @discardableResult
    private func signIn() async -> PlatformAuthError? {
        guard canSubmit else { return nil }
        focus = nil
        isSigningIn = true
        errorMessage = nil
        let address = email.trimmingCharacters(in: .whitespaces)
        var failure: PlatformAuthError?
        do {
            try await session.signInPlatform(email: address, password: password)
            // Kept for Face ID sign-in if the person has (or turns on) the Face ID lock.
            SavedSignIn.pending = .init(username: address, password: password)
        } catch let error as PlatformAuthError {
            failure = error
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "We couldn't reach the server. Check your connection and try again."
        }
        isSigningIn = false
        if errorMessage != nil { password = "" }
        return failure
    }

    private func signInWithSavedDetails() async {
        guard !isSigningIn else { return }
        focus = nil
        guard let saved = await SavedSignIn.load(reason: "Sign in to ProClaimer") else {
            hasSavedSignIn = SavedSignIn.exists
            return
        }
        email = saved.username
        password = saved.password
        await findCompany()
        if await signIn() == .invalidCredentials {
            // The saved password no longer works (changed elsewhere): forget it.
            SavedSignIn.delete()
            hasSavedSignIn = false
            errorMessage = "Your password has changed. Sign in with your new password to use \(Self.biometryName) again."
        }
    }

    private func sendReset() async {
        let address = resetEmail.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        do {
            try await session.requestPasswordReset(email: address)
            errorMessage = nil
            notice = "If \(address) has an account, we've emailed a link to choose a new password."
        } catch let error as PlatformAuthError {
            notice = nil
            errorMessage = Self.message(for: error)
        } catch {
            notice = nil
            errorMessage = "We couldn't reach the server. Check your connection and try again."
        }
    }

    private static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    private static var biometryIcon: String {
        biometryName == "Touch ID" ? "touchid" : "faceid"
    }

    static func message(for error: PlatformAuthError) -> String {
        switch error {
        case .invalidCredentials: "That email and password don't match. Try again, or reset your password."
        case .notSignedIn: "Your sign-in has ended. Sign in again."
        case .rejected(let message): message
        case .server: "Something went wrong on our side. Try again in a moment."
        }
    }
}
