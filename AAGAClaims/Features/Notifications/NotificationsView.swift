import PortalKit
import SwiftUI

/// Bell sheet (spec §6.3). Opening an item's Update sheet comes in milestone 5.
struct NotificationsView: View {
    let viewModel: HomeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showUnreadOnly = true

    private var items: [ActivityItem] {
        viewModel.sortedActivity.filter { !showUnreadOnly || !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $showUnreadOnly) {
                    Text("Unread").tag(true)
                    Text("All").tag(false)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                if items.isEmpty {
                    ContentUnavailableView(
                        showUnreadOnly ? "No unread notifications" : "No notifications",
                        systemImage: "bell.slash"
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(items) { item in
                        ActivityRow(item: item)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task { await viewModel.markAllRead() }
                    }
                    .disabled(viewModel.unreadCount == 0)
                }
            }
        }
    }
}

#Preview {
    NotificationsView(viewModel: PreviewData.loadedHome())
}
