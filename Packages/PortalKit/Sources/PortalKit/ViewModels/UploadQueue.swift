import Foundation
import Observation

/// App-wide upload queue, so uploads continue when the user leaves the screen and failed
/// uploads can be retried (spec §6.10).
@MainActor
@Observable
public final class UploadQueue {
    public enum Status: Equatable, Sendable {
        case waiting
        case uploading
        case uploaded
        case failed(String)
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let record: RecordRef
        public let upload: FileUpload
        public internal(set) var status: Status

        public var title: String { upload.title }
        public var fileName: String { upload.fileName }
        public var size: Int { upload.data.count }
    }

    public private(set) var items: [Item] = []

    private let api: PortalAPI
    private var worker: Task<Void, Never>?
    /// Called after each successful upload, e.g. to refresh the record's file list.
    public var onUploaded: (@MainActor (RecordRef, PortalFile) -> Void)?
    /// Lets the app keep uploading briefly in the background (UIApplication background task).
    public var keepAlive: (@MainActor () -> (@MainActor () -> Void))?

    public init(api: PortalAPI) {
        self.api = api
    }

    public func items(for record: RecordRef) -> [Item] {
        items.filter { $0.record == record }
    }

    public var isBusy: Bool {
        items.contains { $0.status == .waiting || $0.status == .uploading }
    }

    public func enqueue(_ uploads: [FileUpload], to record: RecordRef) {
        items += uploads.map { Item(id: UUID(), record: record, upload: $0, status: .waiting) }
        startIfNeeded()
    }

    public func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), case .failed = items[index].status else { return }
        items[index].status = .waiting
        startIfNeeded()
    }

    public func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id && ($0.status == .uploaded || $0.status.isFailed) }
    }

    /// Removes finished uploads for a record, e.g. after its file list has refreshed.
    public func clearFinished(for record: RecordRef) {
        items.removeAll { $0.record == record && $0.status == .uploaded }
    }

    /// Waits for the queue to drain. For tests.
    public func waitUntilIdle() async {
        await worker?.value
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        let endKeepAlive = keepAlive?()
        worker = Task { [weak self] in
            while let self, let index = self.items.firstIndex(where: { $0.status == .waiting }) {
                await self.upload(at: index)
            }
            endKeepAlive?()
            self?.worker = nil
        }
    }

    private func upload(at index: Int) async {
        items[index].status = .uploading
        let item = items[index]
        let status: Status
        var uploadedFile: PortalFile?
        do {
            uploadedFile = try await api.uploadFile(item.upload, to: item.record)
            status = .uploaded
        } catch {
            status = .failed(Self.message(for: .wrap(error)))
        }
        // The list may have changed while uploading; find the item again.
        guard let current = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[current].status = status
        if let uploadedFile {
            onUploaded?(item.record, uploadedFile)
        }
    }

    private static func message(for error: PortalAPIError) -> String {
        switch error {
        case .offline: "You're offline."
        case .invalidRequest: "The file was rejected."
        default: "Upload failed."
        }
    }
}

extension UploadQueue.Status {
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
