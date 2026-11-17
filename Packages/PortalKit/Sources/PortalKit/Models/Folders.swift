import Foundation

/// A folder on a claim or lead (`GET /{record}/folders`), as on the website's Files tab.
public struct PortalFolder: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let parentId: String?
    /// The policyholder can see this folder.
    public let portalVisible: Bool

    public init(id: String, name: String, parentId: String? = nil, portalVisible: Bool = false) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.portalVisible = portalVisible
    }
}

/// What staff can do to one folder (`POST /{record}/folders/{id}`).
public enum FolderChange: Sendable, Equatable {
    case rename(String)
    case setPortalVisible(Bool)
    /// nil moves it to the top level.
    case move(parentId: String?)
    /// Only the folder goes; its files and subfolders move up a level.
    case delete
}

/// What staff can do to several files at once (`POST /{record}/files/organize`).
public enum FileOrganizeOp: String, Sendable {
    case move, show, hide, remove, restore
}

/// The Files tab's view of one record: which folder is open, what's in it, and where things can go. Pure, so it is tested.
public struct FileExplorer: Sendable, Equatable {
    public var folders: [PortalFolder]
    public var files: [PortalFile]
    /// nil is the top level.
    public var currentId: String?
    /// "All files": every file, whatever folder it is in.
    public var showAll = false

    public init(folders: [PortalFolder] = [], files: [PortalFile] = [], currentId: String? = nil, showAll: Bool = false) {
        self.folders = folders
        self.files = files
        self.currentId = currentId
        self.showAll = showAll
    }

    private func byName(_ a: PortalFolder, _ b: PortalFolder) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    public func folder(_ id: String?) -> PortalFolder? {
        id.flatMap { id in folders.first { $0.id == id } }
    }

    /// Folders directly inside the open one (or the top level), A to Z.
    public var subfolders: [PortalFolder] {
        folders.filter { $0.parentId == currentId }.sorted(by: byName)
    }

    /// Files to list: those in the open folder, or every file under "All files". With no folders, all of them.
    public var visibleFiles: [PortalFile] {
        if showAll || folders.isEmpty { return files }
        // A file in a folder this person can't see (a homeowner never sees staff-only folders) counts as top level.
        let known = Set(folders.map(\.id))
        return files.filter { file in
            let home = file.folderId.flatMap { known.contains($0) ? $0 : nil }
            return home == currentId
        }
    }

    /// From the top level down to the open folder.
    public var breadcrumb: [PortalFolder] {
        var trail: [PortalFolder] = []
        var next = folder(currentId)
        while let f = next, trail.count < 50 {
            trail.insert(f, at: 0)
            next = folder(f.parentId)
        }
        return trail
    }

    /// Files in a folder and everything under it.
    public func fileCount(in folderId: String) -> Int {
        let ids = Set([folderId] + descendants(of: folderId))
        return files.filter { $0.folderId.map(ids.contains) ?? false }.count
    }

    public func descendants(of folderId: String) -> [String] {
        var out: [String] = []
        var queue = [folderId]
        while let id = queue.popLast(), out.count < 2000 {
            for child in folders where child.parentId == id { out.append(child.id); queue.append(child.id) }
        }
        return out
    }

    /// "Insurance / Letters": the folder's place in the tree.
    public func path(of folderId: String) -> String {
        var names: [String] = []
        var next = folder(folderId)
        while let f = next, names.count < 50 {
            names.insert(f.name, at: 0)
            next = folder(f.parentId)
        }
        return names.joined(separator: " / ")
    }

    /// Where a folder can be moved: not into itself or anything inside it.
    public func moveTargets(forFolder id: String? = nil) -> [PortalFolder] {
        let blocked = id.map { Set([$0] + descendants(of: $0)) } ?? []
        return folders.filter { !blocked.contains($0.id) }.sorted { path(of: $0.id).localizedCaseInsensitiveCompare(path(of: $1.id)) == .orderedAscending }
    }
}
