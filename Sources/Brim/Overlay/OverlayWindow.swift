// OverlayWindow.swift
// Brim
//
// One borderless, full-screen window per display, hosting the frozen
// screenshot + dim/selection chrome and (once a selection exists) the
// floating annotation canvas + toolbar/action-bar as plain subviews of its
// content view.

import AppKit

final class OverlayWindow: NSWindow {

    /// Forwarded from `performKeyEquivalent(with:)`; see the doc comment in
    /// `OverlayController+Keyboard.swift` for why `performKeyEquivalent`
    /// (rather than `keyDown`) is used to implement the capture overlay's
    /// keyboard shortcuts.
    var onPerformKeyEquivalent: ((NSEvent) -> Bool)?

    /// Above everything another app can draw. Wispr Flow keeps a transparent 512x614 "Status" window
    /// at screen-saver level (1000) in the middle of the display; at 1001 it still won the clicks
    /// on this machine, so the overlay uses the shielding level that fullscreen blockers use.
    static let captureLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    /// - Note on coordinates: `NSScreen.frame` is expressed in the global
    ///   AppKit desktop coordinate space (bottom-left origin, y increasing
    ///   upward, consistent across every connected display). Giving this
    ///   window that exact frame means its own local coordinate space —
    ///   used by `NSEvent.locationInWindow`, `SelectionOverlayView`'s
    ///   bounds, and every selection/handle/toolbar rect in this module —
    ///   lines up exactly with that one screen's portion of the desktop.
    ///   No further per-screen coordinate translation is needed anywhere
    ///   else in `Overlay/`.
    init(screen: NSScreen) {
        // `initWithContentRect:styleMask:backing:defer:screen:` is a
        // *convenience* initializer, not a designated one — call the
        // designated (screen-less) initializer instead and position the
        // window explicitly via `setFrame(_:display:)` right after.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        // Above other apps' screen-saver-level overlays (dictation bars, recorders): at the same level
        // one of them can sit on top of the capture overlay and take its clicks, which looks frozen.
        level = Self.captureLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp || event.type == .keyDown {
            InputTrace.event("overlay.window.sendEvent", event, window: self)
        }
        super.sendEvent(event)
    }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onPerformKeyEquivalent?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
