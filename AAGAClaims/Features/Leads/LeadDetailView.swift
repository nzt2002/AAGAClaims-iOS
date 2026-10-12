import PortalKit
import SwiftUI

/// Lead detail (spec §6.7).
struct LeadDetailView: View {
    @State private var viewModel: LeadDetailViewModel
    let fallbackName: String?
    let api: PortalAPI

    init(leadId: String, fallbackName: String?, api: PortalAPI) {
        _viewModel = State(initialValue: LeadDetailViewModel(leadId: leadId, api: api))
        self.fallbackName = fallbackName
        self.api = api
    }

    var body: some View {
        content
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.detail.value == nil {
                    await viewModel.load()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.detail {
        case .idle, .loading:
            ScrollView { SkeletonList(rows: 3).padding(Theme.Spacing.l) }
        case .failed(.notFound):
            ContentUnavailableView(
                "Lead not found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This lead isn't connected to your email address. Contact support if you think this is a mistake.")
            )
        case .failed:
            ErrorStateView(subject: "this lead") { Task { await viewModel.load() } }
        case .loaded(let detail, _):
            loaded(detail)
        }
    }

    private var recordName: String {
        viewModel.detail.value?.prospectName ?? fallbackName ?? "Lead"
    }

    private func loaded(_ detail: LeadDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(detail)
                LeadLifecycleCard(position: detail.lifecycle, status: detail.prospectStatus)
                AgreementCard(agreement: detail.agreement)
                SectionBar(selection: $viewModel.section)
                sectionContent(detail)
                ReferralCard(detail: detail)
                TeamCard(
                    adjuster: .init(name: detail.adjusterName, phone: detail.adjusterPhone, email: detail.adjusterEmail),
                    deskAdjuster: .init(name: detail.deskAdjusterName, phone: nil, email: detail.deskAdjusterEmail),
                    accountManager: .init(name: detail.accountManagerName, phone: detail.accountManagerPhone, email: detail.accountManagerEmail),
                    adjusterFees: detail.adjusterFees
                )
            }
            .padding(Theme.Spacing.l)
        }
        .refreshable { await viewModel.load() }
        .recordActions(record: viewModel.record, recordName: recordName, api: api) {
            // Lead comments are published to the lead's updates (spec §5.2).
            viewModel.section = .updates
            Task { await viewModel.loadUpdates() }
        }
    }

    private func header(_ detail: LeadDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.prospectName ?? "Lead")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let status = PortalFormat.nonEmpty(detail.prospectStatus) {
                    StatusPill(text: status, tone: StatusPill.tone(forLeadStatus: status))
                }
            }
            HStack(spacing: Theme.Spacing.l) {
                if let number = PortalFormat.nonEmpty(detail.claimNumber) {
                    Text("Claim \(number)")
                }
                if let policy = PortalFormat.nonEmpty(detail.policyNumber) {
                    Text("Policy \(policy)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionContent(_ detail: LeadDetail) -> some View {
        switch viewModel.section {
        case .updates:
            SectionLoader(state: viewModel.updates, subject: "updates", retry: { await viewModel.loadUpdates() }) { updates in
                UpdatesList(updates: updates, emptyMessage: "No updates have been published for this lead yet.")
            }
        case .details:
            LeadDetailsSection(detail: detail)
        case .insurance:
            LeadInsuranceSection(detail: detail)
        case .files:
            FilesSection(record: viewModel.record, state: viewModel.files, api: api) { await viewModel.loadFiles() }
        }
    }
}

// MARK: - Cards

private struct LeadLifecycleCard: View {
    let position: LeadLifecycle.Position
    let status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Lead progress")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(PortalFormat.nonEmpty(status) ?? "Status not set")
                    .font(.headline)
            }
            if case .stage(_, let isUnqualified) = position {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(position.stages.enumerated()), id: \.offset) { index, stage in
                        StepRow(
                            title: stage,
                            state: position.state(ofStageAt: index),
                            isLast: index == position.stages.count - 1,
                            // Unqualified is shown in a warning style (spec §6.7).
                            currentTint: isUnqualified ? .warning : .brandPrimary
                        )
                    }
                }
            }
        }
        .cardStyle()
    }
}

private struct AgreementCard: View {
    let agreement: Agreement?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeading(PortalFormat.nonEmpty(agreement?.agreementName) ?? "Agreement")
            if let steps = LeadDetailViewModel.agreementSteps(for: agreement) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        StepRow(
                            title: step.title,
                            state: step.state,
                            isLast: index == steps.count - 1,
                            detail: step.date.map { PortalFormat.date($0) },
                            currentTint: step.title == "Signed" ? .success : .brandPrimary
                        )
                    }
                }
            } else {
                Text("Visible once an agreement has been sent.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }
}

private struct ReferralCard: View {
    let detail: LeadDetail

    var body: some View {
        if [detail.associatedPartyName, detail.associatedPartyCompany, detail.associatedPartyEmail, detail.associatedPartyPhone]
            .contains(where: { PortalFormat.nonEmpty($0) != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Referred by")
                FieldRow(label: "Name", value: detail.associatedPartyName, systemImage: "person")
                FieldRow(label: "Company", value: detail.associatedPartyCompany, systemImage: "building.2")
                LinkRow(label: "Phone", value: detail.associatedPartyPhone, url: ContactURL.phone(detail.associatedPartyPhone),
                        systemImage: "phone", actionName: "Call")
                LinkRow(label: "Email", value: detail.associatedPartyEmail, url: ContactURL.email(detail.associatedPartyEmail),
                        systemImage: "envelope", actionName: "Email")
            }
            .cardStyle()
        }
    }
}

private struct LeadDetailsSection: View {
    let detail: LeadDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Lead name", value: detail.prospectName, systemImage: "person")
            FieldRow(label: "Peril", value: detail.peril, systemImage: "cloud.bolt")
            FieldRow(label: "Loss date", value: detail.lossDate == nil ? nil : PortalFormat.date(detail.lossDate), systemImage: "calendar")
            LinkRow(label: "Loss address", value: detail.lossAddress, url: ContactURL.map(detail.lossAddress),
                    systemImage: "mappin.and.ellipse", actionName: "Open in Maps")
            LinkRow(label: "Phone", value: detail.phone, url: ContactURL.phone(detail.phone), systemImage: "phone", actionName: "Call")
            LinkRow(label: "Mobile", value: detail.mobile, url: ContactURL.phone(detail.mobile), systemImage: "iphone", actionName: "Call")
            LinkRow(label: "Email", value: detail.email, url: ContactURL.email(detail.email), systemImage: "envelope", actionName: "Email")
            if let description = PortalFormat.nonEmpty(detail.lossDescription) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loss description")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(description)
                        .font(.subheadline)
                }
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityElement(children: .combine)
            }
            FieldRow(label: "Created", value: detail.createdDate == nil ? nil : PortalFormat.date(detail.createdDate), systemImage: "calendar.badge.plus")
            FieldRow(label: "Last updated", value: detail.lastModifiedDate == nil ? nil : PortalFormat.date(detail.lastModifiedDate), systemImage: "clock")
            LinkRow(label: "Supporting documents", value: ContactURL.web(detail.documentsUrl) == nil ? nil : "Open link",
                    url: ContactURL.web(detail.documentsUrl), systemImage: "folder", actionName: "Open")
        }
        .cardStyle()
    }
}

private struct LeadInsuranceSection: View {
    let detail: LeadDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Insurance company", value: detail.insuranceCompanyName, systemImage: "building.columns")
            FieldRow(label: "Claim filed?", value: detail.didFileClaim, systemImage: "questionmark.circle")
            FieldRow(label: "Claim number", value: detail.claimNumber, systemImage: "number")
            FieldRow(label: "Policy number", value: detail.policyNumber, systemImage: "doc.plaintext")
            if [detail.insuranceCompanyName, detail.didFileClaim, detail.claimNumber, detail.policyNumber]
                .allSatisfy({ PortalFormat.nonEmpty($0) == nil }) {
                Text("We haven't added insurance details to this lead yet.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }
}

#Preview("Lead detail") {
    NavigationStack {
        LeadDetailView(leadId: "a0r000000000001AAA", fallbackName: nil, api: PreviewData.api())
    }
}
