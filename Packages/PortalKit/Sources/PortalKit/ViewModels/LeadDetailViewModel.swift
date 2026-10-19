import Foundation
import Observation

/// Lead detail (spec §6.7). Sections load independently, as on claim detail.
@MainActor
@Observable
public final class LeadDetailViewModel {
    public enum Section: String, CaseIterable, Sendable {
        case updates = "Updates"
        case details = "Details"
        case referredBy = "Referred By"
        case insurance = "Insurance"
        case files = "Files"
    }

    /// One step of the agreement tracker: Sent → Signed.
    public struct AgreementStep: Equatable, Sendable {
        public let title: String
        public let date: Date?
        public let state: StepState
    }

    public let leadId: String
    public private(set) var detail: LoadState<LeadDetail> = .idle
    public private(set) var updates: LoadState<[PortalUpdate]> = .idle
    public private(set) var files: LoadState<[PortalFile]> = .idle
    public var section: Section = .updates

    private let api: PortalAPI

    public init(leadId: String, api: PortalAPI) {
        self.leadId = leadId
        self.api = api
    }

    public var record: RecordRef { .lead(leadId) }

    public func load() async {
        async let detail: Void = loadDetail()
        async let updates: Void = loadUpdates()
        async let files: Void = loadFiles()
        _ = await (detail, updates, files)
    }

    public func loadDetail() async {
        let api = self.api, id = leadId
        await PortalKit.load(self, \.detail) { try await api.lead(id: id) }
    }

    /// Also called after the user comments, because lead comments are published to this feed (spec §5.2).
    public func loadUpdates() async {
        let api = self.api, record = self.record
        await PortalKit.load(self, \.updates) {
            try await api.updates(for: record).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
    }

    public func loadFiles() async {
        let api = self.api, record = self.record
        await PortalKit.load(self, \.files) { try await api.files(for: record) }
    }

    /// Sent → Signed. Nil when no agreement has been sent ("Visible once an agreement has been sent.").
    /// There's no Viewed step: the server never records it (spec §5.2).
    public static func agreementSteps(for agreement: Agreement?) -> [AgreementStep]? {
        guard let agreement, agreement.hasAgreement else { return nil }
        let signed = agreement.isSigned
        return [
            AgreementStep(title: "Sent", date: agreement.sentDate, state: signed ? .complete : .current),
            AgreementStep(title: "Signed", date: signed ? agreement.completedDate : nil, state: signed ? .current : .upcoming)
        ]
    }
}
