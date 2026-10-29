#!/bin/bash
# build_app.sh
# Builds Brim in release mode and assembles it into build/Brim.app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Brim"
PRODUCT_NAME="Brim"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Validate the existing pinned identity before touching the previous app bundle.
"$SCRIPT_DIR/scripts/sign_app.sh" --check
source "$SCRIPT_DIR/scripts/signing-policy.conf"
SOURCE_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SCRIPT_DIR/Resources/Info.plist")"
[[ "$SOURCE_BUNDLE" == "$BRIM_BUNDLE_ID" ]] || { echo "error: bundle identifier differs from signing policy." >&2; exit 1; }

echo "==> Building $APP_NAME (release)..."
swift build --disable-keychain -c release

BINARY_DIR="$(swift build --disable-keychain -c release --show-bin-path)"
BINARY_PATH="$BINARY_DIR/$PRODUCT_NAME"
SPARKLE_FRAMEWORK="$BINARY_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: SwiftPM did not provide Sparkle.framework beside the executable." >&2
    exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "error: expected binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> Assembling app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
mkdir -p "$CONTENTS_DIR/Frameworks"
# ditto preserves the versioned framework's symlinks and helper executables.
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"

# App icon: the Brim logo (Resources/AppIcon/BrimLogo.png), scaled to every size macOS asks for
# into an .iconset and packed by iconutil. Info.plist names it via CFBundleIconFile = Brim. The PNG
# is also bundled, so the app shows the same logo in Settings, About and onboarding.
echo "==> Building the app icon..."
LOGO="$SCRIPT_DIR/Resources/AppIcon/BrimLogo.png"
ICON_WORK="$BUILD_DIR/icon"
rm -rf "$ICON_WORK"
mkdir -p "$ICON_WORK/Brim.iconset"
for BASE in 16 32 128 256 512; do
    sips -z "$BASE" "$BASE" "$LOGO" --out "$ICON_WORK/Brim.iconset/icon_${BASE}x${BASE}.png" >/dev/null
    sips -z "$((BASE * 2))" "$((BASE * 2))" "$LOGO" --out "$ICON_WORK/Brim.iconset/icon_${BASE}x${BASE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_WORK/Brim.iconset" -o "$RESOURCES_DIR/Brim.icns"
cp "$LOGO" "$RESOURCES_DIR/BrimLogo.png"
rm -rf "$ICON_WORK"

# Localizations (English + Romanian): Resources/<lang>.lproj/Localizable.strings.
for LPROJ in "$SCRIPT_DIR"/Resources/*.lproj; do
    cp -R "$LPROJ" "$RESOURCES_DIR/"
done

# Media controls run this helper inside /usr/bin/perl, which mediaremoted still serves
# (see NowPlayingMediaRemote.swift). The app signature below seals both files.
echo "==> Building the MediaRemote helper..."
HELPER_DIR="$SCRIPT_DIR/Resources/MediaRemoteHelper"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 -framework Foundation \
    -o "$RESOURCES_DIR/BrimMediaRemote.dylib" "$HELPER_DIR/BrimMediaRemote.m"
cp "$HELPER_DIR/brim-mediaremote.pl" "$RESOURCES_DIR/brim-mediaremote.pl"

"$SCRIPT_DIR/scripts/sign_app.sh" "$APP_BUNDLE"

echo ""
echo "Build succeeded: $APP_BUNDLE"
echo "   Run it with: open \"$APP_BUNDLE\""
