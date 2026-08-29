import Foundation
import OSLog

// MARK: - MediaPath

/// Central validation for every media path that reaches the renderer.
///
/// Eigenframe runs unsandboxed, starts at login, and reads its assignment list
/// from a plain JSON file in Application Support. Any process running as the
/// user can rewrite that file, so by the time the engine sees a path it is
/// untrusted input rather than something the user picked in a panel. Every path
/// is therefore re-checked at the moment it is used, not only when it is chosen,
/// because the file on disk can change between those two moments.
///
/// The checks are deliberately structural. They do NOT require the file to
/// exist: a path that resolves to nothing is passed through unchanged so that
/// iCloud Drive files which have not been materialised yet keep working exactly
/// as before. What they do reject is a path that resolves to something which is
/// not an ordinary file — a directory, a device node, a fifo, a socket. Those
/// are the shapes that turn "render this media" into "block a thread forever on
/// /dev/fd/x" or "hand a character device to AVFoundation".
enum MediaPath {

    // MARK: - Limits

    /// PATH_MAX on Darwin. Anything longer cannot name a real file.
    static let maxLength = 1024

    /// Ceiling on stored assignments. macOS tops out well below this in
    /// practice, so it never bites a real user; it stops a rewritten config
    /// file from asking the engine to build thousands of wallpaper windows.
    static let maxAssignments = 64

    // MARK: - Rejection reasons

    enum Rejection: Error, CustomStringConvertible {
        case empty
        case notAbsolute
        case tooLong
        case unsupportedType
        case notRegularFile

        var description: String {
            switch self {
            case .empty:           return "empty path"
            case .notAbsolute:     return "not an absolute path"
            case .tooLong:         return "path is longer than \(MediaPath.maxLength) bytes"
            case .unsupportedType: return "file extension is not a supported image or video type"
            case .notRegularFile:  return "path does not point at an ordinary file"
            }
        }
    }

    // MARK: - Validation

    /// Canonicalises a path and checks it is safe to hand to AVFoundation or
    /// ImageIO. Returns the resolved absolute path on success.
    static func validate(_ path: String) -> Result<String, Rejection> {
        guard !path.isEmpty else { return .failure(.empty) }
        guard path.hasPrefix("/") else { return .failure(.notAbsolute) }
        guard path.utf8.count <= maxLength else { return .failure(.tooLong) }

        // Resolve symlinks and remove any ".." components before any other
        // check, so the extension test and the file-type test both apply to the
        // file that will actually be opened rather than to the name given.
        let resolved = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard resolved.path.utf8.count <= maxLength else { return .failure(.tooLong) }
        guard MediaType.from(url: resolved) != nil else { return .failure(.unsupportedType) }

        // If the item exists, it has to be an ordinary file. If it does not
        // exist we allow it through: that is the iCloud placeholder case, and
        // the engine already handles a file it cannot open.
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        if let attributes,
           let type = attributes[.type] as? FileAttributeType,
           type != .typeRegular {
            return .failure(.notRegularFile)
        }

        return .success(resolved.path)
    }

    /// Convenience wrapper that logs the reason and returns nil on rejection.
    static func validated(_ path: String, context: String) -> String? {
        switch validate(path) {
        case .success(let clean):
            return clean
        case .failure(let reason):
            // The path itself is logged privately; the reason is public so the
            // rejection is visible in Console without leaking the user's
            // file layout to anything reading the unified log.
            Log.config.warning(
                "Rejected media path during \(context, privacy: .public): \(reason.description, privacy: .public) — \(path, privacy: .private)"
            )
            return nil
        }
    }
}
