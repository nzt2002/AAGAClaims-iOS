import XCTest
@testable import PortalKit

private struct StubTransport: PortalTransport {
    func send(_ r: TransportRequest) async throws -> TransportResponse {
        let body = ##"[{"id":"a","name":"Roof","number":"JOB-0001","workflow":"retail","stage":"Lead","stageNumber":1,"stageTotal":6,"trade":"Roofing","address":null,"customerName":null,"startDate":null,"completedDate":null,"updatedDate":"2026-11-21T01:10:04.045Z"}]"##
        return TransportResponse(statusCode: 200, body: Data(body.utf8))
    }
}

/// The Jobs list reaches the server when the API is held as `any PortalAPI` (as the app holds it), not the protocol's empty default.
final class JobsThroughProtocolTests: XCTestCase {
    @MainActor
    func testJobsListLoadsThroughTheProtocol() async {
        let api: any PortalAPI = HTTPPortalAPI(transport: StubTransport())
        let vm = JobsListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.jobs.count, 1)
    }
}
