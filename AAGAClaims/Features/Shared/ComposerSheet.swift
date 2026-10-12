import PortalKit
import SwiftUI

/// "Regarding {record}" sheet for Add Comment and Request Assistance (spec §6.5).
struct ComposerSheet: View {
    @State var viewModel: ComposerViewModel
    let recordName: String
    /// Called after a successful submit, before the sheet closes.
    let onSuccess: (ComposerViewModel.Outcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                TextEditor(text: $viewModel.text)
                    .focused($editorFocused)
                    .frame(minHeight: 180)
                    .padding(Theme.Spacing.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(viewModel.isOverLimit ? Color.warning : Color.border, lineWidth: 1)
                    )
                    .accessibilityLabel(viewModel.kind == .comment ? "Comment" : "Questions or comments")
                    .accessibilityIdentifier("composerText")

                HStack {
                    if viewModel.error != nil {
                        Label("We couldn't send that. Please try again.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warning)
                    }
                    Spacer()
                    Text("\(viewModel.count.formatted()) / \(viewModel.limit.formatted())")
                        .foregroundStyle(viewModel.isOverLimit ? Color.warning : Color.textSecondary)
                        .monospacedDigit()
                        .accessibilityLabel("\(viewModel.count) of \(viewModel.limit) characters")
                }
                .font(.caption)

                Spacer()
            }
            .padding(Theme.Spacing.l)
            .navigationTitle("Regarding \(recordName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .disabled(!viewModel.canSubmit)
                        .accessibilityIdentifier("composerSubmit")
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isSubmitting)
            .onAppear { editorFocused = true }
        }
    }

    private var prompt: String {
        switch viewModel.kind {
        case .comment:
            "Send a private note to your account manager."
        case .assistance:
            "Tell us what you need help with, and we'll follow up."
        }
    }

    private func submit() async {
        await viewModel.submit()
        if let outcome = viewModel.outcome {
            onSuccess(outcome)
            dismiss()
        }
    }
}

#Preview {
    ComposerSheet(
        viewModel: ComposerViewModel(kind: .comment, record: .claim("a0X000000000001AAA"), api: PreviewData.api()),
        recordName: "Smith - Roof",
        onSuccess: { _ in }
    )
}
