# Notch activity expansion

## Product brief

Brim should turn its existing per-display notch shelf into one animated,
prioritized activity surface for short-lived Mac context and controls. The surface
remains attached to the physical top edge on every display. MacBooks use the real
notch geometry; external displays keep the current simulated edge-attached notch.
A floating island is outside this product direction.

The first release should make current recording, timer, call and media activities
feel like one system, then add battery, calendar, clipboard OCR and pins,
dictation, contextual app/AI status, system HUD feedback and reliable sharing in
small independent slices. Brim must show only state it can obtain from a
public API or freshly validated local evidence. It must not invent durations,
completion percentages, meeting identities, AI progress, device state or action
success.

### User outcomes

- The highest-value live activity is readable while compact and opens into the
  correct controls without changing displays or detaching from the screen edge.
- Starting a second activity does not silently discard the first; the user can
  switch between active items and return to the library.
- Recording, timer and call actions operate on the exact session the user saw and
  fail closed when that session changes.
- Calendar, clipboard, dictation, batteries and contextual status disclose their
  permission/source and remain useful when optional access is absent.
- Screenshot and clipboard sharing opens a real system share UI anchored to the
  surface or editor that invoked it.

### Non-goals and evidence limits

- Reproducing private Dynamic Island scheduling, system animations or unpublished
  Apple layout constants.
- Reading private call, meeting or AI service data; placing calls; recording call
  audio; or guessing provider keyboard shortcuts.
- Claiming universal app/provider/locale support. Accessibility controls vary by
  app version, language and current window structure.
- Replacing Notification Center, Control Center, Calendar, Clock or Dictation.
- Claiming a competitor exposes a recording stop action. Research supports a
  recording indicator only; Brim's stop control is its own macOS integration.
- Adding an external upload backend. The existing uploader accepts a user-configured
  endpoint; the system share sheet is the default local sharing path.

## Existing foundation

The expansion extends working code rather than replacing it:

- `NotchShelfController` creates one nonactivating `IslandPanel` per `NSScreen`,
  uses real notch geometry when available and `NotchGeometry.simulatedExternal`
  otherwise, suspends during capture, and owns hover/announcement timing.
- `NotchShelfView`, `NotchPresentation`, `IslandActivities` and `NotchMotion`
  already provide compact/expanded layouts, activity switching, reduced-motion
  behavior, and the Home/Library shell. Priority is currently the fixed order
  recording, call, timer, music.
- `ScreenRecordingModel` detects native Screenshot/QuickTime recording evidence
  from bounded local process descriptors. Its stop bridge revalidates the
  recording identity before posting Apple's Command-Control-Escape shortcut.
  This is limited to the native recording flow and requires post-event access.
- `NativeTimerModel`, `NativeTimerProbe` and `NativeTimerControls` observe native
  Clock timers and revalidate identity before pause, resume or cancel.
- `CallActivityModel` and `CallAccessibilityBridge` detect a bounded set of call
  providers from exact, enabled Accessibility controls, then re-scan the same
  process/window/scope before an action. Leave confirmation is bound to a call UUID.
- `NowPlayingModel` and its adapters provide media state and controls with
  source-specific trust and compatibility limits. `AudioOutputModel` uses CoreAudio.
- `ShelfStore`, `ClipboardStore` and `ClipboardLibraryView` persist bounded local
  screenshot/clipboard history, exclude sensitive/transient markers, and support
  search, filtering, copy, drag, edit, save and explicit link opening. OCR and pins
  do not exist yet.
- `CaptureActions.share` already presents `NSSharingServicePicker` when given an
  `NSView`; the coordinator currently passes no anchor and falls back to copy.
- At the planning baseline there were no battery, EventKit calendar, Vision OCR,
  speech recognition, contextual app/AI activity, or volume/brightness HUD models;
  the checklist below defines their incremental introduction.

## Architecture and contracts

### 1. Activity coordinator

Add a typed coordinator alongside `Notch/IslandActivities.swift`; do not make each
view infer global priority independently.

```swift
enum ActivityKind: Hashable, Sendable
struct ActivityID: Hashable, Sendable { let kind: ActivityKind; let source: String }
struct ActivityDescriptor: Identifiable, Equatable, Sendable {
    let id: ActivityID
    let urgency: ActivityUrgency
    let beganAt: Date?
    let isActionable: Bool
}
@MainActor final class ActivityCoordinator: ObservableObject {
    @Published private(set) var ordered: [ActivityDescriptor]
    @Published var selectedID: ActivityID?
}
```

Ordering is explicit Brim policy: destructive/time-critical work in progress,
recording, call, elapsed timer, user-selected activity, newly announced activity,
media, upcoming calendar, dictation/context status, batteries. Stable IDs and a
stable tie-breaker prevent cards from jumping on every poll. A user selection is
retained while its activity exists. Empty state falls back to Home/Library.

Models publish immutable snapshots on the main actor. Probes and provider calls run
off-main with cancellation, time/node/byte bounds. An action accepts an expected
activity/session ID, re-reads current evidence, verifies provider/process/window
identity and required control state, then performs at most one side effect. Success
is published only after a fresh observation confirms it; otherwise the UI reports
an actionable limitation.

### 2. Surface and motion

Keep `NotchShelfController` as the sole per-display panel owner and keep the panel
top-edge attached for external monitors. `NotchGeometry` remains the source of
collapsed, expanded and secondary frames. The coordinator supplies content; each
display retains independent hover, expansion and selected presentation state.

Use one shell whose mask and dimensions animate through `NotchMotion`. Activity
content uses stable identities and matched geometry only for elements present in
both states. New activity announcements may reveal a compact preview but must not
steal keyboard focus or force a full expansion. Reduced Motion uses short opacity
and size changes without spring overshoot. Capture suspension hides all surfaces.

### 3. Provider boundaries

| Domain | Preferred source | Action contract | Honest fallback |
|---|---|---|---|
| Recording | Existing bounded native recorder probe | Existing identity revalidation, then documented system shortcut | Indicator only; explain missing Accessibility/post-event access |
| Timer | Existing native Clock probe | Exact timer ID plus fresh AX validation | Read-only countdown or unavailable control message |
| Calls/share | Exact enabled AX controls in supported app/window/scope | Revocable token, same PID/window/scope/title/control label, identity-bound confirmation for Leave and starting screen share | Open provider; omit controls that are absent or ambiguous |
| Batteries | IOKit/IOPowerSources for Mac and publicly exposed power sources | Read-only | Show only returned devices/percentages; no inferred accessory inventory |
| Calendar | EventKit after explicit user request | Open event/deep link only when a valid identifier/URL exists | Next-event card omitted when denied, restricted or empty |
| OCR | Vision `VNRecognizeTextRequest` on local stored images | Save derived text against the immutable clipboard/shelf entry ID | Keep image and expose “Text unavailable”; never send pixels remotely |
| Dictation | Speech/AVFoundation with explicit permission and visible recording state | Start/stop a Brim-owned session ID; insert/copy only confirmed transcript | Local text entry/copy; no background microphone start |
| App/AI status | Explicit adapter protocol with provider-authored state or user-triggered Brim task state | Only adapter-declared actions with fresh task ID | App name/icon and neutral “Open app”; no guessed progress or completion |
| System HUD | Public notifications/APIs available to this process; otherwise user-triggered Brim changes | Apply value through a public API, then read it back | Omit unsupported global interception, especially brightness on unsupported displays |
| Sharing | Existing `NSSharingServicePicker` anchored to the invoking `NSView` | Retain picker/delegate until completion; keep source item alive | Copy only when the user explicitly chooses Copy, not as silent “share” success |

Every optional integration gets an `AppSettings` preference and a settings row that
states its source, permission and last confirmed availability. Background polling
never prompts for permissions. Persist only data required for the feature, using
the existing protected Application Support conventions and bounded retention.

### 4. Feature slices

**Calls.** Polish `CallActivityView` with the running application's real icon,
readable provider/title hierarchy, observed duration, stateful circular controls
and a red Leave control. Add screen-sharing state/action only when exactly one
known enabled AX label exists alongside existing active-call evidence. Revalidate
the same call and exact label immediately before pressing. Starting sharing and
leaving use confirmation bound to the displayed call UUID. Never replace a missing
control with a shortcut.

**Batteries and calendar.** Add independent read-only models before changing the
surface. Battery snapshots contain stable device ID, display name, level, charging
state and source timestamp. Calendar requests only the minimum EventKit access and
queries a bounded look-ahead window; snapshots contain event ID, title, start/end,
all-day flag and join URL only when safely parsed.

**Clipboard OCR and pins.** Extend persisted clipboard metadata with versioned,
optional OCR state and `isPinned`. Pins are excluded from normal count eviction but
remain subject to an explicit pinned byte/count cap. Vision work is deduplicated by
entry ID/content digest, cancellable and off-main. Search indexes confirmed OCR
text; original images stay local and unchanged. Migration failures preserve the
old library and surface an error.

**Dictation.** Model permission, idle, listening, processing, result and error as
distinct states. The compact indicator must be visible for every microphone-active
moment. Stop on device/input loss, app shutdown, permission revocation or the
session ID changing. Keep partial text ephemeral; persist/copy only after an
explicit user action.

**Contextual app/AI status.** Start with Brim-owned work (capture, encode,
upload, OCR, dictation) because its lifecycle is authoritative. External adapters
must return typed capability/state snapshots and an evidence timestamp. An app
icon or foreground process alone is never evidence that an AI task is running.

**System HUD and sharing.** First show HUD feedback only for changes Brim
initiates and can read back. Treat observation of arbitrary system volume/brightness
changes as a later feasibility spike. Fix screenshot sharing by carrying an anchor
from editor/shelf UI to `CaptureActions.share`; report picker dismissal separately
from a chosen service and do not label clipboard fallback as a completed share.

## Incremental delivery checklist

Each phase is independently mergeable and keeps the existing surface functional.

### Phase 0 — contracts and regression baseline (small)

- [ ] Add coordinator policy tests for stable ordering, user selection, multiple
  simultaneous activities, removal and reduced-motion announcements.
- [ ] Record current screenshot/recording/timer/call/media/library tests and render
  fixtures as the regression baseline; distinguish synthetic renders from live use.
- [ ] Preserve real and simulated notch geometry tests, including exact physical
  top-edge hover and vertically arranged external displays.

### Phase 1 — unify current activities (medium)

- [ ] Introduce `ActivityDescriptor`/`ActivityCoordinator` and adapters for the four
  existing models without changing their provider implementations.
- [ ] Route compact, secondary and expanded selection through the coordinator;
  retain per-display selected/hover state in `NotchPresentation`.
- [ ] Add transition tests for activity arrival/removal during expansion and while a
  confirmation/menu/action is active.
- [ ] Verify the external-display surface remains attached to the top edge. Do not
  adopt a floating capsule.

### Phase 2 — action fidelity and calls (medium)

- [ ] Keep recording stop and timer controls bound to their observed identities;
  make errors/capabilities readable in compact and expanded states.
- [ ] Polish the call card and app icon, title/subtitle, duration and stateful controls.
- [ ] Add exact screen-share label/state parsing and same-call fresh revalidation;
  omit ambiguous providers/labels and require an ID-bound start confirmation.
- [ ] Unit-test normalized labels, ambiguous duplicates, stale snapshot rejection,
  token revocation and state transitions. Use synthetic AX fixtures where possible;
  never end or screen-share a real call as an automated test.

### Phase 3 — batteries and calendar (medium)

- [ ] Add bounded battery and EventKit models with injected clients and immutable
  snapshots; expose explicit permissions in Settings.
- [ ] Add compact/expanded cards, empty/denied/stale states and coordinator adapters.
- [ ] Test no-device, unknown percentage, charging changes, all-day/ongoing events,
  revoked calendar access, malformed join URLs and timezone/day-boundary behavior.

### Phase 4 — OCR and pins (large)

- [ ] Define and test versioned clipboard metadata migration and separate pinned
  storage limits before modifying persistence.
- [ ] Add a cancellable Vision OCR queue with content-digest deduplication and
  language-aware search over confirmed results.
- [ ] Add pin/unpin, pinned filtering and explicit deletion. Verify sensitive-marker
  exclusion still happens before any payload or OCR read.
- [ ] Test migration interruption, corrupt metadata, eviction, oversized images,
  OCR cancellation, duplicate content and complete local deletion.

### Phase 5 — dictation and authoritative context (large)

- [ ] Add an explicit microphone/speech permission flow and session state machine;
  background startup must remain silent.
- [ ] Add compact listening status, expanded transcript review and explicit copy or
  insertion destination.
- [ ] Introduce the external context adapter protocol, then ship Brim-owned
  capture/upload/OCR/dictation adapters first.
- [ ] Test permission revocation, input loss, stale session actions, app termination,
  partial-result cancellation and providers that return no status.

### Phase 6 — system HUD and sharing (medium)

- [ ] Carry real AppKit anchors from shelf/editor share buttons into the existing
  system sharing picker; keep lifecycle and cancellation explicit.
- [ ] Add HUD feedback for public, Brim-initiated and read-back-confirmed changes.
- [ ] Run feasibility spikes before promising observation/control of arbitrary
  volume, internal brightness or external-display brightness; omit unsupported paths.
- [ ] Test anchor lifetime, picker cancellation/service choice, repeated invocation,
  item eviction during sharing, multi-display placement and unsupported hardware.

### Release gate

- [ ] Run Swift format/lint when configured, `swift test`, release build and strict
  signature verification. Do not install as part of automated verification.
- [ ] Perform Accessibility, Calendar, microphone and screen-recording permission
  checks with the same stable signed bundle identity intended for use.
- [ ] Label provider/action validation precisely: automated, synthetic render,
  manually observed, or live action. A rendered card is not integration proof.
- [ ] Confirm no permission prompt occurs during background refresh and no stored
  clipboard, transcript, event or image content leaves the Mac unexpectedly.

## Principal risks

- **AX drift/localization:** exact controls disappear after provider updates. Fail
  closed, keep provider label tables isolated and add captured synthetic fixtures
  for every verified version/locale.
- **False activity priority:** noisy polling could reorder the surface. Debounce
  snapshots, retain stable IDs/selections and define deterministic tie-breakers.
- **Privacy expansion:** OCR, calendar and dictation add sensitive local data. Ask
  only on an explicit action, bound retention, redact diagnostics and make deletion
  complete and testable.
- **Identity drift:** a delayed action could target a new recording, timer, call or
  dictation session. Require expected IDs at the UI/model/bridge boundary and fresh
  evidence immediately before every side effect.
- **Unsupported system integration:** macOS does not expose every HUD or third-party
  task state through public APIs. Ship narrower truthful capability states instead
  of simulated success, guessed shortcuts or private global hooks.

## Implementation status for this expansion pass

Implemented in the call slice: the expanded card uses the running process's real
app icon when available, shows a readable call title/provider and observed duration,
and renders microphone/camera/screen-share state as active white or inactive dark
circular controls with a red Leave action. Screen sharing is exposed only for one
exact known AX label found alongside existing active-call evidence. Both the label
and state are re-read in the same PID/window/scope before one AX press; starting a
share and leaving remain bound to the displayed call UUID. No provider shortcut or
call duration claim was added.

Implemented in the clipboard slice: version-tolerant metadata now stores optional
local Vision OCR text and a pin bit. OCR is bounded to the existing text ceiling,
included in search, and can be copied explicitly with Brim's replay-exclusion
marker. Pinned entries are retained before recent unpinned entries while the same
global count/content quotas remain in force; clear-unpinned preserves pins. Image
drag providers retain data and supply a safe suggested PNG filename. Sensitive and
transient pasteboard markers are still rejected before content or OCR is read.

The implementation does not establish live compatibility for any provider's
screen-share control, and it has not started, stopped or left a real call. Actual
AX labels still depend on provider version and language, so absent or ambiguous
labels remove the control. OCR remains local but Vision accuracy varies by image;
an empty or failed recognition produces no searchable text. No app installation or
permission mutation is part of this pass. Battery, calendar, activity coordination,
dictation, contextual status and HUD work are separate owned slices and must be
assessed from their own tests and integration report.

Targeted verification for this slice passed 28 Swift Testing cases across
`CallActivityTests`, `CallDiscoveryTests`, `ClipboardStoreTests` and
`ClipboardLibraryViewTests`. These include exact/ambiguous screen-share labels,
authorization revocation, quiet permission behavior, legacy metadata decoding,
pin retention and unpin recency, OCR copy/replay exclusion, Unicode byte bounds,
quota preservation and an offscreen synthetic library render. The render and
injected OCR fixture verify code paths, not live provider behavior or Vision
accuracy on arbitrary images.
