import PortalKit
import SafariServices
import SwiftUI

/// tel:, mailto: and Apple Maps URLs for tap-to-call / email / map (spec §8).
enum ContactURL {
    static func phone(_ number: String?) -> URL? {
        guard let number = PortalFormat.nonEmpty(number) else { return nil }
        let digits = number.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    static func email(_ address: String?) -> URL? {
        guard let address = PortalFormat.nonEmpty(address), address.contains("@") else { return nil }
        return URL(string: "mailto:\(address)")
    }

    static func map(_ address: String?) -> URL? {
        guard let address = PortalFormat.nonEmpty(address) else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address.replacingOccurrences(of: "\n", with: ", "))]
        return components?.url
    }

    static func web(_ string: String?) -> URL? {
        guard let string = PortalFormat.nonEmpty(string), let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}

/// A labelled row whose value opens a URL. Hidden when there's no value.
struct LinkRow: View {
    let label: String
    let value: String?
    let url: URL?
    let systemImage: String
    /// VoiceOver action name, e.g. "Call" or "Email".
    var actionName: String = "Open"

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let value = PortalFormat.nonEmpty(value) {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    row(value, tinted: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(value)")
                .accessibilityHint("\(actionName)")
            } else {
                row(value, tinted: false)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ value: String, tinted: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(tinted ? Color.brandPrimary : Color.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
    }
}

/// A plain labelled value row. Hidden when there's no value.
struct FieldRow: View {
    let label: String
    let value: String?
    var systemImage: String?

    var body: some View {
        if let value = PortalFormat.nonEmpty(value) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.minTapTarget)
            .accessibilityElement(children: .combine)
        }
    }
}

/// An HTML update body, rendered safely (see `HTMLText`).
struct RichText: View {
    let html: String?

    var body: some View {
        Text(HTMLText.attributed(html))
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .tint(.brandPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// Web links open in SFSafariViewController (spec §3); tel:, mailto: and maps go to the system.
struct SafariLink: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Routes web links from anywhere below into an in-app Safari sheet.
    func opensWebLinksInSafari(_ link: Binding<SafariLink?>) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host() != "maps.apple.com" else {
                return .systemAction
            }
            link.wrappedValue = SafariLink(url: url)
            return .handled
        })
        .sheet(item: link) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}

/// Lets screens deep in a tab jump to Support (e.g. after Request Assistance).
struct OpenSupportAction {
    let action: (_ caseId: String?) -> Void

    func callAsFunction(caseId: String? = nil) {
        action(caseId)
    }
}

/// Opens a claim or lead in its tab (e.g. a lead's new claim after Convert to Account).
struct OpenRecordAction {
    let action: (_ record: RecordRef, _ name: String?) -> Void

    func callAsFunction(_ record: RecordRef, name: String?) {
        action(record, name)
    }
}

extension EnvironmentValues {
    @Entry var openSupport = OpenSupportAction { _ in }
    @Entry var openRecord = OpenRecordAction { _, _ in }
}
