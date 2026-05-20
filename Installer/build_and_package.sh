#!/bin/bash
# ============================================================
#  Eigenframe - Build and Package Script
#  Run this once on your Mac to produce Eigenframe.dmg
#
#  Requirements:
#    - Xcode Command Line Tools  (xcode-select --install)
#    - create-dmg                (brew install create-dmg)
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/Installer/dmg-contents/Eigenframe.app"
DMG_OUTPUT="$SCRIPT_DIR/Installer/Eigenframe.dmg"
HELP_FILE="$SCRIPT_DIR/Help/Eigenframe_Help.html"

echo ""
echo "============================================"
echo "   Eigenframe - Build and Package"
echo "============================================"
echo ""

# ---- Step 1: Check dependencies ----

echo "Checking dependencies..."

if ! command -v swift &>/dev/null; then
    echo "  ERROR: Swift not found."
    echo "  Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

if ! command -v create-dmg &>/dev/null; then
    echo "  ERROR: create-dmg not found."
    echo "  Install with: brew install create-dmg"
    exit 1
fi

echo "  Swift found"
echo "  create-dmg found"

# ---- Step 2: Determine signing identity ----
# grep returns exit code 1 when no matches found, which would kill the
# script under set -e. The || true prevents that.

# Use local self-signed certificate for stable TCC identity across rebuilds.
# This allows Input Monitoring permission to persist without a paid Developer ID.
DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | awk -F'"' '{print $2}' || true)

LOCAL_CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Eigenframe Dev"' \
    | head -1 \
    | awk -F'"' '{print $2}' || true)

if [ -n "$DEVELOPER_ID" ]; then
    SIGN_IDENTITY="$DEVELOPER_ID"
    echo "  Signing identity: $DEVELOPER_ID"
elif [ -n "$LOCAL_CERT" ]; then
    SIGN_IDENTITY="$LOCAL_CERT"
    echo "  Signing identity: $LOCAL_CERT (local self-signed)"
else
    SIGN_IDENTITY="-"
    echo "  No signing certificate found; using ad-hoc signing"
fi

# ---- Step 3: Build release binary ----

echo ""
echo "Building Eigenframe (Release)..."
cd "$SCRIPT_DIR"
swift build --configuration release 2>&1 | grep -E "(error:|Build complete)" || true

if [ ! -f "$BUILD_DIR/Eigenframe" ]; then
    echo "  ERROR: Build failed. Run 'swift build --configuration release' to see full output."
    exit 1
fi
echo "  Build complete"

# ---- Step 3.5: Generate app icon ----

echo ""
echo "Generating app icon..."

ICON_SRC="$SCRIPT_DIR/Eigenframe/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$SCRIPT_DIR/Installer/AppIcon.iconset"
ICNS_OUTPUT="$SCRIPT_DIR/Installer/AppIcon.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# iconutil expects files named exactly as below.
cp "$ICON_SRC/icon_16x16.png"     "$ICONSET_DIR/icon_16x16.png"
cp "$ICON_SRC/icon_16x16@2x.png"  "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICON_SRC/icon_32x32.png"     "$ICONSET_DIR/icon_32x32.png"
cp "$ICON_SRC/icon_32x32@2x.png"  "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICON_SRC/icon_128x128.png"   "$ICONSET_DIR/icon_128x128.png"
cp "$ICON_SRC/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICON_SRC/icon_256x256.png"   "$ICONSET_DIR/icon_256x256.png"
cp "$ICON_SRC/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICON_SRC/icon_512x512.png"   "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_SRC/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil --convert icns --output "$ICNS_OUTPUT" "$ICONSET_DIR"
rm -rf "$ICONSET_DIR"
echo "  Icon generated"

# ---- Step 4: Assemble .app bundle ----

echo ""
echo "Assembling .app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/Eigenframe"             "$APP_BUNDLE/Contents/MacOS/Eigenframe"
chmod +x                               "$APP_BUNDLE/Contents/MacOS/Eigenframe"
cp "$SCRIPT_DIR/Eigenframe/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$HELP_FILE" ]; then
    cp "$HELP_FILE" "$APP_BUNDLE/Contents/Resources/Help.html"
    echo "  Help file bundled"
fi

if [ -f "$ICNS_OUTPUT" ]; then
    cp "$ICNS_OUTPUT" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  Icon bundled"
else
    echo "  WARNING: Help file not found at $HELP_FILE"
fi

echo "  App bundle assembled"

# ---- Step 5: Code sign ----

echo ""
echo "Code signing..."
ENTITLEMENTS="$SCRIPT_DIR/Eigenframe/Eigenframe.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
    echo "  Signed with entitlements"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    echo "  Signed"
fi

# ---- Step 6: Copy help into DMG contents ----

if [ -f "$HELP_FILE" ]; then
    cp "$HELP_FILE" "$SCRIPT_DIR/Installer/dmg-contents/Eigenframe_Help.html"
fi

# ---- Step 7: Build DMG ----

echo ""
echo "Creating DMG installer..."

rm -f "$DMG_OUTPUT"

create-dmg \
    --volname "Eigenframe" \
    --window-pos 200 120 \
    --window-size 560 340 \
    --icon-size 100 \
    --icon "Eigenframe.app" 140 160 \
    --hide-extension "Eigenframe.app" \
    --app-drop-link 420 160 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$SCRIPT_DIR/Installer/dmg-contents/"

echo ""
echo "Installing to /Applications..."
rm -rf /Applications/Eigenframe.app
cp -R "$SCRIPT_DIR/Installer/dmg-contents/Eigenframe.app" /Applications/
echo "  Installed to /Applications/Eigenframe.app"

# Re-sign after copy so the path is /Applications/Eigenframe.app
# macOS ties TCC permissions to the app path — /Applications gets Input Monitoring prompts
codesign --force --deep --sign "$SIGN_IDENTITY" /Applications/Eigenframe.app 2>/dev/null &&     echo "  Re-signed at /Applications path" || true

echo ""
echo "============================================"
echo "   Done!"
echo ""
echo "   App installed: /Applications/Eigenframe.app"
echo "   DMG:           Installer/Eigenframe.dmg"
echo ""
echo "   IMPORTANT: Launch from /Applications (not the DMG)"
echo "   On first launch, macOS will prompt for Input Monitoring."
echo "   Enable Eigenframe in System Settings → Privacy & Security"
echo "   → Input Monitoring for the pause-while-typing feature."
if [ "$SIGN_IDENTITY" = "-" ]; then
echo ""
echo "   Note: Ad-hoc signed. On first launch"
echo "   right-click the app and choose Open."
fi
echo "============================================"
echo ""
