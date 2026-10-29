// SelectionOverlayView.swift
// Brim
//
// The per-screen view that renders the frozen screenshot, the dimmed
// backdrop with a punched-out hole over the active selection, the
// selection border/handles, and the live pixel-size label.
//
// Mouse/cursor plumbing lives here; the actual selection *state machine*
// (what a click means — create/move/resize/switch screens) lives in
// `OverlayController`, which this view reports raw view-local points to via
// closures rather than deciding for itself.

import AppKit

final class SelectionOverlayView: NSView {

    /// The overlay must take the very first click, even if the app was still in the background.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static let dimAlpha: CGFloat = 0.35

    /// The frozen screenshot for this screen. `nil` in degraded mode, in
    /// which case the backdrop is drawn as plain black before dimming.
    var frozenImage: NSImage? { didSet { needsDisplay = true } }

    /// Whether this screen currently owns the single, cross-screen active
    /// selection. Non-active screens are shown fully dimmed with no hole,
    /// border, or handles.
    var isActiveScreen: Bool = false { didSet { needsDisplay = true } }

    /// The committed selection rect (view-local coordinates), once the user
    /// has finished an initial drag with a valid size. `nil` before that
    /// (or once discarded).
    var selectionRect: CGRect? { didSet { needsDisplay = true } }

    /// The in-progress rubber-band rect while the user is still dragging
    /// out a brand-new selection, before mouse-up commits it.
    var liveDragRect: CGRect? { didSet { needsDisplay = true } }

    /// True once an annotation tool is active: the selection is locked (no
    /// resize handles drawn or hit-tested) so the annotation canvas view
    /// can own mouse input over the selection uncontested.
    var isLocked: Bool = false { didSet { needsDisplay = true } }

    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        InputTrace.event("overlay.view.mouseDown", event, window: window)
        let point = convert(event.locationInWindow, from: nil)
        onMouseDown?(point)
        updateCursor(for: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseDragged?(point)
        updateCursor(for: point)
    }

    override func mouseUp(with event: NSEvent) {
        InputTrace.event("overlay.view.mouseUp", event, window: window)
        let point = convert(event.locationInWindow, from: nil)
        onMouseUp?(point)
        updateCursor(for: point)
    }

    private func updateCursor(for point: CGPoint) {
        guard isActiveScreen, let rect = selectionRect, !isLocked else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = ResizeHandle.hitTest(point, in: rect) {
            handle.cursor.set()
        } else if rect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let frozenImage {
            frozenImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor.black.setFill()
            bounds.fill()
        }

        let hole = isActiveScreen ? (liveDragRect ?? selectionRect) : nil

        context.saveGState()
        let path = CGMutablePath()
        path.addRect(bounds)
        if let hole, hole.width > 0, hole.height > 0 {
            path.addRect(hole)
        }
        context.addPath(path)
        context.setFillColor(NSColor.black.withAlphaComponent(Self.dimAlpha).cgColor)
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        if let hole, hole.width > 0, hole.height > 0 {
            drawSelectionChrome(rect: hole, showHandles: selectionRect != nil && !isLocked, in: context)
        }
    }

    private func drawSelectionChrome(rect: CGRect, showHandles: Bool, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect.insetBy(dx: 0.75, dy: 0.75))
        context.restoreGState()

        if showHandles {
            for handle in ResizeHandle.allCases {
                let handleRect = handle.visualRect(in: rect)
                let path = NSBezierPath(rect: handleRect)
                NSColor.white.setFill()
                path.fill()
                NSColor(white: 0, alpha: 0.6).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }

        drawSizeLabel(for: rect)
    }

    private func drawSizeLabel(for rect: CGRect) {
        // Match the actual output pixel size: derive the pixel/point ratio
        // from the frozen image itself (its point size equals the screen
        // frame per the ScreenCapturer contract). backingScaleFactor is only
        // a fallback for degraded mode — on scaled Retina modes it differs
        // from the true capture ratio.
        let fallback = window?.screen?.backingScaleFactor ?? 2.0
        var scaleX = fallback
        var scaleY = fallback
        if let frozenImage, frozenImage.size.width > 0, frozenImage.size.height > 0,
           let rep = frozenImage.representations.first, rep.pixelsWide > 0 {
            scaleX = CGFloat(rep.pixelsWide) / frozenImage.size.width
            scaleY = CGFloat(rep.pixelsHigh) / frozenImage.size.height
        }
        let pixelWidth = Int((rect.width * scaleX).rounded())
        let pixelHeight = Int((rect.height * scaleY).rounded())
        let text = "\(pixelWidth) \u{00D7} \(pixelHeight) px"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let hPadding: CGFloat = 6
        let vPadding: CGFloat = 3
        let labelSize = CGSize(width: textSize.width + hPadding * 2, height: textSize.height + vPadding * 2)

        // Prefer just above the selection's top-left corner; fall back to
        // just inside it if that would run off the top of the screen. Then
        // clamp fully within bounds so the label is always fully on-screen.
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + labelSize.height > bounds.maxY {
            origin.y = rect.maxY - 6 - labelSize.height
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - labelSize.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - labelSize.height)

        let backgroundRect = CGRect(origin: origin, size: labelSize)
        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        backgroundPath.fill()
        text.draw(at: CGPoint(x: origin.x + hPadding, y: origin.y + vPadding), withAttributes: attributes)
    }
}
