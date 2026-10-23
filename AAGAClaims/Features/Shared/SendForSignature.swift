import PortalKit
import SwiftUI

/// Staff: send a template for e-signature (in-house pilot). Signers are prefilled from the
/// record; for the LOR, signer 1 is the Public Adjuster and signer 2 the insured.
struct SendForSignatureView: View {
    let record: RecordRef
    let template: DocumentTemplate
    let api: PortalAPI
    let onSent: () -> Void

    @Environment(\.isOffline) private var isOffline
    @State private var signers: [SignerInput] = []
    @State private var message = ""
    @State private var loading = true
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if loading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                ForEach($signers) { $signer in
                    Section {
                        TextField("Name", text: binding($signer.name))
                            .textContentType(.name)
                            .accessibilityIdentifier("signerName\(signer.index)")
                        TextField("Email", text: binding($signer.email))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("signerEmail\(signer.index)")
                    } header: {
                        Text("Signer \(signer.index)\(signer.label.map { " · \($0)" } ?? "")")
                    }
                }
                Section {
                    TextField("Message to signers (optional)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Each signer gets an email with a personal link to review and sign. Links expire after 14 days; reminders go out on days 2 and 5.")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Send for Signature")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if sending {
                    ProgressView()
                } else {
                    Button("Send") { Task { await send() } }
                        .disabled(!canSend)
                        .accessibilityIdentifier("sendSignatureRequest")
                }
            }
        }
        .task { await load() }
    }

    private var canSend: Bool {
        !loading && !isOffline && !signers.isEmpty && signers.allSatisfy(\.isComplete)
    }

    private func binding(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 })
    }

    private func load() async {
        defer { loading = false }
        do {
            let setup = try await api.signingSetup(for: record, templateId: template.id)
            signers = setup.signers
        } catch {
            errorMessage = "Couldn't load the signers. Please try again."
        }
    }

    private func send() async {
        sending = true
        errorMessage = nil
        defer { sending = false }
        let trimmed = signers.map { s in
            var copy = s
            copy.name = s.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.email = s.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        do {
            let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await api.sendForSignature(templateId: template.id, signers: trimmed, message: note.isEmpty ? nil : note, for: record)
            onSent()
        } catch {
            switch error as? PortalAPIError {
            case .rejected(let text): errorMessage = text
            case .offline: errorMessage = "You're offline."
            default: errorMessage = "Couldn't send. Please try again."
            }
        }
    }
}

/// One signature request with its signers' progress.
struct SignatureRequestRow: View {
    let request: SignatureRequestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(request.subject ?? request.name ?? "Signature request")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(request.status)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
            ForEach(request.signers, id: \.self) { signer in
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: signer.status == "Signed" ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(signer.status == "Signed" ? .green : .secondary)
                    Text(signer.name ?? signer.email ?? "Signer")
                    Spacer()
                    Text(signer.status ?? "")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if let date = request.completedAt ?? request.sentAt {
                Text((request.completedAt != nil ? "Completed " : "Sent ") + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch request.status {
        case "Signed": .green
        case "Viewed": .orange
        case "Declined", "Expired", "Voided": .red
        default: .blue
        }
    }
}
