import Cocoa
import AVFoundation
import Combine
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

    // Keyed by space index (1-based) which is stable across reboots.
    private var players:      [Int: AVQueuePlayer]  = [:]
    private var loopers:      [Int: AVPlayerLooper] = [:]
    private var windows:      [Int: NSWindow]       = [:]
    private var activePaths:  [Int: String]         = [:]  // tracks what path each window is showing

    private var cancellables    = Set<AnyCancellable>()
    private var isTypingPaused  = false
    private var keyboardMonitor: Any? = nil
    private(set) var eventTap: CFMachPort? = nil
    private var typingTimer:     Timer? = nil

    // MARK: - Lifecycle

    func start() {
        // Wait for SpaceManager to settle before syncing, then react to
        // both space changes and assignment changes.
        spaceManager.$allSpaceIDs
            .filter { !$0.isEmpty }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncToAssignments()
            }
            .store(in: &cancellables)

        spaceManager.$currentSpaceID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] spaceID in
                self?.handleSpaceChange(to: spaceID)
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
        // Local monitor always works — catches keys when Eigenframe has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleTypingEvent()
            return event
        }

        // CGEventTap in listen-only mode requires Input Monitoring permission.
        // Unlike NSEvent.addGlobalMonitorForEvents (which silently returns non-nil
        // but never fires), CGEventTap returns nil when permission is denied —
        // giving us a reliable way to detect missing permission and alert the user.
        setupEventTap()
    }

    /// Called by the UI when the user enables pause-while-typing for the first time.
    /// Attempts to install the event tap; shows the Input Monitoring alert if denied.
    func requestTypingDetection() {
        guard eventTap == nil else { return }
        setupEventTap()
    }

    func setupEventTap() {
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
            // Tap returned nil = Input Monitoring permission not granted.
            // Show an alert after a short delay so the app finishes launching first.
            Log.engine.warning("CGEventTap nil — Input Monitoring permission not granted")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showInputMonitoringAlert()
            }
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        Log.engine.info("CGEventTap installed — typing detection active")
    }

    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring permission needed"
        alert.informativeText = "To pause wallpapers while typing, Eigenframe needs Input Monitoring permission.\n\nOpen System Settings → Privacy & Security → Input Monitoring, then enable Eigenframe.\n\nAfter granting permission, quit and relaunch Eigenframe."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }

    func handleTypingEvent() {
        guard config.pauseOnTyping, !isPaused else { return }
        if !isTypingPaused {
            isTypingPaused = true
            players.values.forEach { $0.rate = 0 }
            Log.engine.info("Typing detected — wallpapers paused")
        }
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isTypingPaused = false
            if !self.isPaused { self.resumeCurrent() }
            Log.engine.info("Typing stopped — wallpapers resumed")
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

    private func handleSpaceChange(to spaceID: CGSSpaceID) {
        guard !isPaused else { return }
        let activeIndex = spaceManager.index(of: spaceID)

        // Use CATransaction to make ALL alpha changes atomic and instant.
        // This prevents any intermediate compositing frames from being visible.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)

        for (index, window) in windows {
            if index == activeIndex {
                // Bring the active window to the front of the window order
                // so it composites above any system transition layers.
                window.alphaValue = 1.0
                window.orderFrontRegardless()
                players[index]?.play()
            } else {
                window.alphaValue = 0.0
            }
        }

        CATransaction.commit()

        // Force an immediate display update to flush the compositor.
        windows[activeIndex]?.contentView?.layer?.setNeedsDisplay()
        windows[activeIndex]?.contentView?.layer?.displayIfNeeded()

        Log.engine.info("Switched to space index \(activeIndex) (id: \(spaceID))")
    }

    // MARK: - Syncing

    private func syncToAssignments() {
        let assignments    = config.assignments
        let assignedIndices = Set(assignments.map { $0.spaceIndex })

        // Tear down windows for spaces that no longer have assignments.
        for index in Set(windows.keys).subtracting(assignedIndices) {
            teardown(spaceIndex: index)
        }

        // Set up or update windows for each assignment.
        for assignment in assignments {
            let index = assignment.spaceIndex
            let path  = assignment.mediaPath

            // Skip only if the window exists AND is already showing this exact path.
            // Compare against activePaths (what the window is actually showing),
            // not config (which already has the new value after a drop).
            if windows[index] != nil, activePaths[index] == path { continue }

            teardown(spaceIndex: index)

            let url = URL(fileURLWithPath: path)
            guard let type = MediaType.from(url: url) else {
                Log.engine.warning("Unsupported media type for space \(index): \(path)")
                continue
            }

            switch type {
            case .video: setupVideo(for: index, url: url)
            case .image: setupImage(for: index, url: url)
            }
        }

        handleSpaceChange(to: spaceManager.currentSpaceID)
        Log.engine.info("Synced \(assignments.count) assignment(s)")
    }

    // MARK: - Video Setup

    private func setupVideo(for spaceIndex: Int, url: URL) {
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
            Log.engine.error("Failed to create wallpaper window for space index \(spaceIndex)")
            return
        }

        layer.frame = hostView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostView.layer?.addSublayer(layer)

        // Pre-buffer by playing immediately — window is transparent so
        // invisible, but GPU pipeline is warm for instant Space switching.
        player.play()

        players[spaceIndex] = player
        loopers[spaceIndex] = looper
        windows[spaceIndex] = window

        activePaths[spaceIndex] = url.path
        Log.engine.info("Video set for space \(spaceIndex): \(url.lastPathComponent)")
    }

    // MARK: - Image Setup

    private func setupImage(for spaceIndex: Int, url: URL) {
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
            Log.engine.error("Failed to set up image for space index \(spaceIndex)")
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
        windows[spaceIndex] = window

        activePaths[spaceIndex] = url.path
        Log.engine.info("Image set for space \(spaceIndex): \(url.lastPathComponent)")
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

        // Start transparent — handleSpaceChange reveals the correct window.
        window.alphaValue = 0.0
        window.orderFront(nil)

        return window
    }

    // MARK: - Teardown

    private func teardown(spaceIndex: Int) {
        activePaths[spaceIndex] = nil
        players[spaceIndex]?.pause()
        loopers[spaceIndex] = nil
        players[spaceIndex] = nil
        windows[spaceIndex]?.orderOut(nil)
        windows[spaceIndex]?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        windows[spaceIndex]?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        windows[spaceIndex] = nil
    }

    private func teardownAll() {
        Array(windows.keys).forEach { teardown(spaceIndex: $0) }
    }

    private func pauseAll() {
        players.values.forEach { $0.pause() }
    }

    private func resumeCurrent() {
        // Resume all players — they stay buffered in background spaces.
        players.values.forEach { $0.play() }
    }
}
