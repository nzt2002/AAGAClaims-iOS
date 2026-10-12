import Foundation

/// Builds a multipart/form-data body.
final class MultipartForm {
    let boundary = "AAGAClaims-" + UUID().uuidString
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    func addFile(name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"; filename=\"\(Self.escape(fileName))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    func encoded() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private func append(_ string: String) {
        body.append(Data(string.utf8))
    }

    /// Quotes and line breaks would break the header.
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
