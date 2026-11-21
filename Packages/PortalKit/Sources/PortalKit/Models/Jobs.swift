import Foundation

/// `GET /jobs` row: a job for a company with the Contractor add-on. The money field is only there for people who may see it.
public struct JobSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// "JOB-0042"
    public let number: String?
    /// "insurance" or "retail" (nil for a customer's view).
    public let workflow: String?
    public let stage: String
    public let stageNumber: Int
    public let stageTotal: Int
    public let trade: String?
    public let address: String?
    public let customerName: String?
    public let startDate: CalendarDate?
    public let completedDate: CalendarDate?
    public let updatedDate: Date?
    public let contractAmount: Decimal?

    /// How far along the board the job is, 0...1.
    public var progress: Double { stageTotal > 1 ? min(1, max(0, Double(stageNumber - 1) / Double(stageTotal - 1))) : (completedDate == nil ? 0 : 1) }
    public var isComplete: Bool { completedDate != nil }
}

public struct JobStage: Codable, Hashable, Sendable {
    public let name: String
    public let current: Bool
}

public struct JobCustomer: Codable, Hashable, Sendable {
    public let name: String?
    public let email: String?
    public let phone: String?
}

public struct JobEstimate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let number: String?
    public let title: String
    public let status: String
    public let validUntil: CalendarDate?
    public let total: Decimal?
}

public struct JobInvoice: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let number: String?
    public let type: String?
    public let status: String
    public let dueDate: CalendarDate?
    public let total: Decimal?
    public let paid: Decimal?
    public let balance: Decimal?
}

public struct JobWork: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let number: String?
    public let title: String
    public let status: String
    public let startDate: CalendarDate?
    public let endDate: CalendarDate?
    public let arrival: String?
    public let crew: String?
}

/// `GET /jobs/{id}`: the job with its stages, customer, estimates, invoices and scheduled work in one call.
public struct JobDetail: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let number: String?
    public let workflow: String?
    public let stage: String
    public let stageNumber: Int
    public let stageTotal: Int
    public let trade: String?
    public let address: String?
    public let customerName: String?
    public let startDate: CalendarDate?
    public let completedDate: CalendarDate?
    public let updatedDate: Date?
    public let contractAmount: Decimal?
    public let customer: JobCustomer?
    public let stages: [JobStage]
    public let openTasks: Int?
    public let estimates: [JobEstimate]
    public let invoices: [JobInvoice]
    public let work: [JobWork]
    public let canSeeMoney: Bool?

    public var isComplete: Bool { completedDate != nil }
    /// What's still owed across the job's invoices.
    public var balanceDue: Decimal { invoices.reduce(0) { $0 + ($1.status == "Paid" || $1.status == "Draft" || $1.status == "Void" ? 0 : ($1.balance ?? 0)) } }
}
