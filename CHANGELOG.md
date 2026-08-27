# Changelog

All notable changes to Eigenframe are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Eigenframe uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] - 2026-08-27

### Added
- Turning on Pause while typing now opens a short walkthrough for granting the Input Monitoring permission, in place of the block of text that was there before. It takes one step at a time, pairs each step with a picture of what will be on screen, and explains in plain language what the permission does and does not allow. All of its text can be selected and copied.
- The walkthrough follows along as you go. It notices when System Settings comes to the front and moves to the next step, and it notices the moment the permission starts working and jumps to the end. Every step can be revisited with a Back button.
- Instructions for adding Eigenframe to the Input Monitoring list with the plus button at the bottom left of the panel, for the case where macOS has not listed the app yet. Turning the feature on also asks macOS for the permission directly, which usually adds the entry for you.
- An application menu appears at the top of the screen while an Eigenframe window is open, and goes away again when the last one closes. It carries About, Configure Spaces, Help, and a standard Edit menu, so text in Eigenframe's windows can be copied from a menu as well as the keyboard.
- About Eigenframe links to the releases page and states the license and copyright. The Help menu links to the releases page and the full license text.
- A Pause While Typing section in the help page, written for people who have not changed a macOS permission before. It covers what to do when Eigenframe is missing from the list, when the setting looks correct but nothing happens, and how to reach the list by hand.

### Changed
- Granting the permission usually starts Pause while typing straight away instead of requiring a restart, because Eigenframe now installs its keyboard tap as soon as it sees the permission take effect. The instructions for quitting and reopening are still shown when that does not work.
- The permission prompt appears in well under a second rather than roughly fifteen, and fades in rather than appearing abruptly.
- The prompt is no longer shown to people who have not turned on Pause while typing, and appears at most once per launch.

### Fixed
- The permission prompt no longer appears when the permission has already been granted. The old check ran once during launch, before macOS had finished working out what Eigenframe was allowed to do, and treated a not-yet-ready answer as a refusal.
- The NOTICE file misspelled the app name as Eugenframe.

## [1.3.0] - 2026-08-26

### Fixed
- Per-Space wallpapers now follow their desktop when Spaces are reordered in Mission Control. Assignments were keyed by a Space's 1-based position rather than its identity, so moving a desktop left its wallpaper behind on the old slot. They are now keyed by each Space's persistent UUID, which is stable across both reordering and reboots.
- Reordering, adding, or removing a desktop is now detected automatically. Previously the Space list was only re-read when you switched to a different desktop, so a reorder stayed invisible until you pressed "Refresh". A lightweight poll now catches the change within a fraction of a second, republishing only when the list actually differs.
- The Input Monitoring prompt no longer appears when permission is already granted. The event tap was attempted once very early in launch, before macOS had finished resolving permissions, and a nil result was treated as a denial. It is now retried with backoff before concluding permission is missing, and appears at most once per launch.
- The Input Monitoring prompt is no longer shown at all to users who have not enabled "Pause while typing". The tap is only installed when the feature is in use.
- The prompt now explains that Eigenframe must be quit from its menu bar icon. It runs as a menu bar agent, so closing the window does not quit it. It also explains that a stale permission entry may need to be switched off and on after reinstalling.

### Changed
- Assignment storage format upgraded to version 2 (keyed by `space_uuid`). Existing version 1 files (keyed by `space_index`) are migrated automatically on first launch by mapping each stored index to the corresponding current Space, so existing setups are preserved.
- The "Refresh" button's tooltip now notes that Space changes are detected automatically. The button is retained as a manual fallback and diagnostic aid.

## [1.2.1] - 2026-06-07

### Added
- About Eigenframe panel accessible from the menu bar icon, showing the version number, app icon, and GitHub link.

## [1.2.0] - 2026-06-07

### Added
- Resizable control panel window with a minimum size of 520×420. Space cards reflow automatically as the window is resized.

### Fixed
- Footer toggles no longer clip at narrow window widths.
- `setupEventTap` and `handleTypingEvent` correctly scoped as private; `requestTypingDetection` is the public entry point.

## [1.1.0] - 2026-05-29

### Added
- Launch at login option in the control panel footer. Uses `SMAppService.mainApp` — no helper process required. The setting persists across launches.

## [1.0.0] - 2026-05-20

### Added
- Assign any static image or video to each Mission Control Space independently
- Supported image formats: JPEG, PNG, HEIC, HEIF, GIF, WebP, TIFF, BMP
- Supported video formats: MP4, MOV, M4V, MKV, AVI, WebM, HEVC, 3GP
- Seamless gapless video looping via AVPlayerLooper
- Drag-and-drop assignment directly onto Space cards
- Click the + icon on any Space card to open a file browser
- File picker via right-click context menu on any Space card
- Thumbnail preview on each Space card with IMAGE / VIDEO badge
- Active Space highlighted with a distinct border
- Pause / Resume toggle in the control panel and menu bar
- Pause while typing — video wallpapers pause automatically during keyboard input (requires Input Monitoring permission)
- Assignments persisted to ~/Library/Application Support/Eigenframe/assignments.json
- Stale assignments pruned automatically when Spaces are removed
- Refresh button for Spaces added after launch
- Self-signed certificate support for stable Input Monitoring permission across rebuilds
- Help and FAQ bundled as a standalone HTML document
- Build script producing a signed DMG installer and auto-installing to /Applications
- Full os_log structured logging across all subsystems
- VoiceOver accessibility labels on all interactive elements

### Notes
- Licensed under the PolyForm Noncommercial License 1.0.0.
