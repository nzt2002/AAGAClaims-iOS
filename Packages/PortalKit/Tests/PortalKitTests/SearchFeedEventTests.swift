import Foundation
import Testing
@testable import PortalKit

@MainActor
@Suite("Search, Chatter and New Event")
struct SearchFeedEventTests {
    private func mock() -> MockPortalAPI { MockPortalAPI(fixtures: try! .bundled()) }

    @Test("Search waits for 2 characters and groups results")
    func search() async {
        let search = SearchViewModel(api: mock(), debounce: .zero)
        search.query = "S"
        #expect(search.state == .idle)

        search.query = "Smith"
        await search.awaitSearch()
        #expect(search.sections.map(\.kind) == [.claim, .supportCase])
        #expect(search.sections.first?.results.count == 4)

        search.query = "Jordan"
        await search.awaitSearch()
        #expect(search.sections.map(\.kind) == [.prospect, .supportCase])

        search.query = "zzz"
        await search.awaitSearch()
        #expect(search.state == .results([]))
    }

    @Test("Search failures are reported")
    func searchFailure() async {
        let search = SearchViewModel(api: MockPortalAPI(fixtures: .empty, failure: .server(status: 500)), debounce: .zero)
        search.query = "Smith"
        await search.awaitSearch()
        #expect(search.state == .failed)
    }

    @Test("Search sends q")
    func searchHTTP() async throws {
        actor Recorder: PortalTransport {
            var request: TransportRequest?
            func send(_ request: TransportRequest) async throws -> TransportResponse {
                self.request = request
                return TransportResponse(statusCode: 200, body: Data(#"[{"type":"Case","id":"500A","title":"Hi","subtitle":null}]"#.utf8))
            }
        }
        let recorder = Recorder()
        let results = try await HTTPPortalAPI(transport: recorder).search("roof")
        #expect(results.first?.type == .supportCase)
        #expect(await recorder.request?.path == "/search")
        #expect(await recorder.request?.queryItems == [URLQueryItem(name: "q", value: "roof")])
    }

    @Test("Recent activity merges updates and Chatter posts, newest first")
    func merged() async {
        let home = HomeViewModel(api: mock())
        await home.load()
        let entries = home.recentEntries
        #expect(entries.count == 6)
        let dates = entries.compactMap(\.date)
        #expect(dates == dates.sorted(by: >))
        #expect(entries.contains { if case .post = $0 { true } else { false } })
    }

    @Test("A failed Chatter feed leaves posts out")
    func feedFailure() async throws {
        var fixtures = try MockPortalAPI.Fixtures.bundled()
        fixtures.feed = []
        let home = HomeViewModel(api: MockPortalAPI(fixtures: fixtures))
        await home.load()
        #expect(home.recentEntries.allSatisfy { if case .update = $0 { true } else { false } })
    }

    @Test("New Event: defaults, validation and creation")
    func newEvent() async throws {
        let api = mock()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 20))!
        let form = NewEventViewModel(api: api, currentUserName: "Jane Doe", now: now)
        #expect(Calendar.current.component(.hour, from: form.start) == 10)
        #expect(form.end.timeIntervalSince(form.start) == 3_600)
        await form.loadOptions()
        #expect(form.assigneeId == "005000000000002AAA")

        form.claimId = "a23000000000001AAA"
        form.subject = "Re-inspection"
        form.end = form.start.addingTimeInterval(-60)
        #expect(!(await form.submit()))
        #expect(form.error(for: .end) == "The end must be after the start.")

        let oldStart = form.start
        form.start = form.start.addingTimeInterval(3_600)
        form.end = oldStart.addingTimeInterval(1_800)
        form.startChanged(from: oldStart)
        #expect(form.end > form.start)
        form.location = " 123 Main St "
        #expect(await form.submit())
        let agenda = try await api.agenda()
        #expect(agenda.items.contains { $0.subject == "Re-inspection" && $0.location == "123 Main St" })
    }

    @Test("All-day events send a date, not times")
    func allDay() async throws {
        let form = NewEventViewModel(api: mock(), currentUserName: nil)
        form.subject = "Site visit"
        form.isAllDay = true
        form.assigneeId = "005000000000001AAA"
        let event = try #require(form.newEvent)
        #expect(event.date != nil)
        #expect(event.startDateTime == nil && event.endDateTime == nil)
        let json = try #require(try JSONSerialization.jsonObject(with: PortalJSON.makeEncoder().encode(event)) as? [String: Any])
        #expect(json["isAllDay"] as? Bool == true)
        #expect((json["date"] as? String)?.count == 10)
    }
}
