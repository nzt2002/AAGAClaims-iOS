import PortalKit
import SwiftUI

/// One published update: title, date, rendered HTML and "Open {Claim|Lead}" (spec §6.2).
struct UpdateSheet: View {
    let item: ActivityItem
    let open: (RecordRef, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(item.title ?? "Update")
                            .font(.title2.bold())
                            .foregroundStyle(Color.textPrimary)
                        Text(PortalFormat.date(item.createdDate))
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Label(
                            "\(item.relatedRecordType.displayName): \(item.relatedRecordName ?? "")",
                            systemImage: item.relatedRecordType == .claim ? "doc.text" : "person.2"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)

                    RichText(html: item.text)
                }
                .padding(Theme.Spacing.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    open(item.recordRef, item.relatedRecordName)
                } label: {
                    Text("Open \(item.relatedRecordType.displayName)")
                        .foregroundStyle(Color.surface)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(.bar)
                .accessibilityIdentifier("openUpdateRecord")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
