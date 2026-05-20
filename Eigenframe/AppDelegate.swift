import Cocoa
import SwiftUI
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {

    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private nonisolated(unsafe) var controlPanelWindow: NSWindow?
    private nonisolated(unsafe) var wallpaperEngine: WallpaperEngine?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let engine = WallpaperEngine()
        wallpaperEngine = engine

        setupStatusBar(engine: engine)
        engine.start()

        // Always show the control panel on launch so the app feels
        // immediately responsive when double-clicked from Finder or Launchpad.
        showControlPanel()

        Log.ui.info("Eigenframe launched")
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        wallpaperEngine?.stop()
        Log.ui.info("Eigenframe terminating")
    }

    // MARK: - Status Bar

    @MainActor
    private func setupStatusBar(engine: WallpaperEngine) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Render a lambda symbol as a small template image for the menu bar.
            // Template images automatically adapt to light/dark mode.
            let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                    .foregroundColor: NSColor.black
                ]
                let str = NSAttributedString(string: "λ", attributes: attrs)
                let strSize = str.size()
                let origin = NSPoint(
                    x: (rect.width  - strSize.width)  / 2,
                    y: (rect.height - strSize.height) / 2
                )
                str.draw(at: origin)
                return true
            }
            image.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Eigenframe menu bar icon")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Configure Spaces...", action: #selector(showControlPanel), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pause Wallpapers", action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Help and FAQ", action: #selector(openHelp), keyEquivalent: "?"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Eigenframe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @MainActor @objc private func showControlPanel() {
        // If the window was closed (isReleasedWhenClosed = false means the
        // object still exists but is not visible), recreate it so it always
        // appears fresh at its last position or centered if first launch.
        if controlPanelWindow == nil || !(controlPanelWindow?.isVisible ?? false) {
            guard let engine = wallpaperEngine else { return }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                styleMask:   [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing:     .buffered,
                defer:       false
            )
            window.titlebarAppearsTransparent  = true
            window.titleVisibility             = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed        = false
            window.minSize                     = NSSize(width: 520, height: 420)

            // Follow the user across Spaces so the control panel
            // is always accessible regardless of which Space is active.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            if let existing = controlPanelWindow {
                // Restore to the same position as the previously closed window.
                window.setFrameOrigin(existing.frame.origin)
            } else {
                window.center()
            }

            window.title       = "Eigenframe"
            window.contentView = NSHostingView(rootView: ControlPanelView(engine: engine))
            controlPanelWindow = window
        }

        controlPanelWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.ui.debug("Control panel shown")
    }

    @MainActor @objc private func openHelp() {
        guard let helpURL = Bundle.main.url(forResource: "Help", withExtension: "html") else {
            Log.ui.error("Help.html not found in app bundle")
            return
        }
        NSWorkspace.shared.open(helpURL)
    }

    @MainActor @objc private func togglePause() {
        guard let engine = wallpaperEngine else { return }
        engine.isPaused.toggle()
        let title = engine.isPaused ? "Resume Wallpapers" : "Pause Wallpapers"
        statusItem?.menu?.item(withTitle: "Pause Wallpapers")?.title  = title
        statusItem?.menu?.item(withTitle: "Resume Wallpapers")?.title = title
    }
}

extension AppDelegate {
    // Called when the user double-clicks the app in Finder or Launchpad
    // while it is already running. Since Eigenframe has no Dock icon,
    // this is the primary way to reopen the control panel after closing it.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showControlPanel()
        }
        return true
    }
}
