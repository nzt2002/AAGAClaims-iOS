import PortalKit
import SwiftUI

// Sections of the claim detail screen (spec §6.5). Updates, Files and the Team card are
// shared with lead detail in milestone 3.

struct UpdatesList: View {
    let updates: [PortalUpdate]
    let emptyMessage: String
    /// Show this many and scroll for the rest (claims show 3); nil shows them all.
    var visibleCount: Int? = nil

    var body: some View {
        if updates.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(Color.textSecondary)
                .cardStyle()
        } else if let visibleCount {
            ScrollingStack(items: updates, visibleCount: visibleCount, spacing: Theme.Spacing.m, noun: "updates") { card($0) }
        } else {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(updates) { update in
                    card(update)
                }
            }
        }
    }

    private func card(_ update: PortalUpdate) -> some View {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(update.title ?? "Update")
                                .font(.headline)
                            Spacer()
                            Text(PortalFormat.date(update.createdDate))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        RichText(html: update.text)
                    }
                    .cardStyle()
    }
}

struct ClaimDetailsSection: View {
    let detail: ClaimDetail
    let lossReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Claim snapshot")
                FieldRow(label: "Peril", value: detail.peril, systemImage: "cloud.bolt")
                FieldRow(label: "Deductible", value: detail.deductible == nil ? nil : PortalFormat.currency(detail.deductible),
                         systemImage: "dollarsign.circle")
                FieldRow(label: "Date of claim", value: date(detail.dateOfClaim), systemImage: "calendar")
                LinkRow(label: "Loss address", value: detail.lossAddress, url: ContactURL.map(detail.lossAddress),
                        systemImage: "mappin.and.ellipse", actionName: "Open in Maps")
                LinkRow(label: "Main phone", value: detail.mainPhone, url: ContactURL.phone(detail.mainPhone),
                        systemImage: "phone", actionName: "Call")
                LinkRow(label: "Email", value: detail.email, url: ContactURL.email(detail.email),
                        systemImage: "envelope", actionName: "Email")
                LinkRow(label: "Business email", value: detail.businessEmail, url: ContactURL.email(detail.businessEmail),
                        systemImage: "envelope", actionName: "Email")
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Loss and documentation")
                FieldRow(label: "Loss date", value: date(detail.lossDate), systemImage: "calendar")
                FieldRow(label: "Date claim filed", value: date(detail.dateClaimFiled), systemImage: "calendar.badge.checkmark")
                FieldRow(label: "Loss reason", value: lossReason, systemImage: "exclamationmark.bubble")
                if let description = PortalFormat.nonEmpty(detail.lossDescription) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loss description")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        // Plain text, not HTML.
                        Text(description)
                            .font(.subheadline)
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityElement(children: .combine)
                }
                LinkRow(label: "Photos or documents", value: ContactURL.web(detail.photosUrl) == nil ? nil : "Open link",
                        url: ContactURL.web(detail.photosUrl), systemImage: "photo.on.rectangle", actionName: "Open")
            }
            .cardStyle()
        }
    }

    private func date(_ value: CalendarDate?) -> String? {
        value == nil ? nil : PortalFormat.date(value)
    }
}

struct ClaimInsuranceSection: View {
    let detail: ClaimDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Insurance company", value: detail.insuranceCompanyName, systemImage: "building.columns")
            LinkRow(label: "Insurance main phone", value: detail.insuranceMainPhone, url: ContactURL.phone(detail.insuranceMainPhone),
                    systemImage: "phone", actionName: "Call")
            FieldRow(label: "Claim number", value: detail.claimNumber, systemImage: "number")
            FieldRow(label: "Policy number", value: detail.policyNumber, systemImage: "doc.plaintext")
            FieldRow(label: "Deductible", value: detail.deductible == nil ? nil : PortalFormat.currency(detail.deductible),
                     systemImage: "dollarsign.circle")
            if [detail.insuranceCompanyName, detail.insuranceMainPhone, detail.claimNumber, detail.policyNumber]
                .allSatisfy({ PortalFormat.nonEmpty($0) == nil }) && detail.deductible == nil {
                Text("We haven't added insurance details to this claim yet.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }
}

/// File rows. Tapping one opens it in Quick Look (see `FilesSection`).
struct FilesList: View {
    let files: [PortalFile]
    var loadingFileId: String?
    var onOpen: ((PortalFile) -> Void)?

    var body: some View {
        if files.isEmpty {
            Text("No files have been added yet.")
                .foregroundStyle(Color.textSecondary)
                .cardStyle()
        } else {
            VStack(spacing: 0) {
                ForEach(files) { file in
                    Button {
                        onOpen?(file)
                    } label: {
                        row(file)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpen == nil || loadingFileId != nil)
                    .accessibilityHint("Opens the file")
                    .accessibilityIdentifier("file-\(file.contentDocumentId)")
                    if file.id != files.last?.id {
                        Divider()
                    }
                }
            }
            .cardStyle()
        }
    }

    private func row(_ file: PortalFile) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: Self.icon(for: file.fileType))
                .font(.title2)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title ?? "Untitled file")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(file.fileType ?? "File") · \(PortalFormat.fileSize(file.contentSize)) · Uploaded \(PortalFormat.date(file.createdDate))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if let name = PortalFormat.nonEmpty(file.createdByName) {
                    Text("Uploaded by \(name)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if loadingFileId == file.id {
                ProgressView()
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func icon(for fileType: String?) -> String {
        switch fileType?.uppercased() {
        case "PDF": "doc.richtext"
        case "JPG", "JPEG", "PNG", "HEIC", "GIF": "photo"
        case "WORD", "WORD_X", "DOC", "DOCX": "doc.text"
        case "EXCEL", "EXCEL_X", "XLS", "XLSX", "CSV": "tablecells"
        default: "doc"
        }
    }
}

struct PaymentsList: View {
    let payments: [Payment]
    let totalCollected: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if payments.isEmpty {
                Text("No payment records have been found for this claim.")
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(payments) { payment in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(payment.paymentsName ?? "Payment")
                            .font(.subheadline.weight(.semibold))
                        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: 2) {
                            row("Date of Notice", PortalFormat.date(payment.dateOfNotice))
                            row("Net Deposit", PortalFormat.currency(payment.netDeposit))
                            row("Insured Payment", PortalFormat.currency(payment.insuredPayment))
                            GridRow {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("Total RCV")
                                    RCVHelpButton()
                                }
                                .foregroundStyle(Color.textSecondary)
                                Text(PortalFormat.currency(payment.totalRcv))
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityElement(children: .combine)
                    Divider()
                }
            }
            AdaptiveStack {
                Text("Total payments collected")
                    .font(.subheadline.weight(.semibold))
                AdaptiveSpacer()
                Text(PortalFormat.currency(totalCollected ?? 0))
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, Theme.Spacing.s)
            .accessibilityElement(children: .combine)
        }
        .cardStyle()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Color.textSecondary)
            Text(value)
        }
    }
}

/// Contact Us: the public adjuster team (spec §6.5).
struct TeamCard: View {
    struct Member {
        let name: String?
        let phone: String?
        let email: String?
    }

    let adjuster: Member
    let deskAdjuster: Member
    let accountManager: Member
    let adjusterFees: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeading("Contact Us")
            member("Adjuster", adjuster)
            member("Desk adjuster", deskAdjuster)
            member("Account manager", accountManager)
            if adjusterFees != nil {
                FieldRow(label: "Adjuster fees", value: PortalFormat.percent(adjusterFees), systemImage: "percent")
            }
            if [adjuster.name, deskAdjuster.name, accountManager.name].allSatisfy({ PortalFormat.nonEmpty($0) == nil }) {
                Text("Your team will appear here once they're assigned.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func member(_ role: String, _ member: Member) -> some View {
        if let name = PortalFormat.nonEmpty(member.name) {
            AdaptiveStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
                AdaptiveSpacer()
                HStack(spacing: Theme.Spacing.m) {
                if let url = ContactURL.phone(member.phone) {
                    contactButton(url: url, systemImage: "phone.fill", label: "Call \(name)")
                }
                if let url = ContactURL.email(member.email) {
                    contactButton(url: url, systemImage: "envelope.fill", label: "Email \(name)")
                }
                }
            }
        }
    }

    private func contactButton(url: URL, systemImage: String, label: String) -> some View {
        Link(destination: url) {
            Image(systemName: systemImage)
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                .background(Color.surfaceTintedStrong, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

struct SectionHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.textPrimary)
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}
