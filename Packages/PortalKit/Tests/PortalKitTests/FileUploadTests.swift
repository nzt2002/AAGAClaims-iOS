import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PortalKit

/// Builds a solid-colour image of the given size in the given format.
private func makeImage(width: Int, height: Int, type: UTType) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.1, green: 0.45, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

/// Random pixels, which compress badly, so the file starts large.
private func noiseImage(width: Int, height: Int, type: UTType) -> Data {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    var seed: UInt32 = 12_345
    for i in 0..<bytes.count {
        seed = seed &* 1_103_515_245 &+ 12_345
        bytes[i] = UInt8(truncatingIfNeeded: seed >> 16)
    }
    let context = bytes.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func pixelSize(_ data: Data) -> (width: Int, height: Int, type: String)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int,
          let type = CGImageSourceGetType(source) as String? else { return nil }
    return (width, height, type)
}

@Suite("File upload rules")
struct FileUploadRuleTests {
    @Test("Allowed types", arguments: ["a.pdf", "a.PNG", "a.jpg", "a.jpeg", "a.HEIC", "a.doc", "a.docx", "a.xls", "a.xlsx"])
    func allowed(name: String) {
        #expect(FileUploadRules.isAllowed(fileName: name))
    }

    @Test("Refused types", arguments: ["a.exe", "a.zip", "a.mov", "a.gif", "noextension", "a.pdf.exe"])
    func refused(name: String) {
        #expect(!FileUploadRules.isAllowed(fileName: name))
        #expect(throws: FileUploadRules.Problem.unsupportedType) {
            _ = try FileUploadRules.prepare(data: Data([1]), fileName: name, title: "x")
        }
    }

    @Test("Empty and oversized files are refused")
    func sizes() {
        #expect(throws: FileUploadRules.Problem.empty) {
            _ = try FileUploadRules.prepare(data: Data(), fileName: "a.pdf", title: "x")
        }
        let big = Data(count: FileUploadRules.maxBytes + 1)
        #expect(throws: FileUploadRules.Problem.tooLarge) {
            _ = try FileUploadRules.prepare(data: big, fileName: "a.pdf", title: "x")
        }
    }

    @Test("Titles")
    func titles() {
        let date = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-03 04:00 UTC
        #expect(FileUploadRules.cameraTitle(at: date, timeZone: TimeZone(identifier: "UTC")!) == "Photo 2026-10-03 04:00")
        #expect(FileUploadRules.title(forFileName: "Roof estimate.pdf") == "Roof estimate")
    }

    @Test("Large JPEG and HEIC photos are downscaled to 4,000 px and keep their format", arguments: [UTType.jpeg, .heic])
    func downscale(type: UTType) throws {
        let original = makeImage(width: 5_000, height: 3_000, type: type)
        let upload = try FileUploadRules.prepare(data: original, fileName: "photo.\(type.preferredFilenameExtension!)", title: "Photo")
        let size = try #require(pixelSize(upload.data))
        #expect(size.width == 4_000)
        #expect(size.height == 2_400)
        #expect(size.type == type.identifier)
        #expect(upload.mimeType == (type == .heic ? "image/heic" : "image/jpeg"))
    }

    @Test("Photos still over the size limit after downscaling are shrunk to fit", arguments: [UTType.jpeg, .png])
    func fitsLargePhotos(type: UTType) throws {
        let original = noiseImage(width: 3_000, height: 2_000, type: type)
        #expect(original.count > FileUploadRules.maxBytes, "Test image must start over the limit")
        let upload = try FileUploadRules.prepare(data: original, fileName: "big.\(type.preferredFilenameExtension!)", title: "Big")
        #expect(upload.data.count <= FileUploadRules.maxBytes)
        #expect(upload.mimeType == "image/jpeg")
        #expect(upload.fileName == "big.jpg")
        #expect(pixelSize(upload.data) != nil)
    }

    @Test("Documents over the limit are still refused")
    func largeDocument() {
        #expect(throws: FileUploadRules.Problem.tooLarge) {
            _ = try FileUploadRules.prepare(data: Data(count: FileUploadRules.maxBytes + 1), fileName: "big.pdf", title: "x")
        }
    }

    @Test("Small photos are uploaded unchanged")
    func smallPhoto() throws {
        let original = makeImage(width: 1_200, height: 900, type: .png)
        let upload = try FileUploadRules.prepare(data: original, fileName: "small.png", title: "Small")
        #expect(upload.data == original)
    }

    @Test("Quick Look extension from bytes, then FileType")
    func previewExtension() {
        #expect(FileUploadRules.previewExtension(for: MockPortalAPI.samplePDF, fileType: "JPG") == "pdf")
        #expect(FileUploadRules.previewExtension(for: makeImage(width: 4, height: 4, type: .jpeg), fileType: nil) == "jpg")
        #expect(FileUploadRules.previewExtension(for: makeImage(width: 4, height: 4, type: .heic), fileType: nil) == "heic")
        #expect(FileUploadRules.previewExtension(for: Data("PK".utf8), fileType: "WORD_X") == "docx")
    }
}

/// Records multipart requests.
private actor RecordingTransport: PortalTransport {
    private(set) var requests: [TransportRequest] = []
    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        let body = #"{"contentDocumentId":"069X","title":"Roof","fileType":"PDF","contentSize":3}"#
        return TransportResponse(statusCode: 201, body: Data(body.utf8))
    }
}

@MainActor
@Suite("File endpoints and upload queue")
struct FileEndpointTests {
    @Test("Upload sends the file bytes, with fileName and title as query parameters")
    func rawUpload() async throws {
        let transport = RecordingTransport()
        let file = try await HTTPPortalAPI(transport: transport).uploadFile(
            FileUpload(fileName: "roof.pdf", title: "Roof", mimeType: "application/pdf", data: Data("abc".utf8)),
            to: .lead("a0r000000000001AAA")
        )
        #expect(file.contentDocumentId == "069X")

        let request = try #require(await transport.requests.first)
        #expect(request.path == "/leads/a0r000000000001AAA/files")
        #expect(request.contentType == "application/pdf")
        #expect(request.body == Data("abc".utf8))
        #expect(request.queryItems == [URLQueryItem(name: "fileName", value: "roof.pdf"), URLQueryItem(name: "title", value: "Roof")])
    }

    @Test("Download path")
    func download() async throws {
        let transport = RecordingTransport()
        _ = try await HTTPPortalAPI(transport: transport).fileContent(contentDocumentId: "069000000000001AAA")
        #expect(await transport.requests.first?.path == "/files/069000000000001AAA/content")
    }

    @Test("Queue uploads, refreshes and appears in the file list")
    func queue() async throws {
        let api = MockPortalAPI(fixtures: try .bundled())
        let queue = UploadQueue(api: api)
        var uploaded: [String] = []
        queue.onUploaded = { _, file in uploaded.append(file.title ?? "") }

        let record = RecordRef.claim("a23000000000001AAA")
        queue.enqueue([
            FileUpload(fileName: "a.pdf", title: "First", mimeType: "application/pdf", data: Data("1".utf8)),
            FileUpload(fileName: "b.pdf", title: "Second", mimeType: "application/pdf", data: Data("2".utf8))
        ], to: record)
        await queue.waitUntilIdle()

        #expect(queue.items(for: record).map(\.status) == [.uploaded, .uploaded])
        #expect(uploaded == ["First", "Second"])
        let files = try await api.files(for: record)
        #expect(files.prefix(2).compactMap(\.title) == ["Second", "First"])
        #expect(try await api.fileContent(contentDocumentId: files[0].contentDocumentId) == Data("2".utf8))

        queue.clearFinished(for: record)
        #expect(queue.items(for: record).isEmpty)
    }

    @Test("Failed uploads can be retried")
    func retry() async throws {
        let api = MockPortalAPI(fixtures: try .bundled(), failure: .offline)
        let queue = UploadQueue(api: api)
        let record = RecordRef.lead("a0r000000000001AAA")
        queue.enqueue([FileUpload(fileName: "a.pdf", title: "A", mimeType: "application/pdf", data: Data("1".utf8))], to: record)
        await queue.waitUntilIdle()
        let item = try #require(queue.items.first)
        #expect(item.status == .failed("You're offline."))

        await api.setFailure(nil)
        queue.retry(item.id)
        await queue.waitUntilIdle()
        #expect(queue.items.first?.status == .uploaded)
    }

    @Test("Files are never served from the offline cache")
    func notCached() async throws {
        let api = CachingPortalAPI(base: MockPortalAPI(fixtures: try .bundled()), cache: MemoryResponseCache())
        _ = try await api.fileContent(contentDocumentId: "069000000000001AAA")
        await api.setOnline(false)
        await #expect(throws: PortalAPIError.offline) {
            _ = try await api.fileContent(contentDocumentId: "069000000000001AAA")
        }
    }
}
