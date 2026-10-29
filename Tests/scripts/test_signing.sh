#!/bin/bash
# Fail-closed signing checks; no private-key operations or full builds.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
fails_with() {
    local expected="$1"
    shift
    if "$@" >"$TEMP/output" 2>&1; then
        echo "FAIL: command unexpectedly succeeded: $*" >&2
        exit 1
    fi
    grep -F "$expected" "$TEMP/output" >/dev/null
    if grep -F 'DO_NOT_PRINT_SIGNING_PASSWORD' "$TEMP/output" >/dev/null; then
        echo 'FAIL: signing password leaked.' >&2
        exit 1
    fi
}
fails_with 'ad-hoc signing is disabled' env BRIM_PUBLIC_RELEASE_ADHOC=1 ./build_app.sh
fails_with 'ad-hoc signing is disabled' env BRIM_ALLOW_ADHOC=1 ./build_app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
fails_with 'ad-hoc signing is disabled' env BRIM_PUBLIC_RELEASE_ADHOC=1 ./scripts/release.sh "v$VERSION"
fails_with 'ad-hoc signing is disabled' env BRIM_ALLOW_ADHOC=1 ./scripts/release.sh "v$VERSION"
fails_with 'signing directory is missing' env BRIM_LOCAL_SIGNING_DIR="$TEMP/missing" ./scripts/sign_app.sh --check
mkdir "$TEMP/signer"
printf 'wrong certificate' >"$TEMP/signer/certificate.der"
printf 'not a keychain' >"$TEMP/signer/signing.keychain-db"
printf 'DO_NOT_PRINT_SIGNING_PASSWORD' >"$TEMP/signer/keychain-password"
chmod 700 "$TEMP/signer"
chmod 600 "$TEMP/signer/"*
fails_with 'certificate differs from the pinned' env BRIM_LOCAL_SIGNING_DIR="$TEMP/signer" ./scripts/sign_app.sh --check
chmod 755 "$TEMP/signer"
fails_with 'permissions 700' env BRIM_LOCAL_SIGNING_DIR="$TEMP/signer" ./scripts/sign_app.sh --check
chmod 700 "$TEMP/signer"
rm "$TEMP/signer/certificate.der"
ln -s "$ROOT/Resources/Info.plist" "$TEMP/signer/certificate.der"
fails_with 'regular files with permissions 600' env BRIM_LOCAL_SIGNING_DIR="$TEMP/signer" ./scripts/sign_app.sh --check
fails_with 'invalid bundle identifier' ./scripts/sign_app.sh --bundle-id 'bad" or true' --verify "$TEMP/missing.app"
./scripts/sign_app.sh --check >/dev/null
printf 'PASS: 9 fail-closed signing checks and stable identity preflight.\n'
