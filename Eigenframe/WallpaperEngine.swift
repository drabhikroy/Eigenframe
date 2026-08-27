import Cocoa
import AVFoundation
import Combine
import CoreGraphics
import OSLog

@MainActor
final class WallpaperEngine: ObservableObject {

    @Published var isPaused: Bool = false {
        didSet {
            isPaused ? pauseAll() : resumeCurrent()
            Log.engine.info("Playback \(self.isPaused ? "paused" : "resumed")")
        }
    }

    private let spaceManager = SpaceManager.shared
    private let config       = ConfigStore.shared

    // Keyed by the Space's persistent uuid. That is stable across reboots and
    // across reordering in Mission Control, so a window stays bound to its desktop.
    private var players:      [String: AVQueuePlayer]  = [:]
    private var loopers:      [String: AVPlayerLooper] = [:]
    private var windows:      [String: NSWindow]       = [:]
    private var activePaths:  [String: String]         = [:]  // what path each window is showing

    private var cancellables    = Set<AnyCancellable>()
    private var isTypingPaused  = false
    private var keyboardMonitor: Any? = nil
    private(set) var eventTap: CFMachPort? = nil
    private var typingTimer:     Timer? = nil

    // MARK: - Lifecycle

    func start() {
        // Wait for SpaceManager to settle, migrate any legacy index-keyed
        // assignments to uuids using the current order, then sync.
        spaceManager.$spaces
            .filter { !$0.isEmpty }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] spaces in
                guard let self else { return }
                self.config.migrateIndexAssignmentsIfNeeded(orderedUUIDs: spaces.map { $0.uuid })
                self.syncToAssignments()
            }
            .store(in: &cancellables)

        spaceManager.$currentSpaceUUID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] uuid in
                self?.handleSpaceChange(toUUID: uuid)
            }
            .store(in: &cancellables)

        config.$assignments
            .dropFirst() // Skip initial value; first() above handles initial sync.
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncToAssignments()
            }
            .store(in: &cancellables)

        setupKeyboardMonitor()
        Log.engine.info("WallpaperEngine started")
    }

    func stop() {
        teardownAll()
        cancellables.removeAll()
        teardownKeyboardMonitor()
        Log.engine.info("WallpaperEngine stopped")
    }

    // MARK: - Keyboard Monitoring

    private func setupKeyboardMonitor() {
        // Local monitor always works. It catches keys when Eigenframe has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleTypingEvent()
            return event
        }

        // CGEventTap in listen-only mode requires Input Monitoring permission.
        // Unlike NSEvent.addGlobalMonitorForEvents (which silently returns non-nil
        // but never fires), CGEventTap returns nil when permission is denied.
        // That gives us a reliable way to detect missing permission.
        //
        // Only attempt this when the user actually wants pause-while-typing.
        // Attempting it unconditionally meant users who never enable the feature
        // were still nagged for a permission they don't need.
        guard config.pauseOnTyping else {
            Log.engine.info("Pause-on-typing disabled. Skipping event tap setup")
            return
        }
        setupEventTap()
    }

    /// Called by the UI when the user enables pause-while-typing.
    /// Attempts to install the event tap; shows the Input Monitoring alert if denied.
    func requestTypingDetection() {
        guard eventTap == nil else { return }
        alertSuppressedForSession = false
        tapAttempt = 0
        setupEventTap()
    }

    /// Attempts made in the current retry cycle.
    private var tapAttempt = 0

    /// Set once the guide has been shown, so a single launch
    /// never nags more than once.
    private var alertSuppressedForSession = false

    /// Number of times to retry before concluding permission is genuinely absent.
    private static let maxTapAttempts = 3

    private func setupEventTap() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, _, userInfo -> Unmanaged<CGEvent>? in
                if let ptr = userInfo {
                    let engine = Unmanaged<WallpaperEngine>.fromOpaque(ptr).takeUnretainedValue()
                    DispatchQueue.main.async { engine.handleTypingEvent() }
                }
                return nil
            },
            userInfo: selfPtr
        ) else {
            // A nil tap usually means permission is missing, though not always.
            // TCC is occasionally not ready in the first moments after launch,
            // so retry a couple of times before concluding anything.
            //
            // CGPreflightListenEventAccess answers the permission question
            // directly, so when it says the permission is absent there is no
            // reason to keep retrying. That turns what used to be a wait of
            // roughly fifteen seconds into well under one.
            tapAttempt += 1

            let permissionKnownAbsent = !CGPreflightListenEventAccess()

            if !permissionKnownAbsent && tapAttempt < Self.maxTapAttempts {
                let delay = 0.2 * Double(tapAttempt)
                Log.engine.info("CGEventTap nil but permission reads as granted (attempt \(self.tapAttempt)/\(Self.maxTapAttempts)). Retrying in \(delay)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.eventTap == nil, self.config.pauseOnTyping else { return }
                    self.setupEventTap()
                }
                return
            }

            Log.engine.warning("Input Monitoring permission not granted. Showing the setup guide")
            guard !alertSuppressedForSession else { return }
            // Short pause so the guide arrives just after the click that caused
            // it, rather than on top of it. The window fades in on arrival.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showInputMonitoringAlert()
            }
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        tapAttempt = 0
        Log.engine.info("CGEventTap installed. Typing detection active")
    }

    private func showInputMonitoringAlert() {
        // Never nag more than once per launch.
        alertSuppressedForSession = true

        PermissionGuideWindowController.shared.show(
            onOpenSettings: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            },
            onOpenHelp: {
                guard let helpURL = Bundle.main.url(forResource: "Help", withExtension: "html") else {
                    Log.engine.error("Help.html not found in app bundle")
                    return
                }
                NSWorkspace.shared.open(helpURL)
            },
            onPermissionGranted: { [weak self] in
                // The guide saw the permission start working, so install the
                // real tap now. In most cases this means typing detection
                // starts immediately, with no need to relaunch.
                guard let self else { return }
                self.tapAttempt = 0
                self.setupEventTap()
            }
        )
    }

    private func handleTypingEvent() {
        guard config.pauseOnTyping, !isPaused else { return }
        if !isTypingPaused {
            isTypingPaused = true
            players.values.forEach { $0.rate = 0 }
            Log.engine.info("Typing detected. Wallpapers paused")
        }
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isTypingPaused = false
            if !self.isPaused { self.resumeCurrent() }
            Log.engine.info("Typing stopped. Wallpapers resumed")
        }
    }

    private func teardownKeyboardMonitor() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        typingTimer?.invalidate()
        typingTimer = nil
        isTypingPaused = false
    }

    // MARK: - Space Switching

    private func handleSpaceChange(toUUID uuid: String) {
        guard !isPaused else { return }

        // Use CATransaction to make ALL alpha changes atomic and instant.
        // This prevents any intermediate compositing frames from being visible.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)

        for (key, window) in windows {
            if key == uuid {
                // Bring the active window to the front of the window order
                // so it composites above any system transition layers.
                window.alphaValue = 1.0
                window.orderFrontRegardless()
                players[key]?.play()
            } else {
                window.alphaValue = 0.0
            }
        }

        CATransaction.commit()

        // Force an immediate display update to flush the compositor.
        windows[uuid]?.contentView?.layer?.setNeedsDisplay()
        windows[uuid]?.contentView?.layer?.displayIfNeeded()

        Log.engine.info("Switched to space uuid \(uuid)")
    }

    // MARK: - Syncing

    private func syncToAssignments() {
        let assignments   = config.assignments
        let assignedUUIDs = Set(assignments.map { $0.spaceUUID })

        // Tear down windows for spaces that no longer have assignments.
        for uuid in Set(windows.keys).subtracting(assignedUUIDs) {
            teardown(spaceUUID: uuid)
        }

        // Set up or update windows for each assignment.
        for assignment in assignments {
            let uuid = assignment.spaceUUID
            let path = assignment.mediaPath

            // Skip only if the window exists AND is already showing this exact path.
            // Compare against activePaths (what the window is actually showing),
            // not config (which already has the new value after a drop).
            if windows[uuid] != nil, activePaths[uuid] == path { continue }

            teardown(spaceUUID: uuid)

            let url = URL(fileURLWithPath: path)
            guard let type = MediaType.from(url: url) else {
                Log.engine.warning("Unsupported media type for space \(uuid): \(path)")
                continue
            }

            switch type {
            case .video: setupVideo(for: uuid, url: url)
            case .image: setupImage(for: uuid, url: url)
            }
        }

        handleSpaceChange(toUUID: spaceManager.currentSpaceUUID)
        Log.engine.info("Synced \(assignments.count) assignment(s)")
    }

    // MARK: - Video Setup

    private func setupVideo(for spaceUUID: String, url: URL) {
        let asset  = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item   = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer  = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill

        if let screen = NSScreen.main {
            layer.contentsScale = screen.backingScaleFactor
        }

        guard let window   = makeWallpaperWindow(),
              let hostView = window.contentView else {
            Log.engine.error("Failed to create wallpaper window for space \(spaceUUID)")
            return
        }

        layer.frame = hostView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostView.layer?.addSublayer(layer)

        // Pre-buffer by playing immediately. The window is transparent so this
        // is invisible, but the GPU pipeline stays warm for instant switching.
        player.play()

        players[spaceUUID] = player
        loopers[spaceUUID] = looper
        windows[spaceUUID] = window

        activePaths[spaceUUID] = url.path
        Log.engine.info("Video set for space \(spaceUUID): \(url.lastPathComponent)")
    }

    // MARK: - Image Setup

    private func setupImage(for spaceUUID: String, url: URL) {
        let image: NSImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = NSImage(cgImage: cgImage, size: .zero)
        } else {
            image = NSImage(contentsOf: url)
        }

        guard let image,
              let window   = makeWallpaperWindow(),
              let hostView = window.contentView else {
            Log.engine.error("Failed to set up image for space \(spaceUUID)")
            return
        }

        let imageView = NSImageView(frame: hostView.bounds)
        imageView.image            = image
        imageView.imageScaling     = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer       = true
        if let screen = NSScreen.main {
            imageView.layer?.contentsScale = screen.backingScaleFactor
        }
        hostView.addSubview(imageView)
        windows[spaceUUID] = window

        activePaths[spaceUUID] = url.path
        Log.engine.info("Image set for space \(spaceUUID): \(url.lastPathComponent)")
    }

    // MARK: - Window Factory

    private func makeWallpaperWindow() -> NSWindow? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.engine.error("No screen available")
            return nil
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        // kCGDesktopWindowLevel + 1 places the window above the macOS wallpaper layer
        // but below the Finder desktop icon layer. This is the correct level for
        // a custom wallpaper window.
        window.level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        window.isOpaque           = true
        window.hasShadow          = false
        window.ignoresMouseEvents = true
        window.backgroundColor    = .black
        window.isReleasedWhenClosed = false

        let hostView = NSView(frame: screen.frame)
        hostView.wantsLayer = true
        hostView.layer?.contentsScale = screen.backingScaleFactor
        window.contentView = hostView

        // Start transparent. handleSpaceChange reveals the correct window.
        window.alphaValue = 0.0
        window.orderFront(nil)

        return window
    }

    // MARK: - Teardown

    private func teardown(spaceUUID: String) {
        activePaths[spaceUUID] = nil
        players[spaceUUID]?.pause()
        loopers[spaceUUID] = nil
        players[spaceUUID] = nil
        windows[spaceUUID]?.orderOut(nil)
        windows[spaceUUID]?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        windows[spaceUUID]?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        windows[spaceUUID] = nil
    }

    private func teardownAll() {
        Array(windows.keys).forEach { teardown(spaceUUID: $0) }
    }

    private func pauseAll() {
        players.values.forEach { $0.pause() }
    }

    private func resumeCurrent() {
        // Resume all players. They stay buffered in background spaces.
        players.values.forEach { $0.play() }
    }
}
