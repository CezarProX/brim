# Dynamic Island activity behavior

## Product and research

Brim adapts iPhone's compact, expanded and minimal activity presentations to the Mac's physical notch and pointer input. Apple documents two simultaneous minimal presentations, one attached and one detached; it does not publish a universal priority order for all system activities.

Sources checked 2026-09-11:
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://support.apple.com/guide/iphone/view-live-activities-in-the-dynamic-island-iph28f50d10d/ios

## Architecture and implementation plan

1. Resolve current activities with a deterministic, tested policy: native screen recording, call, music. With recording and music, keep music in the detached right bubble. Keep a third activity available in the expanded navigation.
2. Observe real native recording evidence in a background model, without treating capture permission or the open Screenshot toolbar as an active recording.
3. Share activity resolution across compact content, expanded content and hit testing. Preserve physical notch clearance; include the secondary bubble in the host canvas and pointer region.
4. Show live recording status. Allow selecting each activity, restore the remaining activity when one ends, and close stale audio drawers on automatic priority changes.
5. Verify resolution, geometry, recording lifecycle and synthetic rendering; build the signed app using the existing identity.

## Interaction

Hover expands the pointed activity. Click the secondary bubble or an expanded activity button to switch. Leaving collapses the surface. Existing Reduce Motion support applies to shell and bubble transitions. Apple touch gestures are adapted to pointer interaction; unavailable iPhone services such as Face ID, telephony or navigation are not fabricated.

## Priority policy

Recording takes precedence over calls and media in Brim. This is our explicit policy for the requested workflow, not a claim about an undocumented iOS priority table. Starting a higher priority activity resets the expanded selection; ending an activity restores an available activity. Paused media can remain available in expanded Home, but does not create an idle compact activity by itself.

## Recording detection verification

Verified on the local Mac on 2026-09-11 with the native `/usr/sbin/screencapture` tool. The test created a floating black window containing only a test label and recorded a 300 × 180 region fully inside that window. Each run used a new UUID movie filename, avoiding an existing-output collision. It did not record the full desktop.

Temporary fixture compilation and execution:

```sh
swiftc Sources/Brim/Activities/ScreenRecordingModel.swift \
  /tmp/brim-recording-check/main.swift \
  -o /tmp/brim-recording-check/check
/tmp/brim-recording-check/check
```

The fixture invoked `screencapture -v -V 6 -R 220,<region-top>,300,180 <unique-output.mov>` after sample 2 and sampled detection every 0.5 seconds. Observed result:

```text
samples 1–2:   recording=false
samples 3–14:  recording=true
samples 15–20: recording=false
```

During the recording, descriptor inspection showed `/usr/libexec/replayd` writing the temporary movie in `~/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/`. The launching `screencapture` process did not own the movie descriptor. Supporting this native ReplayKit writer fixed the initial false-negative detection. After recording stopped, the writable descriptor disappeared and detection returned to idle. A separate idle check also returned false while ScreenshotControls remained running.

`swift test --filter ScreenRecordingModelTests` passed six tests covering recording identity/start-time transitions, passive initialization, duplicate-start prevention, in-flight cancellation, trusted executable/path matching, and real synthetic writable/read-only/closed movie descriptors. The fixture above is a temporary local validation aid, not a committed test dependency.

## Native detection limits

The observer polls every 750 ms in a background task. It checks bounded process/descriptor metadata and requires a writable regular `.mov` file owned by an exact Apple recorder executable. For the shared `replayd` service, the movie must additionally be inside an exact native Screenshot recording directory; unrelated app recordings do not qualify. No recording content is read, no capture or Accessibility permission is requested, and opening the Screenshot toolbar alone does not count as recording.

This supports the native Screenshot recording flow, including current QuickTime New Screen Recording delegation to Screenshot. It does not claim system-wide detection for OBS, browsers, conferencing, camera recording, or arbitrary ScreenCaptureKit clients. Future macOS changes to writer ownership, temporary paths, permissions, or file formats may require updating this adapter. Elapsed time begins when Brim first observes the recording, so an already-running recording does not expose its original start time. The expanded recording view offers Stop and save through the native macOS stop shortcut. It verifies the active recording identity first and requires permission to post the shortcut; observation remains permission-free.

## Release verification

- Full suite: 137 tests passed (24 suites), with code coverage enabled.
- New resolver, recorder model and recording view: 88.27% line coverage combined; the native recorder process enumeration is additionally exercised by the live fixture.
- Synthetic compact/expanded renders verify a visible recording glyph, detached bubble and transparent gap. Geometry tests check physical and external displays and prevent invisible canvas below the bubble from taking pointer input.
- Signed release built and installed at `/Applications/Brim.app`, preserving the existing designated requirement. Previous bundle backed up at `/tmp/Brim-before-dynamic-island.app`.
- Installed application accessibility/screenshot inspection showed `Screen Recording` when a native recording of the neutral fixture region started.

## Visual revision after reference review

The original recording UI used two outlined record symbols; that did not match iOS. The revision uses one filled 12pt red status dot at the leading edge, with no duplicate trailing record icon. The native recording reference shows that exact content hierarchy:
https://mobilelaby.net/images/2022/09/dynmic-island-screen-recording-widget.jpg

Apple's expanded recording reference:
https://cdsassets.apple.com/live/7WUAS350/images/ios/locale/uk-ua/ios-26-iphone-17-pro-home-screen-recording.png

Apple's actual motion and minimal presentations were inspected in WWDC23, Design dynamic Live Activities:
https://developer.apple.com/videos/play/wwdc2023/10194/?time=516
https://developer.apple.com/videos/play/wwdc2023/10194/?time=833
The reference has elastic expansion, stable content placement, vertically aligned primary/secondary containers and a narrow gap. Minimal containers can be short capsules, sized to their content. Apple does not publish exact animation constants; Brim's spring timings are tuned approximations, not a claim of pixel/frame identity.

User preference: make it native on macOS. Keep the physical MacBook notch integrated. Displays without a camera cutout use the same 184 × 32 attached notch treatment at the top edge, so a secondary monitor does not switch to a floating Dynamic Island capsule. A physical MacBook camera cannot be reshaped by software.

Native Clock timers now join recordings, calls and music. Observe read-only Clock timer metadata, including pause/resume and time remaining with Clock closed. Upcoming timer expiry takes priority among native timers. This adapter uses the locally verified current Clock store schema; unsupported schemas yield no activity. Pause, resume and cancel controls operate the verified native Clock Accessibility buttons. They validate timer identity/state and the visible title/countdown before pressing, then wait for the read-only observer to confirm the result. Accessibility permission is required for controls; the store is never modified directly. No artificial timer, call or recording states are shown in production.

### Revision verification

149 tests across 28 suites pass after the visual revision. Regression checks cover the single leading recording dot, timer readout, paused/running native timer data, multiple activities, delayed announcements, expanded companion changes and fixed canvas hit testing. A newly detected recording/call/timer peeks for 2.2 seconds then retracts unless hovered; repeated observations do not restart the peek. Reduce Motion disables spring movement.

Rendered compact reference artifacts are in `docs/visuals/recording-capsule.png` and `docs/visuals/timer-capsule.png`. These are Brim synthetic render fixtures, not screenshots of iOS. The physical notch retains its real shape; the external display uses the capsule.

Installed revision live check: a labeled native two-minute Clock timer continued counting down with Clock closed. Brim showed `Timer` and `Show Music` in accessibility, and the retracted hardware notch displayed the orange remaining time at left with a separate music bubble at right. This validates simultaneous real timer/music activity in the installed signed build, in addition to synthetic rendering tests.

Final installed checks passed: paused native Clock timer stayed at 1:39 for approximately 45 seconds, cancellation restored the single music pill, and a new native screen recording displayed the single filled leading red dot plus a separate music waveform bubble. Signed identity unchanged. The temporary test timer was cancelled and test recording stopped automatically.

## Waveform and activity controls

The playback waveform now draws into a fixed Canvas driven by TimelineView. Only local bar heights change; a repeating SwiftUI animation can no longer inherit and repeat the island's position transition. Reduced Motion uses stationary bars. Regression tests sample the rendered notch after recording ends, on both physical-notch and floating layouts, and require every waveform pixel to remain in the trailing slot.

Recording and timer actions expose an in-progress state and keep the expanded island open while working. Recording remains visible until the native observer confirms it ended. Timer controls reject stale snapshots and surface failures instead of changing their state optimistically. Native Clock Accessibility does not expose the database timer identifier; controls therefore fail closed when more than one timer is active, rather than risk toggling a different timer with identical visible evidence.

Control revision automated verification: 161 tests in 30 suites pass, including stale stop completion, duplicate stop requests, stale timer actions, duplicate native timer candidates, permission refresh and waveform transition rendering. The signed release was installed at `/Applications/Brim.app` with the same certificate-bound designated requirement; previous bundle is `/tmp/Brim-before-activity-controls-20260911.app`.

Installed control revision live checks: native neutral-region recording detection returned `recording=true` and Brim showed the recording glyph; completed fixture movies were saved and valid. After recording ended the music-only waveform returned centered. Native Clock's actual Start/Pause/Resume/Cancel UI transitions were verified and the temporary timer was canceled. Installed Brim exposed Pause timer / Cancel timer in its expanded accessibility tree. Actual notch action clicks remain unverified: CUA cannot reliably expand the borderless system-dialog surface (coordinate actions return `AXError.notImplemented` / `noWindowsAvailable`), including an attempted automatic announcement. Do not treat the live detector/Clock UI checks as proof of an installed notch stop/pause action.

Follow-up waveform regression: expanded timer → music → timer → music → timer switches at 180 ms intervals, then samples the detached waveform repeatedly after settling. Both hardware-notch and floating layouts pass, alongside both recording-end transition cases (four render cases total). The reported 14:35:36 screenshot predates the installed 14:40:05 release binary. No additional production change was required by this reproduction.
