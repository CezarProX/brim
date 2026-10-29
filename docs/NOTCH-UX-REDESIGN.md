# Compact notch navigation

The approved direction follows the competitor research in this task: contextual
cards, explicit navigation and tools that are visible without horizontal scrolling.

## Implementation plan

1. Keep the attached shell and fixed hosting canvas on both displays.
2. Replace icon-only navigation with Now, Files and Tools.
3. Put a compact calendar/battery summary below music and on the quiet home.
4. Replace the tool carousel with a grid and a back-to-tools detail flow.
5. Give Focus a selected duration and an explicit Start action.
6. Route file drops and screenshot sharing into Files.
7. Size utility cards by content category and synchronize hover geometry.
8. Verify media transitions, render the new grid and review before installation.

Provider permissions, recording controls, clipboard storage and device detection
remain on their existing implementations. This change concerns navigation and
presentation; it does not add competitor integrations that were previously absent.

## Delivered behavior

- Now, Files and Tools have visible labels; live activities remain reachable
  from a compact menu and the secondary activity bubble.
- Tools shows four tiles without horizontal scrolling. Detail pages have a back
  control; additional tools remain reachable through More and Connections settings.
- Music and quiet Home show the calendar/battery summary. Calendar permission
  still requires an explicit Connect action.
- Focus presets choose a duration with a visible checkmark; Start focus begins it.
- Files includes sharing, screenshot context menus include Share, and accepted
  drops open sharing after mouse-up so resizing cannot interrupt the drop.
- Utility cards use 480-point width and content-specific height. The file library
  keeps its larger canvas; the fixed host reserves the music footer from startup.

Sol reviewed navigation, geometry, sharing and the tool layout. Render checks cover
the visible navigation labels and both tool-grid gutters, in addition to existing
media transition checks. Run AppKit render tests with `swift test --no-parallel`
to avoid simultaneous animated test windows affecting render timing.

Final verification: 197 tests in 40 suites passed sequentially. Release signing
and strict signature verification passed. Installed and restarted the updated
`/Applications/Brim.app`; previous version is backed up at
`/tmp/Brim-before-ux-20260912-231501.app`. The installed executable matches
the release bundle SHA-256. Native click-through validation remains limited by
the collapsed panel's Accessibility surface; grid/navigation visibility was
verified in rendered AppKit tests.
