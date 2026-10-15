import SwiftUI

/// A subject with suggestions, like desktop's Subject combobox: while the field is focused, the
/// matching subjects show under it (all of them when it's empty); tapping one fills it in. Any
/// text can still be typed.
struct SubjectField: View {
    @Binding var text: String
    let suggestions: [String]
    var identifier: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Subject", text: $text)
            .focused($focused)
            .accessibilityHint(suggestions.isEmpty ? "" : "Suggestions show below as you type")
            .accessibilityIdentifier(identifier)
        if focused {
            ForEach(suggestions.prefix(8), id: \.self) { subject in
                Button {
                    text = subject
                    focused = false
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "text.badge.checkmark")
                            .foregroundStyle(Color.brandPrimary)
                            .accessibilityHidden(true)
                        Text(subject)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use subject \(subject)")
                .accessibilityIdentifier("subjectSuggestion")
            }
        }
    }
}
