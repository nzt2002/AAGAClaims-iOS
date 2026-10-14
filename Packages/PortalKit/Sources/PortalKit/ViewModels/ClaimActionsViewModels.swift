import Foundation
import Observation

/// The staff claim actions on a claim's page: loads what they need (`GET /claims/{id}/staff`)
/// and saves Edit Claim, Update Address, Change Owner and Proof of Loss.
@MainActor
@Observable
public final class ClaimActionsViewModel {
    public let claimId: String
    public private(set) var staff: LoadState<StaffClaim> = .idle
    public private(set) var isSaving = false
    /// A message for the open form, e.g. a validation rule's.
    public private(set) var errorMessage: String?

    private let api: PortalAPI

    public init(api: PortalAPI, claimId: String) {
        self.api = api
        self.claimId = claimId
    }

    public func load() async {
        let api = self.api, id = claimId
        await PortalKit.load(self, \.staff) { try await api.staffClaim(id: id) }
    }

    public func clearError() { errorMessage = nil }

    @discardableResult
    public func saveEdit(_ edit: ClaimEdit) async -> Bool {
        guard !edit.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a claim name."
            return false
        }
        if let fees = edit.adjusterFees, fees > 100 {
            errorMessage = "Adjuster fees must be 100% or less."
            return false
        }
        let api = self.api, id = claimId
        return await run { try await api.editClaim(id: id, edit) }
    }

    @discardableResult
    public func saveAddress(_ address: ClaimAddress) async -> Bool {
        let api = self.api, id = claimId
        return await run { try await api.updateClaimAddress(id: id, address) }
    }

    @discardableResult
    public func changeOwner(to ownerId: String) async -> Bool {
        let api = self.api, id = claimId
        return await run { try await api.changeClaimOwner(id: id, ownerId: ownerId) }
    }

    @discardableResult
    public func saveProofOfLoss(_ proofOfLoss: ProofOfLoss) async -> Bool {
        if let start = proofOfLoss.policyEffectiveDate, let end = proofOfLoss.policyExpirationDate,
           (end.year, end.month, end.day) < (start.year, start.month, start.day) {
            errorMessage = "The policy expiration date must be after the effective date."
            return false
        }
        let api = self.api, id = claimId
        return await run { try await api.saveProofOfLoss(id: id, proofOfLoss) }
    }

    /// Runs a save, then reloads the claim's action data so the forms show what was saved.
    private func run(_ save: @escaping @Sendable () async throws -> Void) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await save()
            await load()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    public nonisolated static func message(for error: Error) -> String {
        switch PortalAPIError.wrap(error) {
        case .rejected(let message): message
        case .offline: "You're offline. Try again when you're connected."
        case .invalidRequest: "Salesforce didn't accept these details. Check the fields and try again."
        case .notFound: "This claim isn't available."
        default: "Something went wrong. Please try again."
        }
    }
}

// MARK: - Apply Payments

/// Apply Payments, as the Apply_Payments_Mobile quick action (claimPaymentCalculatorMobileQA):
/// payment rows, an optional system deductible, and the adjuster fee and insured payment.
@MainActor
@Observable
public final class PaymentCalculatorViewModel {
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        public var rowType: String?
        public var amount: Decimal?
        public init(id: UUID = UUID(), rowType: String? = nil, amount: Decimal? = nil) {
            self.id = id
            self.rowType = rowType
            self.amount = amount
        }
    }

    public static let rcv = "Replacement Cash Value (RCV)"
    public static let deductibleType = "Deductible"
    public static let acv = "Actual Cash Value (ACV)"
    /// Choosing this applies the deductible automatically (as in the quick action).
    public static let netActualCheck = "NET Payment (Actual Check)"

    public let claimId: String
    public private(set) var setup: LoadState<PaymentSetup> = .idle
    public var rows: [Row] = [Row()]
    public var dateCollected = Date()
    public var notes = ""
    /// The user's "Apply deductible" switch.
    public var deductibleSelected = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Shown once, when choosing "Deductible" turns into the system deductible.
    public private(set) var notice: String?

    private let api: PortalAPI

    public init(api: PortalAPI, claimId: String) {
        self.api = api
        self.claimId = claimId
    }

    public func load() async {
        let api = self.api, id = claimId
        await PortalKit.load(self, \.setup) { try await api.paymentSetup(claimId: id) }
    }

    /// The claim needs a deductible before payments can be applied.
    public var isBlocked: Bool {
        guard let deductible = setup.value?.deductible else { return setup.value != nil }
        return deductible <= 0
    }

    /// Types to choose from; Deductible is left out while the deductible is applied automatically.
    public var paymentTypes: [String] {
        let types = setup.value?.paymentTypes ?? []
        return applyDeductible ? types.filter { $0 != Self.deductibleType } : types
    }

    /// On when the user switches it on, or when a NET Payment (Actual Check) row is entered.
    public var applyDeductible: Bool {
        deductibleSelected || rows.contains { Self.normalized($0.rowType) == Self.normalized(Self.netActualCheck) }
    }

    public func setType(_ type: String?, for rowId: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        if type == Self.deductibleType {
            // As in the quick action: the deductible becomes the system row, not a typed one.
            deductibleSelected = true
            rows[index].rowType = nil
            notice = "The deductible is applied automatically."
            return
        }
        rows[index].rowType = type
        if applyDeductible { clearDeductibleRows() }
    }

    public func setApplyDeductible(_ on: Bool) {
        deductibleSelected = on
        if applyDeductible { clearDeductibleRows() }
    }

    public func addRow() { rows.append(Row()) }

    public func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty { rows = [Row()] }
    }

    private func clearDeductibleRows() {
        for index in rows.indices where rows[index].rowType == Self.deductibleType {
            rows[index].rowType = nil
        }
    }

    // MARK: Totals

    public var deductible: Decimal { setup.value?.deductible ?? 0 }

    /// 10 means 10%; values up to 1 are already fractions.
    public var feeRate: Decimal {
        let fees = setup.value?.adjusterFees ?? 0
        guard fees > 0 else { return 0 }
        return fees > 1 ? fees / 100 : fees
    }

    public var totalRCV: Decimal {
        rows.filter { $0.rowType == Self.rcv }.reduce(0) { $0 + abs($1.amount ?? 0) }
    }

    /// Payments received in this entry: everything except RCV and ACV, less any deductible rows.
    public var received: Decimal {
        rows.reduce(0) { sum, row in
            guard let type = row.rowType else { return sum }
            let amount = abs(row.amount ?? 0)
            switch type {
            case Self.rcv, Self.acv: return sum
            case Self.deductibleType: return sum - amount
            default: return sum + amount
            }
        }
    }

    public var systemDeductible: Decimal { applyDeductible && deductible > 0 ? deductible : 0 }

    /// The adjuster fee includes the deductible when it's applied.
    public var adjusterFee: Decimal { (received + systemDeductible) * feeRate }

    public var insuredPayment: Decimal { max(0, received - adjusterFee) }

    // MARK: Save

    public var entry: PaymentEntry {
        PaymentEntry(
            dateCollected: CalendarDate(dateCollected),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            applyDeductible: applyDeductible,
            rows: rows.compactMap { row in
                guard let type = row.rowType else { return nil }
                return .init(rowType: type, amount: abs(row.amount ?? 0))
            }
        )
    }

    @discardableResult
    public func save() async -> Bool {
        guard !isSaving else { return false }
        if isBlocked {
            errorMessage = "Please add the Deductible on this claim before using the payment calculator."
            return false
        }
        guard !entry.rows.isEmpty else {
            errorMessage = "Add at least one payment with a type."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let api = self.api, id = claimId, entry = self.entry
        do {
            try await api.applyPayments(claimId: id, entry)
            return true
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
            return false
        }
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

// MARK: - Add Contact

/// Add Contact (Add_Claim_Contact): an existing contact, or a new one checked for matches first.
@MainActor
@Observable
public final class AddClaimContactViewModel {
    public enum Mode: String, CaseIterable, Sendable {
        case existing = "Existing"
        case new = "New"
    }

    public enum Step: Sendable, Equatable {
        case form, matches, partner, duplicate, done
    }

    public let claimId: String
    public var mode: Mode = .existing
    public var role: String?
    public var selectedContact: ContactMatch?
    public var firstName = ""
    public var lastName = ""
    public var email = ""
    public var mobile = ""
    public var company = ""
    public private(set) var searchResults: [ContactMatch] = []
    public private(set) var matches: [ContactMatch] = []
    public private(set) var duplicates: [ContactMatch] = []
    public var partnerMode: NewClaimViewModel.PartnerMode = .existing
    public var selectedPartner: AccountMatch?
    public var partnerName = ""
    public private(set) var partnerMatches: [AccountMatch] = []
    public private(set) var partnerResults: [AccountMatch] = []
    public private(set) var step: Step = .form
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    private let api: PortalAPI

    public init(api: PortalAPI, claimId: String) {
        self.api = api
        self.claimId = claimId
    }

    public var isSubcontractor: Bool { role == NewClaimViewModel.subcontractorRole }

    public func search(_ query: String) async {
        searchResults = (try? await api.searchContacts(query)) ?? []
    }

    public func searchPartners(_ query: String) async {
        partnerResults = (try? await api.searchAccounts(query, commercialOnly: true)) ?? []
    }

    /// Validates, then for a new contact checks matches (email, mobile, or name) before anything is created.
    public func continueFromForm() async {
        errorMessage = nil
        guard role != nil else { return errorMessage = "Choose the contact's role." }
        switch mode {
        case .existing:
            guard selectedContact != nil else { return errorMessage = "Choose a contact." }
            await submit()
        case .new:
            guard !trim(lastName).isEmpty else { return errorMessage = "Enter a last name." }
            guard NewClaimViewModel.isEmailOrEmpty(email) else { return errorMessage = "Enter a valid email address." }
            isWorking = true
            let found = try? await api.claimContactMatches(
                claimId: claimId, firstName: optional(firstName), lastName: trim(lastName),
                email: optional(email), mobile: optional(mobile)
            )
            isWorking = false
            matches = found ?? []
            if !matches.isEmpty {
                step = .matches
            } else {
                await afterNewContactDetails()
            }
        }
    }

    /// A match was the right person: link them instead.
    public func useMatch(_ contact: ContactMatch) async {
        selectedContact = contact
        mode = .existing
        await submit()
    }

    /// "None of these are a match".
    public func noMatch() async {
        await afterNewContactDetails()
    }

    private func afterNewContactDetails() async {
        guard isSubcontractor else { return await submit() }
        let name = trim(company)
        if !name.isEmpty {
            partnerMatches = (try? await api.matchingPartnerAccounts(name: name)) ?? []
            if partnerName.isEmpty { partnerName = name }
            if partnerMatches.isEmpty { partnerMode = .new }
        }
        step = .partner
    }

    public func continueFromPartner() async {
        errorMessage = nil
        let mustPick = !partnerMatches.isEmpty || partnerMode == .existing
        if mustPick && selectedPartner == nil { return errorMessage = "Choose the company account." }
        if !mustPick && trim(partnerName).isEmpty { return errorMessage = "Enter the company name." }
        await submit()
    }

    /// Duplicate rules matched: use one of them, or don't add a contact.
    public func resolveDuplicate(_ contact: ContactMatch?) async {
        guard let contact else {
            step = .done
            return
        }
        await useMatch(contact)
    }

    public var request: NewClaimRequest.Contact? {
        guard let role else { return nil }
        switch mode {
        case .existing:
            return selectedContact.map { .existing(id: $0.id, role: role) }
        case .new:
            let partner: NewClaimRequest.PartnerAccount? = !isSubcontractor ? nil
                : selectedPartner.map { .existing(id: $0.id) } ?? .new(name: trim(partnerName))
            return .new(.init(firstName: optional(firstName), lastName: trim(lastName), email: optional(email),
                              phone: optional(mobile), company: optional(company)), role: role, partner: partner)
        }
    }

    private func submit() async {
        guard let request else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await api.addClaimContact(claimId: claimId, request)
            step = .done
        } catch {
            let wrapped = PortalAPIError.wrap(error)
            if case .duplicate(let duplicate) = wrapped {
                switch duplicate.kind {
                case .contact:
                    duplicates = duplicate.contacts
                    step = .duplicate
                case .partnerAccount, .account:
                    partnerMatches = duplicate.accounts
                    selectedPartner = nil
                    step = .partner
                }
            } else {
                errorMessage = ClaimActionsViewModel.message(for: error)
            }
        }
    }

    private func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func optional(_ value: String) -> String? { trim(value).isEmpty ? nil : trim(value) }
}

// MARK: - Log a Call and Send an Email

@MainActor
@Observable
public final class LogCallViewModel {
    public var subject = "Call"
    public var details = ""
    public var contactId: String?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    private let api: PortalAPI
    private let claimId: String

    public init(api: PortalAPI, claimId: String) {
        self.api = api
        self.claimId = claimId
    }

    @discardableResult
    public func save() async -> Bool {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            errorMessage = "Enter a subject."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await api.logCall(claimId: claimId, CallLog(subject: subject, description: trimmed.isEmpty ? nil : trimmed, contactId: contactId))
            return true
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
            return false
        }
    }
}

/// Send an Email (the New_Email quick action): sent through Salesforce and logged on the claim.
@MainActor
@Observable
public final class EmailComposerViewModel {
    public var fromAddressId: String?
    public var to: [String] = []
    public var cc: [String] = []
    public var bcc: [String] = []
    public var subject = ""
    public var body = ""
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    private let api: PortalAPI
    private let claimId: String

    public init(api: PortalAPI, claimId: String, defaultRecipient: String?) {
        self.api = api
        self.claimId = claimId
        if let defaultRecipient { to = [defaultRecipient] }
    }

    /// Adds typed addresses (comma, semicolon or space separated), skipping duplicates.
    public func add(_ text: String, to field: WritableKeyPath<EmailComposerViewModel, [String]>) -> Bool {
        let parts = text.split(whereSeparator: { ",; \n".contains($0) }).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ NewClaimViewModel.isEmailOrEmpty($0) }) else { return false }
        var me = self
        for part in parts where !me[keyPath: field].contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            me[keyPath: field].append(part)
        }
        return true
    }

    public var canSend: Bool {
        !to.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// The body as simple HTML: escaped text with line breaks.
    public var htmlBody: String {
        body.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
    }

    @discardableResult
    public func send() async -> Bool {
        guard canSend else {
            errorMessage = "Add a recipient, a subject and a message."
            return false
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let email = OutgoingEmail(fromAddressId: fromAddressId, to: to, cc: cc, bcc: bcc,
                                  subject: subject.trimmingCharacters(in: .whitespaces), body: htmlBody)
        do {
            try await api.sendEmail(claimId: claimId, email)
            return true
        } catch {
            errorMessage = ClaimActionsViewModel.message(for: error)
            return false
        }
    }
}
