import Cocoa
import OSLog

// MARK: - CGS Private API

typealias CGSConnectionID = UInt32
typealias CGSSpaceID      = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

// Note: CGSManagedDisplaySetCurrentSpace is intentionally not declared here.
// Programmatic space switching via that API changes internal state correctly
// but does not trigger macOS's visual transition animation from within a
// GUI app process. Users should use Control+Number keyboard shortcuts instead.

// MARK: - SpaceInfo

/// One Mission Control Space.
///
/// `uuid` is macOS's own persistent identifier for the Space, read from
/// `CGSCopyManagedDisplaySpaces`. It is the correct key for remembering which
/// wallpaper belongs to which desktop because — unlike the two alternatives —
/// it survives BOTH of the events that matter:
///
///   • index (position in the list): changes when Spaces are reordered in
///     Mission Control, so it cannot follow a desktop that moves.
///   • id64 (`CGSSpaceID`): regenerated on every login, so it cannot survive
///     a reboot.
///   • uuid: stable across reordering AND across reboots. This is what macOS
///     itself uses to persist per-Space state.
struct SpaceInfo: Equatable, Identifiable {
    let uuid: String
    let id64: CGSSpaceID
    var id: String { uuid }
}

// MARK: - SpaceManager

final class SpaceManager: ObservableObject {

    static let shared = SpaceManager()

    /// All Spaces in current Mission Control order. Identity is the uuid.
    @Published private(set) var spaces: [SpaceInfo] = []

    /// Persistent uuid of the currently active Space.
    @Published private(set) var currentSpaceUUID: String = ""

    /// Active Space id64. Retained only for fast active-space detection in the
    /// poll below; never used as a storage key.
    private(set) var currentSpaceID: CGSSpaceID = 0

    private var spaceChangeObserver: NSObjectProtocol?
    private var pollTimer: DispatchSourceTimer?
    private var spaceListPollTimer: DispatchSourceTimer?

    private init() {
        refresh()

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        // Both pollers use DispatchSourceTimer on the MAIN queue rather than
        // Timer.scheduledTimer. Two reasons:
        //
        //   1. `spaces` and `currentSpaceUUID` are @Published. SwiftUI only
        //      reliably re-renders when those are mutated on the main thread.
        //      A run-loop Timer fires on whatever thread created it, so an
        //      off-main mutation updates the model but leaves the UI stale
        //      until something else forces a redraw (e.g. the Refresh button).
        //   2. Timer.scheduledTimer attaches to the current thread's run loop
        //      in .default mode — it never fires if that run loop isn't running,
        //      and stalls during UI tracking. A main-queue dispatch source has
        //      neither failure mode.

        // 60Hz: catches active-space switches faster than the notification.
        // Only detects a CHANGE OF ACTIVE SPACE (id64 differs) — it cannot see
        // reordering, since the active space's own id64 doesn't change when
        // Spaces are rearranged in Mission Control.
        let active = DispatchSource.makeTimerSource(queue: .main)
        active.schedule(deadline: .now() + 1.0 / 60.0,
                        repeating: 1.0 / 60.0,
                        leeway: .milliseconds(5))
        active.setEventHandler { [weak self] in
            guard let self else { return }
            let detected = CGSGetActiveSpace(CGSMainConnectionID())
            if detected != 0 && detected != self.currentSpaceID {
                self.refresh()
            }
        }
        active.resume()
        pollTimer = active

        // 5Hz: re-fetches the full ordered Space list to catch what the poll
        // above cannot — reordering, adding, or removing a desktop without
        // switching to a different one. macOS publishes no notification for
        // this, and private CGS notifications are version-fragile, so a light
        // periodic poll is the reliable option. refresh() republishes only when
        // the fetched list actually differs, so idle cost is negligible.
        let list = DispatchSource.makeTimerSource(queue: .main)
        list.schedule(deadline: .now() + 0.2,
                      repeating: 0.2,
                      leeway: .milliseconds(50))
        list.setEventHandler { [weak self] in
            self?.refresh()
        }
        list.resume()
        spaceListPollTimer = list
    }

    deinit {
        pollTimer?.cancel()
        spaceListPollTimer?.cancel()
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public

    func refresh() {
        // All @Published mutations below must happen on the main thread or
        // SwiftUI may not re-render. Callers are main-queue today, but this
        // guard makes refresh() safe from anywhere.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }

        let cid      = CGSMainConnectionID()
        let activeID = CGSGetActiveSpace(cid)
        guard activeID != 0 else {
            Log.spaces.error("CGSGetActiveSpace returned 0 — window server connection may not be ready")
            return
        }

        let fetched = fetchAllSpaces(connectionID: cid)
        currentSpaceID = activeID

        // Called from two pollers (60Hz active-space, 5Hz full-list), so only
        // republish and log when something actually changed — otherwise every
        // tick would trigger a SwiftUI re-render and log line for no reason.
        // Array equality is order-sensitive, so a Mission Control reorder
        // registers here even though the set of uuids is identical.
        let listChanged = fetched != spaces
        if listChanged {
            let reordered = Set(fetched.map(\.uuid)) == Set(spaces.map(\.uuid))
                && fetched.count == spaces.count
                && !spaces.isEmpty
            spaces = fetched
            if reordered {
                Log.spaces.info("Space order changed: \(fetched.map(\.uuid).joined(separator: ", "))")
            } else {
                Log.spaces.info("Space list changed — now \(fetched.count) space(s)")
            }
        }

        // Resolve the active Space's uuid from its id64.
        let resolvedUUID: String
        if let match = fetched.first(where: { $0.id64 == activeID }) {
            resolvedUUID = match.uuid
        } else if let first = fetched.first {
            // Active space not present in the managed list (rare, e.g. a
            // transient system space); fall back to the first known space.
            resolvedUUID = first.uuid
        } else {
            resolvedUUID = currentSpaceUUID
        }
        if resolvedUUID != currentSpaceUUID {
            currentSpaceUUID = resolvedUUID
            Log.spaces.info("Active space uuid: \(resolvedUUID), total: \(self.spaces.count)")
        }
    }

    /// 1-based display position of a Space. For UI labels only — never a key.
    func index(ofUUID uuid: String) -> Int {
        (spaces.firstIndex { $0.uuid == uuid } ?? 0) + 1
    }

    var orderedUUIDs:      [String] { spaces.map { $0.uuid } }
    var currentSpaceIndex: Int      { index(ofUUID: currentSpaceUUID) }
    var spaceCount:        Int      { max(spaces.count, 1) }

    // MARK: - Private

    private func fetchAllSpaces(connectionID cid: CGSConnectionID) -> [SpaceInfo] {
        guard let raw      = CGSCopyManagedDisplaySpaces(cid),
              let displays = raw as? [[String: Any]] else {
            Log.spaces.warning("CGSCopyManagedDisplaySpaces returned nil; using active space only")
            return fallbackSpaces()
        }

        var result: [SpaceInfo] = []
        for display in displays {
            guard let spaceDicts = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaceDicts {
                guard let id64 = space["id64"] as? CGSSpaceID else { continue }
                // Prefer the persistent uuid. If the key is ever absent on some
                // OS build, synthesize a stable per-session fallback from id64 so
                // the app still functions — that fallback simply won't survive a
                // reboot (same limitation the old scheme always had).
                let uuid = (space["uuid"] as? String) ?? "id64:\(id64)"
                result.append(SpaceInfo(uuid: uuid, id64: id64))
            }
        }

        return result.isEmpty ? fallbackSpaces() : result
    }

    private func fallbackSpaces() -> [SpaceInfo] {
        guard currentSpaceID != 0 else { return [] }
        return [SpaceInfo(uuid: "id64:\(currentSpaceID)", id64: currentSpaceID)]
    }
}
