import PortalKit
import SwiftUI

/// Home's "Needs attention": overdue and due-today tasks, unread updates, recent payments and
/// unsigned agreements, most urgent first. One tap opens the thing (or the filtered list); a
/// single task can be marked complete right here. "You're all caught up" when there's nothing.
struct NeedsAttentionSection: View {
    let viewModel: HomeViewModel
    let router: AppRouter
    @State private var completing: String?
    @State private var completedCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shown once the agenda has loaded (or failed), so the section doesn't flash "caught up".
    private var isReady: Bool {
        switch viewModel.agenda {
        case .loaded, .failed: true
        default: false
        }
    }

    var body: some View {
        if isReady {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Needs attention")
                let items = viewModel.needsAttention
                if items.isEmpty {
                    caughtUp
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                    .cardStyle()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("needsAttention")
            .sensoryFeedback(.success, trigger: completedCount)
            .animation(reduceMotion ? nil : .snappy, value: items.map(\.id))
        }
    }

    private var items: [AttentionItem] { viewModel.needsAttention }

    private var caughtUp: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.success)
                .symbolEffect(.bounce, options: .nonRepeating, value: completedCount)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're all caught up")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Nothing overdue, unread or waiting on you.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("attention-caughtUp")
    }

    private func row(_ item: AttentionItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                open(item)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    IconBadge(systemName: icon(item.kind), tint: tint(item.kind))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.cardTitle)
                            .foregroundStyle(item.kind == .overdueTasks ? Color.warning : Color.textPrimary)
                            .contentTransition(.numericText())
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, Theme.Spacing.s)
                .frame(minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("attention-\(item.kind.rawValue)")

            if let task = item.task {
                Button {
                    Task { await complete(task) }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if completing == task.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text("Mark complete")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.brandPrimary)
                .disabled(completing != nil)
                .padding(.leading, 36 + Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
                .accessibilityIdentifier("attentionComplete-\(task.id)")
            }
        }
    }

    private func complete(_ task: AgendaItem) async {
        completing = task.id
        if await viewModel.completeTask(task) { completedCount += 1 }
        completing = nil
    }

    private func open(_ item: AttentionItem) {
        if let record = item.record {
            router.open(record, name: item.recordName)
            return
        }
        switch item.kind {
        case .unread:
            router.showingNotifications = true
        case .payments:
            router.showClaims()
            router.claims.paymentFilter = .received
        case .agreements:
            router.showLeads()
            router.leads.agreementFilter = .sent
        case .overdueTasks, .dueToday:
            // Several tasks: they're listed in Upcoming just below.
            break
        }
    }

    private func icon(_ kind: AttentionItem.Kind) -> String {
        switch kind {
        case .overdueTasks: "exclamationmark.circle"
        case .dueToday: "checklist"
        case .unread: "bell.badge"
        case .payments: "dollarsign.circle"
        case .agreements: "signature"
        }
    }

    private func tint(_ kind: AttentionItem.Kind) -> Color {
        switch kind {
        case .overdueTasks: .warning
        case .payments: .success
        default: .brandPrimary
        }
    }
}
