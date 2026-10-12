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
