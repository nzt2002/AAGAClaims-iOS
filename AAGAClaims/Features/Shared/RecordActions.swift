import PortalKit
import SwiftUI

/// The Add Comment / Request Assistance bar shared by claim and lead detail (spec §6.5, §6.7),
/// with its composer sheet and confirmation alert.
struct RecordActions: ViewModifier {
    let record: RecordRef
    let recordName: String
    let api: PortalAPI
    /// Called after a comment is sent, e.g. to refresh a lead's updates.
    var onCommentSent: () -> Void = {}

    @Environment(\.openSupport) private var openSupport
    @Environment(\.isOffline) private var isOffline
    @State private var composer: ComposerViewModel.Kind?
    @State private var confirmation: Confirmation?

    private struct Confirmation: Identifiable {
        let message: String
        let caseId: String?
        var id: String { message + (caseId ?? "") }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) { bar }
            .sheet(item: $composer, content: sheet)
            .alert("Thank you", isPresented: showingConfirmation, presenting: confirmation, actions: actions) {
                Text($0.message)
            }
    }

    private var bar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if isOffline {
                OfflineHint()
            }
            buttons
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    private var buttons: some View {
        AdaptiveStack(spacing: Theme.Spacing.m) {
            Button {
                composer = .comment
            } label: {
                Label("Add Comment", systemImage: "text.bubble")
                    .foregroundStyle(Color.brandPrimaryDark)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.bordered)
            .disabledWhenOffline(isOffline)
            .accessibilityIdentifier("addComment")

            Button {
                composer = .assistance
            } label: {
                Label("Ask Question", systemImage: "questionmark.bubble")
                    .foregroundStyle(Color.surface)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabledWhenOffline(isOffline)
            .accessibilityIdentifier("requestAssistance")
        }
        .font(.subheadline.weight(.semibold))
    }

    private func sheet(_ kind: ComposerViewModel.Kind) -> some View {
        ComposerSheet(
            viewModel: ComposerViewModel(kind: kind, record: record, api: api),
            recordName: recordName,
            onSuccess: handle
        )
    }

    private var showingConfirmation: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    @ViewBuilder
    private func actions(_ confirmation: Confirmation) -> some View {
        if let caseId = confirmation.caseId {
            Button("View case") { openSupport(caseId: caseId) }
        }
        Button("OK", role: .cancel) {}
    }

    private func handle(_ outcome: ComposerViewModel.Outcome) {
        switch outcome {
        case .commentSent:
            onCommentSent()
            confirmation = Confirmation(
                message: "Your comment has been submitted. Your account manager has been notified.",
                caseId: nil
            )
        case .caseCreated(let caseId):
            confirmation = Confirmation(
                message: "Your request has been submitted. We will follow up with you shortly.",
                caseId: caseId
            )
        }
    }
}

extension View {
    func recordActions(
        record: RecordRef,
        recordName: String,
        api: PortalAPI,
        onCommentSent: @escaping () -> Void = {}
    ) -> some View {
        modifier(RecordActions(record: record, recordName: recordName, api: api, onCommentSent: onCommentSent))
    }
}

extension ComposerViewModel.Kind: Identifiable {
    public var id: Self { self }
}
