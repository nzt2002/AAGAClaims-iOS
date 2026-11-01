import PortalKit
import SwiftUI

/// Support cases on a claim or lead: the last tab of its page. A case opens on the app's case page
/// (staff and homeowners reply there; homeowners can also mark it completed). Staff fall back to
/// Salesforce on servers without `staffCases`.
struct RecordCasesSection: View {
    let state: LoadState<[SupportCase]>
    let noun: String
    let retry: () async -> Void

    @Environment(\.isInternalUser) private var isInternal
    @Environment(\.salesforcePage) private var salesforcePage
    @Environment(\.serverMeta) private var serverMeta
    @Environment(\.isLeadRecord) private var isLead
    @State private var salesforceURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionLoader(state: state, subject: "cases", retry: retry) { cases in
                if cases.isEmpty {
                    Text("No cases have been opened for this \(noun).")
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                } else {
                    VStack(spacing: 0) {
                        ForEach(cases) { supportCase in
                            row(supportCase)
                            if supportCase.id != cases.last?.id {
                                Divider()
                            }
                        }
                    }
                    .cardStyle()
                }
            }
        }
        .sheet(item: Binding(get: { salesforceURL.map(SafariLink.init) }, set: { salesforceURL = $0?.url })) {
            SafariView(url: $0.url).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func row(_ supportCase: SupportCase) -> some View {
        if isInternal && !serverMeta.supports(.staffCases) {
            Button {
                guard let salesforcePage else { return }
                let path = SalesforcePageLink.path("/lightning/r/Case/\(supportCase.caseId)/view", query: [])
                Task { salesforceURL = await salesforcePage.url(for: path) }
            } label: {
                label(supportCase, systemImage: "safari")
            }
            .buttonStyle(.plain)
            .disabled(salesforcePage == nil)
            .accessibilityHint("Opens the case in Salesforce")
            .accessibilityIdentifier("recordCase-\(supportCase.caseId)")
        } else {
            NavigationLink(value: CaseRoute(id: supportCase.caseId)) {
                label(supportCase, systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recordCase-\(supportCase.caseId)")
        }
    }

    private func label(_ supportCase: SupportCase, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            IconBadge(systemName: "questionmark.bubble", tint: supportCase.isClosed ? .textSecondary : .recordAccent(isLead: isLead), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(supportCase.subject ?? "Support request")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text([supportCase.caseNumber.map { "Case \($0)" }, PortalFormat.date(supportCase.createdDate)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            if let status = PortalFormat.nonEmpty(supportCase.status) {
                StatusPill(text: status, tone: supportCase.isClosed ? .neutral : .active)
            }
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
