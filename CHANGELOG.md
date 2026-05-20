# Changelog

All notable changes to Eigenframe are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Eigenframe uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
