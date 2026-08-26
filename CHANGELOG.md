# Changelog

All notable changes to Eigenframe are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Eigenframe uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.3] - 2026-08-26

### Fixed
- The Input Monitoring prompt no longer appears repeatedly when permission is already granted. The event tap was attempted once, very early in launch, before macOS had finished resolving permissions — a nil result was treated as a denial. It is now retried with backoff before concluding permission is missing, and the alert appears at most once per launch.
- The Input Monitoring prompt is no longer shown to users who have not enabled "Pause while typing". The tap is only installed when the feature is actually in use.
- The prompt's instructions now explain that Eigenframe must be quit from its menu bar icon (it runs as a menu bar agent, so closing the window does not quit it), and that a stale entry may need to be toggled off and on after reinstalling.

## [1.3.2] - 2026-08-26

### Fixed
- Mission Control reordering now updates the app's grid without pressing "Refresh". The 1.3.1 poll detected the change but updated `@Published` state off the main thread, so SwiftUI never re-rendered. Both pollers now run as main-queue dispatch sources, and `refresh()` marshals to the main thread regardless of caller.

### Changed
- The "Refresh" button's tooltip now notes that Space changes are detected automatically. The button is retained as a manual fallback and diagnostic aid.

## [1.3.1] - 2026-08-26

### Fixed
- Reordering, adding, or removing a desktop in Mission Control is now detected automatically. Previously the app only re-checked its Space list when you switched to a different desktop, so a reorder was invisible until you pressed the "Refresh" button. A new low-frequency poll (5Hz) now catches this within a fraction of a second, with no measurable overhead when Spaces are untouched.

## [1.3.0] - 2026-08-26

### Fixed
- Per-Space wallpapers now follow their desktop when Spaces are reordered in Mission Control. Assignments are keyed by each Space's persistent UUID instead of its 1-based position, so moving a desktop no longer leaves its wallpaper behind on the old slot.

### Changed
- Assignment storage format upgraded to version 2 (keyed by `space_uuid`). Existing version 1 files (keyed by `space_index`) are migrated automatically on first launch by mapping each stored index to the corresponding current Space, so existing setups are preserved.

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
