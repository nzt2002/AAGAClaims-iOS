import Foundation

/// Home's "Needs attention": the few things worth acting on today, worked out from what Home
/// already loads (agenda, claims, leads, updates). Most urgent first; empty when all caught up.
public struct AttentionItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case overdueTasks
        case dueToday
        case unread
        case payments
        case agreements
    }

    public let kind: Kind
    public let count: Int
    public let title: String
    public let detail: String
    /// What to open when there's exactly one (a task's record, the claim, the lead).
    public let record: RecordRef?
    public let recordName: String?
    /// The single task, so Home can offer Mark complete.
    public let task: AgendaItem?

    public var id: String { kind.rawValue }
}

extension HomeViewModel {
    /// Agreements unsigned this long after sending get a nudge.
    nonisolated static let agreementNudgeDays = 3
    /// Claims updated within this many days with money collected count as "recent payments".
    nonisolated static let recentPaymentDays = 7

    public var needsAttention: [AttentionItem] {
        Self.attention(
            agenda: agenda.value?.items ?? [],
            claims: state.value?.claims ?? [],
            leads: state.value?.leads ?? [],
            unread: unreadCount,
            now: Date()
        )
    }

    nonisolated static func attention(agenda: [AgendaItem], claims: [ClaimSummary], leads: [LeadSummary],
                                      unread: Int, now: Date) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let today = CalendarDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        let openTasks = agenda.filter { $0.kind == .task && $0.isClosed != true }

        let overdue = openTasks.filter { $0.isOverdue == true || ($0.dueDate.map { $0 < today } ?? false) }
        if let first = overdue.first {
            items.append(taskItem(.overdueTasks, tasks: overdue, first: first,
                                  title: overdue.count == 1 ? "1 overdue task" : "\(overdue.count) overdue tasks"))
        }

        let dueToday = openTasks.filter { $0.dueDate == today && !overdue.contains($0) }
        if let first = dueToday.first {
            items.append(taskItem(.dueToday, tasks: dueToday, first: first,
                                  title: dueToday.count == 1 ? "1 task due today" : "\(dueToday.count) tasks due today"))
        }

        if unread > 0 {
            items.append(AttentionItem(kind: .unread, count: unread,
                                       title: unread == 1 ? "1 unread update" : "\(unread) unread updates",
                                       detail: "News on your claims and leads",
                                       record: nil, recordName: nil, task: nil))
        }

        let paymentCutoff = now.addingTimeInterval(-Double(recentPaymentDays) * 86_400)
        let paid = claims.filter {
            ($0.paymentCollected ?? 0) > 0 && ($0.lastModifiedDate ?? .distantPast) >= paymentCutoff
        }
        if let first = paid.first {
            items.append(AttentionItem(kind: .payments, count: paid.count,
                                       title: paid.count == 1 ? "Payment activity on 1 claim" : "Payment activity on \(paid.count) claims",
                                       detail: paid.count == 1 ? (first.recordName ?? "Claim") : "Updated in the last \(recentPaymentDays) days",
                                       record: paid.count == 1 ? .claim(first.recordId) : nil,
                                       recordName: first.recordName, task: nil))
        }

        let nudgeCutoff = now.addingTimeInterval(-Double(agreementNudgeDays) * 86_400)
        let unsigned = leads.filter {
            $0.agreementCompletedDate == nil && ($0.agreementSentDate.map { $0 <= nudgeCutoff } ?? false)
        }
        if let first = unsigned.first {
            items.append(AttentionItem(kind: .agreements, count: unsigned.count,
                                       title: unsigned.count == 1 ? "1 agreement waiting for a signature" : "\(unsigned.count) agreements waiting for signatures",
                                       detail: unsigned.count == 1 ? (first.recordName ?? "Lead") : "Sent more than \(agreementNudgeDays) days ago",
                                       record: unsigned.count == 1 ? .lead(first.recordId) : nil,
                                       recordName: first.recordName, task: nil))
        }
        return items
    }

    private nonisolated static func taskItem(_ kind: AttentionItem.Kind, tasks: [AgendaItem], first: AgendaItem,
                                             title: String) -> AttentionItem {
        let record: RecordRef? = switch (first.relatedRecordType, first.relatedRecordId) {
        case (.claim?, let id?): .claim(id)
        case (.prospect?, let id?): .lead(id)
        default: nil
        }
        let detail = tasks.count == 1
            ? (first.subject ?? "Task")
            : "\(first.subject ?? "Task") and \(tasks.count - 1) more"
        return AttentionItem(kind: kind, count: tasks.count, title: title, detail: detail,
                             record: record, recordName: first.relatedRecordName,
                             task: tasks.count == 1 ? first : nil)
    }

    /// Marks a task complete from Home, then refreshes the agenda. False if it failed.
    public func completeTask(_ task: AgendaItem) async -> Bool {
        do {
            _ = try await api.completeTask(id: task.id)
            await loadAgenda()
            return true
        } catch {
            return false
        }
    }
}
