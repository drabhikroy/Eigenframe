import Foundation
import ServiceManagement
import OSLog

// MARK: - Assignment

/// A single Space-to-media mapping keyed by the Space's persistent uuid.
///
/// The uuid (from `CGSCopyManagedDisplaySpaces`) is stable across reboots AND
/// across reordering Spaces in Mission Control, so a wallpaper stays with its
/// desktop when the desktop is moved. (Previous versions keyed by 1-based index,
/// which followed the slot rather than the desktop — see the v1 migration below.)
struct Assignment: Codable, Equatable {
    let spaceUUID: String
    let mediaPath: String

    enum CodingKeys: String, CodingKey {
        case spaceUUID = "space_uuid"
        case mediaPath = "media_path"
    }
}

// MARK: - Persisted Stores

private struct PersistedStore: Codable {
    var version:       Int          = 2
    var assignments:   [Assignment] = []
    var pauseOnTyping: Bool         = false
    var launchAtLogin: Bool         = false
}

/// Legacy (version 1) on-disk shape: assignments keyed by 1-based Space index.
/// Retained only so we can read an old file once and migrate it to uuid keys.
private struct LegacyAssignmentV1: Codable {
    let spaceIndex: Int
    let mediaPath:  String
    enum CodingKeys: String, CodingKey {
        case spaceIndex = "space_index"
        case mediaPath  = "media_path"
    }
}

private struct LegacyStoreV1: Codable {
    var version:       Int
    var assignments:   [LegacyAssignmentV1]
    var pauseOnTyping: Bool?
    var launchAtLogin: Bool?
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

    /// Index→path pairs read from a v1 file, waiting to be mapped to uuids once
    /// the current Space order is known. Empty on a fresh install or v2 file.
    private var pendingIndexAssignments: [Int: String] = [:]
    private(set) var needsIndexMigration = false

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

    func mediaPath(forSpaceUUID uuid: String) -> String? {
        assignments.first { $0.spaceUUID == uuid }?.mediaPath
    }

    // MARK: - Mutating

    func setMediaPath(_ path: String?, forSpaceUUID uuid: String) {
        if let path {
            // Do not gate on fileExists — it returns false for files outside
            // the app sandbox and for iCloud Drive files not yet downloaded.
            // AVFoundation and NSImage handle missing files gracefully at
            // render time, so we trust the path and let the engine report errors.
            if let i = assignments.firstIndex(where: { $0.spaceUUID == uuid }) {
                assignments[i] = Assignment(spaceUUID: uuid, mediaPath: path)
            } else {
                assignments.append(Assignment(spaceUUID: uuid, mediaPath: path))
            }
            Log.config.info("Assigned space \(uuid) -> \(path)")
        } else {
            assignments.removeAll { $0.spaceUUID == uuid }
            Log.config.info("Cleared assignment for space \(uuid)")
        }
        save()
    }

    /// Removes assignments whose Space no longer exists.
    func pruneStaleAssignments(knownUUIDs: Set<String>) {
        let before = assignments.count
        assignments.removeAll { !knownUUIDs.contains($0.spaceUUID) }
        let removed = before - assignments.count
        if removed > 0 {
            Log.config.info("Pruned \(removed) stale assignment(s)")
            save()
        }
    }

    // MARK: - Migration

    /// Converts queued v1 index-based assignments into uuid-based ones using the
    /// current Space order: old index *i* maps to the uuid of the *i*-th current
    /// Space. Best-effort and one-shot — it assumes the current ordering matches
    /// what the user last configured, which is the most faithful reconstruction
    /// possible since v1 never recorded uuids. Runs once, after SpaceManager has
    /// a populated ordered list, then persists the v2 store.
    func migrateIndexAssignmentsIfNeeded(orderedUUIDs: [String]) {
        guard needsIndexMigration, !orderedUUIDs.isEmpty else { return }

        var migrated: [Assignment] = []
        for (offset, uuid) in orderedUUIDs.enumerated() {
            let index = offset + 1
            if let path = pendingIndexAssignments[index] {
                migrated.append(Assignment(spaceUUID: uuid, mediaPath: path))
            }
        }

        assignments             = migrated
        pendingIndexAssignments = [:]
        needsIndexMigration     = false
        save()
        Log.config.info("Migrated \(migrated.count) assignment(s) from index keys to uuid keys")
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try encoder.encode(PersistedStore(
                version:       2,
                assignments:   assignments,
                pauseOnTyping: pauseOnTyping,
                launchAtLogin: launchAtLogin
            ))
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
            let data    = try Data(contentsOf: storeURL)
            let version = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["version"] as? Int ?? 1

            if version >= 2 {
                let store     = try decoder.decode(PersistedStore.self, from: data)
                assignments   = store.assignments
                pauseOnTyping = store.pauseOnTyping
            } else {
                // v1 file: stash index→path pairs; the engine calls
                // migrateIndexAssignmentsIfNeeded once Spaces are known.
                let legacy = try decoder.decode(LegacyStoreV1.self, from: data)
                pendingIndexAssignments = Dictionary(
                    legacy.assignments.map { ($0.spaceIndex, $0.mediaPath) },
                    uniquingKeysWith: { first, _ in first }
                )
                needsIndexMigration = !pendingIndexAssignments.isEmpty
                pauseOnTyping       = legacy.pauseOnTyping ?? false
                assignments         = []
                Log.config.info("Loaded v1 store; \(self.pendingIndexAssignments.count) assignment(s) queued for uuid migration")
            }

            // Sync with actual SMAppService registration status rather than the
            // saved preference — the user may have changed it in System Settings.
            let actualStatus = SMAppService.mainApp.status
            launchAtLogin = (actualStatus == .enabled)
            Log.config.info("Launch at login status on load: \(actualStatus.rawValue)")
            Log.config.info("Loaded \(self.assignments.count) assignment(s)")
        } catch {
            Log.config.error("Failed to load assignments: \(error.localizedDescription)")
            assignments = []
        }
    }
}
