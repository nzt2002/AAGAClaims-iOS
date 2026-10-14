import Foundation

/// `GET /leads/{id}/staff`: what the lead actions need (staff only).
public struct LeadStaff: Codable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var status: String?
    public var peril: String?
    public var lossDate: CalendarDate?
    public var lossDescription: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var insuranceCompanyId: String?
    public var insuranceCompanyName: String?
    public var policyNumber: String?
    public var claimNumber: String?
    public var email: String?
    public var phone: String?
    public var firstName: String?
    public var lastName: String?
    public var associatedPartyName: String?
    public var associatedPartyCompany: String?
    public var associatedPartyEmail: String?
    public var associatedPartyPhone: String?
    public var isConverted: Bool?
    public var convertedClaimId: String?
    public var statuses: [String]
    public var perils: [String]
    public var contactRoles: [String]
}

/// `POST /leads/{id}/edit`: the core lead fields. Every key is sent, so a cleared field is cleared.
public struct LeadEdit: Codable, Hashable, Sendable {
    public var name: String
    public var status: String?
    public var peril: String?
    public var lossDate: CalendarDate?
    public var lossDescription: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var insuranceCompanyId: String?
    public var policyNumber: String?
    public var claimNumber: String?
    public var email: String?
    public var phone: String?
    public var associatedPartyName: String?
    public var associatedPartyCompany: String?
    public var associatedPartyEmail: String?
    public var associatedPartyPhone: String?

    public init(_ staff: LeadStaff) {
        name = staff.name ?? ""
        status = staff.status
        peril = staff.peril
        lossDate = staff.lossDate
        lossDescription = staff.lossDescription
        street = staff.street
        city = staff.city
        state = staff.state
        postalCode = staff.postalCode
        insuranceCompanyId = staff.insuranceCompanyId
        policyNumber = staff.policyNumber
        claimNumber = staff.claimNumber
        email = staff.email
        phone = staff.phone
        associatedPartyName = staff.associatedPartyName
        associatedPartyCompany = staff.associatedPartyCompany
        associatedPartyEmail = staff.associatedPartyEmail
        associatedPartyPhone = staff.associatedPartyPhone
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encode(peril, forKey: .peril)
        try c.encode(lossDate, forKey: .lossDate)
        try c.encode(lossDescription, forKey: .lossDescription)
        try c.encode(street, forKey: .street)
        try c.encode(city, forKey: .city)
        try c.encode(state, forKey: .state)
        try c.encode(postalCode, forKey: .postalCode)
        try c.encode(insuranceCompanyId, forKey: .insuranceCompanyId)
        try c.encode(policyNumber, forKey: .policyNumber)
        try c.encode(claimNumber, forKey: .claimNumber)
        try c.encode(email, forKey: .email)
        try c.encode(phone, forKey: .phone)
        try c.encode(associatedPartyName, forKey: .associatedPartyName)
        try c.encode(associatedPartyCompany, forKey: .associatedPartyCompany)
        try c.encode(associatedPartyEmail, forKey: .associatedPartyEmail)
        try c.encode(associatedPartyPhone, forKey: .associatedPartyPhone)
    }
}

/// What Convert to Account starts from: the lead's person and associated party.
public struct LeadConversion: Hashable, Sendable {
    public let leadId: String
    public let leadName: String?
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let associatedPartyName: String?
    public let associatedPartyCompany: String?
    public let associatedPartyEmail: String?
    public let associatedPartyPhone: String?

    public init(_ staff: LeadStaff) {
        leadId = staff.id
        leadName = staff.name
        firstName = staff.firstName
        lastName = staff.lastName
        email = staff.email
        phone = staff.phone
        associatedPartyName = staff.associatedPartyName
        associatedPartyCompany = staff.associatedPartyCompany
        associatedPartyEmail = staff.associatedPartyEmail
        associatedPartyPhone = staff.associatedPartyPhone
    }
}
