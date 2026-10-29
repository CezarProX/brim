// OverlayController+Mouse.swift
// Brim
//
// Drag-to-select / move / resize mouse handling. Each `SelectionOverlayView`
// forwards raw view-local points here rather than deciding for itself what
// a click means — a click's meaning (start a new selection vs. move vs.
// resize vs. "the user just switched screens") depends on the cross-screen
// state this controller owns.

import AppKit

extension OverlayController {

    func handleMouseDown(screen: NSScreen, point: CGPoint) {
        windowFor(screen)?.makeKey()

        if activeScreen == screen, let rect = selectionRect {
            let locked = session?.currentTool != nil
            if !locked, let handle = ResizeHandle.hitTest(point, in: rect) {
                dragMode = .resizing(handle: handle, startPoint: point, startRect: rect)
                return
            }
            if rect.contains(point) {
                if !locked {
                    dragMode = .moving(startPoint: point, startRect: rect)
                }
                // Locked (a tool is active): the annotation canvas view
                // sits over this rect and should already own the click.
                // Nothing to do here either way.
                return
            }
            // Clicked outside the current selection -> start a fresh one,
            // discarding this one (and its annotations).
            discardCurrentSelection()
        } else if let current = activeScreen, current != screen {
            // A selection exists on a *different* screen; starting a drag
            // here moves the single active selection to this screen.
            discardCurrentSelection()
        }

        activeScreen = screen
        dragMode = .creating(startPoint: point)
        refreshAllViewStates()
    }

    func handleMouseDragged(screen: NSScreen, point: CGPoint) {
        guard screen == activeScreen else { return }

        switch dragMode {
        case .none:
            return

        case .creating(let start):
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            views[screen]?.liveDragRect = rect

        case .moving(let start, let startRect):
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            let moved = startRect.offsetBy(dx: delta.width, dy: delta.height)
            selectionRect = clampToScreenBounds(moved, screen: screen)
            views[screen]?.selectionRect = selectionRect
            repositionHostedViews()

        case .resizing(let handle, let start, let startRect):
            let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            let resized = handle.resized(from: startRect, delta: delta).standardized
            selectionRect = clampToScreenBounds(resized, screen: screen)
            views[screen]?.selectionRect = selectionRect
            repositionHostedViews()
        }
    }

    func handleMouseUp(screen: NSScreen, point: CGPoint) {
        guard screen == activeScreen else { return }
        defer { dragMode = .none }

        switch dragMode {
        case .none:
            return

        case .creating(let start):
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            views[screen]?.liveDragRect = nil

            if rect.width >= 4, rect.height >= 4 {
                selectionRect = rect
                views[screen]?.selectionRect = rect
                commitSelection(on: screen)
            } else {
                activeScreen = nil
                selectionRect = nil
                refreshAllViewStates()
            }

        case .moving, .resizing:
            break // already committed live during the drag
        }
    }

    /// Keeps a moved/resized selection from being dragged off the screen it
    /// lives on. Selections don't span screens (see the type-level doc
    /// comment on `OverlayController`), so this is a simple same-screen
    /// clamp rather than a multi-monitor reflow.
    func clampToScreenBounds(_ rect: CGRect, screen: NSScreen) -> CGRect {
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        var r = rect.standardized
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }
}
