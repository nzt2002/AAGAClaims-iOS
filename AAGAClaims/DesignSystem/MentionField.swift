import PortalKit
import SwiftUI

/// A text field with @mentions: typing "@" and a name shows matching people; tapping one inserts
/// "@Full Name" and records them, so the post or reply notifies them in Chatter.
struct MentionField: View {
    let prompt: String
    @Binding var draft: MentionDraft
    let search: (String) async -> [Mention]
    var lineLimit: ClosedRange<Int> = 1...5
    var autofocus = false
    /// A tinted rounded box around the field (inline composers); off inside Forms.
    var boxed = true
    var identifier: String

    @State private var suggestions: [Mention] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            TextField(prompt, text: $draft.text, axis: .vertical)
                .lineLimit(lineLimit)
                .padding(boxed ? Theme.Spacing.s : 0)
                .background(boxed ? Color.surfaceTinted : .clear, in: RoundedRectangle(cornerRadius: 10))
                .focused($focused)
                .accessibilityHint("Type @ and a name to mention someone")
                .accessibilityIdentifier(identifier)
                .onAppear { if autofocus { focused = true } }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { person in
                        Button {
                            draft.insert(person)
                            suggestions = []
                        } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                Text(initials(person.name))
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.brandPrimary, in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(person.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary)
                                    if let title = PortalFormat.nonEmpty(person.title) {
                                        Text(title).font(.caption).foregroundStyle(Color.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: Theme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mention \(person.name)")
                        .accessibilityIdentifier("mention-\(person.id)")
                    }
                }
                .padding(.horizontal, Theme.Spacing.s)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
            }
        }
        .task(id: draft.activeQuery) {
            guard let query = draft.activeQuery, !query.isEmpty else {
                suggestions = []
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            suggestions = Array(await search(query).prefix(5))
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Post or reply text with each @mentioned name in bold brand blue.
func mentionText(_ text: String, mentions: [String]?) -> AttributedString {
    var attributed = AttributedString(text)
    for name in mentions ?? [] {
        var searchStart = attributed.startIndex
        while let range = attributed[searchStart...].range(of: "@" + name) ?? attributed[searchStart...].range(of: name) {
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            attributed[range].foregroundColor = Color.brandPrimary
            searchStart = range.upperBound
        }
    }
    return attributed
}
