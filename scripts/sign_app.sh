#!/bin/bash
# Stable app signing, shared by packaging and local installation. Never creates identities.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/signing-policy.conf"
MODE=sign
APP=""
EXPECTED_BUNDLE="$BRIM_BUNDLE_ID"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE=check; shift ;;
        --verify) MODE=verify; shift ;;
        --bundle-id)
            [[ $# -ge 2 ]] || { echo 'error: --bundle-id needs an identifier.' >&2; exit 1; }
            EXPECTED_BUNDLE="$2"; shift 2 ;;
        -*) echo 'usage: sign_app.sh [--check|--verify] [--bundle-id ID] [APP]' >&2; exit 1 ;;
        *) [[ -z "$APP" ]] || { echo 'error: only one app is accepted.' >&2; exit 1; }; APP="$1"; shift ;;
    esac
done
[[ "$EXPECTED_BUNDLE" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || { echo 'error: invalid bundle identifier.' >&2; exit 1; }
[[ "$BRIM_SIGNING_CERT_SHA1" =~ ^[0-9a-f]{40}$ ]] || { echo 'error: invalid pinned signer.' >&2; exit 1; }
REQUIREMENT="identifier \"$EXPECTED_BUNDLE\" and certificate leaf = H\"$BRIM_SIGNING_CERT_SHA1\""
if [[ "${BRIM_PUBLIC_RELEASE_ADHOC:-0}" != "0" || "${BRIM_ALLOW_ADHOC:-0}" != "0" ]]; then
    echo 'error: ad-hoc signing is disabled; it resets privacy permissions on every changed build.' >&2
    exit 1
fi
verify_app() {
    local bundle
    bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
    [[ "$bundle" == "$EXPECTED_BUNDLE" ]] || { echo 'error: app bundle identifier differs from the signing policy.' >&2; return 1; }
    codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"
    local actual
    actual="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
    [[ "$actual" == "$REQUIREMENT" ]] || { echo 'error: app must use the exact stable certificate-bound designated requirement.' >&2; return 1; }
}
if [[ "$MODE" == verify ]]; then
    [[ -d "$APP/Contents" ]] || { echo 'error: app not found.' >&2; exit 1; }
    verify_app
    exit 0
fi
SIGNING_DIR="${BRIM_LOCAL_SIGNING_DIR:-$HOME/Library/Application Support/Brim/DevelopmentSigning}"
[[ -d "$SIGNING_DIR" && ! -L "$SIGNING_DIR" ]] || { echo 'error: existing stable signing directory is missing.' >&2; exit 1; }
[[ "$(stat -f '%Lp' "$SIGNING_DIR")" == 700 ]] || { echo 'error: signing directory must have permissions 700.' >&2; exit 1; }
for signing_file in certificate.der signing.keychain-db keychain-password; do
    candidate="$SIGNING_DIR/$signing_file"
    [[ -f "$candidate" && ! -L "$candidate" && "$(stat -f '%Lp' "$candidate")" == 600 ]] || {
        echo 'error: stable signing files must be regular files with permissions 600.' >&2; exit 1;
    }
done
ACTUAL_CERT="$(shasum -a 1 "$SIGNING_DIR/certificate.der" | awk '{print $1}')"
[[ "$ACTUAL_CERT" == "$BRIM_SIGNING_CERT_SHA1" ]] || {
    echo 'error: certificate differs from the pinned Brim signer; refusing to change identity.' >&2; exit 1;
}
openssl x509 -inform der -in "$SIGNING_DIR/certificate.der" -checkend 0 -noout >/dev/null || {
    echo 'error: stable signing certificate has expired.' >&2; exit 1;
}
REQUESTED="${BRIM_SIGNING_IDENTITY:-$BRIM_SIGNING_CERT_SHA1}"
[[ "$REQUESTED" == "$BRIM_SIGNING_CERT_SHA1" ]] || {
    echo 'error: BRIM_SIGNING_IDENTITY must equal the pinned certificate fingerprint.' >&2; exit 1;
}
if [[ "$MODE" == check ]]; then
    echo "Stable signing identity ready: $BRIM_SIGNING_CERT_SHA1"
    exit 0
fi
[[ -d "$APP/Contents" ]] || { echo 'error: app not found.' >&2; exit 1; }
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$BUNDLE" == "$EXPECTED_BUNDLE" ]] || { echo 'error: app bundle identifier differs from the signing policy.' >&2; exit 1; }
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
ORIGINAL_KEYCHAINS=()
WAS_LISTED=0
KEYCHAIN_LIST="$(security list-keychains -d user)"
while IFS= read -r entry; do
    ORIGINAL_KEYCHAINS+=("$entry")
    [[ "$entry" != "$KEYCHAIN" ]] || WAS_LISTED=1
done < <(printf '%s\n' "$KEYCHAIN_LIST" | sed 's/^ *"//;s/"$//')
cleanup() {
    security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    if [[ "$WAS_LISTED" == 0 ]]; then
        local remaining=()
        local current
        if current="$(security list-keychains -d user)"; then
            while IFS= read -r entry; do
                [[ "$entry" == "$KEYCHAIN" ]] || remaining+=("$entry")
            done < <(printf '%s\n' "$current" | sed 's/^ *"//;s/"$//')
            security list-keychains -d user -s "${remaining[@]}"
        else
            echo 'warning: could not restore signing keychain search list.' >&2
        fi
    fi
}
trap cleanup EXIT
if [[ "$WAS_LISTED" == 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
fi
# The existing protected password file is consumed locally; never echoed or exported.
security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$KEYCHAIN"
SIGN_ARGS=(--timestamp=none --keychain "$KEYCHAIN")
# The deployed app was already non-hardened. Retain that baseline for the self-signed
# identity; do not add a library-validation bypass or change system certificate trust.
# A future Apple-issued channel must deliberately migrate the signer pin and use runtime.
if [[ "${BRIM_APPLE_SIGNING:-0}" == 1 ]]; then
    SIGN_ARGS+=(--options runtime)
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
    for nested in "$SPARKLE/Versions/Current/Autoupdate" "$SPARKLE/Versions/Current/Updater.app" \
        "$SPARKLE/Versions/Current/XPCServices/Downloader.xpc" "$SPARKLE/Versions/Current/XPCServices/Installer.xpc" "$SPARKLE"; do
        [[ -e "$nested" ]] || { echo 'error: Sparkle helper is missing.' >&2; exit 1; }
        codesign --force "${SIGN_ARGS[@]}" --preserve-metadata=entitlements --sign "$BRIM_SIGNING_CERT_SHA1" "$nested"
    done
fi
if [[ -f "$APP/Contents/Resources/BrimMediaRemote.dylib" ]]; then
    codesign --force "${SIGN_ARGS[@]}" --sign "$BRIM_SIGNING_CERT_SHA1" "$APP/Contents/Resources/BrimMediaRemote.dylib"
fi
codesign --force "${SIGN_ARGS[@]}" --requirements "=designated => $REQUIREMENT" \
    --entitlements "$ROOT/Resources/Brim.entitlements" --sign "$BRIM_SIGNING_CERT_SHA1" "$APP"
verify_app
if [[ "${BRIM_APPLE_SIGNING:-0}" == 1 ]]; then
    codesign --verify --strict -R '=anchor apple generic' "$APP"
fi
echo "Signed with stable identity: $BRIM_SIGNING_CERT_SHA1"
