import Testing
@testable import PortalKit

@Suite("File explorer")
struct FileExplorerTests {
    private func file(_ id: String, in folder: String?) -> PortalFile {
        PortalFile(contentDocumentId: id, title: id, fileType: "PDF", contentSize: 1, createdDate: nil, createdByName: nil, folderId: folder, portalVisible: false)
    }

    private let tree = [
        PortalFolder(id: "ins", name: "Insurance"),
        PortalFolder(id: "let", name: "Letters", parentId: "ins"),
        PortalFolder(id: "pho", name: "photos"),
    ]

    @Test func listsSubfoldersAtoZIgnoringCase() {
        let e = FileExplorer(folders: tree)
        #expect(e.subfolders.map(\.id) == ["ins", "pho"])
        #expect(FileExplorer(folders: tree, currentId: "ins").subfolders.map(\.id) == ["let"])
    }

    @Test func showsOnlyTheOpenFoldersFilesUnlessAll() {
        let files = [file("a", in: nil), file("b", in: "ins"), file("c", in: "let")]
        #expect(FileExplorer(folders: tree, files: files).visibleFiles.map(\.id) == ["a"])
        #expect(FileExplorer(folders: tree, files: files, currentId: "ins").visibleFiles.map(\.id) == ["b"])
        #expect(FileExplorer(folders: tree, files: files, showAll: true).visibleFiles.count == 3)
    }

    @Test func aFileInAnUnseenFolderShowsAtTheTopLevel() {
        let files = [file("hidden", in: "staff-only"), file("a", in: nil)]
        #expect(FileExplorer(folders: tree, files: files).visibleFiles.map(\.id) == ["hidden", "a"])
        #expect(FileExplorer(folders: tree, files: files, currentId: "ins").visibleFiles.isEmpty)
    }

    @Test func withNoFoldersEveryFileShows() {
        #expect(FileExplorer(folders: [], files: [file("a", in: nil), file("b", in: "gone")]).visibleFiles.count == 2)
    }

    @Test func breadcrumbRunsFromTheTopDown() {
        #expect(FileExplorer(folders: tree, currentId: "let").breadcrumb.map(\.id) == ["ins", "let"])
        #expect(FileExplorer(folders: tree).breadcrumb.isEmpty)
    }

    @Test func countsFilesInsideSubfolders() {
        let files = [file("b", in: "ins"), file("c", in: "let"), file("d", in: "pho")]
        let e = FileExplorer(folders: tree, files: files)
        #expect(e.fileCount(in: "ins") == 2)
        #expect(e.fileCount(in: "pho") == 1)
    }

    @Test func aFolderCannotMoveIntoItselfOrItsChildren() {
        let e = FileExplorer(folders: tree)
        #expect(e.moveTargets(forFolder: "ins").map(\.id) == ["pho"])
        #expect(e.moveTargets().map(\.id) == ["ins", "let", "pho"])
        #expect(e.path(of: "let") == "Insurance / Letters")
    }

    @Test func aBrokenLoopDoesNotHangTheBreadcrumb() {
        let loop = [PortalFolder(id: "a", name: "A", parentId: "b"), PortalFolder(id: "b", name: "B", parentId: "a")]
        #expect(FileExplorer(folders: loop, currentId: "a").breadcrumb.count <= 50)
    }
}
