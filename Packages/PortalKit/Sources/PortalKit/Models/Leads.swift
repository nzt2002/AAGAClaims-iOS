import Foundation

/// `GET /leads` row (wraps `UserRelatedProspectsController.RelatedProspectDTO`).
public struct LeadSummary: Codable, Hashable, Identifiable, Sendable {
    public let recordId: String
    public let recordName: String?
    public let prospectStatus: String?
    /// May contain a line break between street and "city, state, ZIP".
    public let lossAddress: String?
    public let lossDate: CalendarDate?
    public let peril: String?
    public let claimNumber: String?
    public let policyNumber: String?
    public let customerEmail: String?
    public let associatedPartyName: String?
    public let associatedPartyCompany: String?
    public let associatedPartyEmail: String?
    public let insuranceCompanyName: String?
    public let adjusterName: String?
    public let accountManagerName: String?
    public let lastModifiedDate: Date?
    public let agreementSentDate: Date?
    public let agreementCompletedDate: Date?

    public var id: String { recordId }
    public var lifecycle: LeadLifecycle.Position { LeadLifecycle.position(for: prospectStatus) }
}

/// `GET /leads/{id}` (wraps `ProspectRecordBannerController.ProspectBannerDTO`).
public struct LeadDetail: Codable, Hashable, Sendable {
    public let prospectName: String?
    public let prospectStatus: String?
    public let peril: String?
    public let lossAddress: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let associatedPartyName: String?
    public let associatedPartyCompany: String?
    public let associatedPartyEmail: String?
    public let associatedPartyPhone: String?
    public let adjusterName: String?
    public let adjusterEmail: String?
    public let adjusterPhone: String?
    public let deskAdjusterName: String?
    public let deskAdjusterEmail: String?
    public let accountManagerName: String?
    public let accountManagerEmail: String?
    public let accountManagerPhone: String?
    public let insuranceCompanyName: String?
    public let claimNumber: String?
    public let policyNumber: String?
    public let didFileClaim: String?
    public let adjusterFees: Decimal?
    public let lossDate: CalendarDate?
    /// Plain text, not HTML.
    public let lossDescription: String?
    public let documentsUrl: String?
    public let createdDate: Date?
    public let lastModifiedDate: Date?
    public let agreement: Agreement?

    public var lifecycle: LeadLifecycle.Position { LeadLifecycle.position(for: prospectStatus) }
}

public struct Agreement: Codable, Hashable, Sendable {
    public let hasAgreement: Bool
    public let agreementId: String?
    public let agreementName: String?
    /// "SENT" or "COMPLETE".
    public let agreementStatus: String?
    public let sentDate: Date?
    /// Always null today; the e-signature integration doesn't record views.
    public let viewedDate: Date?
    public let completedDate: Date?

    public var isSigned: Bool {
        agreementStatus?.uppercased() == "COMPLETE"
    }
}

/// `POST /leads` body.
public struct LeadSubmission: Codable, Hashable, Sendable {
    public var leadName: String
    public var email: String?
    public var phone: String?
    public var street: String?
    public var city: String?
    public var stateCode: String?
    public var postalCode: String?
    public var peril: String?
    public var lossDescription: String?
    public var fileLink: String?
    public var insuranceCompanyId: String?
    public var policyNumber: String?
    /// "Yes" or "No".
    public var didFileClaim: String?
    public var claimNumber: String?
    public var associatedPartyCompany: String?
    public var associatedPartyName: String?
    public var associatedPartyPhone: String?
    /// The server always replaces this with the signed-in user's email.
    public var associatedPartyEmail: String?

    public init(leadName: String) {
        self.leadName = leadName
    }
}

public struct InsuranceCompany: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
}
