#!/bin/bash
# Prepare a complete, EdDSA-signed GitHub release. Publication is explicit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PUBLISH=0
NOTES=""
TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish) PUBLISH=1; shift ;;
        --notes)
            [[ $# -ge 2 ]] || { echo "error: --notes needs a file." >&2; exit 1; }
            NOTES="$2"; shift 2 ;;
        v[0-9]*)
            [[ -z "$TAG" ]] || { echo "error: specify only one version tag." >&2; exit 1; }
            TAG="$1"; shift ;;
        *) echo "usage: scripts/release.sh [--notes FILE] [--publish] vVERSION" >&2; exit 1 ;;
    esac
done
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: expected a tag such as v1.0.1." >&2; exit 1; }
VERSION="${TAG#v}"
PLIST="$ROOT/Resources/Info.plist"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
[[ "$SOURCE_VERSION" == "$VERSION" ]] || { echo "error: tag and Info.plist version differ." >&2; exit 1; }
if [[ -n "$NOTES" && ! -f "$NOTES" ]]; then
    echo "error: release notes file does not exist." >&2
    exit 1
fi
# Fail before builds/artifact mutation when the stable signer is unavailable or ad-hoc is requested.
"$ROOT/scripts/sign_app.sh" --check
COMMIT="$(git rev-parse HEAD)"
if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
    [[ "$(git rev-list -n 1 "$TAG")" == "$COMMIT" ]] || { echo "error: existing tag points to another commit." >&2; exit 1; }
fi
if [[ "$PUBLISH" == "1" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "error: commit all changes before publishing." >&2; exit 1; }
    REMOTE_MAIN="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
    [[ "$REMOTE_MAIN" == "$COMMIT" ]] || { echo "error: push this exact commit to origin/main first." >&2; exit 1; }
    if gh release view "$TAG" --repo CezarProX/brim >/dev/null 2>&1; then
        echo "error: this release already exists; published updates are immutable." >&2
        exit 1
    fi
fi

./build_app.sh
APP="$ROOT/build/Brim.app"
BUILT_PLIST="$APP/Contents/Info.plist"
# Exact DR equality to the public pin means every release satisfies every other release's DR.
"$ROOT/scripts/sign_app.sh" --verify "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$BUILT_PLIST")" == "$VERSION" ]] || {
    echo "error: built app version does not match tag." >&2; exit 1;
}
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$BUILT_PLIST")"
TOOLS="${SPARKLE_TOOLS_DIR:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
for tool in generate_keys generate_appcast sign_update; do
    [[ -x "$TOOLS/$tool" ]] || { echo "error: Sparkle tool not found: $TOOLS/$tool" >&2; exit 1; }
done
PUBLIC_KEY="$("$TOOLS/generate_keys" --account brim -p)"
BUNDLED_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$BUILT_PLIST")"
[[ "$PUBLIC_KEY" == "$BUNDLED_KEY" ]] || { echo "error: Keychain account brim does not match the app's update public key." >&2; exit 1; }
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$BUILT_PLIST")"
[[ "$FEED_URL" == "https://github.com/CezarProX/brim/releases/latest/download/appcast.xml" ]] || {
    echo "error: built app is not configured for the public release appcast." >&2; exit 1;
}

OUTPUT="$ROOT/build/releases/$TAG"
[[ ! -e "$OUTPUT" ]] || { echo "error: $OUTPUT already exists; move it aside before preparing again." >&2; exit 1; }
mkdir -p "$OUTPUT/stage"
ditto "$APP" "$OUTPUT/stage/Brim.app"
ln -s /Applications "$OUTPUT/stage/Applications"
DMG="$OUTPUT/Brim.dmg"
hdiutil create -volname "Brim $VERSION" -srcfolder "$OUTPUT/stage" -format UDZO "$DMG" >/dev/null
rm -rf "$OUTPUT/stage"
if [[ -n "$NOTES" ]]; then
    cp "$NOTES" "$OUTPUT/Brim.md"
else
    printf '# Brim %s\n\nSee the GitHub release for the changes in this version.\n' "$VERSION" > "$OUTPUT/Brim.md"
fi
DOWNLOAD_PREFIX="https://github.com/CezarProX/brim/releases/download/$TAG/"
"$TOOLS/generate_appcast" --account brim --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes --maximum-deltas 0 --versions "$BUILD" "$OUTPUT"
APPCAST="$OUTPUT/appcast.xml"
# Both the archive and feed signatures are required by the bundled updater.
"$TOOLS/sign_update" --account brim "$APPCAST"
"$TOOLS/sign_update" --account brim --verify "$APPCAST"
SIGNATURE="$(python3 - "$APPCAST" "$VERSION" "$BUILD" "$DMG" "$DOWNLOAD_PREFIX" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
feed, version, build, archive, prefix = sys.argv[1:]
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = ET.parse(feed).getroot().find('./channel/item')
assert item is not None, 'Appcast has no update'
assert item.findtext('sparkle:version', namespaces=ns) == build, 'Wrong update build'
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == version, 'Wrong update version'
minimum = item.findtext('sparkle:minimumSystemVersion', namespaces=ns) or ''
minimum_parts = [int(part) for part in minimum.split('.')]
assert (minimum_parts + [0, 0])[:3] == [14, 0, 0], 'Wrong minimum macOS'
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing archive enclosure'
assert enclosure.attrib['url'] == prefix + 'Brim.dmg', 'Wrong archive URL'
assert int(enclosure.attrib['length']) == Path(archive).stat().st_size, 'Wrong archive size'
signature = enclosure.attrib['{' + ns['sparkle'] + '}edSignature']
assert signature, 'Missing archive signature'
print(signature)
PY
)"
"$TOOLS/sign_update" --account brim --verify "$DMG" "$SIGNATURE"
(cd "$OUTPUT" && shasum -a 256 Brim.dmg > SHA256SUMS)
cp "$OUTPUT/Brim.md" "$OUTPUT/release-notes.md"
printf '\nPrepared %s at %s\n' "$TAG" "$OUTPUT"
if [[ "$PUBLISH" == "1" ]]; then
    gh release create "$TAG" --repo CezarProX/brim --target "$COMMIT" --title "Brim $VERSION" \
        --notes-file "$OUTPUT/release-notes.md" --latest "$DMG" "$APPCAST" "$OUTPUT/SHA256SUMS"
fi
