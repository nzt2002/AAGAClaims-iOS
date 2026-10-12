import PortalKit
import QuickLook
import SwiftUI

/// Files for a claim or lead: list, Quick Look preview, upload and upload status (spec §6.5, §6.10).
struct FilesSection: View {
    let record: RecordRef
    let state: LoadState<[PortalFile]>
    let api: PortalAPI
    let reload: () async -> Void

    @Environment(UploadQueue.self) private var queue
    @State private var preview: PreviewFile?
    @State private var loadingFileId: String?
    @State private var previewError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeading("Files")
                Spacer()
                UploadMenu(record: record)
            }
            UploadStatusList(record: record)
            SectionLoader(state: state, subject: "files", retry: reload) { files in
                FilesList(files: files, loadingFileId: loadingFileId) { file in
                    Task { await open(file) }
                }
            }
        }
        // Refresh the list as uploads finish.
        .onChange(of: queue.items(for: record).filter { $0.status == .uploaded }.count) { _, count in
            guard count > 0 else { return }
            Task {
                await reload()
                queue.clearFinished(for: record)
            }
        }
        .quickLookPreview($preview.url)
        .onChange(of: preview) { old, new in
            // Delete the temporary copy once Quick Look closes (spec §8: no file caching).
            if new == nil, let old {
                try? FileManager.default.removeItem(at: old.directory)
            }
        }
        .alert("Couldn't open file", isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewError ?? "")
        }
    }

    private func open(_ file: PortalFile) async {
        loadingFileId = file.id
        defer { loadingFileId = nil }
        do {
            let data = try await api.fileContent(contentDocumentId: file.contentDocumentId)
            preview = try PreviewFile.write(data: data, title: file.title, fileType: file.fileType)
        } catch PortalAPIError.offline {
            previewError = "You're offline. Files open when you're back online."
        } catch {
            previewError = "Please try again, or contact support if this keeps happening."
        }
    }
}

/// A temporary copy of a file for Quick Look, in its own folder so it can be removed afterwards.
struct PreviewFile: Equatable {
    let directory: URL
    var url: URL?

    static func write(data: Data, title: String?, fileType: String?) throws -> PreviewFile {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Previews", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = FileUploadRules.previewExtension(for: data, fileType: fileType)
        let url = directory.appending(path: "\(safeFileName(title)).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return PreviewFile(directory: directory, url: url)
    }
}

/// Keeps letters, digits, spaces and hyphens, so a title can't escape the folder.
private func safeFileName(_ title: String?) -> String {
    var name = ""
    for character in (title ?? "File").prefix(80) {
        let keep = character.isLetter || character.isNumber || character == " " || character == "-"
        name.append(keep ? character : "_")
    }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "File" : trimmed
}

private extension Optional where Wrapped == PreviewFile {
    /// Quick Look binds to a URL; clearing it clears the preview.
    var url: URL? {
        get { self?.url }
        set { if newValue == nil { self = nil } }
    }
}

/// Per-file upload status with Retry (spec §6.10).
struct UploadStatusList: View {
    let record: RecordRef
    @Environment(UploadQueue.self) private var queue

    var body: some View {
        let items = queue.items(for: record)
        if !items.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(items) { item in
                    HStack(spacing: Theme.Spacing.m) {
                        statusIcon(item.status)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(statusText(item.status)) · \(PortalFormat.fileSize(item.size))")
                                .font(.caption)
                                .foregroundStyle(item.status.isFailed ? Color.warning : Color.textSecondary)
                        }
                        Spacer()
                        if item.status.isFailed {
                            Button("Retry") { queue.retry(item.id) }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: Theme.minTapTarget)
                            Button {
                                queue.dismiss(item.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                            }
                            .accessibilityLabel("Remove \(item.title)")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("upload-\(item.title)")
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: UploadQueue.Status) -> some View {
        switch status {
        case .waiting: Image(systemName: "clock").foregroundStyle(Color.textSecondary)
        case .uploading: ProgressView()
        case .uploaded: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
        }
    }

    private func statusText(_ status: UploadQueue.Status) -> String {
        switch status {
        case .waiting: "Waiting"
        case .uploading: "Uploading…"
        case .uploaded: "Uploaded"
        case .failed(let message): message
        }
    }
}
