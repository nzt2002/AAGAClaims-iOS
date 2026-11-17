import PortalKit
import SwiftUI

/// A claim's or lead's header as the website's phone layout draws it: a light card with a soft tinted corner and a coloured
/// edge along the top, the status chip, the name, the claim and policy numbers as labelled fields, the address as a link
/// to Maps, and a quiet pencil at the top right.
struct RecordCardHeader: View {
    let isLead: Bool
    let chip: String?
    let name: String
    /// Label and value, shown side by side under the name.
    let facts: [(label: String, value: String)]
    let address: String?
    /// Staff: the pencil.
    var onEdit: (() -> Void)? = nil
    var editLabel = "Edit"
    var editIdentifier = "recordEdit"

    private var accent: Color { Color.recordAccent(isLead: isLead) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let chip = PortalFormat.nonEmpty(chip) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(chip)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 3)
                .background(accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
            }
            Text(name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !facts.isEmpty {
                // Wraps to a second line at large text sizes.
                AdaptiveStack(horizontalAlignment: .top, verticalAlignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label.uppercased())
                                .font(.caption2.weight(.medium))
                                .tracking(0.7)
                                .foregroundStyle(Color.textSecondary)
                            Text(fact.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let address = PortalFormat.nonEmpty(address), let url = ContactURL.map(address) {
                Link(destination: url) {
                    Label {
                        Text(address.replacingOccurrences(of: "\n", with: ", "))
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Theme.minTapTarget - 12, alignment: .leading)
                }
                .accessibilityHint("Opens in Maps")
                .accessibilityIdentifier("headerAddressLink")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
        .padding(.trailing, onEdit == nil ? 0 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .top) {
                Color.surface
                RadialGradient(colors: [accent.opacity(0.13), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                LinearGradient(colors: [accent, accent.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if let onEdit {
                EditPencil(label: editLabel, identifier: editIdentifier, action: onEdit)
                    .padding(Theme.Spacing.xs)
            }
        }
    }
}

private struct EditPencil: View {
    let label: String
    let identifier: String
    let action: () -> Void
    @Environment(\.isOffline) private var isOffline

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabledWhenOffline(isOffline)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// The stage track (staff), as on the website: the current stage and how far along in words, what's next, and a rail of
/// dots: finished stages ticked, the current one as an orb, the rest hollow. It only shows where the record is; the Status
/// button changes it.
struct StageTrackCard: View {
    let stages: [String]
    /// 0-based; nil when the status isn't one of the stages.
    let current: Int?
    let fallbackLabel: String?
    let isLead: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color.recordAccent(isLead: isLead) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline, verticalAlignment: .leading, spacing: Theme.Spacing.s) {
                if let current {
                    (Text(stages[current]).font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary)
                     + Text(" · Stage \(current + 1) of \(stages.count)").font(.subheadline).foregroundStyle(Color.textSecondary))
                } else {
                    Text(PortalFormat.nonEmpty(fallbackLabel) ?? "Status not set")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                AdaptiveSpacer()
                if let current, current + 1 < stages.count {
                    Text("Next: \(stages[current + 1])")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            if let current { rail(current) }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { "\(stages[$0]), stage \($0 + 1) of \(stages.count)" } ?? (fallbackLabel ?? "Status not set"))
        .accessibilityIdentifier("stageTrack")
    }

    private func rail(_ current: Int) -> some View {
        let n = stages.count
        return GeometryReader { proxy in
            let col = proxy.size.width / CGFloat(n)
            let fill = n > 1 ? CGFloat(current) / CGFloat(n - 1) * (proxy.size.width - col) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.border.opacity(0.7)).frame(width: proxy.size.width - col, height: 6).offset(x: col / 2)
                Capsule().fill(LinearGradient(colors: [accent.opacity(0.7), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fill, height: 6).offset(x: col / 2)
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { index in
                        dot(index < current ? .done : index == current ? .now : .todo)
                            .frame(width: col, height: 30)
                    }
                }
            }
        }
        .frame(height: 30)
    }

    private enum DotState { case done, now, todo }

    @ViewBuilder
    private func dot(_ state: DotState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(accent, in: Circle())
        case .now:
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 42, height: 42)
                Circle().fill(accent).frame(width: 28, height: 28)
                Circle().fill(.white).frame(width: 10, height: 10)
            }
            .frame(width: 28, height: 28)
        case .todo:
            Circle().fill(Color.surface).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.border, lineWidth: 2))
        }
    }
}
