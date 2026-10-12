import PhotosUI
import PortalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Upload sources (spec §6.10): camera, photo library (multi-select) and Files. Prepares each
/// pick with `FileUploadRules` and hands the results to the upload queue.
struct UploadMenu: View {
    let record: RecordRef

    @Environment(UploadQueue.self) private var queue
    @Environment(\.isOffline) private var isOffline
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingFiles = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var problems: [String] = []

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo", systemImage: "camera") { showingCamera = true }
            }
            Button("Photo Library", systemImage: "photo.on.rectangle") { showingLibrary = true }
            Button("Files", systemImage: "folder") { showingFiles = true }
        } label: {
            Label("Upload", systemImage: "arrow.up.doc")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: Theme.minTapTarget)
        }
        .disabledWhenOffline(isOffline)
        .accessibilityIdentifier("uploadMenu")
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                add(cameraImage: image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await add(libraryItems: items) }
        }
        .fileImporter(
            isPresented: $showingFiles,
            allowedContentTypes: FileUploadRules.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                add(fileURLs: urls)
            }
        }
        .alert("Some files couldn't be added", isPresented: Binding(get: { !problems.isEmpty }, set: { if !$0 { problems = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problems.joined(separator: "\n"))
        }
    }

    private func add(cameraImage image: UIImage) {
        // Keep HEIC where the device supports it (spec §6.10), otherwise JPEG.
        let (data, ext): (Data?, String) = if let heic = image.heicData() { (heic, "heic") } else { (image.jpegData(compressionQuality: 0.9), "jpg") }
        guard let data else { return }
        let title = FileUploadRules.cameraTitle()
        prepare([(data, "\(title).\(ext)", title)])
    }

    private func add(libraryItems items: [PhotosPickerItem]) async {
        var picks: [(Data, String, String)] = []
        let title = FileUploadRules.cameraTitle()
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                problems.append("A photo couldn't be read.")
                continue
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            // Library picks have no file name without full photo access, so they're titled like camera photos.
            let itemTitle = items.count > 1 ? "\(title) (\(index + 1))" : title
            picks.append((data, "\(itemTitle).\(ext)", itemTitle))
        }
        prepare(picks)
    }

    private func add(fileURLs urls: [URL]) {
        var picks: [(Data, String, String)] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                problems.append("\(url.lastPathComponent) couldn't be read.")
                continue
            }
            picks.append((data, url.lastPathComponent, FileUploadRules.title(forFileName: url.lastPathComponent)))
        }
        prepare(picks)
    }

    private func prepare(_ picks: [(data: Data, fileName: String, title: String)]) {
        var uploads: [FileUpload] = []
        for pick in picks {
            do {
                uploads.append(try FileUploadRules.prepare(data: pick.data, fileName: pick.fileName, title: pick.title))
            } catch {
                problems.append("\(pick.fileName): \(error.message)")
            }
        }
        if !uploads.isEmpty {
            queue.enqueue(uploads, to: record)
        }
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
