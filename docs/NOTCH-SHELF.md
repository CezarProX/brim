# Brim notch shelf

## Product requirements

Hover over the MacBook notch to reveal a compact screenshot shelf. A short dwell prevents accidental opening; leaving closes it after a grace period. Recent captures offer edit, copy, export and drag into another app. Capture completion briefly reveals the shelf. An empty state explains how to begin. Menu access and a top-center fallback support displays without a notch. General preferences allow disabling the shelf and automatic previews.

## Architecture and system design

An AppKit nonactivating panel hosts a SwiftUI surface anchored at the screen's top center. NSScreen safe-area and auxiliary top regions determine real notch geometry. A low-frequency cursor check controls hover without requesting Accessibility access. The panel yields mouse events while collapsed, and is hidden throughout screenshot selection. Display changes rebuild its position. Reduce Motion uses a short fade instead of spring motion.

ShelfStore owns a separate bounded local image cache (20 captures, approximately 150 MB), independent of the existing event history. UUID filenames and private directory permissions keep cache operations scoped. CaptureCoordinator records completed images with one identifier per session. Editing a cached capture reuses the annotation controls in a separate window; exporting preserves native resolution. Drag providers own their PNG data so eviction does not break a transfer.

## Technical tasks

1. Add cache storage and tests for retention, replacement, persistence and errors.
2. Add testable notch geometry and hover transitions.
3. Implement animated shelf, thumbnail actions and accessible controls.
4. Wire capture suspension, completion previews, menu entry and settings.
5. Add standalone re-annotation window using existing editor components.
6. Build, review and test; visually inspect the running bundle.

## Validation and scope

Run Swift Testing with coverage, debug/release builds and bundle signature validation. Exercise hover, leave/re-enter, empty state, recent images and settings on the connected display. Record any interactions requiring manual validation. Existing project has no UI automation test target; automated logic coverage does not imply full UI coverage.

This iteration delivers the local feature. App Store distribution (sandbox entitlements, signing, privacy disclosures, submission) and a landing page are later work. No new upload or sharing service is introduced.

## Verification — 2026-09-11

- Debug and release builds passed; installed bundle passed strict signature verification.
- Storage and hover/geometry tests cover approximately 97% of their combined lines.
- Offscreen AppKit content tests verify empty-state text and populated thumbnail colors; editor export retains native Retina dimensions. These are not full interaction tests.
- Live app verified: collapsed notch, expanded empty shelf, and populated shelf with a newly captured image.
- Previous installed bundle backed up before replacement. No valid Apple Development signing identity was available, so the local build uses ad-hoc signing. The obsolete Brim ScreenCapture grant was reset for this bundle ID only; after the user enabled its new entry and the app restarted, the permission alert cleared and a fresh screenshot appeared in the shelf.
- End-to-end drag destinations, editor keyboard shortcuts, and a second physical monitor still need hands-on validation. The source review has no outstanding critical/high findings.
