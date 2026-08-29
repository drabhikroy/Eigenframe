#!/bin/bash
# ============================================================
#  Eigenframe - Build and Package Script
#  Run this once on your Mac to produce Eigenframe.dmg
#
#  Requirements:
#    - Xcode Command Line Tools  (xcode-select --install)
#    - create-dmg                (brew install create-dmg)
#
#  Options:
#    --no-install        Build and package, but do not touch /Applications
#    --notarize          Submit the DMG to Apple's notary service.
#                        Requires a Developer ID identity and a stored
#                        notarytool keychain profile; set its name in
#                        EIGENFRAME_NOTARY_PROFILE (default: "eigenframe").
#
#  Signing:
#    The app is signed WITH THE HARDENED RUNTIME. That is not cosmetic here.
#    Eigenframe is unsandboxed and holds an Input Monitoring grant, so without
#    the hardened runtime any process running as the same user can inject a
#    library into it (DYLD_INSERT_LIBRARIES, task_for_pid) and inherit that
#    grant - that is, become a keylogger wearing Eigenframe's identity, in a
#    process that launches at login. Library validation, which the hardened
#    runtime turns on, is what closes that door.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
# Assemble and sign outside the repository.
#
# When the repo lives under a folder synced by iCloud Drive, the file provider
# daemon attaches com.apple.FinderInfo and friends to files as they are created.
# codesign refuses a bundle carrying those ("resource fork, Finder information,
# or similar detritus not allowed"), and stripping them in the script is a race
# the daemon wins. /tmp is not synced, so the problem does not arise. The signed
# bundle is copied back into the repo at the end.
STAGE_DIR="${TMPDIR:-/tmp}/eigenframe-stage"
STAGE_CONTENTS="$STAGE_DIR/dmg-contents"
APP_BUNDLE="$STAGE_CONTENTS/Eigenframe.app"
FINAL_BUNDLE="$SCRIPT_DIR/Installer/dmg-contents/Eigenframe.app"
DMG_OUTPUT="$SCRIPT_DIR/Installer/Eigenframe.dmg"
HELP_FILE="$SCRIPT_DIR/Help/Eigenframe_Help.html"
ENTITLEMENTS="$SCRIPT_DIR/Eigenframe/Eigenframe.entitlements"
NOTARY_PROFILE="${EIGENFRAME_NOTARY_PROFILE:-eigenframe}"

DO_INSTALL=1
DO_NOTARIZE=0

for arg in "${@:-}"; do
    case "$arg" in
        "")           ;;
        --no-install) DO_INSTALL=0 ;;
        --notarize)   DO_NOTARIZE=1 ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

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

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "  ERROR: Entitlements file missing at $ENTITLEMENTS"
    echo "  Refusing to build: signing without it would silently ship an app"
    echo "  whose declared capabilities do not match the source."
    exit 1
fi

echo "  Swift found"
echo "  create-dmg found"
echo "  Entitlements found"

# ---- Step 2: Determine signing identity ----
# grep returns exit code 1 when no matches are found, which would kill the
# script under set -e. The || true prevents that.

DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | awk -F'"' '{print $2}' || true)

# Local self-signed certificate. Gives a stable TCC identity across rebuilds
# during development without a paid Developer ID. NOT fit for distribution:
# see the warning printed at the end of the run.
LOCAL_CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Eigenframe Dev"' \
    | head -1 \
    | awk -F'"' '{print $2}' || true)

TIMESTAMP_FLAG="--timestamp"
if [ -n "$DEVELOPER_ID" ]; then
    SIGN_IDENTITY="$DEVELOPER_ID"
    SIGN_KIND="developer-id"
    echo "  Signing identity: $DEVELOPER_ID"
elif [ -n "$LOCAL_CERT" ]; then
    SIGN_IDENTITY="$LOCAL_CERT"
    SIGN_KIND="self-signed"
    echo "  Signing identity: $LOCAL_CERT (local self-signed, development only)"
else
    SIGN_IDENTITY="-"
    SIGN_KIND="ad-hoc"
    # A secure timestamp requires a real certificate; ad-hoc signing cannot use one.
    TIMESTAMP_FLAG="--timestamp=none"
    echo "  No signing certificate found; using ad-hoc signing (development only)"
fi

if [ "$DO_NOTARIZE" -eq 1 ] && [ "$SIGN_KIND" != "developer-id" ]; then
    echo "  ERROR: --notarize requires a Developer ID Application identity."
    exit 1
fi

# ---- Step 3: Build release binary ----

echo ""
echo "Building Eigenframe (Release)..."
cd "$SCRIPT_DIR"

# Remove any previous binary first, so a build that fails cannot be mistaken for
# a build that succeeded because a stale artefact is still sitting there.
rm -f "$BUILD_DIR/Eigenframe"

# Do not pipe through grep: it discards the exit status and hides real errors.
if ! swift build --configuration release; then
    echo "  ERROR: Build failed. See the output above."
    exit 1
fi

if [ ! -f "$BUILD_DIR/Eigenframe" ]; then
    echo "  ERROR: Build reported success but produced no binary."
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
for name in 16x16 16x16@2x 32x32 32x32@2x 128x128 128x128@2x \
            256x256 256x256@2x 512x512 512x512@2x; do
    cp "$ICON_SRC/icon_${name}.png" "$ICONSET_DIR/icon_${name}.png"
done

iconutil --convert icns --output "$ICNS_OUTPUT" "$ICONSET_DIR"
rm -rf "$ICONSET_DIR"
echo "  Icon generated"

# ---- Step 4: Assemble .app bundle ----

echo ""
echo "Assembling .app bundle..."

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_CONTENTS"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/Eigenframe"             "$APP_BUNDLE/Contents/MacOS/Eigenframe"
chmod 755                              "$APP_BUNDLE/Contents/MacOS/Eigenframe"
cp "$SCRIPT_DIR/Eigenframe/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$HELP_FILE" ]; then
    cp "$HELP_FILE" "$APP_BUNDLE/Contents/Resources/Help.html"
    echo "  Help file bundled"
else
    echo "  WARNING: Help file not found at $HELP_FILE"
fi

if [ -f "$ICNS_OUTPUT" ]; then
    cp "$ICNS_OUTPUT" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  Icon bundled"
else
    echo "  WARNING: Icon not found at $ICNS_OUTPUT"
fi

echo "  App bundle assembled"

# ---- Step 5: Code sign ----
#
# Notes on the flags:
#   --options runtime  enables the hardened runtime. This is the control that
#                      stops another process injecting code into an app that
#                      holds Input Monitoring. Do not remove it.
#   --timestamp        binds a secure timestamp so the signature stays valid
#                      after the certificate expires.
#   (no --deep)        Apple deprecated --deep for signing; it silently applies
#                      the same entitlements to every nested item and hides
#                      failures. This bundle has no nested code, so a single
#                      top-level signature is both correct and sufficient.

echo ""
echo "Code signing (hardened runtime)..."

# codesign refuses a bundle carrying extended attributes ("resource fork, Finder
# information, or similar detritus not allowed"). They arrive from Finder,
# iCloud Drive, quarantine flags, and the copy steps above. Strip them first.
xattr -cr "$APP_BUNDLE"

codesign --force \
         --options runtime \
         "$TIMESTAMP_FLAG" \
         --entitlements "$ENTITLEMENTS" \
         --sign "$SIGN_IDENTITY" \
         "$APP_BUNDLE"

echo "  Signed"

echo ""
echo "Verifying signature..."
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

# Confirm the hardened runtime flag actually landed. A signature that verifies
# but lacks CS_RUNTIME is exactly the failure this script exists to prevent, and
# it is invisible unless checked explicitly.
# Capture first, match second. Piping into `grep -q` looks correct but breaks
# under `set -o pipefail`: grep exits as soon as it matches, codesign takes
# SIGPIPE and exits non-zero, and the pipeline reports failure exactly when the
# flag WAS found.
SIG_INFO="$(codesign --display --verbose=2 "$APP_BUNDLE" 2>&1 || true)"
case "$SIG_INFO" in
    *flags=*runtime*) : ;;
    *)
        echo "  ERROR: The hardened runtime flag is not present on the signature."
        echo "  codesign reported:"
        printf '%s\n' "$SIG_INFO" | sed 's/^/    /'
        echo "  Refusing to continue."
        exit 1
        ;;
esac
echo "  Hardened runtime confirmed"

echo "  Entitlements on the signed bundle:"
codesign --display --entitlements - "$APP_BUNDLE" 2>/dev/null | sed 's/^/    /' || true

# ---- Step 5.5: Copy the signed bundle back into the repo ----
#
# Done after signing, never before. Extra attributes picked up on the way in do
# not invalidate an existing signature; they only block creating one.

echo ""
echo "Copying the signed bundle into the repository..."
rm -rf "$FINAL_BUNDLE"
mkdir -p "$SCRIPT_DIR/Installer/dmg-contents"
ditto "$APP_BUNDLE" "$FINAL_BUNDLE"
codesign --verify --strict "$FINAL_BUNDLE"
echo "  Copied and verified"

# ---- Step 6: Copy help into DMG contents ----

if [ -f "$HELP_FILE" ]; then
    cp "$HELP_FILE" "$STAGE_CONTENTS/Eigenframe_Help.html"
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
    "$STAGE_CONTENTS/"

# ---- Step 8: Notarize (optional, Developer ID only) ----

if [ "$DO_NOTARIZE" -eq 1 ]; then
    echo ""
    echo "Submitting to Apple's notary service (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_OUTPUT"
    echo "  Notarized and stapled"
fi

# ---- Step 9: Install to /Applications ----
#
# The previous version of this script re-signed the installed copy WITHOUT
# --entitlements and with stderr discarded. That silently stripped the
# entitlements from the app users actually run, and would strip the hardened
# runtime flag too. It is also unnecessary: `ditto` preserves the signature
# exactly, and TCC keys on the code signing identity, which does not change when
# the bundle moves. So: copy, then verify. Never re-sign after a copy.

if [ "$DO_INSTALL" -eq 1 ]; then
    echo ""
    echo "Installing to /Applications..."
    if [ -e "/Applications/Eigenframe.app" ]; then
        rm -rf "/Applications/Eigenframe.app"
    fi
    ditto "$APP_BUNDLE" "/Applications/Eigenframe.app"

    echo "  Verifying the installed copy..."
    codesign --verify --strict --verbose=2 "/Applications/Eigenframe.app"
    echo "  Installed to /Applications/Eigenframe.app"
fi

echo ""
echo "============================================"
echo "   Done!"
echo ""
if [ "$DO_INSTALL" -eq 1 ]; then
echo "   App installed: /Applications/Eigenframe.app"
fi
echo "   DMG:           Installer/Eigenframe.dmg"
echo ""
echo "   IMPORTANT: Launch from /Applications (not the DMG)"
echo "   On first launch, macOS will prompt for Input Monitoring."
echo "   Enable Eigenframe in System Settings -> Privacy & Security"
echo "   -> Input Monitoring for the pause-while-typing feature."
echo ""
echo "   Note: enabling the hardened runtime changes the code signature."
echo "   The first build after this change will ask for Input Monitoring"
echo "   again, once. That is macOS noticing the app is genuinely different,"
echo "   and is expected."

if [ "$SIGN_KIND" != "developer-id" ]; then
echo ""
echo "   ------------------------------------------------------------"
echo "   WARNING: this build is $SIGN_KIND signed and NOT notarized."
echo "   It is fine on this machine. Do NOT publish this DMG."
echo ""
echo "   Anyone who downloads it will hit Gatekeeper, and the usual"
echo "   workaround (right-click, Open) teaches users to wave through"
echo "   the exact check that protects them - a bad habit to teach for"
echo "   an app that asks for keystroke access."
echo ""
echo "   For a public release: sign with a Developer ID Application"
echo "   certificate and run this script with --notarize."
echo "   ------------------------------------------------------------"
fi
echo "============================================"
echo ""
