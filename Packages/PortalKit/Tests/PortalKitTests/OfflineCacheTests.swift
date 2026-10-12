import Foundation
import Testing
@testable import PortalKit

/// Records when cached data is served.
private actor ServedLog {
    var dates: [Date] = []
    func add(_ date: Date) { dates.append(date) }
}

@Suite("Offline cache")
struct OfflineCacheTests {
    private let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(base: PortalAPI) -> (CachingPortalAPI, ServedLog) {
        let log = ServedLog()
        let api = CachingPortalAPI(
            base: base,
            cache: MemoryResponseCache(now: { [savedAt] in savedAt }),
            onServedFromCache: { await log.add($0) }
        )
        return (api, log)
    }

    @Test("Offline reads return the last saved response and report its age")
    func servesCache() async throws {
        let (api, log) = make(base: MockPortalAPI(fixtures: try .bundled()))
        let online = try await api.claim(id: "a23000000000001AAA")

        await api.setOnline(false)
        let offline = try await api.claim(id: "a23000000000001AAA")
        #expect(offline == online)
        #expect(await log.dates == [savedAt])
    }

    @Test("Every cached endpoint round-trips through JSON")
    func roundTrips() async throws {
        let (api, _) = make(base: MockPortalAPI(fixtures: try .bundled()))
        let claims = try await api.claims()
        let leads = try await api.leads()
        let activity = try await api.activity()
        let cases = try await api.cases()
        let detail = try await api.supportCase(id: "500000000000001AAA")
        let updates = try await api.updates(for: .claim("a23000000000001AAA"))
        let files = try await api.files(for: .claim("a23000000000001AAA"))
        let payments = try await api.claimPayments(id: "a23000000000001AAA")
        let lead = try await api.lead(id: "a0r000000000001AAA")

        await api.setOnline(false)
        #expect(try await api.claims() == claims)
        #expect(try await api.leads() == leads)
        #expect(try await api.activity() == activity)
        #expect(try await api.cases() == cases)
        #expect(try await api.supportCase(id: "500000000000001AAA") == detail)
        #expect(try await api.updates(for: .claim("a23000000000001AAA")) == updates)
        #expect(try await api.files(for: .claim("a23000000000001AAA")) == files)
        #expect(try await api.claimPayments(id: "a23000000000001AAA") == payments)
        #expect(try await api.lead(id: "a0r000000000001AAA") == lead)
    }

    @Test("Nothing cached offline is an offline error")
    func emptyCache() async throws {
        let (api, _) = make(base: MockPortalAPI(fixtures: try .bundled()))
        await api.setOnline(false)
        await #expect(throws: PortalAPIError.offline) {
            _ = try await api.claims()
        }
    }

    @Test("A network failure that means offline falls back to the cache")
    func fallsBackOnOfflineError() async throws {
        let base = MockPortalAPI(fixtures: try .bundled())
        let (api, log) = make(base: base)
        _ = try await api.claims()

        await base.setFailure(.offline)
        #expect(try await api.claims().count == 4)
        #expect(await log.dates.count == 1)
    }

    @Test("Other errors are not hidden by the cache")
    func doesNotMaskErrors() async throws {
        let base = MockPortalAPI(fixtures: try .bundled())
        let (api, _) = make(base: base)
        _ = try await api.claims()

        await base.setFailure(.server(status: 500))
        await #expect(throws: PortalAPIError.server(status: 500)) {
            _ = try await api.claims()
        }
        await #expect(throws: PortalAPIError.notFound) {
            await base.setFailure(nil)
            _ = try await api.claim(id: "a23nope0000000000A")
        }
    }

    @Test("Writes are refused offline")
    func writesRefused() async throws {
        let (api, _) = make(base: MockPortalAPI(fixtures: try .bundled()))
        await api.setOnline(false)
        await #expect(throws: PortalAPIError.offline) {
            try await api.addComment(to: .claim("a23000000000001AAA"), text: "Hi")
        }
        await #expect(throws: PortalAPIError.offline) {
            _ = try await api.requestAssistance(recordId: "a23000000000001AAA", comments: "Help")
        }
        await #expect(throws: PortalAPIError.offline) {
            try await api.replyToCase(id: "500000000000001AAA", body: "Hi")
        }
        await #expect(throws: PortalAPIError.offline) {
            try await api.markActivityRead(commentIds: ["x"])
        }
        var submission = LeadSubmission(leadName: "Jane")
        submission.phone = "555"
        let lead = submission
        await #expect(throws: PortalAPIError.offline) {
            _ = try await api.createLead(lead)
        }
    }

    @Test("File cache stores, loads and clears")
    func fileCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = FileResponseCache(directory: directory)
        await cache.store(Data("[1]".utf8), for: "claims/a23000000000001AAA")
        let loaded = await cache.load("claims/a23000000000001AAA")
        #expect(loaded?.data == Data("[1]".utf8))
        await cache.clear()
        #expect(await cache.load("claims/a23000000000001AAA") == nil)
    }
}
