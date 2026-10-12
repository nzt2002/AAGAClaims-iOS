import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Home redesign")
struct HomeRedesignTests {
    private func mock() -> MockPortalAPI { MockPortalAPI(fixtures: try! .bundled()) }

    @Test("Home loads the agenda and recent claims")
    func agendaAndRecentClaims() async {
        let home = HomeViewModel(api: mock())
        await home.load()
        #expect(home.upcoming.count == 4)
        #expect(home.upcoming.first?.isOverdue == true)
        #expect(home.canCreateTasks)
        #expect(home.recentClaims.compactMap(\.recordName) == ["Smith - Kitchen Water", "Smith - Roof", "Smith - Fence"])
    }

    @Test("A failing agenda doesn't break Home")
    func agendaFailureIsolated() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        let home = HomeViewModel(api: api)
        await home.load()
        #expect(home.state.value != nil)
        await api.setFailure(.server(status: 500))
        await home.loadAgenda()
        #expect(home.agenda.error == .server(status: 500))
        #expect(home.state.value != nil, "Claims, leads and activity are unaffected")
    }

    @Test("Agenda JSON decodes tasks and events")
    func decoding() throws {
        let agenda: Agenda = try MockPortalAPI.Fixtures.load("agenda")
        let event = try #require(agenda.items.first { $0.kind == .event })
        #expect(event.startDateTime != nil && event.location != nil)
        #expect(event.recordRef == .claim("a23000000000001AAA"))
        let allDay = try #require(agenda.items.last)
        #expect(allDay.isAllDay == true && allDay.recordRef == nil)
    }

    @Test("New Task validates, defaults the assignee to me, and creates the task")
    func newTask() async throws {
        let api = mock()
        let form = NewTaskViewModel(api: api, currentUserName: "Alex Smith")
        await form.loadOptions()
        #expect(form.assigneeId == "005000000000001AAA")
        #expect(form.options.value?.claims.count == 4)

        #expect(!(await form.submit()))
        #expect(form.error(for: .claim) != nil)
        #expect(form.error(for: .subject) == "Enter a subject.")

        form.claimId = "a23000000000001AAA"
        form.subject = "  Call the carrier  "
        form.hasDueDate = true
        form.dueDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        #expect(form.newTask?.dueDate == CalendarDate(year: 2026, month: 10, day: 20))
        #expect(form.newTask?.subject == "Call the carrier")
        #expect(await form.submit())

        let agenda = try await api.agenda()
        #expect(agenda.items.contains { $0.subject == "Call the carrier" && $0.relatedRecordName == "Smith - Roof" })
    }

    @Test("Users who can't create tasks get no assignee list")
    func noPermission() async throws {
        var fixtures = try MockPortalAPI.Fixtures.bundled()
        fixtures.agenda = Agenda(items: [], canCreateTasks: false)
        let api = MockPortalAPI(fixtures: fixtures)
        await #expect(throws: PortalAPIError.notFound) { _ = try await api.taskAssignees() }
    }

    @Test("Create task posts JSON to the claim")
    func httpPath() async throws {
        actor Recorder: PortalTransport {
            var request: TransportRequest?
            func send(_ request: TransportRequest) async throws -> TransportResponse {
                self.request = request
                return TransportResponse(statusCode: 201, body: Data(#"{"recordId":"00T1"}"#.utf8))
            }
        }
        let recorder = Recorder()
        let id = try await HTTPPortalAPI(transport: recorder).createTask(
            NewTask(subject: "X", dueDate: CalendarDate(year: 2026, month: 10, day: 20), assignedToId: "005A", description: nil),
            onClaim: "a23000000000001AAA"
        )
        #expect(id == "00T1")
        let request = try #require(await recorder.request)
        #expect(request.path == "/claims/a23000000000001AAA/tasks")
        let body = try #require(request.jsonBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["dueDate"] as? String == "2026-10-20")
        #expect(json["assignedToId"] as? String == "005A")
    }
}
