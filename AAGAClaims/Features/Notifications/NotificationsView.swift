import PortalKit
import SwiftUI

/// Bell sheet (spec §6.3).
struct NotificationsView: View {
    @Bindable var router: AppRouter

    @Environment(\.dismiss) private var dismiss
    @State private var showUnreadOnly = true

    private var viewModel: HomeViewModel { router.home }

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
                        Button {
                            router.present(item, fromNotifications: true)
                        } label: {
                            ActivityRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notification-\(item.commentId)")
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await viewModel.load() }
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
                    .accessibilityIdentifier("markAllRead")
                }
            }
            .sheet(item: $router.notificationUpdate) { item in
                UpdateSheet(item: item) { record, name in router.open(record, name: name) }
            }
        }
    }
}

#Preview {
    NotificationsView(router: PreviewData.router())
}
