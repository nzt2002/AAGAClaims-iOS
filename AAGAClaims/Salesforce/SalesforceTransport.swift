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
            path: request.isAbsolutePath ? request.path : HTTPPortalAPI.basePath + request.path,
            queryParams: queryParams.isEmpty ? nil : queryParams
        )
        // The path is already absolute; don't prefix /services/data.
        restRequest.endpoint = ""
        if let body = request.body {
            restRequest.setCustomRequestBodyData(body, contentType: request.contentType ?? "application/octet-stream")
        }

        do {
            let response = try await RestClient.shared.send(request: restRequest)
            let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? 200
            return TransportResponse(statusCode: status, body: response.asData())
        } catch RestClientError.apiResponseIsEmpty {
            // 204 No Content.
            return TransportResponse(statusCode: 204, body: Data())
        } catch RestClientError.apiFailed(let body, let underlyingError, let urlResponse) {
            if let status = (urlResponse as? HTTPURLResponse)?.statusCode {
                // Keep the error body: it carries the code and any message for the user.
                return TransportResponse(statusCode: status, body: Self.data(from: body))
            }
            throw underlyingError
        }
    }

    /// The SDK hands back a failed response's body as data, text or parsed JSON.
    private static func data(from body: Any?) -> Data {
        switch body {
        case let data as Data: return data
        case let text as String: return Data(text.utf8)
        case let object? where JSONSerialization.isValidJSONObject(object):
            return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        default: return Data()
        }
    }
}
