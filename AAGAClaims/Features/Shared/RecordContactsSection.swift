import PortalKit
import SwiftUI

/// Staff: the Contacts tab on a claim or lead. Claims list their Claim Contacts with roles;
/// leads list the homeowner, Subcontractor and Partner Account. Call and email buttons as in Contact Us.
struct RecordContactsSection: View {
    let state: LoadState<[RecordContact]>
    /// "claim" or "lead", for the empty message.
    let noun: String
    let retry: () async -> Void
    @Environment(\.emailReference) private var emailReference

    var body: some View {
        SectionLoader(state: state, subject: "contacts", retry: retry) { contacts in
            if contacts.isEmpty {
                Text(noun == "claim"
                     ? "No contacts on this claim yet. Use More → Add Contact to add one."
                     : "No contacts on this lead yet.")
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(contacts) { contact in
                        row(contact)
                        if contact.id != contacts.last?.id { Divider() }
                    }
                }
                .cardStyle()
                .accessibilityIdentifier("recordContacts")
            }
        }
        // The page may have loaded before the server said it supports contacts: load on first open.
        .task {
            if case .idle = state { await retry() }
        }
    }

    private func row(_ contact: RecordContact) -> some View {
        let name = PortalFormat.nonEmpty(contact.name) ?? PortalFormat.nonEmpty(contact.email) ?? "Contact"
        return AdaptiveStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if let role = PortalFormat.nonEmpty(contact.role) {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(details(contact), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                }
            }
            AdaptiveSpacer()
            HStack(spacing: Theme.Spacing.m) {
                if let url = ContactURL.phone(contact.mobilePhone ?? contact.phone) {
                    contactButton(url: url, systemImage: "phone.fill", label: "Call \(name)")
                }
                if let url = ContactURL.email(contact.email, reference: emailReference) {
                    contactButton(url: url, systemImage: "envelope.fill", label: "Email \(name)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Phone numbers and email, one per line, so staff can read or copy them.
    private func details(_ contact: RecordContact) -> [String] {
        var lines: [String] = []
        if let mobile = PortalFormat.nonEmpty(contact.mobilePhone) { lines.append("Mobile \(mobile)") }
        if let phone = PortalFormat.nonEmpty(contact.phone), phone != contact.mobilePhone { lines.append("Phone \(phone)") }
        if let email = PortalFormat.nonEmpty(contact.email) { lines.append(email) }
        return lines
    }

    private func contactButton(url: URL, systemImage: String, label: String) -> some View {
        Link(destination: url) {
            Image(systemName: systemImage).iconShadow()
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                .background(Color.surfaceTintedStrong, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
