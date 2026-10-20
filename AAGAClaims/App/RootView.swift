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
                if session.isRestoringSession {
                    // A saved session is coming back: no welcome screen flash.
                    BrandBackdrop { BrandLogo(layout: .stacked).padding(Theme.Spacing.xl) }
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
