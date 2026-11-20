import PortalKit
import SwiftUI

/// Staff: a claim's or lead's Activities tab. Task and Event buttons at the top add one; below, a Recent Activity card
/// lists the open tasks and the events (and emails), the newest date first, six at a time with the rest scrolling in the
/// card. Its ⋯ menu shows or hides the completed tasks. Tapping one opens its page.
struct RecordActivitySection: View {
    let model: RecordActivityViewModel
    let api: PortalAPI
    /// "claim" or "lead", for the empty message and accessibility identifiers.
    let noun: String
    var onTask: (() -> Void)? = nil
    var onEvent: (() -> Void)? = nil
    @State private var showCompleted = false
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 66
    @Environment(\.serverMeta) private var serverMeta
    @Environment(\.isLeadRecord) private var isLead
    @Environment(\.isOffline) private var isOffline

    private static let visibleRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if onTask != nil || onEvent != nil {
                HStack(spacing: Theme.Spacing.s) {
                    addButton("Task", icon: "checklist", id: "\(noun)NewTask", action: onTask)
                    addButton("Event", icon: "calendar.badge.plus", id: "\(noun)NewEvent", action: onEvent)
                }
            }
            switch model.activities {
            case .idle, .loading:
                SkeletonList(rows: 1)
            case .failed:
                HStack {
                    Text("Unable to load activities.")
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Retry") { Task { await model.load() } }
                        .frame(minHeight: Theme.minTapTarget)
                }
                .cardStyle()
            case .loaded(let items, _):
                recentActivity(sorted(items))
            }
        }
    }

    private func addButton(_ title: String, icon: String, id: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget + 4)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(ActionCirclePressStyle())
        .tint(Color.recordAccent(isLead: isLead))
        .disabled(action == nil || isOffline)
        .accessibilityIdentifier(id)
    }

    /// Open tasks, and every event and email; completed tasks too when asked. Newest date first, undated last.
    private func sorted(_ items: [AgendaItem]) -> [AgendaItem] {
        items
            .filter { showCompleted || !($0.kind == .task && $0.isClosed == true) }
            .sorted { a, b in
                switch (a.sortDate, b.sortDate) {
                case let (x?, y?): x > y
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): false
                }
            }
    }

    private func recentActivity(_ items: [AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Button {
                        showCompleted.toggle()
                    } label: {
                        Label(showCompleted ? "Hide completed tasks" : "Show completed tasks", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("\(noun)ToggleCompleted")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Activity options")
                .accessibilityIdentifier("\(noun)ActivityMenu")
            }
            .padding(.leading, Theme.Spacing.l)
            .padding(.trailing, Theme.Spacing.xs)
            if items.isEmpty {
                Text("Nothing open on this \(noun). Add a task or an event above and it shows here.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.l)
            } else {
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            NavigationLink {
                                ActivityDetailView(model: detailModel(for: item))
                            } label: {
                                row(item).frame(height: rowHeight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the \(item.activityKindName.lowercased())")
                            .accessibilityIdentifier("\(noun)Activity-\(item.id)")
                            if item.id != items.last?.id { Divider().padding(.leading, Theme.Spacing.l + 40 + Theme.Spacing.m) }
                        }
                    }
                }
                .frame(height: rowHeight * CGFloat(min(items.count, Self.visibleRows)))
                .scrollIndicators(items.count > Self.visibleRows ? .visible : .hidden)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("scrollingStack")
                if items.count > Self.visibleRows {
                    Divider()
                    Label("Showing \(Self.visibleRows) of \(items.count) · scroll for more", systemImage: "arrow.up.and.down")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.s)
                }
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Color.border.opacity(0.7), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentActivityCard")
    }

    private func row(_ item: AgendaItem) -> some View {
        let done = item.isClosed == true && item.kind == .task
        return HStack(spacing: Theme.Spacing.m) {
            Image(systemName: done ? "checkmark" : item.activityIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(done ? Color.textSecondary : Color.recordAccent(isLead: isLead))
                .frame(width: 40, height: 40)
                .background((done ? Color.textSecondary : Color.recordAccent(isLead: isLead)).opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PortalFormat.nonEmpty(item.subject) ?? item.activityKindName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(done ? Color.textSecondary : Color.textPrimary)
                    .strikethrough(done)
                    .lineLimit(1)
                Text(detailLine(item))
                    .font(.caption)
                    .foregroundStyle(item.isOverdue == true ? Color.warning : Color.textSecondary)
                    .fontWeight(item.isOverdue == true ? .semibold : .regular)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .contentShape(Rectangle())
    }

    private func detailLine(_ item: AgendaItem) -> String {
        let state = item.kind == .email || (item.kind == .task && item.isClosed == true) ? item.activityState.text : nil
        return [item.activityKindName, state, item.activityWhen, item.assignedToName].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · ")
    }

    private func detailModel(for item: AgendaItem) -> ActivityDetailViewModel {
        let detail = ActivityDetailViewModel(api: api, item: item, canChange: serverMeta.supports(.activityEdit))
        detail.onChange = { [model] in model.replace($0) }
        return detail
    }
}

private extension AgendaItem {
    /// When it is: a task's due date (noon), an event's or email's start.
    var sortDate: Date? {
        if let startDateTime { return startDateTime }
        guard let dueDate else { return nil }
        return Calendar.current.date(from: DateComponents(year: dueDate.year, month: dueDate.month, day: dueDate.day, hour: 12))
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
    @Environment(\.isLeadRecord) private var isLead
    let item: AgendaItem

    var body: some View {
        let state = item.activityState
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            IconBadge(systemName: item.activityIcon, tint: item.isOverdue == true ? .warning : .recordAccent(isLead: isLead), size: 36, filled: true)
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
    @Environment(\.isLeadRecord) private var isLead
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
                // Icon above the title at large text, so long subjects aren't squeezed.
                AdaptiveStack(horizontalAlignment: .top, spacing: Theme.Spacing.m) {
                    IconBadge(systemName: item.activityIcon, tint: item.isOverdue == true ? .warning : .recordAccent(isLead: isLead), size: 48, filled: true)
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
                    .accessibilityLabel("Open on the web")
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
            .tint(Color.recordAccent(isLead: isLead))
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
        .tint(Color.recordAccent(isLead: isLead))
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
                if model.canEdit, let priorities = model.options?.taskPriorities, !priorities.isEmpty {
                    priorityMenu(priorities)
                } else {
                    FieldRow(label: "Priority", value: item.priority, systemImage: "flag")
                }
            case .event, .email:
                FieldRow(label: "When", value: AgendaRow.whenText(item), systemImage: "clock")
                FieldRow(label: "Location", value: item.location, systemImage: "mappin.and.ellipse")
            }
            FieldRow(label: "Assigned to", value: item.assignedToName, systemImage: "person")
            FieldRow(label: "Related to", value: relatedTo, systemImage: "doc.text")
        }
        .cardStyle()
    }

    /// The Priority row as a menu: picking a value saves it straight away.
    private func priorityMenu(_ priorities: [String]) -> some View {
        Menu {
            ForEach(priorities, id: \.self) { priority in
                Button {
                    var edit = ActivityEdit()
                    edit.priority = priority
                    Task { await model.save(edit) }
                } label: {
                    if priority == item.priority {
                        Label(priority, systemImage: "checkmark")
                    } else {
                        Text(priority)
                    }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "flag")
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Priority")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.nonEmpty(item.priority) ?? "Not set")
                        .font(.subheadline)
                        .foregroundStyle(Color.recordAccent(isLead: isLead))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .disabled(model.isSaving)
        .disabledWhenOffline(isOffline)
        .accessibilityLabel("Priority, \(PortalFormat.nonEmpty(item.priority) ?? "not set")")
        .accessibilityHint("Changes the task's priority")
        .accessibilityIdentifier("activityPriority")
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
            FieldRow(label: "Attachments", value: item.hasAttachment == true ? "Yes. Open the email on the web to see them." : nil,
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
