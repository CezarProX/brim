// AnnotationCanvasView+Selection.swift
// Brim
//
// Selection-mode (`session.currentTool == nil`) behavior: hit-testing
// topmost-first, click-to-select, drag-to-move (committed as a single undo
// step on mouseUp, mirroring the drafting tools), and the subtle selection
// outline drawn around the active annotation.

import AppKit

extension AnnotationCanvasView {

    // MARK: - Drag to move

    func beginSelectionDrag(at point: CGPoint) {
        guard let hit = hitTestAnnotation(at: point) else {
            session.selectAnnotation(id: nil)
            return
        }
        session.selectAnnotation(id: hit.id)
        selectionDragOriginal = hit
        selectionDragStart = point
        selectionDragOffset = .zero
    }

    func continueSelectionDrag(at point: CGPoint) {
        guard let start = selectionDragStart, selectionDragOriginal != nil else { return }
        selectionDragOffset = CGSize(width: point.x - start.x, height: point.y - start.y)
        needsDisplay = true
    }

    func endSelectionDrag(at point: CGPoint) {
        defer {
            selectionDragOriginal = nil
            selectionDragStart = nil
            selectionDragOffset = .zero
            needsDisplay = true
        }
        guard let original = selectionDragOriginal, selectionDragOffset != .zero else { return }
        session.updateAnnotation(translated(original, by: selectionDragOffset))
    }

    // MARK: - Hit-testing

    /// Topmost-first hit test: the last-drawn (most recently added)
    /// annotation wins when annotations overlap.
    func hitTestAnnotation(at point: CGPoint) -> Annotation? {
        session.visibleAnnotations.reversed().first { annotationContains($0, point: point) }
    }

    private func annotationContains(_ annotation: Annotation, point: CGPoint) -> Bool {
        switch annotation.tool {
        case .pen, .line, .arrow, .highlighter:
            return pathContains(annotation.points, lineWidth: annotation.style.lineWidth, point: point)
        case .curvedArrow:
            return pathContains(AnnotationGeometry.curveSamples(annotation.points),
                                lineWidth: annotation.style.lineWidth, point: point)
        case .ellipse where !annotation.style.isFilled:
            return ellipseOutlineContains(annotation, point: point)
        case .crop:
            return false
        default:
            return AnnotationGeometry.bounds(of: annotation).insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    /// An outlined ellipse is grabbed on its ring, so clicks inside it still
    /// reach whatever is underneath.
    private func ellipseOutlineContains(_ annotation: Annotation, point: CGPoint) -> Bool {
        let r = annotation.rect.standardized
        guard r.width > 0, r.height > 0 else { return false }
        let dx = (point.x - r.midX) / (r.width / 2), dy = (point.y - r.midY) / (r.height / 2)
        let distance = sqrt(dx * dx + dy * dy)
        let tolerance = max(8, annotation.style.lineWidth * 2) / max(1, min(r.width, r.height) / 2)
        return abs(distance - 1) <= tolerance
    }

    private func pathContains(_ points: [CGPoint], lineWidth: CGFloat, point: CGPoint) -> Bool {
        guard points.count >= 2 else {
            guard let first = points.first else { return false }
            return hypot(point.x - first.x, point.y - first.y) <= max(8, lineWidth)
        }
        let threshold = max(8, lineWidth * 2)
        for index in 0..<(points.count - 1)
        where distance(from: point, toSegment: points[index], points[index + 1]) <= threshold {
            return true
        }
        return false
    }

    private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Selection outline

    func drawSelectionOutline() {
        guard let selectedID = session.selectedAnnotationID,
              let annotation = session.visibleAnnotations.first(where: { $0.id == selectedID }) else {
            return
        }

        let displayed: Annotation
        if annotation.id == selectionDragOriginal?.id {
            displayed = translated(annotation, by: selectionDragOffset)
        } else if annotation.id == handleDragPreview?.id, let preview = handleDragPreview {
            displayed = preview
        } else {
            displayed = annotation
        }

        let box = boundingBox(of: displayed)
        let outline = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.5
        let dashPattern: [CGFloat] = [4, 3]
        outline.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        drawHandles(for: displayed)
    }

    private func boundingBox(of annotation: Annotation) -> CGRect {
        let pad: CGFloat = AnnotationGeometry.isRectBased(annotation.tool) ? -4 : -6
        return AnnotationGeometry.bounds(of: annotation).insetBy(dx: pad, dy: pad)
    }
}
