import Cocoa
import CoreText
import ServiceManagement
import SwiftUI
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {

    // nonisolated(unsafe) is required because AppDelegate is an NSObject subclass
    // and Swift 6 strict concurrency does not allow stored properties to be
    // implicitly isolated to @MainActor on non-final reference types. These
    // properties are only ever accessed from the main thread via @MainActor methods.
    private nonisolated(unsafe) var statusItem: NSStatusItem?
    private nonisolated(unsafe) var controlPanelWindow: NSWindow?
    private nonisolated(unsafe) var wallpaperEngine: WallpaperEngine?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let engine = WallpaperEngine()
        wallpaperEngine = engine

        setupStatusBar(engine: engine)

        // Let the permission guide share the control panel's menu bar handling.
        PermissionGuideWindowController.shared.windowDelegate = self
        PermissionGuideWindowController.shared.onWillShow = { [weak self] in
            self?.installMainMenuIfNeeded()
        }

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
            button.image = Self.menuBarIcon()
            button.setAccessibilityLabel("Eigenframe menu bar icon")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Eigenframe", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Configure Spaces...", action: #selector(showControlPanel), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pause Wallpapers", action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? NSControl.StateValue.on : NSControl.StateValue.off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Help and FAQ", action: #selector(openHelp), keyEquivalent: "?"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Eigenframe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    /// Builds the lambda for the menu bar from its glyph outline rather than
    /// from a line of text.
    ///
    /// Centering text by its line box leaves the letter small and a little low,
    /// because the box reserves room for ascenders and descenders that a lambda
    /// never uses. Fitting the outline itself lets the mark stand as tall as the
    /// icons beside it, and the heavier weight keeps its strokes level with
    /// theirs. It is a template image, so macOS tints it for light and dark
    /// menu bars.
    private static func menuBarIcon() -> NSImage {
        let canvas     = NSSize(width: 18, height: 18)
        let markHeight: CGFloat = 16

        let image = NSImage(size: canvas, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 40, weight: .semibold) as CTFont
            var character = UniChar(0x03BB)
            var glyph     = CGGlyph()

            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
                  let outline = CTFontCreatePathForGlyph(font, glyph, nil),
                  let context = NSGraphicsContext.current?.cgContext
            else { return false }

            let box   = outline.boundingBox
            let scale = markHeight / box.height
            var fit = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -box.midX, y: -box.midY)
            guard let placed = outline.copy(using: &fit) else { return false }

            context.setFillColor(NSColor.black.cgColor)
            context.addPath(placed)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Actions

    @MainActor @objc func showControlPanel() {
        // Recreate if closed; restore last position or center on first launch.
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

            // Follow the user across Spaces.
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

        installMainMenuIfNeeded()
        controlPanelWindow?.delegate = self
        controlPanelWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.ui.debug("Control panel shown")
    }

    @MainActor @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        // Built as an attributed string so the release page is a real clickable
        // link rather than a line of text the reader has to retype.
        let credits = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        credits.append(NSAttributedString(
            string: "Assign a scene to each Mission Control Space.\n\n",
            attributes: base
        ))

        let link = NSMutableAttributedString(string: "Check for the latest version\n", attributes: base)
        link.addAttribute(.link,
                          value: Self.releasesURL,
                          range: NSRange(location: 0, length: link.length - 1))
        credits.append(link)

        credits.append(NSAttributedString(
            string: "\nPolyForm Noncommercial License 1.0.0\nCopyright 2026 Abhik Roy",
            attributes: base
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "Eigenframe",
            .applicationVersion: version,
            .credits:            credits
        ])
    }

    @MainActor @objc func openReleases() {
        NSWorkspace.shared.open(URL(string: Self.releasesURL)!)
    }

    @MainActor @objc func openLicense() {
        NSWorkspace.shared.open(URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!)
    }

    static let releasesURL = "https://github.com/drabhikroy/Eigenframe/releases"

    // MARK: - Application Menu

    /// Eigenframe runs without a Dock icon or application menu while it is only
    /// a status item. When a window opens, it switches to a regular app so the
    /// menu bar is available, then switches back once the last window closes.
    @MainActor
    fileprivate func installMainMenuIfNeeded() {
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = MainMenuBuilder.build(target: self)
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @MainActor
    fileprivate func removeMainMenuIfNoWindows() {
        let hasVisible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard !hasVisible else { return }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = nil
    }

    @MainActor @objc private func toggleLaunchAtLogin() {
        ConfigStore.shared.launchAtLogin.toggle()
        let isEnabled = SMAppService.mainApp.status == .enabled
        statusItem?.menu?.item(withTitle: "Launch at Login")?.state = isEnabled ? .on : .off
    }

    @MainActor @objc func openHelp() {
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

// MARK: - Window lifecycle

extension AppDelegate: NSWindowDelegate {

    /// When the last Eigenframe window closes, drop back to a menu bar agent so
    /// the Dock icon and application menu go away again.
    @MainActor
    func windowWillClose(_ notification: Notification) {
        // Run after the window has actually gone, otherwise it still counts as
        // visible and the policy would never change back.
        DispatchQueue.main.async { [weak self] in
            self?.removeMainMenuIfNoWindows()
        }
    }
}
