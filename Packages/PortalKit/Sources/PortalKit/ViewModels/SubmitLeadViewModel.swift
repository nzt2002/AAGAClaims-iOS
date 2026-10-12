import Foundation
import Observation

/// Submit a Lead (spec §6.8).
@MainActor
@Observable
public final class SubmitLeadViewModel {
    public enum Field: Hashable, Sendable {
        case name, contact, email, postalCode, fileLink
    }

    public enum ClaimFiled: String, CaseIterable, Sendable {
        case yes = "Yes"
        case no = "No"
    }

    public enum InsuranceSearch: Equatable, Sendable {
        case idle
        case searching
        case results([InsuranceCompany])
        /// "No insurance companies found"
        case noResults
        /// "Insurance company search is currently unavailable."
        case unavailable
    }

    // 1. Claimant information
    public var name = ""
    public var email = ""
    public var phone = ""
    // 2. Property address
    public var street = ""
    public var city = ""
    public var stateCode: String?
    public var postalCode = ""
    // 3. Loss details
    public var peril: String?
    public var lossDescription = ""
    public var fileLink = ""
    // 4. Insurance
    public var insuranceQuery = "" {
        didSet { insuranceQueryChanged() }
    }
    public private(set) var insuranceCompany: InsuranceCompany?
    public private(set) var insuranceSearch: InsuranceSearch = .idle
    public var policyNumber = ""
    public var claimFiled: ClaimFiled?
    public var claimNumber = ""
    // 5. Referral
    public var referralCompany = ""
    public var referralName = ""
    public var referralPhone = ""
    /// Read-only: the signed-in user's email. It's how the lead appears in My Leads.
    public let referralEmail: String

    public private(set) var perils: LoadState<[String]> = .idle
    /// Errors are shown once the user has tried to submit.
    public private(set) var showErrors = false
    public private(set) var isSubmitting = false
    public private(set) var submitError: PortalAPIError?
    /// The new lead's id after a successful submit.
    public private(set) var createdLeadId: String?

    private let api: PortalAPI
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    /// Set while selecting a company, so filling the field with its name doesn't search again.
    private var isSelectingCompany = false

    public init(api: PortalAPI, userEmail: String, debounce: Duration = .milliseconds(300)) {
        self.api = api
        self.referralEmail = userEmail
        self.debounce = debounce
    }

    // MARK: - Pickers

    public func loadPerils() async {
        let api = self.api
        await PortalKit.load(self, \.perils) { try await api.perilValues() }
    }

    public static let usStates: [(code: String, name: String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"),
        ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"),
        ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"),
        ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"),
        ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
        ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"),
        ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ]

    // MARK: - Insurance typeahead

    public func selectInsuranceCompany(_ company: InsuranceCompany) {
        searchTask?.cancel()
        isSelectingCompany = true
        insuranceCompany = company
        insuranceQuery = company.name
        isSelectingCompany = false
        insuranceSearch = .idle
    }

    private func insuranceQueryChanged() {
        guard !isSelectingCompany else { return }
        // Editing the text clears a previous selection.
        if insuranceCompany?.name != insuranceQuery {
            insuranceCompany = nil
        }
        searchTask?.cancel()

        let query = insuranceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Starts at 2 characters (spec §6.8).
        guard query.count >= 2, insuranceCompany == nil else {
            insuranceSearch = .idle
            return
        }

        let api = self.api, debounce = self.debounce
        searchTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            self?.insuranceSearch = .searching
            do {
                let results = try await api.insuranceCompanies(matching: query)
                guard !Task.isCancelled else { return }
                self?.insuranceSearch = results.isEmpty ? .noResults : .results(results)
            } catch {
                guard !Task.isCancelled else { return }
                self?.insuranceSearch = .unavailable
            }
        }
    }

    /// Waits for the current typeahead search. For tests.
    public func awaitInsuranceSearch() async {
        await searchTask?.value
    }

    // MARK: - Validation

    public var errors: [Field: String] {
        var errors: [Field: String] = [:]
        if trimmed(name).isEmpty {
            errors[.name] = "Enter the claimant's name."
        }
        if trimmed(email).isEmpty && trimmed(phone).isEmpty {
            errors[.contact] = "Enter at least one contact method: email or phone."
        }
        if !trimmed(email).isEmpty && !Self.looksLikeEmail(trimmed(email)) {
            errors[.email] = "Enter a valid email address."
        }
        let zip = trimmed(postalCode)
        if !zip.isEmpty && !(zip.count == 5 && zip.allSatisfy(\.isASCII) && zip.allSatisfy(\.isNumber)) {
            errors[.postalCode] = "Enter a 5-digit ZIP code."
        }
        let link = trimmed(fileLink)
        if !link.isEmpty && !Self.isWebURL(link) {
            errors[.fileLink] = "Enter a full web address, starting with https://."
        }
        return errors
    }

    public func error(for field: Field) -> String? {
        showErrors ? errors[field] : nil
    }

    public var isValid: Bool { errors.isEmpty }

    // MARK: - Submit

    public var submission: LeadSubmission {
        var submission = LeadSubmission(leadName: trimmed(name))
        submission.email = nonEmpty(email)
        submission.phone = nonEmpty(phone)
        submission.street = nonEmpty(street)
        submission.city = nonEmpty(city)
        submission.stateCode = stateCode
        submission.postalCode = nonEmpty(postalCode)
        submission.peril = peril
        submission.lossDescription = nonEmpty(lossDescription)
        submission.fileLink = nonEmpty(fileLink)
        submission.insuranceCompanyId = insuranceCompany?.id
        submission.policyNumber = nonEmpty(policyNumber)
        submission.didFileClaim = claimFiled?.rawValue
        submission.claimNumber = claimFiled == .yes ? nonEmpty(claimNumber) : nil
        submission.associatedPartyCompany = nonEmpty(referralCompany)
        submission.associatedPartyName = nonEmpty(referralName)
        submission.associatedPartyPhone = nonEmpty(referralPhone)
        submission.associatedPartyEmail = referralEmail
        return submission
    }

    /// "Thank you, {name}. We have received your information and our team will review it promptly."
    public var confirmationMessage: String {
        "Thank you, \(trimmed(name)). We have received your information and our team will review it promptly."
    }

    @discardableResult
    public func submit() async -> Bool {
        showErrors = true
        guard isValid, !isSubmitting else { return false }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            createdLeadId = try await api.createLead(submission)
            return true
        } catch {
            submitError = .wrap(error)
            return false
        }
    }

    // MARK: - Helpers

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        value.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host(), host.contains(".") else {
            return false
        }
        return true
    }
}
