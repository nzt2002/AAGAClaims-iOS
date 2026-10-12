import PortalKit
import SwiftUI

/// Request Assistance from the Support tab (spec §6.9): choose a claim or lead, then describe the request.
struct RequestAssistanceSheet: View {
    @State private var viewModel: RequestAssistanceViewModel
    let onCreated: (_ caseId: String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(api: PortalAPI, preselected: String? = nil, onCreated: @escaping (String) -> Void) {
        _viewModel = State(initialValue: RequestAssistanceViewModel(api: api, preselected: preselected))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    recordPicker
                    if let error = viewModel.error(for: .record) {
                        errorLabel(error)
                    }
                } header: {
                    Text("Claim or Lead")
                }

                Section {
                    TextField("Questions or comments", text: $viewModel.comments, axis: .vertical)
                        .lineLimit(6...12)
                        .accessibilityIdentifier("assistanceComments")
                    HStack {
                        if let error = viewModel.error(for: .comments) {
                            errorLabel(error)
                        }
                        Spacer()
                        Text("\(viewModel.comments.count.formatted()) / \(viewModel.limit.formatted())")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(viewModel.comments.count > viewModel.limit ? Color.warning : Color.textSecondary)
                    }
                } header: {
                    Text("How can we help?")
                } footer: {
                    Text("Your account manager will be notified and we'll follow up with you.")
                }

                if viewModel.submitError != nil {
                    Section {
                        errorLabel("We couldn't send your request. Please try again.")
                    }
                }
            }
            .navigationTitle("Ask Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task {
                                if await viewModel.submit(), let caseId = viewModel.createdCaseId {
                                    onCreated(caseId)
                                }
                            }
                        }
                        .accessibilityIdentifier("assistanceSubmit")
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

    @ViewBuilder
    private var recordPicker: some View {
        switch viewModel.options {
        case .loaded(let options, _):
            if options.isEmpty {
                Text("You don't have any claims or leads yet.")
                    .foregroundStyle(Color.textSecondary)
            } else {
                Picker("Claim or Lead", selection: $viewModel.selectedRecordId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(options) { option in
                        Text(label(for: option)).tag(String?.some(option.id))
                    }
                }
                // A menu closes on selection; a navigation-link picker needs an extra Back tap.
                .pickerStyle(.menu)
                .accessibilityIdentifier("assistanceRecord")
            }
        case .failed:
            HStack {
                Text("Your claims and leads couldn't be loaded.")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Retry") { Task { await viewModel.loadOptions() } }
            }
        case .idle, .loading:
            LabeledContent("Claim or Lead") { ProgressView() }
        }
    }

    private func label(for option: RequestAssistanceViewModel.Option) -> String {
        let kind = if case .claim = option.record { "Claim" } else { "Lead" }
        if let detail = PortalFormat.nonEmpty(option.detail) {
            return "\(kind): \(option.name) (\(detail))"
        }
        return "\(kind): \(option.name)"
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Color.warning)
    }
}

#Preview {
    RequestAssistanceSheet(api: PreviewData.api()) { _ in }
}
