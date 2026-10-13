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
                    .environment(session.uploads)
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            // Placeholder until the designer supplies the vector logo (spec §9).
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
                .padding(Theme.Spacing.xl)
                .background(.white.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text("Accurate Adjustments")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("We're here to help with your claim")
                .foregroundStyle(.white)
            Spacer()
            if isDemo {
                Button(action: continueInDemo) {
                    Text("Continue in demo mode")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0x01 / 255, green: 0x44 / 255, blue: 0x86 / 255))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: Capsule())
                }
                .accessibilityIdentifier("continueDemo")
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Signing in")
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandGradient.hero(colorScheme).ignoresSafeArea())
    }
}
