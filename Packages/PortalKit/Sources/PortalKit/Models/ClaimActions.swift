import Foundation

/// A choice from the server: a value and what to show.
public struct ValueOption: Codable, Hashable, Identifiable, Sendable {
    public let value: String?
    public let label: String
    public var id: String { value ?? label }

    public init(value: String?, label: String) {
        self.value = value
        self.label = label
    }
}

/// Proof of Loss fields (the proofOfLossDataEntry component).
public struct ProofOfLoss: Codable, Hashable, Sendable {
    public var totalLossDamage: Decimal?
    public var totalActualCashValue: Decimal?
    public var totalAmountClaimed: Decimal?
    public var lossDate: CalendarDate?
    /// "HH:mm".
    public var timeOfLoss: String?
    public var policyNumber: String?
    public var policyEffectiveDate: CalendarDate?
    public var policyExpirationDate: CalendarDate?
    public var policyCoverageAmount: Decimal?
    public var otherPersons: String?
    public var changesAffectingProperty: String?
    public var primaryHomeOrRental: String?
    public var occupancy: String?

    public init() {}

    /// The document can only be generated when every field has a value.
    public var isComplete: Bool {
        totalLossDamage != nil && totalActualCashValue != nil && totalAmountClaimed != nil && lossDate != nil
            && Self.filled(timeOfLoss) && Self.filled(policyNumber) && policyEffectiveDate != nil
            && policyExpirationDate != nil && policyCoverageAmount != nil && Self.filled(otherPersons)
            && Self.filled(changesAffectingProperty) && Self.filled(primaryHomeOrRental) && Self.filled(occupancy)
    }

    public var missingCount: Int {
        let values: [Bool] = [
            totalLossDamage != nil, totalActualCashValue != nil, totalAmountClaimed != nil, lossDate != nil,
            Self.filled(timeOfLoss), Self.filled(policyNumber), policyEffectiveDate != nil, policyExpirationDate != nil,
            policyCoverageAmount != nil, Self.filled(otherPersons), Self.filled(changesAffectingProperty),
            Self.filled(primaryHomeOrRental), Self.filled(occupancy)
        ]
        return values.filter { !$0 }.count
    }

    private static func filled(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// `GET /claims/{id}/staff`: what the claim actions need (staff only).
public struct StaffClaim: Codable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var status: String?
    public var peril: String?
    public var lossDate: CalendarDate?
    public var lossDescription: String?
    public var claimNumber: String?
    public var policyNumber: String?
    public var insuranceCompanyId: String?
    public var insuranceCompanyName: String?
    public var deductible: Decimal?
    public var adjusterFees: Decimal?
    public var accountManagerId: String?
    public var ownerId: String?
    public var ownerName: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var proofOfLoss: ProofOfLoss
    public var statuses: [String]
    public var perils: [String]
    public var states: [String]
    public var occupancyValues: [String]
    public var primaryHomeValues: [String]
    public var contactRoles: [String]
    public var users: [TaskAssignee]
    public var emailRecipients: [ValueOption]
    public var fromAddresses: [ValueOption]
    public var contacts: [ValueOption]
}

/// `POST /claims/{id}/edit`: the core fields.
public struct ClaimEdit: Codable, Hashable, Sendable {
    public var name: String
    public var status: String?
    public var peril: String?
    public var lossDate: CalendarDate?
    public var lossDescription: String?
    public var claimNumber: String?
    public var policyNumber: String?
    public var insuranceCompanyId: String?
    public var deductible: Decimal?
    public var adjusterFees: Decimal?
    public var accountManagerId: String?

    public init(name: String) { self.name = name }

    // Every key is sent, so a cleared field is cleared in Salesforce.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encode(peril, forKey: .peril)
        try c.encode(lossDate, forKey: .lossDate)
        try c.encode(lossDescription, forKey: .lossDescription)
        try c.encode(claimNumber, forKey: .claimNumber)
        try c.encode(policyNumber, forKey: .policyNumber)
        try c.encode(insuranceCompanyId, forKey: .insuranceCompanyId)
        try c.encode(deductible, forKey: .deductible)
        try c.encode(adjusterFees, forKey: .adjusterFees)
        try c.encode(accountManagerId, forKey: .accountManagerId)
    }
}

/// `POST /claims/{id}/address`.
public struct ClaimAddress: Codable, Hashable, Sendable {
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?

    public init(street: String?, city: String?, state: String?, postalCode: String?) {
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
    }
}

/// `GET /claims/{id}/payment-setup`.
public struct PaymentSetup: Codable, Hashable, Sendable {
    public let claimName: String?
    public let deductible: Decimal?
    public let adjusterFees: Decimal?
    public let lifetimePaymentsReceived: Decimal?
    public let paymentTypes: [String]
}

/// `POST /claims/{id}/payments`.
public struct PaymentEntry: Codable, Hashable, Sendable {
    public struct Row: Codable, Hashable, Sendable {
        public var rowType: String
        public var amount: Decimal
        public init(rowType: String, amount: Decimal) {
            self.rowType = rowType
            self.amount = amount
        }
    }
    public var dateCollected: CalendarDate
    public var notes: String?
    public var applyDeductible: Bool
    public var rows: [Row]

    public init(dateCollected: CalendarDate, notes: String?, applyDeductible: Bool, rows: [Row]) {
        self.dateCollected = dateCollected
        self.notes = notes
        self.applyDeductible = applyDeductible
        self.rows = rows
    }
}

/// `POST /claims/{id}/calls`.
public struct CallLog: Codable, Hashable, Sendable {
    public var subject: String
    public var description: String?
    public var contactId: String?
    public init(subject: String, description: String?, contactId: String?) {
        self.subject = subject
        self.description = description
        self.contactId = contactId
    }
}

/// `POST /claims/{id}/emails`.
public struct OutgoingEmail: Codable, Hashable, Sendable {
    public var fromAddressId: String?
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var body: String
    public init(fromAddressId: String?, to: [String], cc: [String], bcc: [String], subject: String, body: String) {
        self.fromAddressId = fromAddressId
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }
}
