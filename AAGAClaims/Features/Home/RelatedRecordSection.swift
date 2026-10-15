import PortalKit
import SwiftUI

/// "Related to" for New Task and New Event: a Claim or Lead switch, then that record, chosen from
/// a searchable list that shows each record's loss address so the right one is easy to confirm.
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
                lookup(title: "Claim", records: options.claims.map(RecordOption.init), selection: $claimId, id: "\(idPrefix)Claim")
            case .lead:
                if options.leads.isEmpty {
                    Text("You don't have any leads yet.")
                        .foregroundStyle(Color.textSecondary)
                } else {
                    lookup(title: "Lead", records: options.leads.map(RecordOption.init), selection: $leadId, id: "\(idPrefix)Lead")
                }
            }
            error()
        }
    }

    private func lookup(title: String, records: [RecordOption], selection: Binding<String?>, id: String) -> some View {
        let chosen = records.first { $0.id == selection.wrappedValue }
        return NavigationLink {
            RecordLookupList(title: title, records: records, selection: selection)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(chosen?.name ?? "Choose…")
                        .foregroundStyle(chosen == nil ? Color.textSecondary : Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                if let address = chosen?.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityIdentifier(id)
    }
}

/// A claim or lead as a lookup row: name and loss address.
struct RecordOption: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let detail: String?

    init(_ claim: ClaimSummary) {
        id = claim.recordId
        name = claim.recordName ?? claim.claimNumber ?? "Claim"
        address = PortalFormat.nonEmpty(claim.lossAddress)
        detail = [claim.claimNumber, claim.claimStatus].compactMap { PortalFormat.nonEmpty($0) }.joined(separator: " · ")
    }

    init(_ lead: LeadSummary) {
        id = lead.recordId
        name = lead.recordName ?? "Lead"
        address = PortalFormat.nonEmpty(lead.lossAddress)
        detail = PortalFormat.nonEmpty(lead.prospectStatus)
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q) || (address?.localizedCaseInsensitiveContains(q) ?? false)
    }
}

/// Search by name (or address); tap a row to choose it and go back.
struct RecordLookupList: View {
    let title: String
    let records: [RecordOption]
    @Binding var selection: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [RecordOption] { records.filter { $0.matches(query) } }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)
                    TextField("Search by name or address", text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("recordSearchField")
                }
            }
            Section {
                if filtered.isEmpty {
                    Text("No \(title.lowercased())s match \"\(query)\".")
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(filtered) { record in
                    Button {
                        selection = record.id
                        dismiss()
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Label(record.address ?? "No loss address", systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(record.address == nil ? Color.textSecondary : Color.textPrimary)
                                if let detail = PortalFormat.nonEmpty(record.detail) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if record.id == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                        .frame(minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(record.id == selection ? .isSelected : [])
                    .accessibilityIdentifier("recordOption-\(record.id)")
                }
            } header: {
                Text("\(filtered.count) \(title.lowercased())\(filtered.count == 1 ? "" : "s")")
            }
        }
        .navigationTitle("Choose \(title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension RecordRef {
    /// "Claim" or "Lead".
    var kindName: String {
        switch self {
        case .claim: "Claim"
        case .lead: "Lead"
        }
    }
}

extension NewTaskViewModel.Options {
    /// The record's name from the user's claims and leads.
    func name(of record: RecordRef) -> String {
        switch record {
        case .claim(let id): claims.first { $0.recordId == id }?.recordName ?? "This claim"
        case .lead(let id): leads.first { $0.recordId == id }?.recordName ?? "This lead"
        }
    }
}
