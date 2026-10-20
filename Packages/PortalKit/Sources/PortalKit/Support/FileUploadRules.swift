import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File upload rules (spec §6.10).
public enum FileUploadRules {
    /// pdf, png, jpg, jpeg, heic, doc, docx, xls, xlsx.
    public static let allowedExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "doc", "docx", "xls", "xlsx"]
    /// Longest side of an uploaded photo.
    public static let maxPhotoPixels = 4_000
    /// The server's limit: Apex REST bodies count against its 6 MB heap (PortalApiV1.MAX_FILE_BYTES).
    public static let maxBytes = 4 * 1_024 * 1_024
    /// When the server takes large files (`ServerMeta.Feature.largeFiles`): documents and scans up
    /// to 25 MB. Photos are still kept under `maxBytes`, which is plenty for 4,000 px.
    public static let largeMaxBytes = 25 * 1_024 * 1_024

    public static let mimeTypes: [String: String] = [
        "pdf": "application/pdf",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "heic": "image/heic",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ]

    /// The content types the Files picker offers.
    public static var allowedContentTypes: [UTType] {
        allowedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    public enum Problem: Error, Equatable, Sendable {
        case unsupportedType
        case tooLarge
        case empty

        public var message: String {
            switch self {
            case .unsupportedType: "This file type can't be uploaded. Use PDF, photos (JPG, PNG, HEIC), Word or Excel."
            case .tooLarge: "This file is too large to upload. Photos must be under 4 MB, and documents under 25 MB."
            case .empty: "This file is empty."
            }
        }
    }

    public static func fileExtension(of fileName: String) -> String {
        (fileName as NSString).pathExtension.lowercased()
    }

    public static func isAllowed(fileName: String) -> Bool {
        allowedExtensions.contains(fileExtension(of: fileName))
    }

    /// "Photo {yyyy-MM-dd HH:mm}" for camera photos (spec §6.10).
    public static func cameraTitle(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        style.locale = Locale(identifier: "en_US_POSIX")
        return "Photo \(date.formatted(style))"
    }

    /// The original file name without its extension, for everything except camera photos.
    public static func title(forFileName fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Untitled" : base
    }

    /// Checks type and size, downscales photos, and builds the upload.
    public static func prepare(data: Data, fileName: String, title: String, documentLimit: Int = maxBytes) throws(Problem) -> FileUpload {
        guard !data.isEmpty else { throw .empty }
        let ext = fileExtension(of: fileName)
        guard allowedExtensions.contains(ext), let mimeType = mimeTypes[ext] else { throw .unsupportedType }

        guard ["jpg", "jpeg", "png", "heic"].contains(ext) else {
            guard data.count <= documentLimit else { throw .tooLarge }
            return FileUpload(fileName: fileName, title: title, mimeType: mimeType, data: data)
        }

        // Photos never carry their location to Salesforce (App Privacy: location isn't collected).
        let located = ImageDownscaler.downscale(data, maxPixels: maxPhotoPixels) ?? data
        let downscaled = ImageDownscaler.stripLocation(located) ?? located
        if downscaled.count <= maxBytes {
            return FileUpload(fileName: fileName, title: title, mimeType: mimeType, data: downscaled)
        }
        // Still over the server's limit: shrink further. HEIC stays HEIC; JPEG and PNG become JPEG.
        guard let fitted = ImageDownscaler.fit(data, maxBytes: maxBytes) else { throw .tooLarge }
        let fittedExtension = fitted.isHEIC ? "heic" : "jpg"
        let fittedName = (fileName as NSString).deletingPathExtension + "." + fittedExtension
        return FileUpload(fileName: fittedName, title: title, mimeType: mimeTypes[fittedExtension]!, data: fitted.data)
    }

    /// A file extension for Quick Look, from the file's bytes, falling back to Salesforce's
    /// FileType ("PDF", "JPG", "WORD_X", ...).
    public static func previewExtension(for data: Data, fileType: String?) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.count >= 12, String(decoding: bytes[4..<12], as: UTF8.self).hasPrefix("ftyphei") { return "heic" }

        switch fileType?.uppercased() {
        case "PDF": return "pdf"
        case "JPG", "JPEG": return "jpg"
        case "PNG": return "png"
        case "HEIC": return "heic"
        case "WORD": return "doc"
        case "WORD_X": return "docx"
        case "EXCEL": return "xls"
        case "EXCEL_X": return "xlsx"
        default: return "dat"
        }
    }
}

/// Shrinks photos so the longest side is at most `maxPixels`, keeping the original format
/// (HEIC stays HEIC). Returns nil when the image is already small enough or can't be read.
public enum ImageDownscaler {
    /// The photo without its GPS location, copied losslessly (no re-encoding). Nil if it can't be read.
    public static func stripLocation(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else { return nil }
        return output as Data
    }

    public static func downscale(_ data: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxPixels else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        // The thumbnail already applied the orientation, so write it as "up".
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Re-encodes a photo at decreasing sizes until it's at most `maxBytes`. HEIC stays HEIC;
    /// anything else becomes JPEG (PNG can't compress a photo enough). Nil if it can't be read.
    public static func fit(_ data: Data, maxBytes: Int) -> (data: Data, isHEIC: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        let isHEIC = (type as String) == "public.heic"
        let outputType = (isHEIC ? "public.heic" : "public.jpeg") as CFString

        for (pixels, quality) in [(4_000, 0.8), (3_200, 0.75), (2_560, 0.75), (2_048, 0.7), (1_600, 0.7)] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, outputType, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImagePropertyOrientation: 1
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            if output.length <= maxBytes {
                return (output as Data, isHEIC)
            }
        }
        return nil
    }
}
