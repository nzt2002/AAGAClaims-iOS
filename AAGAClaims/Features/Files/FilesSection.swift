import PortalKit
import QuickLook
import SwiftUI

/// Files for a claim or lead: folders, list, Quick Look preview, upload and upload status (spec §6.5, §6.10).
/// On servers with `fileFolders` it works like the website's Files tab: open folders, and staff can make, rename, move,
/// delete and share folders, move files between them, and show, hide or remove several files at once.
struct FilesSection: View {
    let record: RecordRef
    let state: LoadState<[PortalFile]>
    let api: PortalAPI
    let reload: () async -> Void

    @Environment(UploadQueue.self) private var queue
    @Environment(\.isInternalUser) private var isInternal
    @Environment(\.serverMeta) private var serverMeta
    @State private var preview: PreviewFile?
    @State private var loadingFileId: String?
    @State private var previewError: String?

    // Folders (loaded only when this tab is open)
    @State private var folders: [PortalFolder] = []
    @State private var currentId: String?
    @State private var showAll = false
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var prompt: FolderPrompt?
    @State private var promptText = ""
    @State private var movingFolder: PortalFolder?
    @State private var movingFileIds: [String] = []
    @State private var deleting: PortalFolder?
    @State private var removedIds: [String] = []
    @State private var actionError: String?

    private enum FolderPrompt: Identifiable {
        case create, rename(PortalFolder)
        var id: String { switch self { case .create: "create"; case .rename(let f): "rename-\(f.id)" } }
    }

    private var hasFolders: Bool { serverMeta.supports(.fileFolders) }
    private var canManage: Bool { isInternal && hasFolders }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeading("Files")
                Spacer()
                if canManage { manageMenu }
                if !selecting { UploadMenu(record: record, folderId: canManage ? currentId : nil) }
            }
            UploadStatusList(record: record)
            // Only once there are folders to move between; with none, a "Files" crumb just repeats the heading.
            if hasFolders && (!folders.isEmpty || showAll) { breadcrumb }
            if !removedIds.isEmpty { undoBar }
            SectionLoader(state: state, subject: "files", retry: reload) { files in
                let explorer = FileExplorer(folders: folders, files: files, currentId: currentId, showAll: showAll)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if hasFolders && !showAll && !explorer.subfolders.isEmpty { folderList(explorer) }
                    FilesList(files: explorer.visibleFiles, loadingFileId: loadingFileId, onOpen: { file in
                        Task { await open(file) }
                    }, selected: selecting ? selected : nil, onToggle: toggle, menu: canManage ? { fileMenu($0) } : nil,
                       emptyText: emptyText(explorer), showsVisibility: canManage)
                    if selecting { selectionBar(explorer) }
                }
            }
        }
        .task(id: record) { await loadFolders() }
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
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Folder name", text: $promptText)
            Button("Cancel", role: .cancel) {}
            Button(promptButton) { Task { await submitPrompt() } }
        }
        .confirmationDialog("Delete this folder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { folder in
            Button("Delete \(folder.name)", role: .destructive) { Task { await change(folder, .delete) } }
        } message: { _ in
            Text("Only the folder goes. Its files and folders move up a level.")
        }
        .sheet(item: $movingFolder) { folder in
            MoveToFolderSheet(title: "Move \(folder.name)", explorer: FileExplorer(folders: folders), excluding: folder.id, current: folder.parentId) { target in
                Task { await change(folder, .move(parentId: target)) }
            }
        }
        .sheet(isPresented: Binding(get: { !movingFileIds.isEmpty }, set: { if !$0 { movingFileIds = [] } })) {
            MoveToFolderSheet(title: movingFileIds.count == 1 ? "Move file" : "Move \(movingFileIds.count) files", explorer: FileExplorer(folders: folders), excluding: nil, current: nil) { target in
                let ids = movingFileIds
                Task { await organize(ids, .move, folderId: target, done: "Moved.") }
            }
        }
    }

    // MARK: Folder navigation

    private var breadcrumb: some View {
        let explorer = FileExplorer(folders: folders, currentId: currentId)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                crumb("Files", id: nil, isCurrent: currentId == nil && !showAll)
                if showAll {
                    Image(systemName: "chevron.right").iconShadow().font(.caption2).foregroundStyle(Color.textSecondary)
                    Text("All files").font(.subheadline.weight(.semibold))
                }
                ForEach(explorer.breadcrumb) { folder in
                    Image(systemName: "chevron.right").iconShadow().font(.caption2).foregroundStyle(Color.textSecondary)
                    crumb(folder.name, id: folder.id, isCurrent: folder.id == currentId && !showAll)
                }
            }
        }
    }

    private func crumb(_ title: String, id: String?, isCurrent: Bool) -> some View {
        Button { open(folder: id) } label: {
            Text(title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.textPrimary : Color.brandPrimary)
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("crumb-\(id ?? "top")")
    }

    private func open(folder id: String?) {
        currentId = id
        showAll = false
        selected = []
    }

    private func folderList(_ explorer: FileExplorer) -> some View {
        VStack(spacing: 0) {
            ForEach(explorer.subfolders) { folder in
                Button { open(folder: folder.id) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "folder.fill").iconShadow().font(.title2).foregroundStyle(Color.brandPrimary).frame(width: 32)
                        Text(folder.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary)
                        Spacer(minLength: 0)
                        if canManage {
                            Image(systemName: folder.portalVisible ? "eye" : "eye.slash").iconShadow()
                                .font(.caption)
                                .foregroundStyle(folder.portalVisible ? Color.success : Color.textSecondary)
                                .accessibilityLabel(folder.portalVisible ? "The policyholder sees this folder" : "Staff only")
                        }
                        let count = explorer.fileCount(in: folder.id)
                        if count > 0 { Text("\(count)").font(.caption).foregroundStyle(Color.textSecondary) }
                        Image(systemName: "chevron.right").iconShadow().font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(minHeight: Theme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { if canManage { folderMenu(folder) } }
                .accessibilityIdentifier("folder-\(folder.id)")
                if folder.id != explorer.subfolders.last?.id { Divider() }
            }
        }
        .cardStyle()
    }

    private func emptyText(_ explorer: FileExplorer) -> String {
        if hasFolders && !showAll && !folders.isEmpty { return explorer.subfolders.isEmpty ? "This folder is empty." : "No files at this level." }
        return "No files have been added yet."
    }

    // MARK: Staff menus

    private var manageMenu: some View {
        Menu {
            Button("New Folder", systemImage: "folder.badge.plus") { promptText = ""; prompt = .create }
            Button(selecting ? "Done Selecting" : "Select Files", systemImage: selecting ? "checkmark.circle" : "checklist") {
                selecting.toggle()
                selected = []
            }
            Button(showAll ? "Show Folders" : "Show All Files", systemImage: showAll ? "folder" : "square.stack") { showAll.toggle() }
            if let current = FileExplorer(folders: folders, currentId: currentId).folder(currentId) {
                Divider()
                Menu(current.name) { folderMenu(current) }
            }
        } label: {
            Image(systemName: "ellipsis.circle").iconShadow()
                .font(.title3)
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
        }
        .accessibilityLabel("Folder options")
        .accessibilityIdentifier("folderOptions")
    }

    @ViewBuilder
    private func folderMenu(_ folder: PortalFolder) -> some View {
        Button("Rename", systemImage: "pencil") { promptText = folder.name; prompt = .rename(folder) }
        Button("Move", systemImage: "folder") { movingFolder = folder }
        Button(folder.portalVisible ? "Staff Only" : "Show Policyholder", systemImage: folder.portalVisible ? "eye.slash" : "eye") {
            Task { await change(folder, .setPortalVisible(!folder.portalVisible)) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = folder }
    }

    private func fileMenu(_ file: PortalFile) -> AnyView {
        AnyView(Group {
            Button("Move to Folder", systemImage: "folder") { movingFileIds = [file.id] }
            if file.portalVisible == true {
                Button("Staff Only", systemImage: "eye.slash") { Task { await organize([file.id], .hide, done: "Now staff only.") } }
            } else {
                Button("Show Policyholder", systemImage: "eye") { Task { await organize([file.id], .show, done: "Visible to the policyholder.") } }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { Task { await remove([file.id]) } }
        })
    }

    private func toggle(_ file: PortalFile) {
        if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
    }

    private func selectionBar(_ explorer: FileExplorer) -> some View {
        let ids = Array(selected)
        return HStack(spacing: Theme.Spacing.s) {
            Text("\(selected.count) selected").font(.subheadline.weight(.semibold))
            Spacer()
            Button("All") { selected = Set(explorer.visibleFiles.map(\.id)) }
            Button { movingFileIds = ids } label: { Image(systemName: "folder").iconShadow() }.accessibilityLabel("Move")
            Button { Task { await organize(ids, .show, done: "Visible to the policyholder.") } } label: { Image(systemName: "eye").iconShadow() }.accessibilityLabel("Show policyholder")
            Button { Task { await organize(ids, .hide, done: "Now staff only.") } } label: { Image(systemName: "eye.slash").iconShadow() }.accessibilityLabel("Staff only")
            Button(role: .destructive) { Task { await remove(ids) } } label: { Image(systemName: "trash").iconShadow() }.accessibilityLabel("Remove")
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .padding(Theme.Spacing.s)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var undoBar: some View {
        HStack {
            Text(removedIds.count == 1 ? "File removed." : "\(removedIds.count) files removed.").font(.subheadline)
            Spacer()
            Button("Undo") {
                let ids = removedIds
                removedIds = []
                Task { await organize(ids, .restore, done: nil) }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(Theme.Spacing.m)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: Actions

    private var promptTitle: String {
        switch prompt { case .rename: "Rename folder"; default: "New folder" }
    }
    private var promptButton: String {
        switch prompt { case .rename: "Rename"; default: "Create" }
    }

    private func loadFolders() async {
        guard hasFolders else { return }
        if let loaded = try? await api.folders(for: record) { folders = loaded }
    }

    private func submitPrompt() async {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let prompt else { return }
        do {
            switch prompt {
            case .create:
                let folder = try await api.createFolder(named: name, parentId: showAll ? nil : currentId, in: record)
                folders.append(folder)
            case .rename(let folder):
                try await api.changeFolder(folder.id, .rename(name), in: record)
                await loadFolders()
            }
        } catch {
            actionError = message(for: error, fallback: "Couldn't save the folder.")
        }
    }

    private func change(_ folder: PortalFolder, _ change: FolderChange) async {
        do {
            try await api.changeFolder(folder.id, change, in: record)
            if case .delete = change, currentId == folder.id { currentId = folder.parentId }
            await loadFolders()
            if case .delete = change { await reload() }
        } catch {
            actionError = message(for: error, fallback: "Couldn't change the folder.")
        }
    }

    private func organize(_ ids: [String], _ op: FileOrganizeOp, folderId: String? = nil, done: String?) async {
        guard !ids.isEmpty else { return }
        do {
            try await api.organizeFiles(ids, op, folderId: folderId, in: record)
            selected = []
            await reload()
        } catch {
            actionError = message(for: error, fallback: "Couldn't update the files.")
        }
    }

    private func remove(_ ids: [String]) async {
        await organize(ids, .remove, done: nil)
        if actionError == nil { removedIds = ids }
    }

    private func message(for error: Error, fallback: String) -> String {
        if case PortalAPIError.rejected(let text) = error { return text }
        if case PortalAPIError.offline = error { return "You're offline. Try again when you're back online." }
        return fallback
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

/// Pick a folder (or the top level) to move files or a folder into.
struct MoveToFolderSheet: View {
    let title: String
    let explorer: FileExplorer
    let excluding: String?
    let current: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button { pick(nil) } label: { Label("Top level", systemImage: "tray") }
                    .disabled(excluding != nil && current == nil)
                ForEach(explorer.moveTargets(forFolder: excluding)) { folder in
                    Button { pick(folder.id) } label: { Label(explorer.path(of: folder.id), systemImage: "folder") }
                        .disabled(folder.id == current)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ id: String?) {
        dismiss()
        onPick(id)
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
func safeFileName(_ title: String?) -> String {
    var name = ""
    for character in (title ?? "File").prefix(80) {
        let keep = character.isLetter || character.isNumber || character == " " || character == "-"
        name.append(keep ? character : "_")
    }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "File" : trimmed
}

extension Optional where Wrapped == PreviewFile {
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
                                Image(systemName: "xmark").iconShadow()
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
        case .waiting: Image(systemName: "clock").iconShadow().foregroundStyle(Color.textSecondary)
        case .uploading: ProgressView()
        case .uploaded: Image(systemName: "checkmark.circle.fill").iconShadow().foregroundStyle(Color.success)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").iconShadow().foregroundStyle(Color.warning)
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
