import PortalKit
import SafariServices
import SwiftUI

/// tel:, mailto: and Apple Maps URLs for tap-to-call / email / map (spec §8).
enum ContactURL {
    static func phone(_ number: String?) -> URL? {
        guard let number = PortalFormat.nonEmpty(number) else { return nil }
        return URL(string: "tel:" + telValue(number))
    }

    /// The number as a tel: value, keeping the dial script that follows an extension marker
    /// ("800-555-1234 x1,,40182" → "8005551234,1,,40182"). Commas wait on the iPhone dialer, and
    /// in-app calls play the whole script into the call once connected.
    static func telValue(_ number: String) -> String {
        let (base, script) = splitExtension(number)
        let digits = base.filter { $0.isNumber || $0 == "+" }
        guard let script, !digits.isEmpty else { return digits }
        let encoded = script.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ",*"))) ?? ""
        return digits + "," + encoded
    }

    /// The same number for the iPhone's own dialer: only keys and waits, since it can't say "continue".
    static func nativeTel(_ url: URL) -> URL {
        let value = String(url.absoluteString.dropFirst("tel:".count)).removingPercentEncoding ?? ""
        let keys = value.replacingOccurrences(of: "continue", with: "").filter { $0.isNumber || "+,#*".contains($0) }
        return URL(string: "tel:" + (keys.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "+,*"))) ?? keys)) ?? url
    }

    /// Splits "(800) 555-1234 x continue, 40182" into the number and its dial script (digits, # *,
    /// commas for 2 second waits, and the spoken word "continue"). Only when the part before the
    /// marker has at least 10 digits, so short codes are left alone.
    static func splitExtension(_ raw: String) -> (number: String, script: String?) {
        let pattern = #"^(.*?)\s*(?:extension|ext\.?|x|#|,|;)\s*((?:continue|[0-9#*,w\s])+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let baseRange = Range(m.range(at: 1), in: raw), let scriptRange = Range(m.range(at: 2), in: raw),
              raw[baseRange].filter(\.isNumber).count >= 10 else { return (raw, nil) }
        let script = String(raw[scriptRange]).lowercased().filter { !$0.isWhitespace }
        guard script.count <= 40, script.contains(where: \.isNumber) || script.contains("continue") else { return (raw, nil) }
        return (String(raw[baseRange]), script)
    }

    /// With a `reference` (the claim or lead's email ID), the draft ends with it, so replies
    /// that quote it can be filed on the record.
    static func email(_ address: String?, reference: String? = nil) -> URL? {
        guard let address = PortalFormat.nonEmpty(address), address.contains("@") else { return nil }
        guard let footer = EmailReference.footer(reference) else { return URL(string: "mailto:\(address)") }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "body", value: "\n\n" + footer)]
        return components.url
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
    @Environment(\.isLeadRecord) private var isLead

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
            Image(systemName: systemImage).iconShadow()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(tinted ? Color.recordAccent(isLead: isLead) : Color.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
    }
}

/// The loss address under a record's hero: tap to open Apple Maps. Hidden when there's no address.
struct LossAddressCard: View {
    let address: String?
    @Environment(\.isLeadRecord) private var isLead

    var body: some View {
        if let address = PortalFormat.nonEmpty(address) {
            LinkRow(label: "Loss address", value: address, url: ContactURL.map(address),
                    systemImage: "mappin.and.ellipse", actionName: "Open in Maps")
                .overlay(alignment: .trailing) {
                    Image(systemName: "map").iconShadow()
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.recordAccent(isLead: isLead))
                        .accessibilityHidden(true)
                }
                .cardStyle()
                .accessibilityIdentifier("lossAddressCard")
        }
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
                    Image(systemName: systemImage).iconShadow()
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

/// A labelled value with a Copy button. Hidden when there's no value.
struct CopyFieldRow: View {
    let label: String
    let value: String?
    var systemImage: String?
    @State private var copied = false

    var body: some View {
        if let value = PortalFormat.nonEmpty(value) {
            HStack(spacing: Theme.Spacing.s) {
                FieldRow(label: label, value: value, systemImage: systemImage)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = value
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
                .accessibilityLabel(copied ? "Copied" : "Copy \(label)")
                .accessibilityIdentifier("copy-\(label)")
            }
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
            .tint(.brandTheme)
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
    /// The open claim or lead's email ID ("ref_ (…)"), added to the bottom of emails started from its page.
    @Entry var emailReference: String?
    @Entry var openSupport = OpenSupportAction { _ in }
    @Entry var openRecord = OpenRecordAction { _, _ in }
}
