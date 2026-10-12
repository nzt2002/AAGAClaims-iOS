import Foundation
import PortalKit
import SalesforceSDKCore

/// Sends portal requests through the Mobile SDK's `RestClient`, which adds the OAuth token
/// and refreshes it when it expires.
nonisolated struct SalesforceTransport: PortalTransport {
    func send(_ request: TransportRequest) async throws -> TransportResponse {
        let queryParams = Dictionary(
            request.queryItems.map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
        let restRequest = RestRequest(
            method: request.method == .get ? .GET : .POST,
            serviceHostType: .instance,
            path: HTTPPortalAPI.basePath + request.path,
            queryParams: queryParams.isEmpty ? nil : queryParams
        )
        // The path is already absolute; don't prefix /services/data.
        restRequest.endpoint = ""
        if let body = request.jsonBody {
            restRequest.setCustomRequestBodyData(body, contentType: "application/json")
        }

        do {
            let response = try await RestClient.shared.send(request: restRequest)
            let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? 200
            return TransportResponse(statusCode: status, body: response.asData())
        } catch RestClientError.apiResponseIsEmpty {
            // 204 No Content.
            return TransportResponse(statusCode: 204, body: Data())
        } catch RestClientError.apiFailed(_, let underlyingError, let urlResponse) {
            if let status = (urlResponse as? HTTPURLResponse)?.statusCode {
                return TransportResponse(statusCode: status, body: Data())
            }
            throw underlyingError
        }
    }
}
