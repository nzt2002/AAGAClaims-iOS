import Foundation

public enum StepState: Hashable, Sendable {
    case complete
    case current
    case upcoming
}

/// The 7-stage claim lifecycle (spec §6.5).
public enum ClaimLifecycle {
    public static let stages = [
        "Preparation", "Inspection", "Negotiations", "Restoration", "Litigation", "Settlement", "Closed"
    ]

    /// Plain-language help for homeowners: what's happening at this stage, and what comes next.
    public struct Guide: Hashable, Sendable {
        public let now: String
        public let next: String
    }

    public static func guide(for stage: String?) -> Guide? {
        switch stage {
        case "Preparation":
            Guide(now: "We're gathering your policy, photos and documents and opening the claim with your insurance company.",
                  next: "We'll schedule an inspection of the damage with your insurer's adjuster.")
        case "Inspection":
            Guide(now: "Your property is being inspected and the damage documented, usually with your insurance company's adjuster.",
                  next: "We'll prepare a detailed estimate of the damage and send it to your insurer.")
        case "Negotiations":
            Guide(now: "We're negotiating with your insurance company for a fair settlement of your claim.",
                  next: "Once the amount is agreed, your insurer issues payments and repairs can begin.")
        case "Restoration":
            Guide(now: "Your settlement is agreed and repairs can go ahead. We keep track of payments from your insurer.",
                  next: "We'll collect any remaining payments, such as recoverable depreciation, as the work is finished.")
        case "Litigation":
            Guide(now: "Your claim is going through legal or appraisal proceedings to settle a disagreement with your insurer.",
                  next: "We'll keep you updated as it moves forward. This stage can take longer than the others.")
        case "Settlement":
            Guide(now: "Your claim is settled and the final payments are being collected.",
                  next: "Once everything has been paid, we'll close your claim.")
        case "Closed":
            Guide(now: "Your claim is complete. Thank you for working with us.",
                  next: "If anything else comes up, contact us through Support.")
        default:
            nil
        }
    }

    public enum Position: Hashable, Sendable {
        /// `index` is 0-based into `stages`.
        case stage(index: Int)
        /// Status not in the lifecycle (or blank): show it raw and hide progress.
        case unknown(String?)

        /// round(((index + 1) ÷ 7) × 100), matching the portal. Nil when unknown.
        public var percentComplete: Int? {
            guard case .stage(let index) = self else { return nil }
            let value = (Double(index + 1) / Double(ClaimLifecycle.stages.count)) * 100
            return Int(value.rounded())
        }

        public func state(ofStageAt stageIndex: Int) -> StepState {
            guard case .stage(let index) = self else { return .upcoming }
            if stageIndex < index { return .complete }
            if stageIndex == index { return .current }
            return .upcoming
        }
    }

    public static func position(for status: String?) -> Position {
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let index = stages.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .stage(index: index)
        }
        return .unknown(status)
    }
}

/// Lead lifecycle (spec §6.7).
public enum LeadLifecycle {
    public static let stages = ["New", "Working", "Qualified", "Converted"]
    public static let unqualifiedStages = ["New", "Working", "Unqualified"]

    public enum Position: Hashable, Sendable {
        case stage(index: Int, isUnqualified: Bool)
        case unknown(String?)

        public var stages: [String] {
            if case .stage(_, true) = self { return LeadLifecycle.unqualifiedStages }
            return LeadLifecycle.stages
        }

        public func state(ofStageAt stageIndex: Int) -> StepState {
            guard case .stage(let index, _) = self else { return .upcoming }
            if stageIndex < index { return .complete }
            if stageIndex == index { return .current }
            return .upcoming
        }
    }

    public static func position(for status: String?) -> Position {
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.caseInsensitiveCompare("Unqualified") == .orderedSame {
            return .stage(index: 2, isUnqualified: true)
        }
        if let index = stages.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .stage(index: index, isUnqualified: false)
        }
        return .unknown(status)
    }
}
