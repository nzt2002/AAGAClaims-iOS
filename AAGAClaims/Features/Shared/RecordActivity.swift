import PortalKit
import SwiftUI

/// Staff: a claim's or lead's tasks, events and emails in Home's Recent activity style, three at
/// a time. Tapping one opens its page.
struct RecordActivitySection: View {
    let model: RecordActivityViewModel
    let api: PortalAPI
    /// "claim" or "lead", for the empty message and accessibility identifiers.
    let noun: String
    @Environment(\.serverMeta) private var serverMeta

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent activity")
            switch model.activities {
            case .idle, .loading:
                SkeletonList(rows: 1)
            case .failed:
                HStack {
                    Text("Unable to load recent activity.")
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Retry") { Task { await model.load() } }
                        .frame(minHeight: Theme.minTapTarget)
                }
                .cardStyle()
            case .loaded(let items, _):
                if items.isEmpty {
                    Text("No tasks or events on this \(noun) yet. Use Task or Event to add one.")
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                } else {
                    ScrollingStack(items: items, noun: "activities") { item in
                        NavigationLink {
                            ActivityDetailView(model: detailModel(for: item))
                        } label: {
                            ActivityItemRow(item: item)
                                .cardStyle()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the \(item.activityKindName.lowercased())")
                        .accessibilityIdentifier("\(noun)Activity-\(item.id)")
                    }
                }
            }
        }
    }

    private func detailModel(for item: AgendaItem) -> ActivityDetailViewModel {
        let detail = ActivityDetailViewModel(api: api, item: item, canChange: serverMeta.supports(.activityEdit))
        detail.onChange = { [model] in model.replace($0) }
        return detail
    }
}

extension AgendaItem {
    /// Phone for calls, envelope for emails, checklist for to-dos, calendar for events.
    var activityIcon: String {
        switch (kind, subtype) {
        case (.event, _): "calendar"
        case (.email, _): isIncoming == true ? "envelope.open.fill" : "paperplane.fill"
        case (_, "Call"): "phone.fill"
        case (_, "Email"): "envelope.fill"
        default: "checklist"
        }
    }

    /// "Call", "Email", "Task" or "Event".
    var activityKindName: String {
        switch kind {
        case .event: "Event"
        case .email: "Email"
        case .task: subtype == "Call" || subtype == "Email" ? subtype! : "Task"
        }
    }

    /// Done, overdue, or open (status for tasks; upcoming for events; received or sent for emails).
    var activityState: (text: String, tone: StatusPill.Tone) {
        if isOverdue == true { return ("Overdue", .warning) }
        switch kind {
        case .task:
            if isClosed == true { return (PortalFormat.nonEmpty(status) ?? "Completed", .success) }
            return (PortalFormat.nonEmpty(status) ?? "Open", .active)
        case .event:
            return isClosed == true ? ("Past", .neutral) : ("Upcoming", .active)
        case .email:
            return isIncoming == true ? ("Received", .active) : ("Sent", .neutral)
        }
    }

    /// The comments' (or email's) first 90 characters, for the card.
    var descriptionPreview: String? {
        guard let text = PortalFormat.nonEmpty(description)?
            .replacingOccurrences(of: "\n", with: " ") else { return nil }
        guard text.count > 90 else { return text }
        let cut = text.prefix(90)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    var activityWhen: String {
        switch kind {
        case .email:
            return startDateTime.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        case .task where isClosed == true:
            if let due = dueDate { return PortalFormat.date(due) }
            return AgendaRow.whenText(self)
        default:
            return AgendaRow.whenText(self)
        }
    }

    /// "From Pat Carrier" or "To claims@example.com", for email cards.
    var emailParty: String? {
        guard kind == .email else { return nil }
        if isIncoming == true {
            return PortalFormat.nonEmpty(fromName).map { "From \($0)" } ?? PortalFormat.nonEmpty(fromAddress).map { "From \($0)" }
        }
        return PortalFormat.nonEmpty(toAddress).map { "To \($0)" }
    }
}

/// One task, event or email card.
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
                if let party = item.emailParty {
                    Label(party, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else if let owner = PortalFormat.nonEmpty(item.assignedToName) {
                    Label(owner, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                if let preview = item.descriptionPreview {
                    // Shortened in code rather than with lineLimit, so large text sizes wrap instead of clipping.
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Task, event and email page

/// A task's, event's or email's page. Tasks: Mark Complete, Edit and Reassign; events: Edit and
/// Reassign; emails are read-only. A Safari icon opens the record in Salesforce.
struct ActivityDetailView: View {
    @State var model: ActivityDetailViewModel
    @Environment(\.salesforcePage) private var salesforcePage
    @Environment(\.isOffline) private var isOffline
    @State private var salesforceURL: URL?
    @State private var editing = false

    private var item: AgendaItem { model.item }

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

                if model.canEdit {
                    actions
                }
                ErrorRow(message: model.errorMessage)

                if item.kind == .email {
                    emailDetails
                } else {
                    details
                }

                if let description = PortalFormat.nonEmpty(item.description) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeading(item.kind == .task ? "Comments" : item.kind == .email ? "Message" : "Description")
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .cardStyle()
                    .accessibilityIdentifier("activityDescription")
                }

                if let created = item.createdDate, item.kind != .email {
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
            if model.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                        .disabledWhenOffline(isOffline)
                        .accessibilityLabel("Edit \(item.activityKindName)")
                        .accessibilityIdentifier("activityEdit")
                }
            }
            if let salesforcePage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let object = switch item.kind {
                        case .event: "Event"
                        case .email: "EmailMessage"
                        case .task: "Task"
                        }
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
        .sheet(isPresented: $editing) {
            EditActivityForm(model: model)
        }
        .sheet(item: Binding(get: { salesforceURL.map(SafariLink.init) }, set: { salesforceURL = $0?.url })) {
            SafariView(url: $0.url).ignoresSafeArea()
        }
        .task { await model.loadOptions() }
    }

    /// Mark Complete (open tasks) and Reassign.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { actionButtons }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.canComplete {
            Button {
                Task { await model.complete() }
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Theme.minTapTarget)
                    .padding(.horizontal, Theme.Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.brandPrimary)
            .disabled(model.isSaving)
            .disabledWhenOffline(isOffline)
            .accessibilityIdentifier("activityComplete")
        }
        Menu {
            ForEach(model.assignees) { person in
                Button {
                    Task { await model.reassign(to: person.userId) }
                } label: {
                    if person.userId == item.assignedToId {
                        Label(person.name, systemImage: "checkmark")
                    } else {
                        Text(person.name)
                    }
                }
            }
        } label: {
            Label("Reassign", systemImage: "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: Theme.minTapTarget)
                .padding(.horizontal, Theme.Spacing.s)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.brandPrimary)
        .disabled(model.isSaving || model.assignees.isEmpty)
        .disabledWhenOffline(isOffline)
        .accessibilityIdentifier("activityReassign")
        if model.isSaving {
            ProgressView()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(item.kind == .event ? "Event details" : "Task details")
            switch item.kind {
            case .task:
                FieldRow(label: "Due date", value: item.dueDate.map { PortalFormat.date($0) } ?? "No due date", systemImage: "calendar")
                FieldRow(label: "Status", value: item.status, systemImage: "checkmark.circle")
                FieldRow(label: "Priority", value: item.priority, systemImage: "flag")
            case .event, .email:
                FieldRow(label: "When", value: AgendaRow.whenText(item), systemImage: "clock")
                FieldRow(label: "Location", value: item.location, systemImage: "mappin.and.ellipse")
            }
            FieldRow(label: "Assigned to", value: item.assignedToName, systemImage: "person")
            FieldRow(label: "Related to", value: relatedTo, systemImage: "doc.text")
        }
        .cardStyle()
    }

    private var emailDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Email details")
            FieldRow(label: "From", value: [item.fromName, item.fromAddress.map { "<\($0)>" }].compactMap { $0 }.joined(separator: " "),
                     systemImage: "person")
            FieldRow(label: "To", value: item.toAddress, systemImage: "person.2")
            FieldRow(label: "Cc", value: item.ccAddress, systemImage: "person.2")
            FieldRow(label: item.isIncoming == true ? "Received" : "Sent",
                     value: item.startDateTime?.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            FieldRow(label: "Attachments", value: item.hasAttachment == true ? "Yes. Open the email in Salesforce to see them." : nil,
                     systemImage: "paperclip")
            FieldRow(label: "Related to", value: relatedTo, systemImage: "doc.text")
        }
        .cardStyle()
    }

    private var relatedTo: String? {
        guard let name = item.relatedRecordName else { return nil }
        return "\(item.relatedRecordType?.displayName ?? "Record") · \(name)"
    }
}

/// Edit a task (subject, status, priority, due date, assignee, comments) or an event (subject,
/// start and end, location, assignee, description). Only what changed is sent.
struct EditActivityForm: View {
    let model: ActivityDetailViewModel
    @State private var subject: String
    @State private var status: String
    @State private var priority: String
    @State private var dueDate: CalendarDate?
    @State private var description: String
    @State private var assigneeId: String
    @State private var location: String
    @State private var start: Date
    @State private var end: Date
    @Environment(\.dismiss) private var dismiss

    init(model: ActivityDetailViewModel) {
        self.model = model
        let item = model.item
        _subject = State(initialValue: item.subject ?? "")
        _status = State(initialValue: item.status ?? "")
        _priority = State(initialValue: item.priority ?? "")
        _dueDate = State(initialValue: item.dueDate)
        _description = State(initialValue: item.description ?? "")
        _assigneeId = State(initialValue: item.assignedToId ?? "")
        _location = State(initialValue: item.location ?? "")
        _start = State(initialValue: item.startDateTime ?? Date())
        _end = State(initialValue: item.endDateTime ?? Date().addingTimeInterval(3600))
    }

    private var item: AgendaItem { model.item }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subject", text: $subject, axis: .vertical)
                        .accessibilityIdentifier("editActivitySubject")
                    if item.kind == .task {
                        Picker("Status", selection: $status) {
                            ForEach(model.options?.taskStatuses ?? [status], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("editActivityStatus")
                        Picker("Priority", selection: $priority) {
                            ForEach(model.options?.taskPriorities ?? [priority], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        OptionalDateRow(title: "Due date", value: $dueDate)
                    } else if item.isAllDay != true {
                        DatePicker("Starts", selection: $start)
                        DatePicker("Ends", selection: $end, in: start...)
                    }
                    if item.kind == .event {
                        TextField("Location", text: $location)
                    }
                }
                Section {
                    Picker("Assigned to", selection: $assigneeId) {
                        if !model.assignees.contains(where: { $0.userId == assigneeId }) {
                            Text(item.assignedToName ?? "Not set").tag(assigneeId)
                        }
                        ForEach(model.assignees) { Text($0.name).tag($0.userId) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("editActivityAssignee")
                }
                Section(item.kind == .task ? "Comments" : "Description") {
                    TextField(item.kind == .task ? "Comments" : "Description", text: $description, axis: .vertical)
                        .lineLimit(3...10)
                }
                ErrorRow(message: model.errorMessage)
            }
            .navigationTitle("Edit \(item.activityKindName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FormToolbar(isSaving: model.isSaving, canSave: !subject.trimmingCharacters(in: .whitespaces).isEmpty) {
                    if await model.save(changes) { dismiss() }
                }
            }
        }
        .onAppear { model.clearError() }
    }

    /// Only the fields that changed.
    private var changes: ActivityEdit {
        var edit = ActivityEdit()
        if subject != (item.subject ?? "") { edit.subject = subject }
        if description != (item.description ?? "") { edit.description = description }
        if !assigneeId.isEmpty, assigneeId != (item.assignedToId ?? "") { edit.assignedToId = assigneeId }
        switch item.kind {
        case .task:
            if status != (item.status ?? "") { edit.status = status }
            if priority != (item.priority ?? "") { edit.priority = priority }
            if dueDate != item.dueDate {
                edit.changesDueDate = true
                edit.dueDate = dueDate
            }
        case .event:
            if location != (item.location ?? "") { edit.location = location }
            if item.isAllDay != true {
                if start != item.startDateTime { edit.startDateTime = start }
                if end != item.endDateTime { edit.endDateTime = end }
            }
        case .email:
            break
        }
        return edit
    }
}
