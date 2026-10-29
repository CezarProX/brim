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

# Resolve a stable identity before replacing the existing build. An ad-hoc
# signature changes the app's designated requirement on every changed build.
SIGN_IDENTITY=""
REQUESTED_IDENTITY="${BRIM_SIGNING_IDENTITY:-}"
LOCAL_SIGNING_DIR="$HOME/Library/Application Support/Brim/DevelopmentSigning"
LOCAL_KEYCHAIN=""
LOCAL_REQUIREMENT=""
# Keep an existing local development identity stable even if a new Apple
# certificate appears later. An explicit identity override takes precedence.
if [[ -z "$REQUESTED_IDENTITY" && -d "$LOCAL_SIGNING_DIR" ]]; then
    if [[ "$(stat -f '%Lp' "$LOCAL_SIGNING_DIR")" != "700" ]]; then
        echo "error: the local signing directory must have permissions 700." >&2
        exit 1
    fi
    for local_file in signing.keychain-db certificate.der keychain-password; do
        if [[ ! -f "$LOCAL_SIGNING_DIR/$local_file" || -L "$LOCAL_SIGNING_DIR/$local_file" || "$(stat -f '%Lp' "$LOCAL_SIGNING_DIR/$local_file")" != "600" ]]; then
            echo "error: local signing files are missing or must have permissions 600." >&2
            exit 1
        fi
    done
    # Certificate fingerprint pins the exact private-key identity; never use
    # an identifier-only requirement or add the certificate to system trust.
    SIGN_IDENTITY="$(shasum -a 1 "$LOCAL_SIGNING_DIR/certificate.der" | awk '{print $1}')"
    LOCAL_KEYCHAIN="$LOCAL_SIGNING_DIR/signing.keychain-db"
    LOCAL_REQUIREMENT="designated => identifier \"io.github.cezarprox.brim\" and certificate leaf = H\"$SIGN_IDENTITY\""
else
VALID_IDENTITIES="$(security find-identity -v -p codesigning)"
IDENTITY_PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"([^"]+)"'
while IFS= read -r identity_line; do
    if [[ "$identity_line" =~ $IDENTITY_PATTERN ]]; then
        identity_hash="${BASH_REMATCH[1]}"
        identity_name="${BASH_REMATCH[2]}"
        if [[ -n "$REQUESTED_IDENTITY" ]]; then
            if [[ "$REQUESTED_IDENTITY" == "$identity_name" || "$REQUESTED_IDENTITY" == "$identity_hash" ]]; then
                SIGN_IDENTITY="$identity_hash"
                break
            fi
        elif [[ "$identity_name" == "Apple Development: "* ]]; then
            SIGN_IDENTITY="$identity_hash"
            break
        fi
    fi
done <<< "$VALID_IDENTITIES"
fi

if [[ -n "$REQUESTED_IDENTITY" && -z "$SIGN_IDENTITY" ]]; then
    echo "error: BRIM_SIGNING_IDENTITY must name a valid code-signing identity or its exact certificate hash." >&2
    exit 1
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    if [[ "${BRIM_ALLOW_ADHOC:-0}" != "1" ]]; then
        echo "error: no valid Apple Development signing identity. Renew it in Xcode or set BRIM_SIGNING_IDENTITY." >&2
        echo "For temporary ad-hoc testing only, set BRIM_ALLOW_ADHOC=1; rebuilt apps may need permission again." >&2
        exit 1
    fi
    SIGN_IDENTITY="-"
fi

echo "==> Building $APP_NAME (release)..."
swift build -c release

BINARY_PATH="$(swift build -c release --show-bin-path)/$PRODUCT_NAME"

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
codesign --force --sign - "$RESOURCES_DIR/BrimMediaRemote.dylib"
cp "$HELPER_DIR/brim-mediaremote.pl" "$RESOURCES_DIR/brim-mediaremote.pl"

if [[ -n "$LOCAL_KEYCHAIN" ]]; then
    echo "==> Signing with the existing local development certificate."
    # codesign's certificate resolution also consults the search list. Add this
    # isolated keychain only for signing; do not change certificate trust.
    signing_keychains=()
    local_keychain_was_listed=0
    signing_keychain_list="$(security list-keychains -d user)"
    while IFS= read -r entry; do
        signing_keychains+=("$entry")
        if [[ "$entry" == "$LOCAL_KEYCHAIN" ]]; then local_keychain_was_listed=1; fi
    done < <(printf '%s\n' "$signing_keychain_list" | sed 's/^ *"//;s/"$//')
    cleanup_local_signing() {
        security lock-keychain "$LOCAL_KEYCHAIN" >/dev/null 2>&1 || true
        if [[ "$local_keychain_was_listed" == "0" ]]; then
            if ! remaining_keychain_list="$(security list-keychains -d user)"; then
                echo "warning: could not read the keychain search list; leaving it unchanged." >&2
                return 1
            fi
            remaining_keychains=()
            while IFS= read -r entry; do
                if [[ "$entry" != "$LOCAL_KEYCHAIN" ]]; then remaining_keychains+=("$entry"); fi
            done < <(printf '%s\n' "$remaining_keychain_list" | sed 's/^ *"//;s/"$//')
            security list-keychains -d user -s "${remaining_keychains[@]}"
        fi
    }
    trap cleanup_local_signing EXIT
    if [[ "$local_keychain_was_listed" == "0" ]]; then
        security list-keychains -d user -s "${signing_keychains[@]}" "$LOCAL_KEYCHAIN"
    fi
    security unlock-keychain -p "$(cat "$LOCAL_SIGNING_DIR/keychain-password")" "$LOCAL_KEYCHAIN"
    codesign --force --deep --options runtime --timestamp=none \
        --keychain "$LOCAL_KEYCHAIN" --requirements "=$LOCAL_REQUIREMENT" \
        --entitlements "$SCRIPT_DIR/Resources/Brim.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Explicit ad-hoc test build; privacy permissions may not survive rebuilding."
    codesign --force --deep --entitlements "$SCRIPT_DIR/Resources/Brim.entitlements" --sign - "$APP_BUNDLE"
else
    echo "==> Code signing with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --entitlements "$SCRIPT_DIR/Resources/Brim.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --strict "$APP_BUNDLE"

echo ""
echo "Build succeeded: $APP_BUNDLE"
echo "   Run it with: open \"$APP_BUNDLE\""
