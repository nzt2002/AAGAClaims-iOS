import Foundation
import Observation

/// New Claim (staff): the Prospect Conversion Guided Process without a Prospect.
///
/// 1. Account: an existing account (search by name), or a new one. A new account is always
///    checked for matches first (same email, or same first and last name); when any exist the user
///    must pick one, as in the flow. The server checks again when the claim is created.
/// 2. Claim details: the fields the flow copies from the Prospect.
/// 3. Claim contact (optional): an existing contact, or a new one checked for matches. A new
///    subcontractor needs a Commercial partner account, which is also checked for matches.
/// 4. Review and create. Everything is created together, or nothing is.
@MainActor
@Observable
public final class NewClaimViewModel {
    public enum Step: Hashable, Sendable {
        case accountSearch, newAccount, accountMatches, claimDetails, contact, contactMatches,
             partner, review, duplicateContact
    }

    public enum Field: Hashable, Sendable {
        case accountLastName, accountEmail, claimName, claimEmail, adjusterFees,
             contactRole, contact, contactLastName, contactEmail, partner
    }

    public enum ContactMode: String, CaseIterable, Hashable, Sendable {
        case skip = "None"
        case existing = "Existing"
        case new = "New"
    }

    public enum PartnerMode: String, CaseIterable, Hashable, Sendable {
        case existing = "Existing account"
        case new = "New account"
    }

    public static let subcontractorRole = "Sub-Contractor"

    public private(set) var options: LoadState<NewClaimOptions> = .idle

    // 1. Account
    /// The chosen existing account (from search or from the matches). Nil while creating a new one.
    public private(set) var selectedAccount: AccountMatch?
    public var accountFirstName = ""
    public var accountLastName = ""
    public var accountEmail = ""
    public var accountPhone = ""
    /// Accounts that may be the same person. When not empty, one must be chosen.
    public private(set) var accountMatches: [AccountMatch] = []
    public private(set) var accountResults: [AccountMatch] = []

    // 2. Claim
    public var claimName = ""
    public var street = ""
    public var city = ""
    public var state: String?
    public var postalCode = ""
    public var hasLossDate = false
    public var lossDate = Date()
    public var peril: String?
    public var lossDescription = ""
    public var claimNumber = ""
    public var policyNumber = ""
    public var insuranceQuery = ""
    public private(set) var insuranceCompany: InsuranceCompany?
    public private(set) var insuranceResults: [InsuranceCompany] = []
    public var claimEmail = ""
    public var claimPhone = ""
    public var source: String?
    public var adjusterFees = ""
    public var ownerId: String?
    public var accountManagerId: String?

    // 3. Contact
    public var contactMode: ContactMode = .skip
    public var contactRole: String?
    public var selectedContact: ContactMatch?
    public var contactFirstName = ""
    public var contactLastName = ""
    public var contactEmail = ""
    public var contactPhone = ""
    public var contactCompany = ""
    public private(set) var contactResults: [ContactMatch] = []
    public private(set) var contactMatches: [ContactMatch] = []
    /// From the 409 when the duplicate rules match the new contact.
    public private(set) var duplicateContacts: [ContactMatch] = []
    public var partnerMode: PartnerMode = .existing
    public var selectedPartner: AccountMatch?
    public var partnerName = ""
    /// Commercial accounts with the same name. When not empty, one must be chosen.
    public private(set) var partnerMatches: [AccountMatch] = []
    public private(set) var partnerResults: [AccountMatch] = []

    public private(set) var showErrors: Set<Step> = []
    public private(set) var isWorking = false
    public private(set) var error: PortalAPIError?
    public private(set) var createdClaimId: String?

    private let api: PortalAPI

    public init(api: PortalAPI) {
        self.api = api
    }

    public func loadOptions() async {
        let api = self.api
        await PortalKit.load(self, \.options) { try await api.newClaimOptions() }
        if let options = options.value {
            if ownerId == nil { ownerId = options.currentUserId }
            if source == nil { source = options.defaultSource }
        }
    }

    public var isNewAccount: Bool { selectedAccount == nil }
    public var isSubcontractor: Bool { contactRole == Self.subcontractorRole }

    /// What the account step shows in the summary.
    public var accountDisplayName: String {
        if let selectedAccount { return selectedAccount.name ?? "Account" }
        return [accountFirstName, accountLastName].map(trimmed).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Validation

    public func errors(for step: Step) -> [Field: String] {
        var errors: [Field: String] = [:]
        switch step {
        case .newAccount:
            if trimmed(accountLastName).isEmpty { errors[.accountLastName] = "Enter a last name." }
            if !Self.isEmailOrEmpty(accountEmail) { errors[.accountEmail] = "Enter a valid email address." }
        case .claimDetails:
            if trimmed(claimName).isEmpty { errors[.claimName] = "Enter a claim name." }
            if !Self.isEmailOrEmpty(claimEmail) { errors[.claimEmail] = "Enter a valid email address." }
            if !trimmed(adjusterFees).isEmpty {
                if let fees = Decimal(string: trimmed(adjusterFees)), fees >= 0, fees <= 100 {} else {
                    errors[.adjusterFees] = "Enter a percentage from 0 to 100."
                }
            }
        case .contact:
            guard contactMode != .skip else { break }
            if contactRole == nil { errors[.contactRole] = "Choose the contact's role." }
            if contactMode == .existing && selectedContact == nil { errors[.contact] = "Choose a contact." }
            if contactMode == .new {
                if trimmed(contactLastName).isEmpty { errors[.contactLastName] = "Enter a last name." }
                if !Self.isEmailOrEmpty(contactEmail) { errors[.contactEmail] = "Enter a valid email address." }
            }
        case .partner:
            let needsPick = !partnerMatches.isEmpty || partnerMode == .existing
            if needsPick && selectedPartner == nil {
                errors[.partner] = "Choose the subcontractor's company account."
            } else if !needsPick && trimmed(partnerName).isEmpty {
                errors[.partner] = "Enter the company name."
            }
        default:
            break
        }
        return errors
    }

    public func error(_ field: Field, on step: Step) -> String? {
        showErrors.contains(step) ? errors(for: step)[field] : nil
    }

    // MARK: - 1. Account

    public func searchAccounts(_ query: String) async {
        accountResults = (try? await api.searchAccounts(query, commercialOnly: false)) ?? []
    }

    public func chooseAccount(_ account: AccountMatch) -> Step {
        selectedAccount = account
        accountMatches = []
        prefillClaim(name: account.name, email: account.email, phone: account.phone)
        return .claimDetails
    }

    /// Get_Matching_Person_Accounts before anything is created: matches must be used instead.
    public func continueWithNewAccount() async -> Step? {
        showErrors.insert(.newAccount)
        guard errors(for: .newAccount).isEmpty else { return nil }
        selectedAccount = nil
        guard let matches = await run({ [self] in
            try await api.matchingAccounts(firstName: optional(accountFirstName), lastName: trimmed(accountLastName), email: optional(accountEmail))
        }) else { return nil }
        accountMatches = matches
        if !matches.isEmpty { return .accountMatches }
        prefillClaim(name: accountDisplayName, email: optional(accountEmail), phone: optional(accountPhone))
        return .claimDetails
    }

    // MARK: - 2. Claim

    public func searchInsurance(_ query: String) async {
        let q = trimmed(query)
        guard q.count >= 2, insuranceCompany?.name != q else {
            insuranceResults = []
            return
        }
        insuranceResults = (try? await api.insuranceCompanies(matching: q)) ?? []
    }

    public func chooseInsurance(_ company: InsuranceCompany?) {
        insuranceCompany = company
        insuranceQuery = company?.name ?? ""
        insuranceResults = []
    }

    public func continueFromClaimDetails() -> Step? {
        showErrors.insert(.claimDetails)
        // Typed but not picked from the list: don't send a company the user didn't choose.
        if insuranceCompany?.name != trimmed(insuranceQuery) { insuranceCompany = nil }
        return errors(for: .claimDetails).isEmpty ? .contact : nil
    }

    // MARK: - 3. Contact

    public func searchContacts(_ query: String) async {
        contactResults = (try? await api.searchContacts(query)) ?? []
    }

    public func searchPartners(_ query: String) async {
        partnerResults = (try? await api.searchAccounts(query, commercialOnly: true)) ?? []
    }

    /// Get_Matching_Contacts for a new contact, then the partner account for subcontractors.
    public func continueFromContact() async -> Step? {
        showErrors.insert(.contact)
        guard errors(for: .contact).isEmpty else { return nil }
        guard contactMode == .new else { return .review }
        guard let matches = await run({ [self] in
            try await api.matchingContacts(firstName: optional(contactFirstName), lastName: trimmed(contactLastName), email: optional(contactEmail))
        }) else { return nil }
        contactMatches = matches
        if !matches.isEmpty { return .contactMatches }
        return await stepAfterNewContact()
    }

    /// A matching contact was the right one: link it instead of creating a new one.
    public func useMatchingContact(_ contact: ContactMatch) -> Step {
        selectedContact = contact
        contactMode = .existing
        return .review
    }

    /// "None of these are a match": carry on creating the new contact.
    public func noContactMatches() async -> Step? {
        await stepAfterNewContact()
    }

    private func stepAfterNewContact() async -> Step? {
        guard isSubcontractor else { return .review }
        // Get_Matching_Partner_Accounts on the company name.
        let company = trimmed(contactCompany)
        if !company.isEmpty {
            guard let matches = await run({ [self] in try await api.matchingPartnerAccounts(name: company) }) else { return nil }
            partnerMatches = matches
            if partnerName.isEmpty { partnerName = company }
            if matches.isEmpty && selectedPartner == nil { partnerMode = .new }
        } else {
            partnerMatches = []
        }
        return .partner
    }

    public func continueFromPartner() -> Step? {
        showErrors.insert(.partner)
        return errors(for: .partner).isEmpty ? .review : nil
    }

    // MARK: - 4. Create

    public var request: NewClaimRequest {
        let account: NewClaimRequest.Account = selectedAccount.map { .existing(id: $0.id) } ?? .new(.init(
            firstName: optional(accountFirstName), lastName: trimmed(accountLastName),
            email: optional(accountEmail), phone: optional(accountPhone)
        ))

        var claim = NewClaimRequest.Claim(name: trimmed(claimName))
        claim.street = optional(street)
        claim.city = optional(city)
        claim.state = state
        claim.postalCode = optional(postalCode)
        claim.lossDate = hasLossDate ? CalendarDate(lossDate) : nil
        claim.peril = peril
        claim.lossDescription = optional(lossDescription)
        claim.claimNumber = optional(claimNumber)
        claim.policyNumber = optional(policyNumber)
        claim.insuranceCompanyId = insuranceCompany?.id
        claim.email = optional(claimEmail)
        claim.phone = optional(claimPhone)
        claim.source = source
        claim.adjusterFees = optional(adjusterFees).flatMap { Decimal(string: $0) }
        claim.ownerId = ownerId
        claim.accountManagerId = accountManagerId

        var contact: NewClaimRequest.Contact?
        if let role = contactRole {
            switch contactMode {
            case .skip:
                contact = nil
            case .existing:
                contact = selectedContact.map { .existing(id: $0.id, role: role) }
            case .new:
                let partner: NewClaimRequest.PartnerAccount? = !isSubcontractor ? nil
                    : selectedPartner.map { .existing(id: $0.id) } ?? .new(name: trimmed(partnerName))
                contact = .new(.init(
                    firstName: optional(contactFirstName), lastName: trimmed(contactLastName),
                    email: optional(contactEmail), phone: optional(contactPhone), company: optional(contactCompany)
                ), role: role, partner: partner)
            }
        }
        return NewClaimRequest(account: account, claim: claim, contact: contact)
    }

    /// Creates everything. On a duplicate, returns the step where the user picks the match.
    public func submit() async -> Step? {
        guard !isWorking else { return nil }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            createdClaimId = try await api.createClaim(request)
            return nil
        } catch {
            let wrapped = PortalAPIError.wrap(error)
            guard case .duplicate(let duplicate) = wrapped else {
                self.error = wrapped
                return nil
            }
            switch duplicate.kind {
            case .account:
                accountMatches = duplicate.accounts
                return .accountMatches
            case .partnerAccount:
                partnerMatches = duplicate.accounts
                selectedPartner = nil
                partnerMode = .existing
                return .partner
            case .contact:
                duplicateContacts = duplicate.contacts
                return .duplicateContact
            }
        }
    }

    /// Resolve_Duplicate_Associated_Party_Contact: use the existing contact, or skip the contact.
    public func resolveDuplicateContact(using contact: ContactMatch?) async -> Step? {
        if let contact {
            selectedContact = contact
            contactMode = .existing
        } else {
            contactMode = .skip
        }
        return await submit()
    }

    // MARK: - Helpers

    private func prefillClaim(name: String?, email: String?, phone: String?) {
        if trimmed(claimName).isEmpty, let name { claimName = name }
        if trimmed(claimEmail).isEmpty, let email { claimEmail = email }
        if trimmed(claimPhone).isEmpty, let phone { claimPhone = phone }
    }

    /// Runs a lookup, recording a failure for the screen. Nil on failure.
    private func run<T: Sendable>(_ call: @escaping () async throws -> T) async -> T? {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            return try await call()
        } catch {
            self.error = .wrap(error)
            return nil
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optional(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }

    static func isEmailOrEmpty(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}

extension CalendarDate {
    /// The calendar date of `date` in the current time zone.
    init(_ date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}
