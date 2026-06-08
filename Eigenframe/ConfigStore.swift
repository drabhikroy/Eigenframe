import Foundation
import ServiceManagement
import OSLog

// MARK: - Assignment

/// A single Space-to-media mapping keyed by Space index (1-based).
/// Space index is stable across reboots; CGSSpaceID is not.
struct Assignment: Codable, Equatable {
    let spaceIndex: Int
    let mediaPath:  String

    enum CodingKeys: String, CodingKey {
        case spaceIndex = "space_index"
        case mediaPath  = "media_path"
    }
}

// MARK: - PersistedStore

private struct PersistedStore: Codable {
    var version:      Int          = 1
    var assignments:  [Assignment] = []
    var pauseOnTyping:  Bool        = false
    var launchAtLogin:  Bool        = false
}

// MARK: - ConfigStore

@MainActor
final class ConfigStore: ObservableObject {

    static let shared = ConfigStore()

    @Published private(set) var assignments: [Assignment] = []
    @Published var pauseOnTyping: Bool = false {
        didSet { save() }
    }

    @Published var launchAtLogin: Bool = false {
        didSet {
            save()
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                    Log.config.info("Launch at login registered — status: \(SMAppService.mainApp.status.rawValue)")
                } else {
                    try SMAppService.mainApp.unregister()
                    Log.config.info("Launch at login unregistered")
                }
            } catch {
                Log.config.error("SMAppService failed: \(error.localizedDescription)")
                // Roll back the toggle if registration failed
                DispatchQueue.main.async {
                    self.launchAtLogin = !self.launchAtLogin
                }
            }
        }
    }

    private let storeURL: URL
    private let encoder  = JSONEncoder()
    private let decoder  = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = support.appendingPathComponent("Eigenframe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("assignments.json")
        load()
    }

    // MARK: - Querying

    func mediaPath(forSpaceIndex index: Int) -> String? {
        assignments.first { $0.spaceIndex == index }?.mediaPath
    }

    // MARK: - Mutating

    func setMediaPath(_ path: String?, forSpaceIndex index: Int) {
        if let path {
            // Do not gate on fileExists — it returns false for files outside
            // the app sandbox and for iCloud Drive files not yet downloaded.
            // AVFoundation and NSImage handle missing files gracefully at
            // render time, so we trust the path and let the engine report errors.
            if let i = assignments.firstIndex(where: { $0.spaceIndex == index }) {
                assignments[i] = Assignment(spaceIndex: index, mediaPath: path)
            } else {
                assignments.append(Assignment(spaceIndex: index, mediaPath: path))
            }
            Log.config.info("Assigned space index \(index) -> \(path)")
        } else {
            assignments.removeAll { $0.spaceIndex == index }
            Log.config.info("Cleared assignment for space index \(index)")
        }
        save()
    }

    /// Removes assignments for indices beyond the current Space count.
    func pruneStaleAssignments(knownIndices: Set<Int>) {
        let before = assignments.count
        assignments.removeAll { !knownIndices.contains($0.spaceIndex) }
        let removed = before - assignments.count
        if removed > 0 {
            Log.config.info("Pruned \(removed) stale assignment(s)")
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try encoder.encode(PersistedStore(version: 1, assignments: assignments, pauseOnTyping: pauseOnTyping, launchAtLogin: launchAtLogin))
            try data.write(to: storeURL, options: .atomic)
        } catch {
            Log.config.error("Failed to save: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            Log.config.info("No assignments file found; starting fresh")
            return
        }
        do {
            let data  = try Data(contentsOf: storeURL)
            let store = try decoder.decode(PersistedStore.self, from: data)
            // Trust persisted paths without checking existence — files may be
            // on external drives, network shares, or iCloud and temporarily unavailable.
            // The engine will log an error if a file cannot be opened at render time.
            assignments   = store.assignments
            pauseOnTyping  = store.pauseOnTyping
            // Sync with actual SMAppService registration status rather than
            // the saved preference — the user may have changed it in System Settings.
            let actualStatus = SMAppService.mainApp.status
            launchAtLogin = (actualStatus == .enabled)
            Log.config.info("Launch at login status on load: \(actualStatus.rawValue)")
            Log.config.info("Loaded \(self.assignments.count) valid assignment(s)")
        } catch {
            Log.config.error("Failed to load assignments: \(error.localizedDescription)")
            assignments = []
        }
    }
}
