import PortalKit
import SwiftUI

/// New Task (Home quick action): a task on a claim or lead, assigned to a team member.
struct NewTaskSheet: View {
    @State private var viewModel: NewTaskViewModel
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// `record`: opened from a claim or lead page, so the new item belongs to it.
    init(api: PortalAPI, currentUserName: String?, record: RecordRef? = nil, onCreated: @escaping () -> Void) {
        _viewModel = State(initialValue: NewTaskViewModel(api: api, currentUserName: currentUserName, record: record))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.options {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    ErrorStateView(subject: "the task form") { Task { await viewModel.loadOptions() } }
                case .loaded(let options, _):
                    form(options)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.submit() {
                                    onCreated()
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.options.value == nil)
                        .accessibilityIdentifier("newTaskSave")
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isSubmitting)
        }
        .task {
            if viewModel.options.value == nil {
                await viewModel.loadOptions()
            }
        }
    }

    private func form(_ options: NewTaskViewModel.Options) -> some View {
        Form {
            if let locked = viewModel.lockedRecord {
                Section("Related to") {
                    LabeledContent(locked.kindName, value: options.name(of: locked))
                        .accessibilityIdentifier("newTaskLockedRecord")
                }
            } else {
            RelatedRecordSection(
                kind: $viewModel.relatedKind,
                claimId: $viewModel.claimId,
                leadId: $viewModel.leadId,
                options: options,
                idPrefix: "newTask"
            ) {
                errorText(.record)
            }
            }

            Section {
                SubjectField(text: $viewModel.subject, suggestions: viewModel.subjectSuggestions, identifier: "newTaskSubject")
                errorText(.subject)
                Toggle("Due date", isOn: $viewModel.hasDueDate.animation())
                if viewModel.hasDueDate {
                    DatePicker("Due", selection: $viewModel.dueDate, displayedComponents: .date)
                }
            }

            Section {
                Picker("Assign to", selection: $viewModel.assigneeId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(options.assignees) { person in
                        Text(person.name).tag(String?.some(person.userId))
                    }
                }
                .pickerStyle(.menu)
                errorText(.assignee)
            }

            Section("Details") {
                TextField("Optional", text: $viewModel.details, axis: .vertical)
                    .lineLimit(3...8)
            }

            if viewModel.submitError != nil {
                Section {
                    Label("We couldn't save the task. Please try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func errorText(_ field: NewTaskViewModel.Field) -> some View {
        if let message = viewModel.error(for: field) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.warning)
        }
    }
}

#Preview {
    NewTaskSheet(api: PreviewData.api(), currentUserName: "Alex Smith") {}
}
