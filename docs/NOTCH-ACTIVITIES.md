# Notch activities — local development version

## Product scope

Each display has an independent hover surface sharing the activity and library
models. A MacBook uses its hardware notch; displays without a notch show a small
plain notch attached to the top edge. Active music/calls appear compactly while
collapsed. Hovering for a short dwell expands the panel. Launch, reopen,
screenshot completion and activity changes never expand it. Leaving collapses it
after a short grace period; a drag, menu or confirmation retains an open panel.
All surfaces disappear during capture. Reduced Motion uses short fades.

Home prioritizes an active call, then music, with recent screenshots when idle.
Library combines screenshots with new copied images, text and HTTP/HTTPS links.
It provides text search, All/Images/Text/Links filters, copy and drag actions,
screenshot editing/export, and explicit link opening. Its search field can receive
keyboard focus after a click; hovering alone does not activate the app.

Clipboard monitoring begins at launch and skips clipboard contents that predate
monitoring or were copied while paused. Recognized concealed/transient/password
markers and Brim's own copy markers are excluded before reading content.
History is stored locally under `Application Support/Brim/Clipboard` with
mode-700 directory and mode-600 files. Limits are 100 entries, 100 MB of content
and thumbnails, 100,000 UTF-8 bytes per text item, and 16 MB per encoded image.
Images also have pixel/dimension limits. JSON metadata has a separate bounded
size allowing escaped text. Duplicate items move to the front. Pause, delete and
clear controls are available in Library; pause lasts for the current app session.
Clipboard previews never fetch links or send stored content to external services.

## Connections and trust boundaries

Running players and supported calls are discovered automatically. The panel and
Preferences → Connections show an access action when an OS grant is missing. Music
uses public Apple Events for supported native players and browser integrations,
plus Accessibility for the installed YouTube Music app where needed. Calls use
public Accessibility to identify known, enabled call controls. Simply running a
chat app is not evidence of an active call. Controls are revalidated before use.
No call is placed by Brim and no microphone recording is added.

`AppSettings.callIntegrationEnabled` controls automatic call detection and defaults
to enabled; a previously saved off preference is respected. Music sources come
from currently running supported applications, not the legacy saved source list.
System Automation and Accessibility grants remain controlled by
macOS. Background refresh must not request new grants. Work runs on serialized
background queues with time/node budgets; UI updates stay on the main actor.

Music adapters target Apple Music, Spotify, YouTube Music in supported browsers,
and the installed YouTube Music app. Call adapters target Zoom, FaceTime,
WhatsApp, Phone, Discord, Teams and Google Meet. Availability depends on a provider's
exposed controls, browser settings and language. Unrecognized controls remain
unavailable rather than being replaced by guessed actions. This is not a claim
of universal compatibility with every calling or audio app.

## Architecture and delivery plan

- `Activities/NowPlaying*`: typed snapshots, source adapters, polling model and
  playback card. Scripts/events are fixed and scoped; metadata is treated as data.
- `Activities/Call*`: exact call evidence, bounded AX traversal, fresh control
  validation, polling model and call card.
- `Notch/`: per-display hover state/geometry, native panels, Home and searchable
  Library, bounded clipboard persistence and existing screenshot storage.
- `Settings/ConnectionsSettingsView`: discovery status and missing-permission actions.
- `Resources/Brim.entitlements`: Apple Events entitlement for development
  signing. It permits requesting Automation consent, not automatic access.

Changes are verified with integrated tests, independent source/security review,
release build and local installation. Keep the last working installed bundle as a
rollback copy. Avoid rebuilding the installed app during interaction checks.

## Local development signing

The local setup keeps `signing.keychain-db`, `certificate.der` and
`keychain-password` under `~/Library/Application Support/Brim/DevelopmentSigning`.
The directory requires mode 700 and each file mode 600. No key material belongs in
the repository. Builds reuse the existing identity and never generate a replacement.

`build_app.sh` prefers this identity when present, preserving it if an Apple
certificate is later installed. `BRIM_SIGNING_IDENTITY` explicitly selects a
valid identity by exact hash or name instead. Without either, the default requires
a valid Apple Development certificate. Ad-hoc signing requires explicit
`BRIM_ALLOW_ADHOC=1`; signing failures never silently fall back.

The local designated requirement pins both the leaf certificate and
`io.github.cezarprox.brim`. The isolated keychain is unlocked and temporarily added to
the user search list for signing. Cleanup locks it and removes only the build's
addition, preserving other entries. No certificate trust settings are modified.
Strict signature verification follows signing. This setup provides stable local
code identity; it does not replace macOS grants or qualify for App Store distribution.
Moving from an ad-hoc build may require granting access to the new signed identity.

## Verification

Earlier 2026-09-11 delivery: the full Swift suite passed 47 tests. Release packaging and strict bundle signature verification
passed. Captures, populated/empty music and empty calls were checked in offscreen
AppKit renders using explicitly synthetic fixtures. The installed app launched
successfully and its Connections pane was inspected on this Mac. A live macOS
toolbar overflow found during that check was fixed with explicit segmented
settings navigation; the targeted settings test and independent review passed.
The corrected release was installed in `/Applications/Brim.app`; its strict
signature check passed and live UI inspection confirmed all six visible settings
categories and the Connections pane. The notch setting remained enabled.
At that earlier delivery, real playback and active-call actions had not been
verified. The later installed YouTube Music transport fix passed a live
Play/Pause/Play sequence through Brim's shared player, with advancing time
confirmed independently in YouTube Music. Active-call actions and the other
music providers have not been live-tested.

The library update additionally passed eight targeted clipboard tests covering
new-copy observation, sensitive markers, local persistence, size/count limits,
image replay exclusion, safe URLs, pause behavior and failed-write preservation.
The current integrated build and live checks are recorded in the delivery report.

Automated tests cover hover-only transitions, collapsed pixels, capture storage,
native-resolution export, music snapshot parsing, provider URL scoping, call
evidence, automatic discovery, permission classification and consent boundaries.
Offscreen AppKit renders check content but do not
replace live player or active-call testing. Never place a real call or hang up a
user's call to run tests. Live controls requiring new system grants are tested
only after the user grants access.

The App Store work remains a separate phase: distribution signing, sandbox eligibility
for integrations, entitlement review, distribution and disclosures. No private
MediaRemote API is used to bypass public integration limits.

## API references

- [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- [AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)
- [Automation consent preflight](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)
- [Chromium AppleScript support](https://www.chromium.org/developers/applescript/)

## Known integration limits

Standalone YouTube Music uses the named Accessibility player toolbar, heading,
artist links and available timing text. Its remote controls may belong to Chrome
while their window belongs to the PWA shim; control validation retains the exact
window from the shim's AXWindows list and re-reads only that window. Play/pause,
next and previous go to the PWA's own MediaRemote player, as Control Center does,
without activating its window: since macOS 15.4 mediaremoted ignores unentitled
processes, so the bundled `Resources/MediaRemoteHelper` runs inside Apple-signed
`/usr/bin/perl` (`NowPlayingMediaRemote.swift`). Play/pause is then verified by
re-reading the player. A build without the helper falls back to briefly activating
the PWA window and clicking the verified button. If Apple closes the perl route,
controls fail with an explicit message instead of sending to another player.
No global keyboard events or Chrome-wide fallback are used. When it exposes a recognized album link,
artwork loading reads that public YouTube Music album page and requires its title
to match the player's album. Image hosts and album redirects are allowlisted;
requests have time and byte limits, use no stored cookies and submit no consent
forms. Missing, mismatched or inaccessible artwork remains empty. This optional
artwork request is separate from the entirely local clipboard library. Active
player parsing and playback require live validation for each supported app. Browser sources require their explicit JavaScript
automation option in addition to macOS Automation consent. Call detection uses
supported English controls and conservative exact matching; unknown/localized
controls do not become guessed actions. Provider names list implemented adapters,
not a claim that every app/version/locale has been tested with a real call.
