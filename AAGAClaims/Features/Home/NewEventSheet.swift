import PortalKit
import SwiftUI

/// New Event (Home quick action): an event on a claim or lead, assigned to a team member.
struct NewEventSheet: View {
    @State private var viewModel: NewEventViewModel
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, currentUserName: String?, onCreated: @escaping () -> Void) {
        _viewModel = State(initialValue: NewEventViewModel(api: api, currentUserName: currentUserName))
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
                    ErrorStateView(subject: "the event form") { Task { await viewModel.loadOptions() } }
                case .loaded(let options, _):
                    form(options)
                }
            }
            .navigationTitle("New Event")
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
                        .accessibilityIdentifier("newEventSave")
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
            RelatedRecordSection(
                kind: $viewModel.relatedKind,
                claimId: $viewModel.claimId,
                leadId: $viewModel.leadId,
                options: options,
                idPrefix: "newEvent"
            ) {
                errorText(.record)
            }

            Section {
                TextField("Subject", text: $viewModel.subject)
                    .accessibilityIdentifier("newEventSubject")
                errorText(.subject)
                Toggle("All day", isOn: $viewModel.isAllDay.animation())
                if viewModel.isAllDay {
                    DatePicker("Date", selection: $viewModel.start, displayedComponents: .date)
                } else {
                    DatePicker("Starts", selection: $viewModel.start)
                        .onChange(of: viewModel.start) { old, _ in viewModel.startChanged(from: old) }
                    DatePicker("Ends", selection: $viewModel.end, in: viewModel.start...)
                    errorText(.end)
                }
                TextField("Location (optional)", text: $viewModel.location)
                    .textContentType(.fullStreetAddress)
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
                    Label("We couldn't save the event. Please try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func errorText(_ field: NewEventViewModel.Field) -> some View {
        if let message = viewModel.error(for: field) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Color.warning)
        }
    }
}
