import PortalKit
import SwiftUI

/// A row of capsule filter chips that scrolls sideways, used above the Claims and Leads lists and
/// for Home's activity filters, so every filter looks the same.
struct ChipBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                content()
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// The capsule look for chips: brand-filled when active, outlined otherwise.
private struct ChipLabel: View {
    let title: String
    var systemImage: String?
    let isActive: Bool
    var showsMenuIndicator = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isActive ? Color.surface : Color.textPrimary)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: Theme.minTapTarget - 8)
        .background {
            Capsule().fill(isActive ? Color.brandPrimary : Color.surface)
        }
        .overlay {
            Capsule().stroke(isActive ? Color.clear : Color.border, lineWidth: 1)
        }
        .contentShape(Capsule())
        .frame(minHeight: Theme.minTapTarget)
        .animation(.snappy, value: isActive)
    }
}

/// An on/off chip, e.g. "Open" or "Mine".
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isActive)
    }
}

/// A chip that opens a menu of choices, e.g. "Stage ▾"; shows the choice when one is picked.
struct MenuChip<Options: View>: View {
    /// "Stage" when nothing is picked.
    let title: String
    /// The picked value, or nil.
    let value: String?
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            options()
        } label: {
            ChipLabel(title: value.map { "\(title): \($0)" } ?? title, isActive: value != nil, showsMenuIndicator: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(value != nil ? .isSelected : [])
    }
}

/// "Clear" at the end of the chip bar when any filter is on.
struct ClearChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: "Clear", systemImage: "xmark", isActive: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear filters")
        .accessibilityIdentifier("filterChip-clear")
    }
}

/// The toolbar sort menu for the lists.
struct SortMenu: View {
    @Binding var order: ListSortOrder

    var body: some View {
        Menu {
            Picker("Sort by", selection: $order) {
                ForEach(ListSortOrder.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
        }
        .accessibilityLabel("Sort, \(order.rawValue)")
        .accessibilityIdentifier("sortMenu")
    }
}

/// Saves a list's filters and sort on this device, so it opens the way the user left it.
enum ListFilterMemory {
    static func load(_ list: String) -> ListFilterState? {
        guard let data = UserDefaults.standard.data(forKey: "listFilters.\(list)") else { return nil }
        return try? JSONDecoder().decode(ListFilterState.self, from: data)
    }

    static func save(_ state: ListFilterState, for list: String) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "listFilters.\(list)")
        }
    }
}
