import PortalKit
import SwiftUI

struct RootView: View {
    let session: AppSession

    var body: some View {
        ZStack {
            switch session.state {
            case .signingIn:
                SplashView(isDemo: session.isDemo) {
                    session.didSignIn(.demo)
                }
            case .signedIn(let user):
                MainTabView(session: session, user: user)
                if session.lock.isLocked {
                    LockScreen(lock: session.lock)
                }
            }
            if session.isShielded {
                PrivacyShield()
            }
        }
    }
}

/// Shown behind the SDK's login screen, and after signing out in demo mode.
struct SplashView: View {
    let isDemo: Bool
    let continueInDemo: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            // Placeholder until the designer supplies the vector logo (spec §9).
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text("Accurate Adjustments")
                .font(.title.bold())
                .foregroundStyle(Color.textPrimary)
            Text("We're here to help with your claim")
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if isDemo {
                Button(action: continueInDemo) {
                    Text("Continue in demo mode").foregroundStyle(Color.surface)
                }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Theme.minTapTarget)
                    .accessibilityIdentifier("continueDemo")
            } else {
                ProgressView()
                    .accessibilityLabel("Signing in")
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
