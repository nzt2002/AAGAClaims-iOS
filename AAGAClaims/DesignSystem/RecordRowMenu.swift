import PortalKit
import SwiftUI
import UIKit

extension PortalFormat {
    /// "2 hours ago" for the last few days, a date after that, so a list shows what moved lately.
    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSinceNow) < 7 * 86_400 {
            return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
        }
        return PortalFormat.date(date)
    }
}

extension View {
    /// Press and hold a claim or lead in a list: directions to the loss address, copy the address or the number.
    func recordRowMenu(address: String?, number: String?) -> some View {
        contextMenu {
            if let url = ContactURL.map(address) {
                Link(destination: url) { Label("Directions", systemImage: "map") }
            }
            if let address = PortalFormat.nonEmpty(address) {
                Button {
                    UIPasteboard.general.string = address.replacingOccurrences(of: "\n", with: ", ")
                } label: { Label("Copy address", systemImage: "doc.on.doc") }
            }
            if let number = PortalFormat.nonEmpty(number) {
                Button { UIPasteboard.general.string = number } label: { Label("Copy number", systemImage: "number") }
            }
        }
    }
}

/// Shown under the offline banner (and after it) while posts written offline wait to send.
struct QueuedBanner: View {
    private var outbox: Outbox { Outbox.shared }

    var body: some View {
        if outbox.pendingCount > 0 {
            let count = outbox.pendingCount
            Label(count == 1 ? "1 update waiting to send" : "\(count) updates waiting to send", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(Color.textPrimary)
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .background(Color.brandTheme.opacity(0.12))
                .accessibilityIdentifier("queuedBanner")
        }
    }
}
