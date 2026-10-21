import Foundation
import Testing
@testable import PortalKit

@Suite("Home: needs attention")
struct HomeAttentionTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func task(_ id: String, due: CalendarDate?, overdue: Bool = false, closed: Bool = false) -> AgendaItem {
        AgendaItem(id: id, kind: .task, subject: "Task \(id)", dueDate: due, startDateTime: nil, endDateTime: nil,
                   isAllDay: nil, location: nil, status: nil, isOverdue: overdue, assignedToName: nil,
                   relatedRecordId: "a23X", relatedRecordName: "Smith - Roof", relatedRecordType: .claim,
                   isClosed: closed)
    }

    private var today: CalendarDate {
        let p = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: p.year!, month: p.month!, day: p.day!)
    }

    @Test("Overdue first, then due today; closed tasks ignored; one task offers its record and Mark complete")
    func tasks() {
        let items = HomeViewModel.attention(
            agenda: [task("1", due: CalendarDate(year: 2020, month: 1, day: 1), overdue: true),
                     task("2", due: today), task("3", due: today, closed: true)],
            claims: [], leads: [], unread: 0, now: now)
        #expect(items.map(\.kind) == [.overdueTasks, .dueToday])
        #expect(items[0].count == 1)
        #expect(items[0].task?.id == "1")
        #expect(items[0].record == .claim("a23X"))
        #expect(items[1].title == "1 task due today")
    }

    @Test("Several tasks: a count, no single task")
    func severalTasks() {
        let items = HomeViewModel.attention(
            agenda: [task("1", due: today), task("2", due: today)], claims: [], leads: [], unread: 0, now: now)
        #expect(items.first?.title == "2 tasks due today")
        #expect(items.first?.task == nil)
        #expect(items.first?.detail == "Task 1 and 1 more")
    }

    @Test("Unread updates, and all caught up when there's nothing")
    func unreadAndEmpty() {
        #expect(HomeViewModel.attention(agenda: [], claims: [], leads: [], unread: 0, now: now).isEmpty)
        let items = HomeViewModel.attention(agenda: [], claims: [], leads: [], unread: 3, now: now)
        #expect(items.map(\.kind) == [.unread])
        #expect(items[0].title == "3 unread updates")
    }

    @Test("The mock agenda's overdue task shows up")
    @MainActor
    func mockData() async {
        let viewModel = HomeViewModel(api: MockPortalAPI(fixtures: try! .bundled()), isInternalUser: true)
        await viewModel.load()
        #expect(viewModel.needsAttention.contains { $0.kind == .overdueTasks })
    }
}
