# Activity island and library

The island appears on every connected display. On a MacBook it meets the physical
notch; on an external display it is a plain notch attached to the top edge. Each
surface has independent hover state, but shares music, calls and library data.
Expansion requires a160ms hover; leaving collapses after500ms, except during a
drag, menu or confirmation. Reduced Motion uses short fades.

Home shows an active call, otherwise the current song, otherwise a quiet capture
entry point. Music no longer requires selecting a Music tab. Compact playback
shows artwork and an activity waveform beside the hardware notch. Library is a
secondary destination with search and content filters.

The local clipboard history observes new copies after startup and supports text,
web links and images. Screen captures retain their existing ShelfStore records.
History is bounded to100items/100MB, with100KB text and16MB image limits, and
skips concealed, transient and password-manager pasteboard markers. It does not
fetch link previews or send clipboard content to a server. Users can pause or
clear history from Library options. Image export retains original pixels.

YouTube Music artwork resolves the album URL exposed by the active player.
Returned album metadata must match the actual album title; image and redirect
hosts are restricted, requests omit cookies and have byte/time limits. A missing
or unrecognized source leaves an honest placeholder, never a guessed cover.

On2026-09-11 the existing Screen Recording entry for Brim was removed and
re-added through System Settings, followed by macOS's Quit & Reopen action.
Subsequent installed builds keep the certificate-pinned local signing identity.
ScreenCaptureKit still requires macOS consent; Brim cannot silently grant
itself system access. Local signing is for development, not App Store distribution.

Verification on 2026-09-11: the integrated 65-test suite passed, followed by the
additional library rendering/OCR test. Release build and strict code-signature
verification passed. The installed update retained the same certificate-pinned
designated requirement. A real capture opened the screen-selection overlay
without a permission alert and was cancelled without saving. Live YouTube Music
metadata displayed Wanderlust by The Weeknd with its actual Kiss Land cover.
External-display geometry and compact/expanded rendering were tested; physical
hover interaction on each display and a real active call were not exercised.

The reference-style music layout uses a landscape artwork thumbnail, title and
artist, a playback activity indicator, one-row elapsed/progress/remaining time,
and plain transport glyphs. The output drawer lists actual Core Audio output
devices and changes the default media output only after selecting a device.
Opening the drawer extends the island downward while preserving its top edge
and compact hover target; leaving the island still collapses it.

Reference-player verification: 74 tests passed, including fake-provider routing
failure/readback and drawer rendering. Release build and strict signing passed;
installed live player displayed Lonely Star by The Weeknd with cover artwork.
Opening Sound output listed DELL S3425DW and the selected MacBook Pro Speakers.
No live output switch was made during verification.

Earlier shell revision: the island adopted one opaque RGB-black surface in both
collapsed and expanded states, removing the material/gradient crossfade. The
later output-drawer revision below adds glass only beneath the player. During hover
transitions, content retains its final layout size and fades inside the animated
clipping shape, preventing text/control compression. All 74 tests passed after
this change; static renders were inspected. Live motion quality is not established
by the static rendering tests.

Playback fix: live diagnostics identified a Chrome-owned player button inside a
YouTube Music shim-owned window. Commands now validate the exact PWA window and
its fresh toolbar rather than requiring the button and window to share a PID.
An explicit command briefly activates and raises that existing window, presses
the unique enabled control once, and restores the previous app only while the
player is still foreground. Polling never changes focus. Play/pause is verified
against the fresh pre-press snapshot with bounded readback; failures persist
through polling and toggles are never blindly repeated.

The signed installed build passed 81 tests and independent review. Live testing
through Brim's Connections player (the same view/model used by the notch)
started Lonely Star at 0:32, paused it at 0:53, and resumed it. The YouTube Music
toolbar independently confirmed playing at 1:09. No connection or permission
changes were needed. Direct physical hover/click testing on each notch remains
separate from this verified transport path.

Reference proportion revision: the music surface uses a 600-by-310-point upper
layout, with a 190-point full-width output drawer. Header, progress and transport
positions follow the supplied reference at that scale. Music navigation is moved
to a discreet menu. The upper shell remains opaque black; only the output drawer
uses a native behind-window visual effect, respecting Reduce Transparency.
Reference proportion revision passed 79 tests and strict signed release build.
The complete player-plus-drawer render was inspected, including capsule rows,
selection indicators, artwork sidebars, and blue/orange playback indicator.

The music island now displays the normalized reference at70% scale:420×217points,
or420×350with the output drawer. Library retains its600-point width. The reference
coordinates stay600-based internally; artwork, text, controls and glass scale
together. Static renders were inspected at the smaller size.

Visual system revision (2026-09-24): every island surface now draws from
`Notch/IslandStyle.swift`: six type styles, three text levels, one fill scale,
three corner radii, and shared pill, round-control and glyph buttons. The output
drawer's behind-window glass is removed; the whole island is opaque black again.
Stock bordered buttons and nested card backgrounds are gone from the activity
pages, and explanatory copy is shortened (details moved to tooltips).

Motion lives in `NotchMotion`: opening uses a slightly bouncy spring and closing
a settled one. Expanded content blurs in shortly after the shell starts moving,
and compact content returns once the shell has nearly closed. Tabs, library
filters and Focus durations use sliding selection capsules. Controls have spring
press feedback and hover halos. Play/pause and toggles morph their symbols, and
countdowns roll their digits. The scrubber thickens under the pointer, and the
music waveform takes its tint from the album artwork. Reduce Motion disables all
of these. All 197 tests passed and static renders were inspected; live motion
still needs a hands-on check on hardware.

Revision (2026-09-24): these features were built
locally in Brim's own design system: floating glass navigation capsule, Home
dashboard with customizable widgets, file Tray and shake-to-open Basket, clipboard
colors/files/tags/blur/edit, calendar month + agenda + reminders + quick add, timer
dial and Pomodoro, voice memos, keep awake, notes, system stats, camera mirror,
browser and Claude Code/Codex skins, live flashes and the ⌥⌘R Ring. Excluded on
purpose (they need network services, private APIs or other platforms): weather,
lyrics, HUD suppression, lock-screen player, notification replies, cloud links,
iPhone sync, per-app volume and keystroke sounds. 226 tests pass; renders were
inspected; live hover, drag, AppleScript and permission flows still need a
hands-on pass on hardware.
