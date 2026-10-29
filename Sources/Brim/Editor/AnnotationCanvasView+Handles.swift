// AnnotationCanvasView+Handles.swift
// Brim
//
// Resize handles for the selected annotation, available in ANY tool mode:
//  - line / arrow / straight highlighter: a handle on each endpoint (drag to resize
//    or re-aim the shape),
//  - rectangle: a handle on each corner (opposite corner stays anchored),
//  - text: a single scale handle at the bottom-right of the text box (drag
//    to grow/shrink the font),
//  - curved arrow: both endpoints plus the bend (control) point,
//  - ellipse / blur / pixelate / spotlight / magnifier: rect corners,
//  - pen, freehand highlighter, step counter: no handles (move-only).
//
// Dragging previews the resize live and commits it as a single undo step on
// mouseUp, mirroring how drafting and move-drags already work.

import AppKit

/// Which handle of the selected annotation a drag grabbed.
enum AnnotationHandle {
    case endpoint(Int)
    case rectCorner(anchor: CGPoint)
    case textScale
}

extension AnnotationCanvasView {

    private var handleHitRadius: CGFloat { 9 }
    private var handleDrawRadius: CGFloat { 4.5 }

    // MARK: - Handle geometry

    /// Handle positions for `annotation`, in canvas coordinates.
    func handlePositions(for annotation: Annotation) -> [(AnnotationHandle, CGPoint)] {
        switch annotation.tool {
        case .line, .arrow, .curvedArrow, .highlighter:
            let points = annotation.points
            // Freehand highlighter strokes are move-only, like the pen.
            guard points.count >= 2, annotation.tool != .highlighter || points.count == 2 else { return [] }
            return points.indices.map { (.endpoint($0), points[$0]) }
        case .rectangle, .ellipse, .blur, .pixelate, .spotlight, .magnifier:
            let r = annotation.rect.standardized
            return [
                (.rectCorner(anchor: CGPoint(x: r.maxX, y: r.maxY)), CGPoint(x: r.minX, y: r.minY)),
                (.rectCorner(anchor: CGPoint(x: r.minX, y: r.maxY)), CGPoint(x: r.maxX, y: r.minY)),
                (.rectCorner(anchor: CGPoint(x: r.maxX, y: r.minY)), CGPoint(x: r.minX, y: r.maxY)),
                (.rectCorner(anchor: CGPoint(x: r.minX, y: r.minY)), CGPoint(x: r.maxX, y: r.maxY))
            ]
        case .text:
            let size = AnnotationRenderer.textSize(for: annotation)
            guard size.width > 0 else { return [] }
            let origin = annotation.rect.origin
            return [(.textScale, CGPoint(x: origin.x + size.width, y: origin.y))]
        case .pen, .counter, .crop:
            return []
        }
    }

    /// Hit-tests the handles of the currently selected annotation.
    func hitTestHandle(at point: CGPoint) -> (Annotation, AnnotationHandle)? {
        guard let id = session.selectedAnnotationID,
              let annotation = session.document.annotations.first(where: { $0.id == id }) else {
            return nil
        }
        for (handle, position) in handlePositions(for: annotation)
        where hypot(point.x - position.x, point.y - position.y) <= handleHitRadius {
            return (annotation, handle)
        }
        return nil
    }

    // MARK: - Handle drag lifecycle

    func beginHandleDrag(annotation: Annotation, handle: AnnotationHandle, at point: CGPoint) {
        handleDragOriginal = annotation
        activeHandle = handle
        handleDragPreview = nil
        if case .textScale = handle {
            handleDragOriginalTextSize = AnnotationRenderer.textSize(for: annotation)
        }
        needsDisplay = true
    }

    func continueHandleDrag(at point: CGPoint) {
        guard let original = handleDragOriginal, let handle = activeHandle else { return }
        handleDragPreview = resized(original, handle: handle, to: point)
        needsDisplay = true
    }

    func endHandleDrag(at point: CGPoint) {
        defer {
            handleDragOriginal = nil
            activeHandle = nil
            handleDragPreview = nil
            handleDragOriginalTextSize = .zero
            needsDisplay = true
        }
        guard let original = handleDragOriginal, let handle = activeHandle else { return }
        let final = resized(original, handle: handle, to: point)
        session.updateAnnotation(final)
    }

    // MARK: - Resize math

    private func resized(_ annotation: Annotation, handle: AnnotationHandle, to point: CGPoint) -> Annotation {
        switch handle {
        case .endpoint(let index):
            guard annotation.points.indices.contains(index) else { return annotation }
            var points = annotation.points
            points[index] = point
            return annotation.with(points: points)

        case .rectCorner(let anchor) where annotation.tool == .magnifier:
            return annotation.with(rect: Self.squareRect(from: anchor, to: point))

        case .rectCorner(let anchor):
            let rect = CGRect(
                x: min(anchor.x, point.x),
                y: min(anchor.y, point.y),
                width: abs(point.x - anchor.x),
                height: abs(point.y - anchor.y)
            )
            return annotation.with(rect: rect)

        case .textScale:
            let originalSize = handleDragOriginalTextSize
            guard originalSize.width > 1 else { return annotation }
            let scale = max(0.2, (point.x - annotation.rect.origin.x) / originalSize.width)
            let newFontSize = min(288, max(8, annotation.style.fontSize * scale))
            var copy = annotation
            copy.style.fontSize = newFontSize
            return copy
        }
    }

    // MARK: - Drawing

    /// Draws the selection handles for `annotation` (already the displayed /
    /// preview variant). Called from `drawSelectionOutline()`.
    func drawHandles(for annotation: Annotation) {
        for (_, position) in handlePositions(for: annotation) {
            let rect = CGRect(
                x: position.x - handleDrawRadius,
                y: position.y - handleDrawRadius,
                width: handleDrawRadius * 2,
                height: handleDrawRadius * 2
            )
            let path = NSBezierPath(ovalIn: rect)
            NSColor.white.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}
