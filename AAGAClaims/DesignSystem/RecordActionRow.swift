import SwiftUI

/// One button in a record's action row.
struct RecordActionItem: Identifiable {
    let id: String
    /// Under the icon.
    let title: String
    /// In the More menu, and read out by VoiceOver.
    let menuTitle: String
    let icon: String
    let action: () -> Void
}

/// The actions under a claim's or lead's header, as icon tiles straight on the page (no card). As many as fit
/// the width show: about five on an iPhone, fewer on a small screen or at larger text, more on an iPad. The
/// rest are in a More menu.
struct RecordActionRow: View {
    let items: [RecordActionItem]
    /// "claimAction" or "leadAction": the prefix of each button's accessibility identifier.
    let idPrefix: String
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .caption) private var slot: CGFloat = 60
    @Environment(\.isOffline) private var isOffline

    var body: some View {
        let capacity = max(3, Int(width / slot))
        let fits = items.count <= capacity
        let shown = fits ? items : Array(items.prefix(capacity - 1))
        let rest = fits ? [] : Array(items.dropFirst(capacity - 1))
        let tile = width > 0 ? width / CGFloat(capacity) : slot
        HStack(alignment: .top, spacing: 0) {
            ForEach(shown) { item in
                Button(action: item.action) {
                    ActionCircle(title: item.title, icon: item.icon)
                }
                .buttonStyle(ActionCirclePressStyle())
                .disabledWhenOffline(isOffline)
                .accessibilityLabel(item.menuTitle)
                .accessibilityIdentifier("\(idPrefix)-\(item.id)")
                .frame(width: tile)
            }
            if !rest.isEmpty {
                Menu {
                    ForEach(rest) { item in
                        Button(action: item.action) { Label(item.menuTitle, systemImage: item.icon) }
                            .accessibilityIdentifier("\(idPrefix)-\(item.id)")
                    }
                } label: {
                    ActionCircle(title: "More", icon: "ellipsis")
                }
                .buttonStyle(ActionCirclePressStyle())
                .disabledWhenOffline(isOffline)
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("\(idPrefix)More")
                .frame(width: tile)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
