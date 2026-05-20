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

// MARK: - SpaceManager

final class SpaceManager: ObservableObject {

    static let shared = SpaceManager()

    @Published private(set) var currentSpaceID: CGSSpaceID = 0
    @Published private(set) var allSpaceIDs: [CGSSpaceID] = []

    private var spaceChangeObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    private init() {
        refresh()

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        // Poll at 30fps to catch space changes faster than the notification.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let detected = CGSGetActiveSpace(CGSMainConnectionID())
            if detected != 0 && detected != self.currentSpaceID {
                DispatchQueue.main.async { self.refresh() }
            }
        }
        pollTimer?.tolerance = 0.005
    }

    deinit {
        pollTimer?.invalidate()
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public

    func refresh() {
        let cid        = CGSMainConnectionID()
        let newSpaceID = CGSGetActiveSpace(cid)
        guard newSpaceID != 0 else {
            Log.spaces.error("CGSGetActiveSpace returned 0 — window server connection may not be ready")
            return
        }
        currentSpaceID = newSpaceID
        allSpaceIDs    = fetchAllSpaceIDs(connectionID: cid)
        Log.spaces.info("Active space: \(newSpaceID), total: \(self.allSpaceIDs.count)")
    }

    func index(of spaceID: CGSSpaceID) -> Int {
        (self.allSpaceIDs.firstIndex(of: spaceID) ?? 0) + 1
    }

    var currentSpaceIndex: Int { index(of: currentSpaceID) }
    var spaceCount: Int        { max(self.allSpaceIDs.count, 1)  }

    // MARK: - Private

    private func fetchAllSpaceIDs(connectionID cid: CGSConnectionID) -> [CGSSpaceID] {
        guard let raw      = CGSCopyManagedDisplaySpaces(cid),
              let displays = raw as? [[String: Any]] else {
            Log.spaces.warning("CGSCopyManagedDisplaySpaces returned nil; using current space only")
            return self.currentSpaceID != 0 ? [self.currentSpaceID] : []
        }

        let ids: [CGSSpaceID] = displays.flatMap { display -> [CGSSpaceID] in
            guard let spaces = display["Spaces"] as? [[String: Any]] else { return [] }
            return spaces.compactMap { $0["id64"] as? CGSSpaceID }
        }

        return ids.isEmpty ? (self.currentSpaceID != 0 ? [self.currentSpaceID] : []) : ids
    }
}
