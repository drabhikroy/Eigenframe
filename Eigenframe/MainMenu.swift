import AppKit

/// Builds the application menu that appears at the top of the screen while an
/// Eigenframe window is open.
///
/// Eigenframe normally runs as a menu bar agent with no Dock icon and no
/// application menu. That is right when it is only a status item, but it leaves
/// a window with no Edit menu, so there is no visible way to copy text and no
/// standard place to look for About or Help. This menu is installed while a
/// window is on screen and taken away again when the last one closes.
enum MainMenuBuilder {

    static func build(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem(target: target))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem(target: target))

        return mainMenu
    }

    // MARK: - Eigenframe menu

    private static func appMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Eigenframe")

        let about = NSMenuItem(title: "About Eigenframe",
                               action: #selector(AppDelegate.showAbout),
                               keyEquivalent: "")
        about.target = target
        menu.addItem(about)

        let releases = NSMenuItem(title: "Latest Version",
                                  action: #selector(AppDelegate.openReleases),
                                  keyEquivalent: "")
        releases.target = target
        menu.addItem(releases)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Configure Spaces",
                                  action: #selector(AppDelegate.showControlPanel),
                                  keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Hide Eigenframe",
                                action: #selector(NSApplication.hide(_:)),
                                keyEquivalent: "h"))

        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Eigenframe",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        item.submenu = menu
        return item
    }

    // MARK: - Edit menu

    /// Present mainly so text in Eigenframe's windows can be selected and copied
    /// with a visible menu command and the usual keyboard shortcuts.
    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(NSMenuItem(title: "Undo",
                                action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Cut",
                                action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy",
                                action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste",
                                action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All",
                                action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        item.submenu = menu
        return item
    }

    // MARK: - Window menu

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(NSMenuItem(title: "Minimize",
                                action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Close",
                                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        item.submenu = menu
        return item
    }

    // MARK: - Help menu

    private static func helpMenuItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")

        let help = NSMenuItem(title: "Eigenframe Help",
                              action: #selector(AppDelegate.openHelp), keyEquivalent: "?")
        help.target = target
        menu.addItem(help)

        menu.addItem(.separator())

        let releases = NSMenuItem(title: "Releases on GitHub",
                                  action: #selector(AppDelegate.openReleases), keyEquivalent: "")
        releases.target = target
        menu.addItem(releases)

        let license = NSMenuItem(title: "License",
                                 action: #selector(AppDelegate.openLicense), keyEquivalent: "")
        license.target = target
        menu.addItem(license)

        item.submenu = menu
        return item
    }
}
