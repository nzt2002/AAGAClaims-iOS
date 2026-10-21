import PortalKit
import SwiftUI

struct RootView: View {
    let session: AppSession
    /// The animated splash, picking up from the launch screen.
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            switch session.state {
            case .signingIn:
                if session.isRestoringSession || session.usesNativeLogin {
                    // A saved session is coming back, or the app's sign-in screen is shown over this:
                    // no welcome screen (and no second Sign In button).
                    BrandBackdrop {
                        VStack(spacing: Theme.Spacing.xl) {
                            BrandLogo(layout: .stacked)
                            SignInStallNotice(session: session)
                        }
                        .padding(Theme.Spacing.xl)
                    }
                } else {
                    WelcomeView(
                        isDemo: session.isDemo,
                        isSigningIn: session.isSigningIn,
                        signIn: { session.startSignIn?() },
                        continueInDemo: { session.didSignIn(.demo) }
                    )
                }
            case .signedIn(let user):
                MainTabView(session: session, user: user)
                    .environment(session.uploads)
                if session.lock.isLocked {
                    LockScreen(lock: session.lock)
                }
            }
            if showingSplash {
                BrandSplash()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if session.isShielded {
                PrivacyShield()
                    .zIndex(2)
            }
        }
        .task {
            // Long enough to read the name; UI tests don't wait for it.
            let delay = UserDefaults.standard.bool(forKey: "UITestDemo") ? 0.2 : 1.4
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.easeOut(duration: 0.45)) { showingSplash = false }
        }
    }
}

/// After a successful sign-in the app should move on within seconds. If it hasn't after 12, say so
/// and offer to try again, instead of leaving what looks like a frozen splash.
private struct SignInStallNotice: View {
    let session: AppSession
    @State private var isStalled = false

    var body: some View {
        Group {
            if isStalled {
                VStack(spacing: Theme.Spacing.m) {
                    Text("Still signing you in…")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("Try Again") {
                        session.noteSignInStep("retry")
                        isStalled = false
                        session.retrySignIn?()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityIdentifier("signInRetry")
                    if !session.signInSteps.isEmpty {
                        Text(session.signInSteps.joined(separator: " › "))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                .transition(.opacity)
            }
        }
        .task(id: isStalled) {
            guard !isStalled else { return }
            try? await Task.sleep(for: .seconds(12))
            withAnimation { isStalled = true }
        }
    }
}
