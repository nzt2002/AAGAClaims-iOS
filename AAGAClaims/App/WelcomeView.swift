import SwiftUI

/// Signed out: the brand, what the app does, and Sign In. Salesforce's sign-in sheet opens only
/// when the user taps Sign In, so the app never opens onto a web page.
struct WelcomeView: View {
    let isDemo: Bool
    let isSigningIn: Bool
    let signIn: () -> Void
    let continueInDemo: () -> Void

    @State private var showingHelp = false
    @Environment(\.colorScheme) private var colorScheme

    private static let forgotPasswordURL = URL(string: "https://portal.accurateadjustmentsga.com/s/login/ForgotPassword")!

    var body: some View {
        BrandBackdrop {
            ScrollView {
                VStack(spacing: 0) {
                    BrandLogo(layout: .stacked)
                        .padding(.top, 72)
                        .padding(.horizontal, Theme.Spacing.xl)

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        feature("chart.line.uptrend.xyaxis", "Follow every step of your claim")
                        feature("bell.badge", "Get updates and payments as they happen")
                        feature("doc.on.doc", "Share photos and documents with your team")
                    }
                    .padding(.vertical, Theme.Spacing.xl)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .frame(maxWidth: 480)

                    Spacer(minLength: Theme.Spacing.l)

                    signInCard
                }
                .frame(minHeight: UIScreen.main.bounds.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $showingHelp) {
            SafariView(url: Self.forgotPasswordURL).ignoresSafeArea()
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The white card at the bottom, like Salesforce's sign-in panel.
    private var signInCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Welcome")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(isDemo ? "Explore the app with sample claims and leads." : "Sign in with your ProClaimer portal account.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isDemo {
                Button(action: continueInDemo) {
                    Text("Continue in demo mode")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.brandPrimary)
                .accessibilityIdentifier("continueDemo")
            } else {
                Button(action: signIn) {
                    HStack(spacing: Theme.Spacing.s) {
                        if isSigningIn {
                            ProgressView().tint(.white)
                        }
                        Text(isSigningIn ? "Signing in…" : "Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.brandPrimary)
                .disabled(isSigningIn)
                .accessibilityIdentifier("signIn")

                Button("Trouble signing in?") { showingHelp = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    .accessibilityIdentifier("signInHelp")
            }

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
}

#Preview("Welcome") {
    WelcomeView(isDemo: false, isSigningIn: false, signIn: {}, continueInDemo: {})
}
