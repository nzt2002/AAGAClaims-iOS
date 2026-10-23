import Foundation

/// An active Word template that staff can generate a PDF from (in-house e-sign pilot).
/// `GET /services/apexrest/portaldocs/v1/templates?object=`.
public struct DocumentTemplate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let objectName: String
    /// Agreement_LOR, Proof_of_Loss, Letter or Other.
    public let category: String?
    /// Signature places in the template (0 = no signatures).
    public let signerCount: Int

    public init(id: String, name: String, objectName: String, category: String?, signerCount: Int) {
        self.id = id
        self.name = name
        self.objectName = objectName
        self.category = category
        self.signerCount = signerCount
    }
}

/// `POST /services/apexrest/portaldocs/v1/records/{id}/documents`.
public struct GeneratedDocument: Codable, Hashable, Sendable {
    public let title: String
    public let pageCount: Int
    public let pdfBase64: String
    /// Set when the PDF was saved as a file on the record.
    public let contentDocumentId: String?

    public init(title: String, pageCount: Int, pdfBase64: String, contentDocumentId: String?) {
        self.title = title
        self.pageCount = pageCount
        self.pdfBase64 = pdfBase64
        self.contentDocumentId = contentDocumentId
    }

    public var pdfData: Data? { Data(base64Encoded: pdfBase64) }
}

extension RecordRef {
    /// The Salesforce object that document templates are defined for.
    public var objectApiName: String {
        switch self {
        case .claim: "Claims2__c"
        case .lead: "Prospects__c"
        }
    }
}

// MARK: - Signature requests (pilot)

/// One signer to send to. `GET .../signing-setup` prefills these from the record:
/// for a two-signer agreement, signer 1 is the Public Adjuster and signer 2 the insured.
public struct SignerInput: Codable, Hashable, Identifiable, Sendable {
    public var index: Int
    public var label: String?
    public var name: String?
    public var email: String?
    public var contactId: String?
    public var userId: String?

    public var id: Int { index }

    public init(index: Int, label: String?, name: String?, email: String?, contactId: String? = nil, userId: String? = nil) {
        self.index = index
        self.label = label
        self.name = name
        self.email = email
        self.contactId = contactId
        self.userId = userId
    }

    /// Name present and a plausible email.
    public var isComplete: Bool {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        let e = (email ?? "").trimmingCharacters(in: .whitespaces)
        return n.count >= 2 && e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}

/// `GET /portaldocs/v1/records/{id}/signing-setup?templateId=`.
public struct SigningSetup: Codable, Hashable, Sendable {
    public let templates: [DocumentTemplate]
    public let signers: [SignerInput]
    public let templateId: String?

    public init(templates: [DocumentTemplate], signers: [SignerInput], templateId: String?) {
        self.templates = templates
        self.signers = signers
        self.templateId = templateId
    }
}

/// `GET /portaldocs/v1/records/{id}/signature-requests`, newest first.
public struct SignatureRequestSummary: Codable, Hashable, Identifiable, Sendable {
    public struct Signer: Codable, Hashable, Sendable {
        public let index: Int?
        public let name: String?
        public let email: String?
        /// Pending, Sent, Viewed, Signed, Declined.
        public let status: String?
        public let signedAt: Date?

        public init(index: Int?, name: String?, email: String?, status: String?, signedAt: Date?) {
            self.index = index
            self.name = name
            self.email = email
            self.status = status
            self.signedAt = signedAt
        }
    }

    public let id: String
    public let name: String?
    public let subject: String?
    /// Sent, Viewed, Signed, Declined, Expired, Voided.
    public let status: String
    public let source: String?
    public let sentAt: Date?
    public let completedAt: Date?
    public let expiresAt: Date?
    public let lastError: String?
    public let signers: [Signer]

    public init(id: String, name: String?, subject: String?, status: String, source: String?, sentAt: Date?,
                completedAt: Date?, expiresAt: Date?, lastError: String?, signers: [Signer]) {
        self.id = id
        self.name = name
        self.subject = subject
        self.status = status
        self.source = source
        self.sentAt = sentAt
        self.completedAt = completedAt
        self.expiresAt = expiresAt
        self.lastError = lastError
        self.signers = signers
    }

    public var isOpen: Bool { status == "Sent" || status == "Viewed" }
}
