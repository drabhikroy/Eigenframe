# Eigenframe

[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-black?logo=apple&logoColor=white)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](#requirements)
[![Release](https://img.shields.io/github/v/release/drabhikroy/Eigenframe)](https://github.com/drabhikroy/Eigenframe/releases/latest)

Eigenframe is a macOS app that lets you assign a different image or
looping video to each Mission Control Space.

Inspired by the idea of parallel worlds from Hugh Everett's many-worlds
interpretation, Eigenframe gives each Space its own visual environment
while you work.

Everything runs locally on your Mac. No account is required, no server
is used, and your images and videos stay on your computer.

![Eigenframe --- Space 2 showing black hole accretion disk
wallpaper](docs/screenshot.png)

![Eigenframe --- Space 1 showing Herbig-Haro nebula
wallpaper](docs/screenshot2.png)

## Features

-   Assign a different image or video to each Mission Control Space
-   Switch Spaces and see each scene change with you
-   Support static images and looping videos
-   Run quietly from the macOS menu bar
-   Pause playback when typing
-   Keep all content local on your Mac

## Requirements

-   macOS 14 (Sonoma) or later
-   Apple Silicon (M1 or later)

## Install

Download the latest `Eigenframe.dmg` from the Releases page.

Open the DMG file and drag Eigenframe to your Applications folder.

The first launch may require Control-click or right-click → Open because
the app is not distributed through the Mac App Store.

## First Launch

1.  Open Eigenframe from the menu bar.
2.  Select a Mission Control Space.
3.  Add an image or video.
4.  Switch Spaces and each scene plays independently.

## Supported Formats

**Images**  
`.jpg` · `.jpeg` · `.png` · `.heic` · `.gif` · `.webp` · `.tiff` · `.bmp`

**Videos**  
`.mp4` · `.mov` · `.m4v` · `.mkv` · `.avi` · `.webm` · `.hevc` · `.3gp`

## Permissions

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

## Build from Source

Build requirements:

-   Xcode Command Line Tools
-   Homebrew
-   create-dmg

Create a signing certificate named `Eigenframe Dev` in Keychain Access,
then run:

``` bash
git clone https://github.com/drabhikroy/Eigenframe
cd Eigenframe
chmod +x Installer/build_and_package.sh
./Installer/build_and_package.sh
```

## How It Works

Eigenframe uses macOS system features to connect scenes with Mission
Control Spaces.

-   `CGSGetActiveSpace()` identifies the active Space
-   `AVPlayerLayer` renders video
-   `AVPlayerLooper` provides seamless looping
-   `NSImageView` displays static images
-   `CGEventTap` supports keyboard activity detection

## Known Limitations

-   Programmatic Space switching does not reproduce macOS's visual
    transition animation.
-   A brief delay can occur when switching Spaces while a wallpaper
    loads.

## Help and FAQ

Open `Help/Eigenframe_Help.html` or use Help and FAQ from the menu bar.

## Screenshot Credits

The wallpapers shown are NASA/ESA public domain imagery.

## Disclaimer

Eigenframe uses private undocumented macOS APIs for Space detection.
Apple may change or remove these APIs in future releases.

Eigenframe is an independent open source project with no affiliation
with Apple Inc.

## License

Copyright (c) 2026 Abhik Roy.

PolyForm Noncommercial License 1.0.0.
