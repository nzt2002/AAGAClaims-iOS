import SwiftUI

extension View {
    /// On a claim or lead page: tapping a phone number offers to call over the business line in
    /// the app (logged on this record) or from the iPhone's own number. Without in-app calling,
    /// phone links behave as before. Other links go on to the handler above (e.g. in-app Safari).
    func businessLineCalls(recordId: String, recordName: String?) -> some View {
        modifier(BusinessLineCallsModifier(recordId: recordId, recordName: recordName))
    }
}

private struct BusinessLineCallsModifier: ViewModifier {
    let recordId: String
    let recordName: String?

    @Environment(\.openURL) private var openURL
    @State private var pending: URL?
    private var calls: CallManager { CallManager.shared }

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme?.lowercased() == "tel", calls.isEnabled else {
                    openURL(url)
                    return .handled
                }
                pending = url
                return .handled
            })
            .confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
                if let url = pending {
                    Button(businessLineLabel) {
                        calls.start(to: number(url), recordId: recordId, name: recordName)
                    }
                    .disabled(calls.hasActiveCall)
                    Button("Call from my iPhone") { openURL(ContactURL.nativeTel(url)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Business-line calls show your work number and are logged on this record.")
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var title: String {
        guard let url = pending else { return "Call" }
        let parts = number(url).components(separatedBy: " x")
        let shown = CallManager.display(parts[0]) ?? parts[0]
        return "Call \(parts.count > 1 ? shown + " x" + parts[1] : shown)"
    }

    private var businessLineLabel: String {
        if let line = CallManager.display(calls.businessLine) {
            return "Call from business line \(line)"
        }
        return "Call from business line"
    }

    private func number(_ url: URL) -> String {
        // "tel:8005551234,1,,40182": everything after the first comma is the dial script, played in the call once connected.
        let value = String(url.absoluteString.dropFirst("tel:".count)).removingPercentEncoding ?? ""
        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let raw = (parts.first ?? "").filter { $0.isNumber || $0 == "+" }
        let script = parts.count > 1 ? parts[1].filter { $0.isNumber || ",#*w".contains($0) || $0.isLetter } : ""
        let base = raw.hasPrefix("+") ? raw
            : raw.count == 10 ? "+1" + raw : (raw.count == 11 && raw.hasPrefix("1") ? "+" + raw : raw)
        return script.isEmpty ? base : base + " x" + script
    }
}
