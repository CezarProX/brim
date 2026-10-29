# Notch expansion — delivery, 11 September 2026

## Implemented

- Existing recording, call, native Clock timer and music providers now share the
  same priority list with dictation, focus, calendar, sharing, agent, system,
  batteries and optional foreground-app activities. User selection survives
  lower-priority context updates. Recording and calls can interrupt it.
- The attached notch remains on both internal and external displays. The compact
  shoulders curve into the top edge. Visible dimensions follow the current card
  immediately; the waveform still animates inside its fixed canvas.
- The grid button opens Activities. Extra live activities remain accessible in
  an overflow menu. Long activity cards scroll; native file/share dialogs keep
  the surface open.
- Native recording stop and Clock pause/resume/cancel remain available. A new
  independent Focus timer supports presets, pause/resume, restart and stop.
- Calls use actual app icons, stateful circular controls and exact Accessibility
  screen-share controls when a provider exposes them. Call identity is revalidated.
- Calendar is opt-in through EventKit. The next event appears in the panel, and
  becomes a live activity 15 minutes before it begins. Join accepts HTTPS meeting
  links from Zoom, Google Meet, Teams and Webex. No calendar events are modified.
- Battery cards read Mac/UPS and HID values. Separate AirPods left/right/case
  levels are read from connected System Information records with a bounded local
  probe. Disconnected cached levels and unknown charging state are not presented
  as live measurements.
- Clipboard image OCR runs locally through Vision. Clipboard items can be pinned,
  searched by recognized text, and copied as text. Existing metadata migrates and
  pin-aware quota eviction preserves the bounded local store.
- Dictation uses Speech and AVAudioEngine only after explicit Start and permission.
  On-device recognition is required; there is no server fallback. Collapse or
  switching cards keeps a recording active; Stop, session timeout and app shutdown
  release audio resources. Copy and insertion are explicit actions. Insertion
  revalidates the original editable AX target and never synthesizes global typing.
- Sharing accepts readable local files through a picker or drag/drop, then opens
  the native sharing picker. HTTP(S) links can be displayed as local QR codes.
  No upload or message is sent automatically. Clearing a list invalidates delayed
  drop callbacks.
- Optional foreground-app identity and short volume/Caps Lock changes use real
  OS state. Caps Lock is read through NSEvent.modifierFlags, without installing a
  keyboard monitor. Disabled sources stop their corresponding observation.
- An optional local JSON status provider displays genuine automation/agent state,
  model, progress and token values supplied by the producer. It does not infer
  token counts from a running Codex/Claude application.

## Local agent status contract

Open Activities → Agent status → Choose status file. A local tool may atomically
replace that file with JSON like:

```json
{
  "title": "Building the application",
  "state": "working",
  "updatedAt": "2026-09-11T16:00:00Z",
  "model": "Sol",
  "tokens": 1234,
  "progress": 0.4
}
```

Use the current ISO-8601 timestamp. Valid states are `working`, `waiting`,
`completed`, `failed`. Model, tokens and progress are optional. Progress must be
within 0…1, tokens nonnegative. Files are limited to 64 KiB and status expires
after two minutes. Polling rejects symlinks/nonregular files and executes no data
as code. No transcript folders are scanned. Disconnect removes the saved path.

## Verification and boundaries

The integrated Swift suite passed **191 tests in 37 suites**, including the
music/timer/recording transition checks, attached-notch geometry, new local
provider validation, clipboard migration/OCR/pins, dictation lifecycle, and
render/OCR checks for the new cards. Synthetic render artifacts are under
`/tmp/brim-expansion-renders`. Sol independently reviewed the expansion;
identified lifecycle, stale callback, scrolling and preference issues were fixed.
The Bluetooth probe regression also verifies that a timed-out subprocess and its
worker are terminated. A visual run made while inspecting app windows failed;
the isolated waveform check and subsequent full run without UI interaction passed.
The final release bundle at `build/Brim.app` passed strict code-signature
verification and retains the installed app's designated signing requirement.
After explicit user confirmation, the release was installed at
`/Applications/Brim.app` and restarted. The running app's installed executable
matches the release bundle SHA-256. The previous app is backed up at
`/tmp/Brim-before-expansion-20260911-225553.app`.

Live microphone consent, dictation insertion, calendar access, active-call actions
and AirPods reconnection require the appropriate device/app/permission state.
Automated tests do not claim those real actions were exercised.

Not delivered as universal OS integrations: notification mirroring/quick reply,
brightness HUD replacement, weather, browser navigation, automatic Codex/Claude
session adapters, and direct Google Drive OAuth uploads. The native volume HUD is
not suppressed. AirDrop and other native sharing services depend on installed
services. Clipboard OCR covers new copied images; older images and screenshot
shelf records are not automatically backfilled. These boundaries replace the
broader speculative competitor feature list with the actual shipped behavior.
