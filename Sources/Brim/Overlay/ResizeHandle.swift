// ResizeHandle.swift
// Brim
//
// The eight drag handles drawn around a committed selection rectangle
// (four corners + four edge midpoints), plus the geometry/cursor helpers
// `SelectionOverlayView` and `OverlayController` need to draw, hit-test, and
// resize against them.
//
// Coordinate convention: all rects/points here are in the same local,
// bottom-left-origin, y-up space as `NSScreen`/window-local geometry (see
// the doc comment on `OverlayWindow`) — "top" means greater y, "bottom"
// means lesser y.

import AppKit

enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    /// Visual size of the drawn handle square, in points.
    static let visualSize: CGFloat = 8

    /// Hit-testing size is larger than the visual square so handles stay
    /// easy to grab with the mouse.
    static let hitSize: CGFloat = 12

    /// Center point of this handle for the given selection rect.
    func center(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }

    /// The (small) square used when drawing the handle.
    func visualRect(in rect: CGRect) -> CGRect {
        square(around: center(in: rect), size: Self.visualSize)
    }

    /// The (larger) square used for hit-testing.
    func hitRect(in rect: CGRect) -> CGRect {
        square(around: center(in: rect), size: Self.hitSize)
    }

    private func square(around center: CGPoint, size: CGFloat) -> CGRect {
        CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    /// Finds the handle (if any) hit by `point` for the given selection
    /// rect. Handles straddle the selection border, so this must be
    /// checked independently of (and before) a plain `rect.contains(point)`
    /// "am I inside the selection" test.
    static func hitTest(_ point: CGPoint, in rect: CGRect) -> ResizeHandle? {
        for handle in ResizeHandle.allCases where handle.hitRect(in: rect).contains(point) {
            return handle
        }
        return nil
    }

    /// The best available public AppKit cursor for this handle's resize
    /// direction. AppKit has no public diagonal-resize cursor, so the four
    /// corner handles fall back to `.crosshair` (documented limitation).
    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }

    /// Returns a new rect after dragging this handle by `delta` (current
    /// point minus drag-start point) from `originalRect`. The result is not
    /// normalized — it may have a negative width/height if dragged past the
    /// opposite edge, so callers should apply `.standardized` before use.
    func resized(from originalRect: CGRect, delta: CGSize) -> CGRect {
        var r = originalRect
        switch self {
        case .topLeft:
            r.origin.x += delta.width
            r.size.width -= delta.width
            r.size.height += delta.height
        case .top:
            r.size.height += delta.height
        case .topRight:
            r.size.width += delta.width
            r.size.height += delta.height
        case .left:
            r.origin.x += delta.width
            r.size.width -= delta.width
        case .right:
            r.size.width += delta.width
        case .bottomLeft:
            r.origin.x += delta.width
            r.size.width -= delta.width
            r.origin.y += delta.height
            r.size.height -= delta.height
        case .bottom:
            r.origin.y += delta.height
            r.size.height -= delta.height
        case .bottomRight:
            r.size.width += delta.width
            r.origin.y += delta.height
            r.size.height -= delta.height
        }
        return r
    }
}
