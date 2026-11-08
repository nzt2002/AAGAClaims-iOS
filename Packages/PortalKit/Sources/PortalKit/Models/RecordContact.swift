import Foundation

/// `GET /{claims|leads}/{id}/contacts` row (staff only): a person or company tied to the record.
/// Claims: their Claim Contacts with roles. Leads: the homeowner, Subcontractor and Partner Account.
public struct RecordContact: Codable, Hashable, Identifiable, Sendable {
    /// The Contact or Account Id; nil for a lead's homeowner (stored on the lead itself).
    public let contactId: String?
    public let name: String?
    public let role: String?
    public let email: String?
    public let phone: String?
    public let mobilePhone: String?
    /// "Contact", "Account" or "Lead".
    public let kind: String?

    public var id: String { contactId ?? "\(kind ?? "")-\(name ?? "")-\(email ?? "")-\(phone ?? "")" }

    enum CodingKeys: String, CodingKey {
        case contactId = "id", name, role, email, phone, mobilePhone, kind
    }

    public init(contactId: String?, name: String?, role: String?, email: String?, phone: String?,
                mobilePhone: String? = nil, kind: String? = "Contact") {
        self.contactId = contactId
        self.name = name
        self.role = role
        self.email = email
        self.phone = phone
        self.mobilePhone = mobilePhone
        self.kind = kind
    }
}
