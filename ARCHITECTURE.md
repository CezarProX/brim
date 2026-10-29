# Brim Architecture

Brim is a menu-bar-only (`.accessory`, `LSUIElement`) macOS screenshot
utility, built as a pure Swift Package Manager executable (no SPM
dependencies — AppKit / ScreenCaptureKit / Carbon / UserNotifications only)
and assembled into a `.app` bundle by `build_app.sh`.

## Module layout

```
Sources/Brim/
├── main.swift                    NSApplication bootstrap (.accessory policy)
├── AppDelegate.swift              Status item + menu, launch wiring
├── Core/
│   ├── AppSettings.swift          Typed UserDefaults-backed preferences (contract)
│   ├── CaptureCoordinator.swift   Capture state machine (contract)
│   └── Annotation.swift           Annotation data model + undo/redo (contract)
├── Hotkey/
│   └── HotkeyManager.swift        Global hotkey registration (implemented)
├── Overlay/
│   └── OverlayController.swift    Per-screen selection overlay windows (implemented)
├── Editor/
│   ├── EditorSession.swift        Annotation editor state (implemented)
│   └── ...                        Canvas / toolbar / action-bar UI (implemented)
├── Capture/
│   ├── ScreenCapturer.swift       ScreenCaptureKit capture + crop (implemented)
│   ├── PermissionsHelper.swift    Screen Recording permission (implemented)
│   └── (CaptureActions.swift is actually under Actions/, see below)
├── Actions/
│   └── CaptureActions.swift       Copy/save/print/upload/search actions (implemented)
├── History/
│   ├── HistoryStore.swift             JSON-backed save/upload/clipboard log (implemented)
│   └── HistoryWindowController.swift  History list window (implemented)
├── Notifications/
│   └── NotificationCenterHelper.swift  UNUserNotificationCenter wrapper (implemented)
└── Settings/
    └── SettingsWindowController.swift  Preferences window (implemented)
```

## Shared contracts

### Notch shelf

`Notch/NotchShelfController` hosts a nonactivating SwiftUI panel, deriving its
position from NSScreen's real notch geometry. `NotchGeometry` and
`ShelfHoverState` isolate positioning and dwell/grace timing for tests.
`CaptureCoordinator` suspends the shelf before freezing displays and records
completed images with a stable per-session UUID. Repeated actions replace
that session's shelf entry.

`ShelfStore` keeps a separate private PNG and thumbnail cache under Application
Support/Brim/Shelf, bounded by 20 entries and 150 MB. UUID-only cleanup
never touches files saved by the user. Writes currently serialize on the main
actor; large-image encoding is a performance area to profile before release.
Drag providers hold PNG data independently of cache eviction. The standalone
`ShelfEditorWindowController` uses the existing annotation components and
retains native image resolution when exporting. Edited results receive a new
UUID, preserving the source capture.

See `docs/NOTCH-SHELF.md` for requirements, scope and validation.

The activity expansion adds `Activities/NowPlaying*` (public Apple Events,
browser-specific YouTube Music adapters and an Accessibility fallback) and
`Activities/Call*` (bounded Accessibility call evidence and controls). Models
refresh off-main and require explicit per-source consent. Queued call actions
use a revocable authorization gate; Leave confirmations are bound to a call UUID.
Music commands revalidate the selected source and track. The YouTube Music app
adapter sends to the active system media session using runtime-loaded MediaRemote;
it verifies playback through Accessibility, without foreground UI automation.
This route shares Control Center's global target and uses a private system API.
Activity changes never
expand the notch. `docs/NOTCH-ACTIVITIES.md` describes trust boundaries and limits.

These types are fully specified and should be treated as a stable API by all
feature agents — extend behavior, don't change signatures without
coordinating:

- **`AppSettings`** (`Core/AppSettings.swift`) — the only sanctioned way to
  read/write user preferences. Every feature reads its config from here.
- **`CaptureCoordinator`** (`Core/CaptureCoordinator.swift`, `@MainActor`) —
  the capture state machine (`idle` → `selecting` → `idle`; annotation-editing
  state lives inside `OverlayController`/`EditorSession` rather than as a
  separate coordinator state). Entry points: `startCapture()`,
  `cancelCapture()`, `finishWithImage(_:)` (legacy alias for firing `.confirm`
  directly). Wires together `OverlayController.shared`'s `onAction` /
  `onCancelled` callbacks exactly once, in `init`.
- **`Annotation` / `AnnotationStyle` / `AnnotationTool` / `AnnotationDocument`**
  (`Core/Annotation.swift`) — the full annotation data model, including
  immutable `with(...)` update helpers and snapshot-based undo/redo. This is
  the model the editor UI binds to.

## Capture flow

1. Global hotkey (Cmd+Shift+9 by default) or menu item → `CaptureCoordinator.startCapture()`.
2. `ScreenCapturer.captureFullScreens()` freezes every display.
3. `OverlayController.shared.begin(screens:frozenImages:)` shows one
   borderless window per screen over its frozen image; the user drags out a
   selection rect, then annotates it via the hosted editor UI
   (`EditorSession` / `AnnotationCanvasView` / `EditToolbarView` /
   `ActionBarView`).
4. The user picks a final action from the action bar or a keyboard shortcut
   (`⌘C` copy, `⌘S` save, `⌘U` upload, `⌘P` print, Enter to confirm, Esc to
   cancel). `OverlayController` crops the frozen image to the selection and
   flattens annotations into it, then fires `onAction(action, image)`.
5. `CaptureCoordinator` (the sole subscriber to `onAction` / `onCancelled`)
   dispatches to `CaptureActions` (copy / save / upload / print / search /
   share) per `AppSettings`, then tears the overlay down and returns to
   `.idle`.
6. Cancel at any point (Esc, action bar close button) → `onCancelled` fires →
   `CaptureCoordinator` dismisses the overlay → back to `.idle`.

## Status

**Integration complete.** All feature modules (hotkey/settings, overlay,
editor, capture/actions/notifications) are wired together end-to-end through
`CaptureCoordinator`, the app builds and bundles cleanly
(`swift build` / `./build_app.sh`), and the assembled `.app` launches without
crashing. See the root `README.md` for user-facing docs (build steps,
permissions, shortcuts, settings).

Known simplifications made during integration:
- `OverlayAction.confirm` (Enter) is treated identically to `.copy` — it
  always copies to the clipboard, closing the overlay only if
  `closeAfterCopy` is enabled.
- `.share` has no view to anchor the system share sheet to at the
  `CaptureCoordinator` layer, so `CaptureActions.share(_:from:)` is called
  with `nil` and degrades to a clipboard copy; the overlay is intentionally
  left open in that case rather than torn down, since nothing was actually
  "shared" to close out on.
- The "Check for Updates" menu item is a placeholder alert
  ("You're up to date. Brim 1.0.0.") — no real update feed/server
  exists yet.

## Ownership by directory (historical — parallel agent work is complete)

| Directory                                    | Owner                        |
|-----------------------------------------------|-------------------------------|
| `Hotkey/`, `Settings/`                        | agent-hotkey-settings          |
| `Overlay/`                                    | agent-overlay                  |
| `Editor/`                                     | agent-editor                   |
| `Capture/`, `Actions/`, `Notifications/`, `History/` | agent-capture            |
| `Core/`, `AppDelegate.swift`, `main.swift`    | agent-integration (final wiring across all of the above) |

## Build

```bash
swift build              # debug build, sanity check
swift build -c release   # release build
./build_app.sh            # assembles build/Brim.app (ad-hoc signed)
open build/Brim.app
```
