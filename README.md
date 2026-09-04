# Eigenframe

[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](#requirements)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-black?logo=apple&logoColor=white)
[![Release](https://img.shields.io/github/v/release/drabhikroy/Eigenframe)](https://github.com/drabhikroy/Eigenframe/releases/latest)

Eigenframe is a macOS app that lets you assign a different image or
looping video to each Mission Control Space.

Inspired by the idea of parallel worlds from Hugh Everett's many-worlds
interpretation, Eigenframe gives each Space its own visual environment
while you work.

Everything runs locally on your Mac. No account is required, no server
is used, and your images and videos stay on your computer.

![Eigenframe running on Space 2, showing a black hole accretion disk
wallpaper](docs/screenshot.png)

![Eigenframe running on Space 1, showing a Herbig-Haro nebula
wallpaper](docs/screenshot2.png)

## What it does

- Assign a different image or video to each Mission Control Space
- Switch Spaces and see each scene change with you
- Support static images and looping videos
- Run quietly from the macOS menu bar
- Pause playback when typing
- Keep all content local on your Mac

## What it does not do

- Programmatic Space switching does not reproduce macOS's visual
  transition animation.
- A brief delay can occur when switching Spaces while a wallpaper
  loads.

### Platform dependency

Eigenframe uses private undocumented macOS APIs for Space detection.
Apple may change or remove these APIs in future releases.

Eigenframe is an independent open source project with no affiliation
with Apple Inc.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1 or later)

## Install

Download the latest `Eigenframe.dmg` from the Releases page.

Open the DMG file and drag Eigenframe to your Applications folder.

The first launch may require Control-click or right-click → Open because
the app is not distributed through the Mac App Store.

## First run

1. Open Eigenframe from the menu bar.
2. Select a Mission Control Space.
3. Add an image or video.
4. Switch Spaces and each scene plays independently.

### Permissions

Input Monitoring is only required for the optional Pause while typing
feature. Everything else works without it.

The first time you turn that feature on, Eigenframe opens a short
walkthrough that takes you through granting the permission one step at a
time, including what to do if Eigenframe is not listed in System Settings
yet. It watches for the permission taking effect and moves along on its
own, so in most cases there is nothing to confirm and no need to restart
the app.

Eigenframe is told only that a key was pressed. It is never told which
key, and it does not record, save, or send anything you type.

No other permissions are required.

## Your data

**Images**  
`.jpg` · `.jpeg` · `.png` · `.heic` · `.gif` · `.webp` · `.tiff` · `.bmp`

**Videos**  
`.mp4` · `.mov` · `.m4v` · `.mkv` · `.avi` · `.webm` · `.hevc` · `.3gp`

## How it works

Eigenframe uses macOS system features to connect scenes with Mission
Control Spaces.

- `CGSGetActiveSpace()` identifies the active Space
- `AVPlayerLayer` renders video
- `AVPlayerLooper` provides continuous looping
- `NSImageView` displays static images
- `CGEventTap` supports keyboard activity detection

## Help

Open `Help/Eigenframe_Help.html` or use Help and FAQ from the menu bar.

## For developers

### Running from source

Build requirements:

- Xcode Command Line Tools
- Homebrew
- create-dmg

Create a signing certificate named `Eigenframe Dev` in Keychain Access,
then run:

```bash
git clone https://github.com/drabhikroy/Eigenframe
cd Eigenframe
chmod +x Installer/build_and_package.sh
./Installer/build_and_package.sh
```

## Credits and background

The wallpapers shown are NASA/ESA public domain imagery.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE). The full text is also at
<https://polyformproject.org/licenses/noncommercial/1.0.0>.

Personal use, personal study, hobby projects, teaching, academic research, and
use by charitable, educational, nonprofit, public research, public health, and
government organizations are permitted. Commercial use is not permitted without
a separate license.

Required notice: Copyright 2026 Abhik Roy.
