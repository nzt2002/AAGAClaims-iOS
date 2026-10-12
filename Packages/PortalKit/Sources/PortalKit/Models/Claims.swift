import Foundation

/// `GET /claims` row (wraps `CustomerRelatedClaimsController.RelatedClaimDTO`).
public struct ClaimSummary: Codable, Hashable, Identifiable, Sendable {
    public let recordId: String
    public let recordName: String?
    public let claimNumber: String?
    public let policyNumber: String?
    public let claimStatus: String?
    public let peril: String?
    public let lossAddress: String?
    public let lossDate: CalendarDate?
    public let lossReason: String?
    public let paymentCollected: Decimal?
    public let adjusterName: String?
    public let accountManagerName: String?
    public let lastModifiedDate: Date?

    public var id: String { recordId }
    public var lifecycle: ClaimLifecycle.Position { ClaimLifecycle.position(for: claimStatus) }
}

/// `GET /claims/{id}` (wraps `ClaimRecordBannerController.ClaimBannerDTO`).
public struct ClaimDetail: Codable, Hashable, Sendable {
    public let claimName: String?
    public let claimStatus: String?
    public let peril: String?
    public let lossAddress: String?
    public let email: String?
    public let mainPhone: String?
    public let businessEmail: String?
    public let adjusterName: String?
    public let adjusterEmail: String?
    public let adjusterPhone: String?
    public let deskAdjusterName: String?
    public let deskAdjusterEmail: String?
    public let accountManagerName: String?
    public let accountManagerEmail: String?
    public let accountManagerPhone: String?
    public let insuranceCompanyName: String?
    public let insuranceMainPhone: String?
    public let claimNumber: String?
    public let policyNumber: String?
    public let dateClaimFiled: CalendarDate?
    public let dateOfClaim: CalendarDate?
    public let lossDate: CalendarDate?
    /// Plain text, not HTML.
    public let lossDescription: String?
    public let photosUrl: String?
    public let adjusterFees: Decimal?
    public let deductible: Decimal?
    public let paymentCollected: Decimal?
    public let totalRcv: Decimal?

    public var lifecycle: ClaimLifecycle.Position { ClaimLifecycle.position(for: claimStatus) }
}

/// `GET /claims/{id}/payments` row.
public struct Payment: Codable, Hashable, Identifiable, Sendable {
    public let paymentsId: String
    public let paymentsName: String?
    public let dateOfNotice: CalendarDate?
    public let netDeposit: Decimal?
    public let insuredPayment: Decimal?
    public let totalRcv: Decimal?

    public var id: String { paymentsId }
}

/// Published update on a claim or lead (`GET /claims/{id}/updates`, `GET /leads/{id}/updates`).
public struct PortalUpdate: Codable, Hashable, Identifiable, Sendable {
    public let commentId: String
    public let relatedRecordId: String?
    public let relatedRecordName: String?
    public let createdDate: Date?
    public let title: String?
    /// HTML.
    public let text: String?

    public var id: String { commentId }
}

/// File row for claims and leads.
public struct PortalFile: Codable, Hashable, Identifiable, Sendable {
    public let contentDocumentId: String
    public let title: String?
    public let fileType: String?
    public let contentSize: Int?
    public let createdDate: Date?
    public let createdByName: String?

    public var id: String { contentDocumentId }
}
