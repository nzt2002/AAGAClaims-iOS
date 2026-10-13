import PortalKit
import SwiftUI

struct StatusPill: View {
    enum Tone {
        case neutral, active, success, warning

        var foreground: Color {
            switch self {
            case .neutral: .textSecondary
            case .active: .brandPrimaryDark
            case .success: .success
            case .warning: .warning
            }
        }
    }

    let text: String
    var tone: Tone = .active

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 5)
            .background(tone.foreground.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tone.foreground.opacity(0.18), lineWidth: 1))
            .accessibilityLabel("Status: \(text)")
    }

    static func tone(forClaimStatus status: String?) -> Tone {
        switch ClaimLifecycle.position(for: status) {
        case .stage(let index) where index == ClaimLifecycle.stages.count - 1: .success
        case .stage: .active
        case .unknown: .neutral
        }
    }

    static func tone(forLeadStatus status: String?) -> Tone {
        switch status?.lowercased() {
        case "converted": .success
        case "unqualified": .warning
        case .none: .neutral
        default: .active
        }
    }
}

struct ProgressBar: View {
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ProgressView(value: Double(percent), total: 100)
                .tint(.brandPrimary)
            Text("\(percent)% complete")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent complete")
    }
}

/// A labelled value that hides itself when there's no value.
struct InfoRow: View {
    let label: String
    let value: String?
    var systemImage: String?

    var body: some View {
        if let value = PortalFormat.nonEmpty(value) {
            Label {
                Text(value)
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .font(.subheadline)
            .accessibilityLabel("\(label): \(value)")
        }
    }
}

/// Loading placeholders: skeletons, not spinners (spec §7).
struct SkeletonList: View {
    var rows = 4

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(0..<rows, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Placeholder claim name")
                        .font(.headline)
                    Text("Placeholder address line, City, ST 00000")
                    Text("Placeholder status and details")
                }
                .cardStyle()
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

struct ErrorStateView: View {
    /// e.g. "claims", giving "Unable to load claims."
    let subject: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Unable to load \(subject). Pull to refresh or contact support.")
        } actions: {
            Button(action: retry) {
                Text("Retry").foregroundStyle(Color.surface)
            }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Theme.minTapTarget)
        }
    }
}

/// Shows a skeleton while loading for the first time, an error with Retry, or the content.
struct LoadingContainer<Value: Sendable, Content: View>: View {
    let state: LoadState<Value>
    let subject: String
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ScrollView {
                SkeletonList()
                    .padding(Theme.Spacing.l)
            }
        case .failed:
            ErrorStateView(subject: subject, retry: retry)
        case .loaded(let value, _):
            content(value)
        }
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo mode: sample data, not your account.", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(Color.brandPrimaryDark)
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceTintedStrong)
    }
}

extension View {
    /// Pins the demo and offline banners under the navigation bar, so they never cover toolbar buttons.
    func statusBanners(_ session: AppSession) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if session.offline.isOffline {
                    OfflineBanner(showingDataFrom: session.offline.showingDataFrom)
                }
                if session.isDemo {
                    DemoBanner()
                }
            }
            // Large but capped, so the banners never crowd out the screen at accessibility sizes.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}
