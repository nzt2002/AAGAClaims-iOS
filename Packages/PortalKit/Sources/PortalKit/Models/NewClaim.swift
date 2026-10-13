import Foundation

/// An account from New Claim's lookups (`GET /new-claim/accounts`, `/account-matches`, `/partner-matches`).
public struct AccountMatch: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let city: String?
    public let state: String?
    /// "Person" or "Business".
    public let kind: String?

    public init(id: String, name: String?, email: String? = nil, phone: String? = nil,
                city: String? = nil, state: String? = nil, kind: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.city = city
        self.state = state
        self.kind = kind
    }

    /// "alex@example.com · Atlanta, GA", for list rows.
    public var details: String {
        let place = [city, state].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: ", ")
        return [email, phone, place].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · ")
    }
}

/// A contact from New Claim's lookups (`GET /new-claim/contacts`, `/contact-matches`).
public struct ContactMatch: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let accountName: String?

    public init(id: String, name: String?, email: String? = nil, phone: String? = nil, accountName: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.accountName = accountName
    }

    public var details: String {
        [email, phone, accountName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · ")
    }
}

/// `GET /new-claim/options`.
public struct NewClaimOptions: Codable, Hashable, Sendable {
    public let perils: [String]
    public let states: [String]
    public let sources: [String]
    public let defaultSource: String?
    public let contactRoles: [String]
    /// Internal users, for Adjuster (the claim owner) and Account Manager.
    public let users: [TaskAssignee]
    public let currentUserId: String
}

/// `POST /new-claim`: the account (existing or new), the claim, and an optional claim contact.
public struct NewClaimRequest: Encodable, Hashable, Sendable {
    public struct NewAccount: Codable, Hashable, Sendable {
        public var firstName: String?
        public var lastName: String
        public var email: String?
        public var phone: String?

        public init(firstName: String?, lastName: String, email: String?, phone: String?) {
            self.firstName = firstName
            self.lastName = lastName
            self.email = email
            self.phone = phone
        }
    }

    public enum Account: Hashable, Sendable {
        case existing(id: String)
        case new(NewAccount)
    }

    public struct Claim: Codable, Hashable, Sendable {
        public var name: String
        public var street: String?
        public var city: String?
        public var state: String?
        public var postalCode: String?
        public var lossDate: CalendarDate?
        public var peril: String?
        public var lossDescription: String?
        public var claimNumber: String?
        public var policyNumber: String?
        public var insuranceCompanyId: String?
        public var email: String?
        public var phone: String?
        public var source: String?
        public var adjusterFees: Decimal?
        public var ownerId: String?
        public var accountManagerId: String?

        public init(name: String) {
            self.name = name
        }
    }

    public struct NewContact: Codable, Hashable, Sendable {
        public var firstName: String?
        public var lastName: String
        public var email: String?
        public var phone: String?
        public var company: String?

        public init(firstName: String?, lastName: String, email: String?, phone: String?, company: String?) {
            self.firstName = firstName
            self.lastName = lastName
            self.email = email
            self.phone = phone
            self.company = company
        }
    }

    /// Subcontractor contacts belong to a Commercial account.
    public enum PartnerAccount: Hashable, Sendable {
        case existing(id: String)
        case new(name: String)
    }

    public enum Contact: Hashable, Sendable {
        case existing(id: String, role: String)
        case new(NewContact, role: String, partner: PartnerAccount?)
    }

    public var account: Account
    public var claim: Claim
    public var contact: Contact?

    public init(account: Account, claim: Claim, contact: Contact?) {
        self.account = account
        self.claim = claim
        self.contact = contact
    }

    private enum Keys: String, CodingKey {
        case account, claim, contact, id, new, role, partnerAccount, name
    }

    public func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: Keys.self)
        var account = root.nestedContainer(keyedBy: Keys.self, forKey: .account)
        switch self.account {
        case .existing(let id): try account.encode(id, forKey: .id)
        case .new(let details): try account.encode(details, forKey: .new)
        }
        try root.encode(claim, forKey: .claim)
        guard let contact else { return }
        var container = root.nestedContainer(keyedBy: Keys.self, forKey: .contact)
        switch contact {
        case .existing(let id, let role):
            try container.encode(id, forKey: .id)
            try container.encode(role, forKey: .role)
        case .new(let details, let role, let partner):
            try container.encode(details, forKey: .new)
            try container.encode(role, forKey: .role)
            if let partner {
                var p = container.nestedContainer(keyedBy: Keys.self, forKey: .partnerAccount)
                switch partner {
                case .existing(let id): try p.encode(id, forKey: .id)
                case .new(let name): try p.encode(name, forKey: .name)
                }
            }
        }
    }
}

/// 409 from `POST /new-claim`: what already exists, which the user must choose instead.
public struct DuplicateMatches: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case account = "duplicate_account"
        case partnerAccount = "duplicate_partner_account"
        case contact = "duplicate_contact"
    }

    public let kind: Kind
    public let accounts: [AccountMatch]
    public let contacts: [ContactMatch]

    public init(kind: Kind, accounts: [AccountMatch] = [], contacts: [ContactMatch] = []) {
        self.kind = kind
        self.accounts = accounts
        self.contacts = contacts
    }
}
