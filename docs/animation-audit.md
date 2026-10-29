# Notch animation audit

## Plan

Keep the existing Home/Library appearance and behavior. Use a fixed, top-centered AppKit hosting canvas so only SwiftUI animates the visible shell; retain the actual visible geometry for hover and mouse passthrough. Share restrained spring timing between opening, closing, navigation, and the output drawer. Remove delayed insertion and use transform-based waveform motion. Respect Reduce Motion.

Suppress redundant music polling publications and prepare artwork away from the main actor. Review storage costs separately: existing synchronous screenshot persistence and initial thumbnail reads can still interrupt UI during capture/library loading.

## Verification

- Geometry tests: fixed canvas across all layouts/displays; visible hover footprint remains unchanged.
- Existing render, library round-trip, drawer, capture, clipboard, and provider tests.
- Release build, signed identity verification, and installed-app check.
- Source review and bounded process sampling; no claim of a measured frame-rate improvement without a frame trace.

## Result

- Opening uses a 0.32-second spring response; closing uses 0.24. Both are critically damped, without bounce or delayed insertion. Navigation and the audio drawer use the same layout spring.
- The AppKit window stays at a fixed hostingFrame across Home, Library, and audio drawer transitions. SwiftUI animates the visible shell. Mouse passthrough checks the visible panelFrame. NSHostingView skips intrinsic/min/max sizing probes, as supported by [Apple's sizingOptions documentation](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions).
- Music artwork decoding runs off the main actor. Stable music/call polls emit no redundant updates; regression tests measured 8–9 unnecessary call publications before the fix and zero afterward.
- Waveform bars animate their scale inside fixed bounds. The audio backdrop keeps its effect view when music expands/collapses. Reduce Motion disables geometric transitions and waveform motion.
- All 105 tests in 17 suites passed, including fixed-canvas transparency/centering and hardware-clearance integration. Release bundle built and installed with the existing certificate-bound identity.
- CUA could read the installed window, but its hover-only panel rejected the available click action with AXError.notImplemented. Live hover frame pacing therefore remains unmeasured; render/geometry tests are not an FPS benchmark. Bounded process samples were collected locally.

Synchronous screenshot persistence and first thumbnail reads remain potential hitches during capture or the first Library load; they are not fixed by changing animation timing.

## Output button follow-up

The changing player aspect ratio caused a second, reproducible resize problem: opening the audio drawer while the shell still proposed its closed height shrank the whole player to fit. The regression render found zero output-icon pixels at the expected location (245 when closed). The player now scales from width only, so the button stays anchored while the drawer grows below it. Embedded drawer state is bound directly to the shelf presentation. Glyph changes do not inherit the shell animation.

Output detection previously ran only after the picker was clicked. The app now starts a read-only background refresh at launch and repeats every second; stop cancels it, and unchanged snapshots do not publish updates. Request generations prevent an old read from replacing an explicitly selected route. AirPods family names/model identifiers map to supported AirPods symbols. A live CoreAudio read verified the selected output as AirPods Pro with the `airpodspro` symbol without changing routing.

Final combined verification: 123 tests in 19 suites passed; signed release installed and restarted. The output regression now passes at the unchanged button location. Audio tests cover external route updates, no-op polls, monitor stop/restart, stale reads during selection, and supported AirPods symbols.
