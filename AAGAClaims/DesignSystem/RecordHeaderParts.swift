import PortalKit
import SwiftUI

/// The loss address in a record's header, under the claim and policy numbers: a link that opens Maps.
struct HeaderAddressLink: View {
    let address: String?

    var body: some View {
        if let address = PortalFormat.nonEmpty(address), let url = ContactURL.map(address) {
            Link(destination: url) {
                Label(address.replacingOccurrences(of: "\n", with: ", "), systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Theme.minTapTarget, alignment: .leading)
            }
            .accessibilityHint("Opens in Maps")
            .accessibilityIdentifier("headerAddressLink")
        }
    }
}

/// The pencil at the header's top right that edits the record.
struct HeaderEditButton: View {
    let label: String
    let identifier: String
    let action: () -> Void
    @Environment(\.isOffline) private var isOffline

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: Circle())
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabledWhenOffline(isOffline)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
