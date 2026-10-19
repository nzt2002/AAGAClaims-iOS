import PhotosUI
import PortalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Upload sources (spec §6.10) for a record's Files: picks go to the upload queue.
struct UploadMenu: View {
    let record: RecordRef
    @Environment(UploadQueue.self) private var queue

    var body: some View {
        FileSourceMenu(maxCount: 10, onPicked: { queue.enqueue($0, to: record) }) {
            Label("Upload", systemImage: "arrow.up.doc")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: Theme.minTapTarget)
        }
        .accessibilityIdentifier("uploadMenu")
    }
}

/// Camera, photo library (multi-select) and Files. Prepares each pick with `FileUploadRules`
/// and hands the results to `onPicked`.
struct FileSourceMenu<MenuLabel: View>: View {
    var maxCount = 10
    let onPicked: ([FileUpload]) -> Void
    @ViewBuilder let label: () -> MenuLabel

    @Environment(\.isOffline) private var isOffline
    @Environment(\.serverMeta) private var serverMeta
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingFiles = false
    @State private var showingInspection = false
    @State private var showingScanner = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var problems: [String] = []

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo", systemImage: "camera") { showingCamera = true }
            }
            Button("Photo Library", systemImage: "photo.on.rectangle") { showingLibrary = true }
            Button("Files", systemImage: "folder") { showingFiles = true }
            if maxCount > 1 {
                // Several photos with captions, e.g. "Roof – north slope".
                Button("Inspection Photos", systemImage: "camera.on.rectangle") { showingInspection = true }
            }
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Document", systemImage: "doc.viewfinder") { showingScanner = true }
            }
        } label: {
            label()
        }
        .disabledWhenOffline(isOffline)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                add(cameraImage: image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingInspection) {
            InspectionPhotosView(maxCount: maxCount) { uploads in
                onPicked(uploads)
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScanner { pages in
                guard let pdf = ScannedDocument.pdf(from: pages) else {
                    problems.append("The scan couldn't be saved as a PDF.")
                    return
                }
                let title = "Scan \(FileUploadRules.cameraTitle())"
                prepare([(pdf, "\(title).pdf", title)])
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItems, maxSelectionCount: maxCount, matching: .images)
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await add(libraryItems: items) }
        }
        .fileImporter(
            isPresented: $showingFiles,
            allowedContentTypes: FileUploadRules.allowedContentTypes,
            allowsMultipleSelection: maxCount > 1
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

    /// Documents up to 25 MB once the server takes large files.
    private var documentLimit: Int {
        serverMeta.supports(.largeFiles) ? FileUploadRules.largeMaxBytes : FileUploadRules.maxBytes
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
                uploads.append(try FileUploadRules.prepare(data: pick.data, fileName: pick.fileName, title: pick.title, documentLimit: documentLimit))
            } catch {
                problems.append("\(pick.fileName): \(error.message)")
            }
        }
        if !uploads.isEmpty {
            onPicked(uploads)
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

// MARK: - Inspection photos

/// Several photos for an inspection, each with a caption that becomes its file title
/// ("Roof – north slope"). Take them one after another with the camera, or add from the library.
struct InspectionPhotosView: View {
    let maxCount: Int
    let onDone: ([FileUpload]) -> Void

    struct Photo: Identifiable {
        let id = UUID()
        let image: UIImage
        var caption = ""
    }

    @State private var photos: [Photo] = []
    @State private var showingCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var showingLibrary = false
    @State private var problems: [String] = []
    @Environment(\.dismiss) private var dismiss

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            List {
                if photos.isEmpty {
                    ContentUnavailableView("No photos yet", systemImage: "camera.on.rectangle",
                                           description: Text("Take photos one after another, then add a caption to each, like \"Roof – north slope\"."))
                }
                ForEach($photos) { $photo in
                    HStack(spacing: Theme.Spacing.m) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        TextField("Caption (e.g. Roof – north slope)", text: $photo.caption, axis: .vertical)
                            .accessibilityIdentifier("inspectionCaption")
                    }
                }
                .onDelete { photos.remove(atOffsets: $0) }
                Section {
                    if hasCamera {
                        Button("Take Photo", systemImage: "camera") { showingCamera = true }
                            .disabled(photos.count >= maxCount)
                    }
                    Button("Add from Library", systemImage: "photo.on.rectangle") { showingLibrary = true }
                        .disabled(photos.count >= maxCount)
                        .accessibilityIdentifier("inspectionAddFromLibrary")
                } footer: {
                    Text("Up to \(maxCount) photos at a time. Photos without a caption are named by date and time.")
                }
            }
            .navigationTitle("Inspection Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(photos.isEmpty ? "Upload" : "Upload \(photos.count)") { upload() }
                        .bold()
                        .disabled(photos.isEmpty)
                        .accessibilityIdentifier("inspectionUpload")
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    photos.append(Photo(image: image))
                    // Straight back to the camera for the next shot.
                    if photos.count < maxCount {
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            showingCamera = true
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItems,
                          maxSelectionCount: max(maxCount - photos.count, 1), matching: .images)
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                libraryItems = []
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            photos.append(Photo(image: image))
                        }
                    }
                }
            }
            .alert("Some photos couldn't be added", isPresented: Binding(get: { !problems.isEmpty }, set: { if !$0 { problems = [] } })) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(problems.joined(separator: "\n"))
            }
        }
    }

    private func upload() {
        let stamp = FileUploadRules.cameraTitle()
        var uploads: [FileUpload] = []
        for (index, photo) in photos.enumerated() {
            let caption = photo.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = caption.isEmpty ? (photos.count > 1 ? "\(stamp) (\(index + 1))" : stamp) : caption
            let (data, ext): (Data?, String) = if let heic = photo.image.heicData() { (heic, "heic") } else { (photo.image.jpegData(compressionQuality: 0.9), "jpg") }
            guard let data else { continue }
            do {
                uploads.append(try FileUploadRules.prepare(data: data, fileName: "\(safeFileName(title)).\(ext)", title: title))
            } catch {
                problems.append("\(title): \(error.message)")
            }
        }
        if !uploads.isEmpty { onDone(uploads) }
        if problems.isEmpty { dismiss() }
    }
}

// MARK: - Document scanner

/// The system document scanner (VisionKit): edge detection, cropping and multiple pages.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

/// Scanned pages as one PDF, US Letter, each page scaled to fit and compressed so a few pages stay
/// under the 4 MB upload limit.
enum ScannedDocument {
    static func pdf(from pages: [UIImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                let image = compressed(page)
                let scale = min(pageRect.width / image.size.width, pageRect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (pageRect.width - size.width) / 2, y: (pageRect.height - size.height) / 2,
                                      width: size.width, height: size.height))
            }
        }
        return data.isEmpty ? nil : data
    }

    /// At most 1,700 pixels on the long side, re-encoded as JPEG.
    private static func compressed(_ image: UIImage) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        let factor = min(1, 1_700 / longSide)
        let target = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.6), let result = UIImage(data: jpeg) else { return resized }
        return result
    }
}
