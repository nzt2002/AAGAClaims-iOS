import PortalKit
import SwiftUI

/// Staff: the claim's tasks and events in Home's Recent activity style, three at a time.
/// Tapping one opens its record page.
struct ClaimActivitySection: View {
    let actions: ClaimActionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent activity")
            switch actions.activities {
            case .idle, .loading:
                SkeletonList(rows: 1)
            case .failed:
                HStack {
                    Text("Unable to load tasks and events.")
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Retry") { Task { await actions.loadActivities() } }
                        .frame(minHeight: Theme.minTapTarget)
                }
                .cardStyle()
            case .loaded(let items, _):
                if items.isEmpty {
                    Text("No tasks or events on this claim yet. Use Task or Event to add one.")
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                } else {
                    ScrollingStack(items: items, noun: "activities") { item in
                        NavigationLink {
                            ActivityDetailView(item: item)
                        } label: {
                            ActivityItemRow(item: item)
                                .cardStyle()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the \(item.kind == .event ? "event" : "task")")
                        .accessibilityIdentifier("claimActivity-\(item.id)")
                    }
                }
            }
        }
    }
}

extension AgendaItem {
    /// Phone for calls, envelope for emails, checklist for to-dos, calendar for events.
    var activityIcon: String {
        switch (kind, subtype) {
        case (.event, _): "calendar"
        case (_, "Call"): "phone.fill"
        case (_, "Email"): "envelope.fill"
        default: "checklist"
        }
    }

    /// "Call", "Email", "Task" or "Event".
    var activityKindName: String {
        kind == .event ? "Event" : (subtype == "Call" || subtype == "Email" ? subtype! : "Task")
    }

    /// Done, overdue, or open (status for tasks; upcoming for events).
    var activityState: (text: String, tone: StatusPill.Tone) {
        if isOverdue == true { return ("Overdue", .warning) }
        switch kind {
        case .task:
            if isClosed == true { return (PortalFormat.nonEmpty(status) ?? "Completed", .success) }
            return (PortalFormat.nonEmpty(status) ?? "Open", .active)
        case .event:
            return isClosed == true ? ("Past", .neutral) : ("Upcoming", .active)
        }
    }

    var activityWhen: String {
        if kind == .task, isClosed == true, let due = dueDate {
            return PortalFormat.date(due)
        }
        return AgendaRow.whenText(self)
    }
}

/// One task or event card.
struct ActivityItemRow: View {
    let item: AgendaItem

    var body: some View {
        let state = item.activityState
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            IconBadge(systemName: item.activityIcon, tint: item.isOverdue == true ? .warning : .brandPrimary, size: 36, filled: true)
            VStack(alignment: .leading, spacing: 3) {
                AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                    Text(item.subject ?? item.activityKindName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    AdaptiveSpacer()
                    StatusPill(text: state.text, tone: state.tone)
                }
                Text("\(item.activityKindName) · \(item.activityWhen)")
                    .font(.caption)
                    .foregroundStyle(item.isOverdue == true ? Color.warning : Color.textSecondary)
                if let owner = PortalFormat.nonEmpty(item.assignedToName) {
                    Label(owner, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                if let description = PortalFormat.nonEmpty(item.description) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A task or event's record page.
struct ActivityDetailView: View {
    let item: AgendaItem
    @Environment(\.salesforcePage) private var salesforcePage
    @State private var salesforceURL: URL?

    var body: some View {
        let state = item.activityState
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    IconBadge(systemName: item.activityIcon, tint: item.isOverdue == true ? .warning : .brandPrimary, size: 48, filled: true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(item.activityKindName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text(item.subject ?? item.activityKindName)
                            .font(.title2.bold())
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusPill(text: state.text, tone: state.tone)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("activityHeader")

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(item.kind == .event ? "Event details" : "Task details")
                    switch item.kind {
                    case .task:
                        FieldRow(label: "Due date", value: item.dueDate.map { PortalFormat.date($0) } ?? "No due date", systemImage: "calendar")
                        FieldRow(label: "Status", value: item.status, systemImage: "checkmark.circle")
                        FieldRow(label: "Priority", value: item.priority, systemImage: "flag")
                    case .event:
                        FieldRow(label: "When", value: AgendaRow.whenText(item), systemImage: "clock")
                        FieldRow(label: "Location", value: item.location, systemImage: "mappin.and.ellipse")
                    }
                    FieldRow(label: "Assigned to", value: item.assignedToName, systemImage: "person")
                    FieldRow(label: "Related to", value: item.relatedRecordName.map { "Claim · \($0)" }, systemImage: "doc.text")
                }
                .cardStyle()

                if let description = PortalFormat.nonEmpty(item.description) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeading(item.kind == .event ? "Description" : "Comments")
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .cardStyle()
                    .accessibilityIdentifier("activityDescription")
                }

                if let created = item.createdDate {
                    Text(["Created", item.createdByName.map { "by \($0)" }, created.formatted(date: .abbreviated, time: .shortened)]
                        .compactMap { $0 }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.appBackground)
        .navigationTitle(item.activityKindName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let salesforcePage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let object = item.kind == .event ? "Event" : "Task"
                        let path = SalesforcePageLink.path("/lightning/r/\(object)/\(item.id)/view", query: [])
                        Task { salesforceURL = await salesforcePage.url(for: path) }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in Salesforce")
                    .accessibilityIdentifier("activityOpenInSalesforce")
                }
            }
        }
        .sheet(item: Binding(get: { salesforceURL.map(SafariLink.init) }, set: { salesforceURL = $0?.url })) {
            SafariView(url: $0.url).ignoresSafeArea()
        }
    }
}
