import PortalKit
import SwiftUI

/// Staff: "Create Recent Portal Update" on a claim or lead (as in Salesforce): an AI draft from the
/// last 30 days of activity to review, who to email, then Post. Customers see it on the portal and in the app.
struct PortalUpdateComposer: View {
    @State private var model: PortalUpdateComposerViewModel
    let posted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didPost = false

    init(api: PortalAPI, record: RecordRef, posted: @escaping () async -> Void) {
        _model = State(initialValue: PortalUpdateComposerViewModel(api: api, record: record))
        self.posted = posted
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.isLoading {
                    Section {
                        HStack(spacing: Theme.Spacing.m) {
                            ProgressView()
                            Text("Reading the last 30 days of activity and writing a draft…")
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(minHeight: Theme.minTapTarget)
                    }
                } else {
                    if let notice = model.notice {
                        Section {
                            Label(notice, systemImage: "info.circle")
                                .foregroundStyle(Color.warning)
                        }
                    }
                    Section {
                        TextField("What's new on this \(noun)?", text: $model.text, axis: .vertical)
                            .lineLimit(8...24)
                            .accessibilityIdentifier("portalUpdateText")
                    } header: {
                        Text("Update")
                    } footer: {
                        Text(model.hasNewActivity
                             ? "Customers see this on the portal and in the app. Use **bold** for headings and \"- \" for bullets."
                             : "Nothing new in the last 30 days, so this is the standard message. Edit it if you have news.")
                    }
                    emailSection
                    ErrorRow(message: model.errorMessage)
                }
            }
            .navigationTitle("Portal Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FormToolbar(saveTitle: "Post", isSaving: model.isPosting, canSave: model.canPost) {
                    if await model.post() != nil {
                        didPost = true
                        await posted()
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: didPost) { _, new in new }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var emailSection: some View {
        Section {
            Toggle("Email this update", isOn: $model.sendEmail)
                .disabled(model.recipients.isEmpty)
                .accessibilityIdentifier("portalUpdateEmail")
            if model.sendEmail {
                ForEach(model.recipients) { recipient in
                    Toggle(isOn: Binding(
                        get: { model.selectedRecipientIds.contains(recipient.id) },
                        set: { on in
                            if on { model.selectedRecipientIds.insert(recipient.id) } else { model.selectedRecipientIds.remove(recipient.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipient.name ?? recipient.email ?? "Portal user")
                            if let email = recipient.email, recipient.name != nil {
                                Text(email).font(.caption).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
        } footer: {
            if model.recipients.isEmpty {
                Text("Nobody on this \(noun) uses the portal, so there's no one to email.")
            }
        }
    }

    private var noun: String {
        if case .lead = model.record { "lead" } else { "claim" }
    }
}

/// The "Write Portal Update" button above a record's portal updates (staff, when the server supports it).
struct PortalUpdateButton: View {
    let api: PortalAPI
    let record: RecordRef
    let posted: () async -> Void
    @State private var showing = false
    @Environment(\.isLeadRecord) private var isLead

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("Write Portal Update", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.recordAccent(isLead: isLead))
        .accessibilityIdentifier("writePortalUpdate")
        .sheet(isPresented: $showing) {
            PortalUpdateComposer(api: api, record: record, posted: posted)
        }
    }
}
