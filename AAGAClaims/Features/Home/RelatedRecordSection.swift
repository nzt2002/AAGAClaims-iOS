import PortalKit
import SwiftUI

/// "Related to" for New Task and New Event: a Claim or Lead switch, then that record.
struct RelatedRecordSection<ErrorView: View>: View {
    @Binding var kind: NewTaskViewModel.RelatedKind
    @Binding var claimId: String?
    @Binding var leadId: String?
    let options: NewTaskViewModel.Options
    /// Prefix for accessibility identifiers ("newTask", "newEvent").
    let idPrefix: String
    @ViewBuilder let error: () -> ErrorView

    var body: some View {
        Section("Related to") {
            Picker("Related to", selection: $kind.animation()) {
                ForEach(NewTaskViewModel.RelatedKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("\(idPrefix)RelatedKind")

            switch kind {
            case .claim:
                Picker("Claim", selection: $claimId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(options.claims) { claim in
                        Text(claim.recordName ?? claim.claimNumber ?? "Claim").tag(String?.some(claim.recordId))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("\(idPrefix)Claim")
            case .lead:
                if options.leads.isEmpty {
                    Text("You don't have any leads yet.")
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Picker("Lead", selection: $leadId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(options.leads) { lead in
                            Text(lead.recordName ?? "Lead").tag(String?.some(lead.recordId))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("\(idPrefix)Lead")
                }
            }
            error()
        }
    }
}
