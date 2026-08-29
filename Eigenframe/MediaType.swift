import UniformTypeIdentifiers

// MARK: - MediaType

/// Classifies a file URL as a supported video, supported image, or unsupported.
///
/// Detection uses the file extension rather than UTType conformance checks
/// because some container formats (e.g. MKV, WebM) lack first-class UTType
/// definitions on older macOS versions.
enum MediaType: Equatable {
    case video
    case image

    // MARK: - Supported extensions

    /// Video container extensions supported by AVFoundation on macOS 14+.
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "hevc", "3gp", "mp4v"
    ]

    /// Image format extensions supported by NSImage / ImageIO on macOS 14+.
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp"
    ]

    // MARK: - Factory

    /// Returns `nil` for unsupported file types rather than an `.unsupported`
    /// case, which forces callers to handle the nil path explicitly.
    static func from(url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    // MARK: - Open panel helpers

    /// UTTypes accepted by NSOpenPanel. Covers both named types and extension-
    /// based fallbacks for formats without a canonical UTType.
    static var allowedContentTypes: [UTType] {
        let named: [UTType] = [
            .mpeg4Movie, .quickTimeMovie, .avi, .jpeg, .png,
            .heic, .gif, .webP, .tiff, .bmp
        ]
        let byExtension: [UTType] = ["mkv", "webm", "m4v", "hevc", "3gp", "heif"]
            .compactMap { UTType(filenameExtension: $0) }

        // Deduplicate while preserving order.
        var seen  = Set<UTType>()
        return (named + byExtension).filter { seen.insert($0).inserted }
    }

    // MARK: - Display

    /// Short uppercase label shown in the UI badge.
    var badgeLabel: String {
        switch self {
        case .video: return "VIDEO"
        case .image: return "IMAGE"
        }
    }
}
